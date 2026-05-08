import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/config/routes/app_routes.dart';
import 'package:frontend/core/services/socket_service.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/services/server_time_service.dart';
import '../../../core/utils/auction_status_resolver.dart';
import '../../../core/utils/app_localizations.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';
import '../../bloc/auth/auth_state.dart';
import '../../bloc/auction_detail/auction_detail_bloc.dart';
import '../../bloc/auction_detail/auction_detail_event.dart';
import '../../bloc/auction_detail/auction_detail_state.dart';
import '../../bloc/chat/chat_bloc.dart';
import '../chat/chat_screen.dart';
import '../../widgets/auction/bid_history_card.dart';
import '../../widgets/auction/countdown_timer.dart';
import '../../widgets/auction/image_gallery.dart';
import '../../widgets/auction/place_bid_dialog.dart';
import '../../widgets/auction/seller_info_card.dart';
import '../../widgets/common/custom_app_bar.dart';
import '../../widgets/common/custom_back_button.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/text/expandable_text.dart';

class AuctionDetailPage extends StatefulWidget {
  final String auctionId;

  const AuctionDetailPage({super.key, required this.auctionId});

  @override
  State<AuctionDetailPage> createState() => _AuctionDetailPageState();
}

class _AuctionDetailPageState extends State<AuctionDetailPage> {
  final SocketService _socketService = SocketService();
  StreamSubscription<Map<String, dynamic>>? _auctionEventSubscription;
  Timer? _countdownExpiryRefreshTimer;
  Timer? _statusTransitionPollTimer;

  @override
  void initState() {
    super.initState();
    context.read<AuctionDetailBloc>().add(
      LoadAuctionDetail(auctionId: widget.auctionId),
    );
    _socketService.joinAuctionRoom(widget.auctionId);
    _auctionEventSubscription = _socketService.auctionEventStream.listen(
      _handleAuctionEvent,
    );
  }

  @override
  void dispose() {
    _countdownExpiryRefreshTimer?.cancel();
    _statusTransitionPollTimer?.cancel();
    _auctionEventSubscription?.cancel();
    _socketService.leaveAuctionRoom(widget.auctionId);
    super.dispose();
  }

  // ==================== SOCKET EVENT HANDLERS ====================

