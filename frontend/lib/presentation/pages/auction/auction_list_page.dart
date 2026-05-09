import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes/app_routes.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/services/server_time_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/utils/app_localizations.dart';
import '../../../core/utils/auction_status_resolver.dart';
import '../../bloc/auction/auction_bloc.dart';
import '../../bloc/auction/auction_event.dart';
import '../../bloc/auction/auction_state.dart';
import '../../bloc/category/category_bloc.dart';
import '../../bloc/category/category_event.dart';
import '../../bloc/category/category_state.dart';
import '../../widgets/auction/auction_card.dart';
import '../../widgets/common/category_chip.dart';

class AuctionListPage extends StatefulWidget {
  final String? statusFilter;

  const AuctionListPage({super.key, this.statusFilter});

  @override
  State<AuctionListPage> createState() => _AuctionListPageState();
}

class _AuctionListPageState extends State<AuctionListPage> {
  final SocketService _socketService = SocketService();
  final TextEditingController _searchController = TextEditingController();

  String? _selectedCategoryId;
  String _searchQuery = '';
  StreamSubscription<Map<String, dynamic>>? _auctionEventSubscription;

  @override
  void initState() {
    super.initState();
    _auctionEventSubscription = _socketService.auctionEventStream.listen((_) {
      if (mounted) {
        context.read<AuctionBloc>().add(RefreshAuctions());
      }
    });

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _auctionEventSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<AuctionBloc>().add(RefreshAuctions());
          context.read<CategoryBloc>().add(GetCategories());
        },
        color: AppColors.black,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildSearchBar(),
              ),
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Danh mục',
                      style: AppTextStyles.h3.copyWith(
                        color: AppColors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCategoryList(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            BlocBuilder<AuctionBloc, AuctionState>(
              builder: (context, state) {
                if (state is AuctionLoading) {
                  return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (state is AuctionError) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: AppColors.black,
                          ),
                          const SizedBox(height: 16),
                          Text(state.message, style: AppTextStyles.bodyMedium),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              context.read<AuctionBloc>().add(RefreshAuctions());
                            },
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (state is AuctionLoaded) {
                  var filteredAuctions = _filterAuctionsByStatus(state.auctions);

                  if (_selectedCategoryId != null) {
                    filteredAuctions = filteredAuctions
                        .where(
                          (auction) =>
                              auction.categoryId == _selectedCategoryId,
                        )
                        .toList();
                  }

                  if (_searchQuery.isNotEmpty) {
                    filteredAuctions = filteredAuctions.where((auction) {
                      final titleLower = auction.title.toLowerCase();
                      final descLower = auction.description.toLowerCase();
                      return titleLower.contains(_searchQuery) ||
                          descLower.contains(_searchQuery);
                    }).toList();
                  }

                  if (filteredAuctions.isEmpty) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 64,
                              color: AppColors.grey.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _buildEmptyMessage(),
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.6,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final auction = filteredAuctions[index];
                        return AuctionCard(
                          auctionId: auction.auctionId,
                          title: auction.title,
                          imageUrl: auction.images.isNotEmpty
                              ? auction.images.first
                              : null,
                          currentBid: auction.formattedCurrentPrice,
                          timeLeft: _calculateTimeLeft(
                            auction.startTime,
                            auction.endTime,
                            auction.status,
                          ),
                          status: resolveAuctionStatus(
                            status: auction.status,
                            startTime: auction.startTime,
                            endTime: auction.endTime,
                          ),
                          bidCount: auction.bidCount,
                          sellerName: auction.sellerName,
                          onTap: () {
                            context.go(
                              '${AppRoutes.auctionDetail}/${auction.auctionId}',
                            );
                          },
                        );
                      }, childCount: filteredAuctions.length),
                    ),
                  );
                }

                return const SliverToBoxAdapter(child: SizedBox.shrink());
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        _getPageTitle(),
        style: AppTextStyles.h2.copyWith(
          color: AppColors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: AppColors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: AppColors.black,
          size: 20,
        ),
        onPressed: () => context.go(AppRoutes.home),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.black, width: 1.5),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Tìm kiếm phiên đấu giá...',
          hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey),
          prefixIcon: const Icon(Icons.search, color: AppColors.black),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppColors.grey),
                  onPressed: _searchController.clear,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return BlocBuilder<CategoryBloc, CategoryState>(
      builder: (context, state) {
        if (state is CategoryLoaded) {
          final allCategories = [
            {'id': null, 'name': 'Tất cả', 'icon': Icons.apps},
            ...state.categories.map(
              (cat) => {
                'id': cat.id,
                'name': cat.name,
                'icon': _getCategoryIcon(cat.name),
              },
            ),
          ];

          return SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: allCategories.length,
              itemBuilder: (context, index) {
                final category = allCategories[index];
                final isSelected = _selectedCategoryId == category['id'];

                return Padding(
                  padding: EdgeInsets.only(
                    right: index < allCategories.length - 1 ? 8 : 0,
                  ),
                  child: CategoryChip(
                    label: category['name'] as String,
                    icon: category['icon'] as IconData?,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() {
                        _selectedCategoryId = category['id'] as String?;
                      });
                    },
                  ),
                );
              },
            ),
          );
        }

        if (state is CategoryLoading) {
          return const SizedBox(
            height: 50,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        return SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              CategoryChip(
                label: 'Tất cả',
                icon: Icons.apps,
                isSelected: _selectedCategoryId == null,
                onTap: () {
                  setState(() {
                    _selectedCategoryId = null;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  List<dynamic> _filterAuctionsByStatus(List<dynamic> auctions) {
    switch (widget.statusFilter?.toLowerCase()) {
      case 'active':
        return auctions.where((auction) {
          final effectiveStatus = resolveAuctionStatus(
            status: auction.status,
            startTime: auction.startTime,
            endTime: auction.endTime,
          );
          return effectiveStatus == 'ACTIVE';
        }).toList();
      case 'upcoming':
        return auctions
            .where((auction) => auction.status.toUpperCase() == 'APPROVED')
            .toList();
      default:
        return List<dynamic>.from(auctions);
    }
  }

  String _getPageTitle() {
    switch (widget.statusFilter?.toLowerCase()) {
      case 'active':
        return 'Phiên đang diễn ra';
      case 'upcoming':
        return 'Phiên sắp diễn ra';
      default:
        return 'Tất cả phiên đấu giá';
    }
  }

  String _buildEmptyMessage() {
    if (_searchQuery.isNotEmpty) {
      return 'Không tìm thấy phiên đấu giá cho "$_searchQuery"';
    }

    if (_selectedCategoryId != null) {
      return 'Không có phiên đấu giá nào trong danh mục này';
    }

    switch (widget.statusFilter?.toLowerCase()) {
      case 'active':
        return 'Hiện chưa có phiên đấu giá đang diễn ra';
      case 'upcoming':
        return 'Hiện chưa có phiên đấu giá sắp diễn ra';
      default:
        return 'Hiện chưa có phiên đấu giá nào';
    }
  }

  IconData _getCategoryIcon(String categoryName) {
    final name = categoryName.toLowerCase();

    if (name.contains('điện tử') ||
        name.contains('điện thoại') ||
        name.contains('laptop')) {
      return Icons.devices;
    }
    if (name.contains('thời trang') ||
        name.contains('quần áo') ||
        name.contains('giày')) {
      return Icons.checkroom;
    }
    if (name.contains('nghệ thuật') ||
        name.contains('tranh') ||
        name.contains('tác phẩm')) {
      return Icons.palette;
    }
    if (name.contains('đồ cổ') || name.contains('sưu tầm')) {
      return Icons.stars;
    }
    if (name.contains('xe') ||
        name.contains('phương tiện') ||
        name.contains('ô tô') ||
        name.contains('xe máy')) {
      return Icons.directions_car;
    }
    if (name.contains('thủ công') ||
        name.contains('mỹ nghệ') ||
        name.contains('handmade') ||
        name.contains('gốm')) {
      return Icons.handyman;
    }
    if (name.contains('sách') || name.contains('book')) {
      return Icons.book;
    }

    return Icons.category;
  }

  String _calculateTimeLeft(
    DateTime? startTime,
    DateTime endTime,
    String status,
  ) {
    final now = ServerTimeService().now;
    final effectiveStatus = resolveAuctionStatus(
      status: status,
      startTime: startTime,
      endTime: endTime,
      now: now,
    );

    if (effectiveStatus == 'APPROVED' &&
        startTime != null &&
        now.isBefore(startTime)) {
      return 'Bắt đầu ${AppLocalizations.formatTimeLeft(startTime)}';
    }

    return AppLocalizations.formatTimeLeft(endTime);
  }
}
