const fs = require("fs");
const path = require("path");
const ethers = require("ethers");
const Auction = require("../models/Auction");
const Bid = require("../models/Bid");
const User = require("../models/User");
const Notification = require("../models/Notification");
const { provider, walletFromPrivateKey } = require("../blockchain/contract");
const { settleBid, isWalletContractAvailable } = require("../blockchain/wallet-contract");
const { formatVnd } = require("../utils/conversion");
const { AUCTION_STATUS } = require("../config/constants");
const { getCurrentAuctionTimestampSeconds } = require("../utils/auctionTime");
require("dotenv").config();

const SETTLEMENT_BUFFER_SECONDS = Number(process.env.SETTLEMENT_BUFFER_SECONDS || 3);

function getAuctionAbi() {
    const abiPath = process.env.CONTRACT_ABI_PATH || "./abi/Auction.json";
    const abiRaw = fs.readFileSync(path.resolve(abiPath), "utf8");
    const abiParsed = JSON.parse(abiRaw);
    return abiParsed.abi || abiParsed;
}

function getAuctionContractAt(contractAddress, signerOrProvider = provider) {
    return new ethers.Contract(contractAddress, getAuctionAbi(), signerOrProvider);
}

async function mirrorAuctionEndedOnChain(auction) {
    if (!auction.contract_address || !auction.blockchain_id) {
        return;
    }

    try {
        const deployer = walletFromPrivateKey(process.env.DEPLOYER_PRIVATE_KEY);
        const auctionContract = getAuctionContractAt(auction.contract_address, deployer);
        const onChainAuction = await auctionContract.getAuction(auction.blockchain_id);

        if (onChainAuction.ended) {
            return;
        }

        const tx = await auctionContract.endAuction(auction.blockchain_id);
        await tx.wait();
        console.log(`Auction ${auction._id} mirrored as ended on-chain`);
    } catch (error) {
        console.warn(`Unable to mirror ended state for auction ${auction._id}: ${error.message}`);
    }
}

function isSettlementWindowOpen(auction) {
    const endTimestamp = Math.floor(new Date(auction.end_time).getTime() / 1000);
    return getCurrentAuctionTimestampSeconds() >= endTimestamp + SETTLEMENT_BUFFER_SECONDS;
}

async function finalizeSuccessfulSettlement(auction, winningBid, seller, txHash) {
    const winnerLockedBigInt = BigInt(winningBid.user_id.locked_eth || "0");
    const winnerBalanceBigInt = BigInt(winningBid.user_id.balance_eth || "0");
    const sellerBalanceBigInt = BigInt(seller.balance_eth || "0");
    const bidAmountBigInt = BigInt(winningBid.amount_wei);

    if (winnerLockedBigInt < bidAmountBigInt) {
        throw new Error(
            `Winner locked balance is insufficient for settlement: locked=${winnerLockedBigInt} amount=${bidAmountBigInt}`
        );
    }

    if (winnerBalanceBigInt < bidAmountBigInt) {
        throw new Error(
            `Winner total balance is insufficient for settlement: balance=${winnerBalanceBigInt} amount=${bidAmountBigInt}`
        );
    }

    const newWinnerLocked = (winnerLockedBigInt - bidAmountBigInt).toString();
    const newWinnerBalance = (winnerBalanceBigInt - bidAmountBigInt).toString();
    const newSellerBalance = (sellerBalanceBigInt + bidAmountBigInt).toString();

    await Promise.all([
        Auction.findByIdAndUpdate(auction._id, {
            status: AUCTION_STATUS.WAITING_CONFIRMATION,
            settled_on_chain: true,
            settlement_tx: txHash
        }),
        User.findByIdAndUpdate(winningBid.user_id._id, {
            $set: {
                locked_eth: newWinnerLocked,
                balance_eth: newWinnerBalance
            }
        }),
        User.findByIdAndUpdate(seller._id, {
            $set: {
                balance_eth: newSellerBalance
            }
        }),
        Bid.findByIdAndUpdate(winningBid._id, {
            tx_settle_hash: txHash
        }),
        Notification.create({
            user_id: winningBid.user_id._id,
            type: "WON_AUCTION",
            title: "Chuc mung! Ban da thang dau gia",
            message: `Ban da thang phien dau gia "${auction.title}" voi gia ${formatVnd(winningBid.amount_vnd)}`,
            related_id: auction._id
        }),
        Notification.create({
            user_id: seller._id,
            type: "AUCTION_SOLD",
            title: "Phien dau gia da ket thuc",
            message: `Phien dau gia "${auction.title}" da ket thuc. Vui long giao hang de nhan tien.`,
            related_id: auction._id
        })
    ]);

    const io = global.io;
    if (io) {
        const payload = {
            auction_id: auction._id.toString(),
            status: AUCTION_STATUS.WAITING_CONFIRMATION,
            start_time: auction.start_time,
            end_time: auction.end_time,
            winner_id: winningBid.user_id._id.toString(),
            highest_bidder_id: winningBid.user_id._id.toString(),
            settlement_tx: txHash,
            server_time: new Date().toISOString()
        };

        io.to(`user_${winningBid.user_id._id}`).emit("auction_won", {
            auction_id: auction._id,
            title: auction.title,
            final_price_vnd: winningBid.amount_vnd,
            formatted_final_price: formatVnd(winningBid.amount_vnd)
        });

        io.to(`user_${seller._id}`).emit("auction_sold", {
            auction_id: auction._id,
            title: auction.title,
            final_price_vnd: winningBid.amount_vnd,
            formatted_final_price: formatVnd(winningBid.amount_vnd)
        });

        io.to(`auction_${auction._id}`).emit("auction_state_changed", payload);
        io.to(`auction_${auction._id}`).emit("auction_settled", payload);
    }
}

