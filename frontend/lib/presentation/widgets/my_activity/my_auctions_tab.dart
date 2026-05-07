import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/auction_status_resolver.dart';
import '../../../domain/entities/my_auction_entity.dart';
import '../common/empty_state.dart';
import 'my_auction_card.dart';

class MyAuctionsTab extends StatelessWidget {
  final List<MyAuctionEntity> auctions;
  final VoidCallback onRefresh;
  final Function(String) onAuctionTap;

  const MyAuctionsTab({
    super.key,
    required this.auctions,
    required this.onRefresh,
    required this.onAuctionTap,
  });

  /// Filters auctions to remove duplicates, prioritizing approved statuses over pending
  /// Groups by product identity (title + category) since each approval creates a new auction record
  List<MyAuctionEntity> _filterAuctions(List<MyAuctionEntity> auctions) {
    // Group auctions by product identity (same product can have multiple auction records)
    // Use title as the unique identifier for the same product
    final Map<String, List<MyAuctionEntity>> groupedByProduct = {};
    
    for (var auction in auctions) {
      // Create a composite key: title (normalize to avoid case/spacing issues)
      final productKey = auction.title.trim().toLowerCase();
      
      if (!groupedByProduct.containsKey(productKey)) {
        groupedByProduct[productKey] = [];
      }
      groupedByProduct[productKey]!.add(auction);
    }
    
    // For each product group, prioritize approved statuses
    final List<MyAuctionEntity> filtered = [];
    
    groupedByProduct.forEach((productKey, auctionGroup) {
      final sortedGroup = [...auctionGroup];
      int priority(MyAuctionEntity auction) {
        final effectiveStatus = resolveAuctionStatus(
          status: auction.status,
          endTime: auction.endTime,
        );
        switch (effectiveStatus) {
          case 'ACTIVE':
            return 0;
          case 'APPROVED':
            return 1;
          case 'ENDED':
          case 'SETTLED':
            return 2;
          default:
            return 3;
        }
      }

      sortedGroup.sort((a, b) => priority(a).compareTo(priority(b)));

      // Priority order: ACTIVE > APPROVED > ENDED > PENDING_APPROVAL
      MyAuctionEntity? selectedAuction;
      
      // Try to find ACTIVE first
      selectedAuction = sortedGroup.firstWhere(
        (a) => resolveAuctionStatus(
              status: a.status,
              endTime: a.endTime,
            ) ==
            'ACTIVE',
        orElse: () => sortedGroup.first,
      );
      
      // If no ACTIVE, try APPROVED
      if (resolveAuctionStatus(
            status: selectedAuction.status,
            endTime: selectedAuction.endTime,
          ) !=
          'ACTIVE') {
        selectedAuction = sortedGroup.firstWhere(
          (a) => resolveAuctionStatus(
                status: a.status,
                endTime: a.endTime,
              ) ==
              'APPROVED',
          orElse: () => selectedAuction!,
        );
      }
      
      // If no ACTIVE/APPROVED, try ENDED
      final selectedEffectiveStatus = resolveAuctionStatus(
        status: selectedAuction.status,
        endTime: selectedAuction.endTime,
      );
      if (selectedEffectiveStatus != 'ACTIVE' &&
          selectedEffectiveStatus != 'APPROVED') {
        selectedAuction = sortedGroup.firstWhere(
          (a) => resolveAuctionStatus(
                status: a.status,
                endTime: a.endTime,
              ) ==
              'ENDED',
          orElse: () => selectedAuction!,
        );
      }
      
      // Otherwise, take the first PENDING_APPROVAL (or any remaining)
      filtered.add(selectedAuction);
    });
    
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    // Filter auctions to prioritize active status
    final filteredAuctions = _filterAuctions(auctions);
    
    if (filteredAuctions.isEmpty) {
      return EmptyState(
        icon: Icons.gavel_outlined,
        title: 'Chưa có đấu giá',
        message:
            'Bạn chưa tạo phiên đấu giá nào.\nHãy tạo phiên đấu giá đầu tiên của bạn!',
        actionLabel: 'Tạo đấu giá',
        onAction: () {
          // Navigate to create auction page
          context.go('/create-auction');
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        onRefresh();
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredAuctions.length,
        itemBuilder: (context, index) {
          final auction = filteredAuctions[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: MyAuctionCard(
              auction: auction,
              onTap: () => onAuctionTap(auction.id),
            ),
          );
        },
      ),
    );
  }
}
