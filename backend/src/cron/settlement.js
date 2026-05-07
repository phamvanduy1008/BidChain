const fs = require("fs");
const path = require("path");
const ethers = require("ethers");
const Auction = require("../models/Auction");
const Bid = require("../models/Bid");
const User = require("../models/User");
const Notification = require("../models/Notification");
const { provider, walletFromPrivateKey } = require("../blockchain/contract");
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

async function fetchOnChainAuctionState(auction) {
    if (!auction.blockchain_id || !auction.contract_address) {
        throw new Error("Auction missing blockchain_id or contract_address");
    }

    const [onChainAuction, latestBlock] = await Promise.all([
        getAuctionContractAt(auction.contract_address).getAuction(auction.blockchain_id),
        provider.getBlock("latest")
    ]);

    return { onChainAuction, latestBlock };
}

function isSettlementWindowOpen(onChainAuction, latestBlock) {
    return getCurrentAuctionTimestampSeconds() >= onChainAuction.endTime.toNumber() + SETTLEMENT_BUFFER_SECONDS;
}

async function finalizeNoBidAuction(auction, onChainAuction) {
    await Auction.findByIdAndUpdate(auction._id, {
        status: onChainAuction.ended ? AUCTION_STATUS.ENDED : AUCTION_STATUS.ENDED,
        settled_on_chain: true,
        end_time: new Date(onChainAuction.endTime.toNumber() * 1000)
    });
}

async function finalizeSuccessfulSettlement(auction, winningBid, seller, txHash, onChainAuction) {
    const winnerLockedBigInt = BigInt(winningBid.user_id.locked_eth || "0");
    const winnerBalanceBigInt = BigInt(winningBid.user_id.balance_eth || "0");
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

    await Promise.all([
        Auction.findByIdAndUpdate(auction._id, {
            status: AUCTION_STATUS.WAITING_CONFIRMATION,
            settled_on_chain: true,
            settlement_tx: txHash,
            end_time: new Date(onChainAuction.endTime.toNumber() * 1000)
        }),
        User.findByIdAndUpdate(winningBid.user_id._id, {
            $set: {
                locked_eth: newWinnerLocked,
                balance_eth: newWinnerBalance
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
    }
}

async function settleAuctionOnChain(auction) {
    try {
        console.log(`\n========== Settling Auction ${auction._id} ==========`);

        const { onChainAuction, latestBlock } = await fetchOnChainAuctionState(auction);
        const currentTimestamp = getCurrentAuctionTimestampSeconds();

        if (!isSettlementWindowOpen(onChainAuction, latestBlock)) {
            console.log(
                `Skipping ${auction._id}: latest=${latestBlock.timestamp}, server=${currentTimestamp}, end=${onChainAuction.endTime.toString()}, buffer=${SETTLEMENT_BUFFER_SECONDS}s`
            );
            return;
        }

        if (onChainAuction.settled) {
            console.log(`Auction ${auction._id} already settled on-chain. Syncing DB state only.`);
            await Auction.findByIdAndUpdate(auction._id, {
                status: AUCTION_STATUS.WAITING_CONFIRMATION,
                settled_on_chain: true,
                end_time: new Date(onChainAuction.endTime.toNumber() * 1000)
            });
            return;
        }

        if (!auction.highest_bidder_id) {
            console.log(`No bids on auction ${auction._id}, marking as ENDED`);
            await finalizeNoBidAuction(auction, onChainAuction);
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

        const deployer = walletFromPrivateKey(process.env.DEPLOYER_PRIVATE_KEY);
        const auctionContract = getAuctionContractAt(auction.contract_address, deployer);

        const tx = await auctionContract.settleAuction(
            auction.blockchain_id,
            winningBid.user_id.wallet_address,
            winningBid.amount_wei
        );

        console.log(`Settlement transaction sent: ${tx.hash}`);
        const receipt = await tx.wait();

        if (receipt.status !== 1) {
            throw new Error(`Settlement transaction reverted for auction ${auction._id}`);
        }

        console.log(`Settlement confirmed in block ${receipt.blockNumber}`);

        const refreshedOnChainAuction = await auctionContract.getAuction(auction.blockchain_id);
        await finalizeSuccessfulSettlement(
            auction,
            winningBid,
            seller,
            tx.hash,
            refreshedOnChainAuction
        );

        console.log(`Auction ${auction._id} settled successfully`);
    } catch (error) {
        console.error(`Settlement failed for auction ${auction._id}:`, error.message || error);
    }
}

async function runSettlementCron() {
    try {
        const candidates = await Auction.find({
            status: AUCTION_STATUS.ENDED,
            settled_on_chain: false,
            blockchain_id: { $exists: true, $ne: null },
            contract_address: { $exists: true, $ne: null }
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
