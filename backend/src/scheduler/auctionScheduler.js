const Auction = require("../models/Auction");
const Notification = require("../models/Notification");
const { AUCTION_STATUS } = require("../config/constants");
const { getCurrentAuctionTime } = require("../utils/auctionTime");

const AUTO_START_INTERVAL_MS = Number(
  process.env.AUCTION_AUTO_START_INTERVAL_MS || 10000
);

async function startAuctionLogic(auction) {
  try {
    const now = getCurrentAuctionTime();

    const updatedAuction = await Auction.findOneAndUpdate(
      {
        _id: auction._id,
        status: { $in: [AUCTION_STATUS.DEPLOYING, AUCTION_STATUS.APPROVED] },
      },
      {
        status: AUCTION_STATUS.ACTIVE,
        started_at: now,
      },
      { new: true }
    ).populate("seller_id");

    if (!updatedAuction) {
      return false;
    }

    console.log(
      `AUTO-START Auction ${updatedAuction._id} - ${updatedAuction.title} moved to ACTIVE`
    );

    if (updatedAuction.seller_id?._id) {
      await Notification.create({
        user_id: updatedAuction.seller_id._id,
        type: "AUCTION_STARTED",
        title: "Auction started",
        message: `Auction ${updatedAuction.title} has started automatically`,
        related_id: updatedAuction._id,
      });
    }

    const io = global.io;
    if (io) {
      const payload = {
        auction_id: updatedAuction._id.toString(),
        title: updatedAuction.title,
        status: updatedAuction.status,
        start_time: updatedAuction.start_time,
        end_time: updatedAuction.end_time,
        server_time: now.toISOString(),
      };

      io.emit("auction_started", payload);
      io.emit("auction_state_changed", payload);
      io.to(`auction_${updatedAuction._id}`).emit("auction_started", payload);
      io
        .to(`auction_${updatedAuction._id}`)
        .emit("auction_state_changed", payload);
    }

    return true;
  } catch (error) {
    console.error(`Auto start failed for auction ${auction._id}:`, error);
    return false;
  }
}

function startAuctionScheduler() {
  console.log(
    `Auction Auto-Start Scheduler started (runs every ${AUTO_START_INTERVAL_MS / 1000}s)`
  );

  return setInterval(async () => {
    try {
      const now = getCurrentAuctionTime();

      const auctionsToStart = await Auction.find({
        status: { $in: [AUCTION_STATUS.DEPLOYING, AUCTION_STATUS.APPROVED] },
        start_time: { $lte: now },
      }).populate("seller_id");

      if (auctionsToStart.length === 0) {
        return;
      }

      console.log(
        `AUTO-START found ${auctionsToStart.length} auction(s) ready to activate`
      );

      for (const auction of auctionsToStart) {
        await startAuctionLogic(auction);
      }
    } catch (error) {
      console.error("Auction auto-start scheduler error:", error);
    }
  }, AUTO_START_INTERVAL_MS);
}

module.exports = startAuctionScheduler;
