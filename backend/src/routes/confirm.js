const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth');
const Auction = require('../models/Auction');
const Notification = require('../models/Notification');
const { AUCTION_STATUS } = require('../config/constants');

// POST /api/confirm/:id
router.post('/:id', authMiddleware, async (req, res) => {
    try {
        const auctionId = req.params.id;
        const userId = req.user.id;

        const auction = await Auction.findById(auctionId).populate('seller_id');
        if (!auction) {
            return res.status(404).json({ error: 'Auction not found' });
        }

        if (!auction.highest_bidder_id || auction.highest_bidder_id.toString() !== userId) {
            return res.status(403).json({ error: 'Only the winner can confirm receipt' });
        }

        if (auction.status !== AUCTION_STATUS.WAITING_CONFIRMATION) {
            return res.status(400).json({ error: 'Auction is not waiting for confirmation' });
        }

        const updatedAuction = await Auction.findByIdAndUpdate(
            auction._id,
            {
                status: AUCTION_STATUS.SETTLED,
                settled_on_chain: true,
                confirmed_at: new Date(),
                confirmed_by: userId
            },
            { new: true }
        );

        const io = global.io;
        if (io) {
            const payload = {
                auction_id: auction._id.toString(),
                status: AUCTION_STATUS.SETTLED,
                start_time: auction.start_time,
                end_time: auction.end_time,
                winner_id: auction.highest_bidder_id.toString(),
                highest_bidder_id: auction.highest_bidder_id.toString(),
                confirmed_at: updatedAuction?.confirmed_at?.toISOString?.() || new Date().toISOString(),
                server_time: new Date().toISOString()
            };

            io.to(`auction_${auction._id}`).emit('auction_state_changed', payload);
            io.to(`auction_${auction._id}`).emit('auction_settled', payload);
        }

        await Notification.create({
            user_id: auction.seller_id._id,
            type: 'AUCTION_SOLD',
            title: 'Nguoi mua da xac nhan nhan hang',
            message: `Nguoi mua da xac nhan nhan hang cho phien dau gia "${auction.title}".`,
            related_id: auction._id
        });

        await Notification.create({
            user_id: userId,
            type: 'WON_AUCTION',
            title: 'Giao dich thanh cong',
            message: 'Ban da xac nhan nhan hang thanh cong.',
            related_id: auction._id
        });

        res.json({
            success: true,
            message: 'Receipt confirmed successfully',
            status: AUCTION_STATUS.SETTLED
        });
    } catch (error) {
        console.error('Confirmation error:', error);
        res.status(500).json({ error: 'Internal server error', details: error.message });
    }
});

module.exports = router;