  void _handleAuctionEvent(Map<String, dynamic> event) {
    if (!mounted || event['auction_id']?.toString() != widget.auctionId) {
      return;
    }

    final eventName = event['event_name']?.toString();

    // Refresh auction data
    context.read<AuctionDetailBloc>().add(
      RefreshAuctionDetail(auctionId: widget.auctionId),
    );

    if (eventName == 'user_outbid') {
      _showOutbidDialog();
      return;
    }

    if (eventName == 'auction_ended') {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthSuccessState) {
        final winnerId = event['winner_id']?.toString();
        final isWinner = winnerId != null && winnerId == authState.user.id;
        _showAuctionEndedDialog(isWinner: isWinner);
      }
    }
  }

  void _showOutbidDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bạn đã bị vượt giá'),
        content: const Text(
          'Có người đã đặt giá cao hơn bạn. Bạn có muốn tiếp tục nâng giá không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Để sau'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              final state = context.read<AuctionDetailBloc>().state;
              if (state is AuctionDetailLoaded) {
                _showPlaceBidDialog(context, state.auction);
              }
            },
            child: const Text('Tiếp tục ra giá'),
          ),
        ],
      ),
    );
  }

  void _showAuctionEndedDialog({required bool isWinner}) {
    final message = isWinner
        ? 'Bạn đã là người chiến thắng'
        : 'Phiên đấu giá đã kết thúc. Bạn không phải là người chiến thắng.';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isWinner ? 'Kết quả đấu giá' : 'Phiên đấu giá kết thúc'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _handleCountdownExpired() {
    _countdownExpiryRefreshTimer?.cancel();
    _statusTransitionPollTimer?.cancel();

    final currentState = context.read<AuctionDetailBloc>().state;
    String? expectedOldStatus;

    if (currentState is AuctionDetailLoaded) {
      expectedOldStatus = currentState.auction.status;
    }

    _countdownExpiryRefreshTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      context.read<AuctionDetailBloc>().add(
        RefreshAuctionDetail(auctionId: widget.auctionId),
      );

      if (expectedOldStatus != null) {
        _startStatusTransitionPolling(expectedOldStatus);
      }
    });
  }

  void _startStatusTransitionPolling(String expectedOldStatus) {
    var attempts = 0;

    _statusTransitionPollTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final state = context.read<AuctionDetailBloc>().state;
      if (state is AuctionDetailLoaded &&
          state.auction.status != expectedOldStatus &&
          !_shouldContinueStatusPolling(state.auction)) {
        timer.cancel();
        return;
      }

      attempts++;
      context.read<AuctionDetailBloc>().add(
        RefreshAuctionDetail(auctionId: widget.auctionId),
      );

      if (attempts >= 30) {
        timer.cancel();
      }
    });
  }

  // ==================== CHAT ====================

  void _openChatWithContext(BuildContext context, AuctionDetailState state) {
    Map<String, dynamic>? auctionData;

    if (state is AuctionDetailLoaded) {
      final auction = state.auction;
      auctionData = {
        'id': widget.auctionId,
        'title': auction.title,
        'description': auction.description,
        'category': auction.categoryId ?? 'Không rõ',
        'current_price': auction.currentPriceVnd,
        'start_price': auction.startPriceVnd,
        'step_price': auction.stepPriceVnd,
        'bid_count': auction.bidCount,
        'end_time': auction.endTime.toIso8601String(),
        'status': auction.status,
        'seller_name': auction.sellerName,
      };
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 90,
          top: 60,
        ),
        child: BlocProvider.value(
          value: context.read<ChatBloc>(),
          child: ChatScreen(
            auctionId: widget.auctionId,
            auctionData: auctionData,
            onClose: () => Navigator.pop(dialogContext),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuctionDetailBloc, AuctionDetailState>(
      listener: (context, state) {
        if (state is BidPlaced) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.read<AuthBloc>().add(const AuthCheckStatusEvent());
        } else if (state is BidError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (state is ReceiptConfirmed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.read<AuthBloc>().add(const AuthCheckStatusEvent());
        } else if (state is ReceiptError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: CustomAppBar(
            title: 'Chi tiết đấu giá',
            leading: const CustomBackButton(color: AppColors.accent),
            actions: [
              IconButton(
                icon: const Icon(Icons.smart_toy_outlined),
                color: AppColors.accent,
                tooltip: 'Hỏi BidBot về sản phẩm',
                onPressed: () => _openChatWithContext(context, state),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                color: AppColors.accent,
                onPressed: () {
                  // Share functionality
                },
              ),
            ],
          ),
          body: _buildBody(context, state),
          floatingActionButton: _buildFloatingActionButton(context, state),
        );
      },
    );
  }

  bool _isAuctionCreator(
    BuildContext context, {
    required String sellerId,
    String? sellerEmail,
    String? sellerName,
  }) {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthSuccessState) {
      final user = authState.user;

      if (user.id == sellerId) {
        return true;
      }

      if (sellerEmail != null &&
          sellerEmail.isNotEmpty &&
          user.email.toLowerCase() == sellerEmail.toLowerCase()) {
        return true;
      }

      if (sellerName != null &&
          sellerName.isNotEmpty &&
          user.fullName.trim().toLowerCase() == sellerName.trim().toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  bool _isWinner(BuildContext context, auction) {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthSuccessState) {
      return authState.user.id == auction.highestBidderId;
    }
    return false;
  }

  String _resolveEffectiveStatus(auction) {
    return resolveAuctionStatus(
      status: auction.status,
      startTime: auction.startTime,
      endTime: auction.endTime,
    );
  }

  bool _shouldContinueStatusPolling(auction) {
    final status = auction.status.toUpperCase();

    if (status == 'ACTIVE') {
      return true;
    }

    if (status == 'ENDED' && auction.highestBidderId != null) {
      return true;
    }

    return false;
  }

  String _resolveViewerStatus(
    BuildContext context,
    auction, {
    required bool isAuctionCreator,
  }) {
    final effectiveStatus = _resolveEffectiveStatus(auction);

    if ((effectiveStatus == 'WAITING_CONFIRMATION' ||
            effectiveStatus == 'SETTLED') &&
        !isAuctionCreator &&
        !_isWinner(context, auction)) {
      return 'ENDED';
    }

    return effectiveStatus;
  }

  void _showConfirmDialog(BuildContext context, auction) {
    final bloc = context.read<AuctionDetailBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận nhận hàng'),
        content: const Text(
          'Bạn có chắc chắn đã nhận được hàng và muốn giải phóng tiền cho người bán không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(ConfirmReceiptEvent(widget.auctionId));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AuctionDetailState state) {
    if (state is AuctionDetailLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is AuctionDetailError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Đã xảy ra lỗi',
                style: AppTextStyles.h4.copyWith(color: AppColors.accent),
              ),
              const SizedBox(height: 8),
              Text(
                state.message,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  context.read<AuctionDetailBloc>().add(
                    LoadAuctionDetail(auctionId: widget.auctionId),
                  );
                },
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is AuctionDetailLoaded ||
        state is BidPlacing ||
        state is BidPlaced ||
        state is BidError ||
        state is ReceiptConfirming ||
        state is ReceiptConfirmed ||
        state is ReceiptError) {
      final auction = state is AuctionDetailLoaded
          ? state.auction
          : state is BidPlacing
          ? state.auction
          : state is BidPlaced
          ? state.auction
          : state is ReceiptConfirming
          ? state.auction
          : state is ReceiptConfirmed
          ? state.auction
          : state is ReceiptError
          ? state.auction
          : (state as BidError).auction;
      final effectiveStatus = _resolveEffectiveStatus(auction);
      final isAuctionCreator = _isAuctionCreator(
        context,
        sellerId: auction.sellerId,
        sellerEmail: auction.sellerEmail,
        sellerName: auction.sellerName,
      );
      final viewerStatus = _resolveViewerStatus(
        context,
        auction,
        isAuctionCreator: isAuctionCreator,
      );

      return RefreshIndicator(
        onRefresh: () async {
          context.read<AuctionDetailBloc>().add(
            RefreshAuctionDetail(auctionId: widget.auctionId),
          );
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ImageGallery(images: auction.images),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusBadge(status: viewerStatus),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: CountdownTimer(
                          startTime: auction.startTime,
                          endTime: auction.endTime,
                          status: effectiveStatus,
                          onExpired: _handleCountdownExpired,
                        ),
                      ),
                    ],
                  ),

                  if (isAuctionCreator) ...[
                    const SizedBox(height: 16),
                    // Owner badge
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.workspace_premium_rounded,
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Phiên đấu giá của bạn',
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Bạn là người tạo phiên này',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'CHỦ PHIÊN',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  Text(
                    auction.title,
                    style: AppTextStyles.h2.copyWith(color: AppColors.accent),
                  ),
                  const SizedBox(height: 12),

                  ExpandableInlineText(
                    text: auction.description,
                    maxLines: 5,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.grey,
                      height: 1.6,
                    ),
                    readMoreStyle: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 20),
                  SellerInfoCard(
                    sellerId: auction.sellerId,
                    sellerName: auction.sellerName,
                    sellerEmail: auction.sellerEmail,
                    onTap: () => context.push(
                      '${AppRoutes.publicProfile}/${auction.sellerId}',
                    ),
                  ),
                  const SizedBox(height: 20),

                  _buildPriceInfo(auction),
                  const SizedBox(height: 24),
                  _buildBidHistory(auction),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox();
  }

  Widget _buildPriceInfo(auction) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppColors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thông tin giá',
              style: AppTextStyles.h4.copyWith(color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _PriceItem(
                    label: 'Giá khởi điểm',
                    value: auction.formattedStartPrice,
                    color: AppColors.grey,
                  ),
                ),
                Expanded(
                  child: _PriceItem(
                    label: 'Giá hiện tại',
                    value: auction.formattedCurrentPrice,
                    color: AppColors.accent,
                    isHighlight: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PriceItem(
                    label: 'Bước giá',
                    value: auction.formattedStepPrice,
                    color: AppColors.accent,
                  ),
                ),
                Expanded(
                  child: _PriceItem(
                    label: 'Số lượt đấu giá',
                    value: '${auction.bidCount}',
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBidHistory(auction) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lịch sử đấu giá (${auction.bidCount})',
          style: AppTextStyles.h4.copyWith(color: AppColors.accent),
        ),
        const SizedBox(height: 12),
        if (auction.bids.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.history, size: 48, color: AppColors.grey),
                  const SizedBox(height: 12),
                  Text(
                    'Chưa có lượt đấu giá nào',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.grey,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: auction.bids.length,
            itemBuilder: (context, index) {
              final bid = auction.bids[index];
              return BidHistoryCard(bid: bid, isHighest: index == 0);
            },
          ),
      ],
    );
  }

  void _showPlaceBidDialog(BuildContext context, auction) {
    final effectiveStatus = _resolveEffectiveStatus(auction);
    showDialog(
      context: context,
      builder: (dialogContext) => PlaceBidDialog(
        currentPrice: auction.currentPriceVnd,
        stepPrice: auction.stepPriceVnd,
        startTime: auction.startTime,
        formattedCurrentPrice: auction.formattedCurrentPrice,
        formattedStepPrice: auction.formattedStepPrice,
        endTime: auction.endTime,
        status: effectiveStatus,
        onPlaceBid: (amount) {
          context.read<AuctionDetailBloc>().add(
            PlaceBid(auctionId: widget.auctionId, amountVnd: amount),
          );
        },
      ),
    );
  }

  Widget? _buildFloatingActionButton(
    BuildContext context,
    AuctionDetailState state,
  ) {
    if (state is! AuctionDetailLoaded) return null;

    final auction = state.auction;
    final effectiveStatus = _resolveEffectiveStatus(auction);
    final isAuctionCreator = _isAuctionCreator(
      context,
      sellerId: auction.sellerId,
      sellerEmail: auction.sellerEmail,
      sellerName: auction.sellerName,
    );

    if (effectiveStatus == 'ACTIVE' && !isAuctionCreator) {
      return FloatingActionButton.extended(
        onPressed: () => _showPlaceBidDialog(context, auction),
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.gavel, color: AppColors.white),
        label: Text(
          'Đặt giá',
          style: AppTextStyles.labelLarge.copyWith(color: AppColors.white),
        ),
      );
    }

    if (effectiveStatus == 'APPROVED' && !isAuctionCreator) {
      return FloatingActionButton.extended(
        onPressed: null,
        backgroundColor: AppColors.grey,
        icon: const Icon(Icons.schedule, color: AppColors.white),
        label: Text(
          'Chưa tới giờ bắt đầu',
          style: AppTextStyles.labelLarge.copyWith(color: AppColors.white),
        ),
      );
    }

    if (auction.status == 'WAITING_CONFIRMATION' &&
        _isWinner(context, auction)) {
      return FloatingActionButton.extended(
        onPressed: () => _showConfirmDialog(context, auction),
        backgroundColor: AppColors.success,
        icon: const Icon(Icons.check_circle, color: AppColors.white),
        label: Text(
          'Da nhan duoc hang',
          style: AppTextStyles.labelLarge.copyWith(color: AppColors.white),
        ),
      );
    }

    if (auction.status == 'WAITING_CONFIRMATION' &&
        _isWinner(context, auction)) {
      return FloatingActionButton.extended(
        onPressed: () => _showConfirmDialog(context, auction),
        backgroundColor: AppColors.success,
        icon: const Icon(Icons.check_circle, color: AppColors.white),
        label: Text(
          'Xác nhận đã nhận hàng',
          style: AppTextStyles.labelLarge.copyWith(color: AppColors.white),
        ),
      );
    }

    if ((auction.status == 'SETTLED' || auction.status == 'CONFIRMED') &&
        _isWinner(context, auction)) {
      return FloatingActionButton.extended(
        onPressed: null,
        backgroundColor: AppColors.grey,
        icon: const Icon(Icons.check_circle_outline, color: AppColors.white),
        label: Text(
          'Đơn hàng đã được nhận',
          style: AppTextStyles.labelLarge.copyWith(color: AppColors.white),
        ),
      );
    }

    return null;
  }
}

class _PriceItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isHighlight;

  const _PriceItem({
    required this.label,
    required this.value,
    required this.color,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodyLarge.copyWith(
            color: color,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
            fontSize: isHighlight ? 20 : 16,
          ),
        ),
      ],
    );
  }
}
