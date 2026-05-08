const fs = require("fs");
const path = require("path");
const ethers = require("ethers");
const Auction = require("../models/Auction");
const Bid = require("../models/Bid");
const Notification = require("../models/Notification");
const { AUCTION_STATUS } = require("../config/constants");
const { weiToVnd, formatVnd } = require("../utils/conversion");
const { getCurrentAuctionTime } = require("../utils/auctionTime");
const { provider, walletFromPrivateKey } = require("../blockchain/contract");

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
        console.warn(`Failed to mirror ended state for auction ${auction._id}: ${error.message}`);
    }
}

function emitAuctionState(io, auction, eventName, extra = {}) {
    if (!io) {
        return;
    }

    const payload = {
        auction_id: auction._id.toString(),
        status: auction.status,
        start_time: auction.start_time,
        end_time: auction.end_time,
        current_price_vnd: weiToVnd(auction.current_price.toString()),
        formatted_current_price: formatVnd(weiToVnd(auction.current_price.toString())),
        highest_bidder_id: auction.highest_bidder_id?.toString() || null,
        server_time: new Date().toISOString(),
        ...extra
    };

    io.emit(eventName, payload);
    io.emit("auction_state_changed", payload);
    io.to(`auction_${auction._id}`).emit(eventName, payload);
    io.to(`auction_${auction._id}`).emit("auction_state_changed", payload);
}

async function transitionUpcomingAuctions(io, chainNow) {
    const auctionsToActivate = await Auction.find({
        status: AUCTION_STATUS.APPROVED,
        start_time: { $lte: chainNow },
        end_time: { $gt: chainNow }
    }).populate("seller_id");

    for (const auction of auctionsToActivate) {
        await Auction.findByIdAndUpdate(auction._id, {
            status: AUCTION_STATUS.ACTIVE
        });

        auction.status = AUCTION_STATUS.ACTIVE;

        await Notification.create({
            user_id: auction.seller_id._id,
            type: "AUCTION_STARTED",
            title: "Phien dau gia da bat dau",
            message: `Phien dau gia "${auction.title}" da bat dau va dang nhan bids.`,
            related_id: auction._id
        });

        emitAuctionState(io, auction, "auction_started");
        console.log(`Auction ${auction._id} activated`);
    }
}

async function transitionEndedAuctions(io, chainNow) {
    const auctionsToEnd = await Auction.find({
        status: AUCTION_STATUS.ACTIVE,
        end_time: { $lte: chainNow }
    }).populate("seller_id highest_bidder_id");

    for (const auction of auctionsToEnd) {
        const nextStatus = AUCTION_STATUS.ENDED;

        await mirrorAuctionEndedOnChain(auction);

        await Auction.findByIdAndUpdate(auction._id, {
            status: nextStatus,
            settled_on_chain: !auction.highest_bidder_id
        });

        auction.status = nextStatus;

        if (auction.highest_bidder_id) {
            const winnerNotification = await Notification.create({
                user_id: auction.highest_bidder_id._id,
                type: "WON_AUCTION",
                title: "Ban da la nguoi chien thang",
                message: `Ban tam thoi la nguoi chien thang trong phien dau gia "${auction.title}".`,
                related_id: auction._id
            });

            if (io) {
                io.to(`user_${auction.highest_bidder_id._id}`).emit("notification", {
                    ...winnerNotification.toObject(),
                    _id: winnerNotification._id.toString()
                });
            }

            const participantIds = await Bid.distinct("user_id", {
                auction_id: auction._id
            });
            const winnerId = auction.highest_bidder_id._id.toString();
            const loserIds = participantIds
                .map((id) => id.toString())
                .filter((userId) => userId !== winnerId);

            if (loserIds.length > 0) {
                const loserNotifications = await Notification.insertMany(
                    loserIds.map((userId) => ({
                        user_id: userId,
                        type: "AUCTION_LOST",
                        title: "Phien dau gia da ket thuc",
                        message: `Phien dau gia "${auction.title}" da ket thuc. Ban khong phai la nguoi chien thang.`,
                        related_id: auction._id
                    }))
                );

                if (io) {
                    for (const notification of loserNotifications) {
                        io.to(`user_${notification.user_id.toString()}`).emit("notification", {
                            ...notification.toObject(),
                            _id: notification._id.toString()
                        });
                    }
                }
            }
        }

        emitAuctionState(io, auction, "auction_ended", {
            winner_id: auction.highest_bidder_id?._id?.toString() || null
        });
        console.log(`Auction ${auction._id} ended with status ${nextStatus}`);
    }
}

async function runAuctionLifecycleCron() {
    try {
        const currentNow = getCurrentAuctionTime();
        const io = global.io;

        if (io) {
            io.emit("server_time_sync", {
                server_time: currentNow.toISOString()
            });
        }

        await transitionUpcomingAuctions(io, currentNow);
        await transitionEndedAuctions(io, currentNow);
    } catch (error) {
        console.error("Auction lifecycle cron error:", error);
    }
}

module.exports = { runAuctionLifecycleCron };
