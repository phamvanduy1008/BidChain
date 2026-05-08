const Auction = require("../models/Auction");
const Notification = require("../models/Notification");
const { AUCTION_STATUS } = require("../config/constants");
const { weiToVnd, formatVnd } = require("../utils/conversion");
const { getCurrentAuctionTime } = require("../utils/auctionTime");

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
        const nextStatus = auction.highest_bidder_id
            ? AUCTION_STATUS.WAITING_CONFIRMATION
            : AUCTION_STATUS.ENDED;

        await Auction.findByIdAndUpdate(auction._id, {
            status: nextStatus
        });

        auction.status = nextStatus;

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