async function settleAuctionOnChain(auction) {
    try {
        console.log(`\n========== Settling Auction ${auction._id} ==========`);

        if (!isSettlementWindowOpen(auction)) {
            console.log(
                `Skipping ${auction._id}: server=${getCurrentAuctionTimestampSeconds()}, end=${Math.floor(new Date(auction.end_time).getTime() / 1000)}, buffer=${SETTLEMENT_BUFFER_SECONDS}s`
            );
            return;
        }

        if (!auction.highest_bidder_id) {
            console.log(`Skipping ${auction._id}: no highest bidder.`);
            await Auction.findByIdAndUpdate(auction._id, {
                status: AUCTION_STATUS.ENDED,
                settled_on_chain: true
            });
            return;
        }

        const winningBid = await Bid.findOne({
            auction_id: auction._id,
            status: "WINNING"
        }).populate("user_id");

        if (!winningBid) {
            throw new Error(`No winning bid found for auction ${auction._id}`);
        }

        const seller = await User.findById(auction.seller_id);
        if (!seller) {
            throw new Error(`Seller not found for auction ${auction._id}`);
        }

        await mirrorAuctionEndedOnChain(auction);

        if (!isWalletContractAvailable()) {
            throw new Error("BidChainWallet contract is not configured");
        }

        const result = await settleBid(
            winningBid.user_id.wallet_address,
            seller.wallet_address,
            auction.blockchain_id,
            winningBid.amount_wei
        );

        await finalizeSuccessfulSettlement(auction, winningBid, seller, result.txHash);
        console.log(`Auction ${auction._id} settled successfully via BidChainWallet`);
    } catch (error) {
        console.error(`Settlement failed for auction ${auction._id}:`, error.message || error);
    }
}

async function runSettlementCron() {
    try {
        const candidates = await Auction.find({
            status: AUCTION_STATUS.ENDED,
            settled_on_chain: false,
            highest_bidder_id: { $exists: true, $ne: null },
            blockchain_id: { $exists: true, $ne: null }
        }).populate("seller_id highest_bidder_id");

        if (candidates.length > 0) {
            console.log(`\nFound ${candidates.length} auction(s) to evaluate for settlement`);
        }

        for (const auction of candidates) {
            await settleAuctionOnChain(auction);
        }
    } catch (error) {
        console.error("Settlement cron error:", error);
    }
}

module.exports = {
    runSettlementCron,
    settleAuctionOnChain,
    SETTLEMENT_BUFFER_SECONDS
};
