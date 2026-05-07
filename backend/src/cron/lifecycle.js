const Auction = require("../models/Auction");
const Notification = require("../models/Notification");
const { provider } = require("../blockchain/contract");
const { AUCTION_STATUS } = require("../config/constants");
const { weiToVnd, formatVnd } = require("../utils/conversion");

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
        await Auction.findByIdAndUpdate(auction._id, {
            status: AUCTION_STATUS.ENDED
        });

        auction.status = AUCTION_STATUS.ENDED;

        if (auction.highest_bidder_id) {
            await Notification.create({
                user_id: auction.highest_bidder_id._id,
                type: "WON_AUCTION",
                title: "Ban da la nguoi chien thang",
                message: `Ban tam thoi la nguoi chien thang trong phien dau gia "${auction.title}".`,
                related_id: auction._id
            });
        }

        emitAuctionState(io, auction, "auction_ended", {
            winner_id: auction.highest_bidder_id?._id?.toString() || null
        });
        console.log(`Auction ${auction._id} ended`);
    }
}

async function runAuctionLifecycleCron() {
    try {
        const latestBlock = await provider.getBlock("latest");
        const chainNow = new Date(latestBlock.timestamp * 1000);
        const io = global.io;

        if (io) {
            io.emit("server_time_sync", {
                server_time: chainNow.toISOString()
            });
        }

        await transitionUpcomingAuctions(io, chainNow);
        await transitionEndedAuctions(io, chainNow);
    } catch (error) {
        console.error("Auction lifecycle cron error:", error);
    }
}

module.exports = { runAuctionLifecycleCron };