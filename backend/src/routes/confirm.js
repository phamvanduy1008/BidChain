const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth');
const Auction = require('../models/Auction');
const Bid = require('../models/Bid');
const User = require('../models/User');
const Notification = require('../models/Notification');
const { AUCTION_STATUS } = require('../config/constants');
const { settleBid, isWalletContractAvailable } = require('../blockchain/wallet-contract');

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

        const [winner, seller, winningBid] = await Promise.all([
            User.findById(userId),
            User.findById(auction.seller_id._id),
            Bid.findOne({
                auction_id: auction._id,
                user_id: userId,
                status: 'WINNING'
            })
        ]);

        if (!winner) {
            return res.status(404).json({ error: 'Winner not found' });
        }

        if (!seller) {
            return res.status(404).json({ error: 'Seller not found' });
        }

        if (!winningBid) {
            return res.status(404).json({ error: 'Winning bid not found' });
        }

        const bidAmountBigInt = BigInt(winningBid.amount_wei);
        const winnerLockedBigInt = BigInt(winner.locked_eth || '0');
        const winnerBalanceBigInt = BigInt(winner.balance_eth || '0');
        const sellerBalanceBigInt = BigInt(seller.balance_eth || '0');

        if (winnerLockedBigInt < bidAmountBigInt) {
            return res.status(400).json({ error: 'Locked balance is insufficient for confirmation' });
        }

        if (winnerBalanceBigInt < bidAmountBigInt) {
            return res.status(400).json({ error: 'Total balance is insufficient for confirmation' });
        }

        let settlementTxHash = auction.settlement_tx || null;

        if (isWalletContractAvailable() && auction.blockchain_id && winner.wallet_address && seller.wallet_address) {
            const result = await settleBid(
                winner.wallet_address,
                seller.wallet_address,
                auction.blockchain_id,
                winningBid.amount_wei
            );
            settlementTxHash = result.txHash;
        }

        const newWinnerLocked = (winnerLockedBigInt - bidAmountBigInt).toString();
        const newWinnerBalance = (winnerBalanceBigInt - bidAmountBigInt).toString();
        const newSellerBalance = (sellerBalanceBigInt + bidAmountBigInt).toString();

        const confirmedAt = new Date();

        const [updatedAuction] = await Promise.all([
            Auction.findByIdAndUpdate(
                auction._id,
                {
                    status: AUCTION_STATUS.SETTLED,
                    settled_on_chain: true,
                    settlement_tx: settlementTxHash,
                    confirmed_at: confirmedAt,
                    confirmed_by: userId
                },
                { new: true }
            ),
            User.findByIdAndUpdate(winner._id, {
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
                tx_settle_hash: settlementTxHash
            })
        ]);

        const io = global.io;
        if (io) {
            const payload = {
                auction_id: auction._id.toString(),
                status: AUCTION_STATUS.SETTLED,
                start_time: auction.start_time,
                end_time: auction.end_time,
                winner_id: auction.highest_bidder_id.toString(),
                highest_bidder_id: auction.highest_bidder_id.toString(),
                confirmed_at: updatedAuction?.confirmed_at?.toISOString?.() || confirmedAt.toISOString(),
                settlement_tx: settlementTxHash,
                server_time: new Date().toISOString()
            };

            io.to(`auction_${auction._id}`).emit('auction_state_changed', payload);
            io.to(`auction_${auction._id}`).emit('auction_settled', payload);
            io.to(`user_${winner._id}`).emit('balance_updated', { user_id: winner._id.toString() });
            io.to(`user_${seller._id}`).emit('balance_updated', { user_id: seller._id.toString() });
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
