import 'dart:async';
import 'dart:math';

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
import '../../bloc/notification/notification_bloc.dart';
import '../../widgets/auction/auction_card.dart';
import '../../widgets/common/category_chip.dart';
import '../../widgets/common/section_header.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final Random _random = Random();
  final TextEditingController _searchController = TextEditingController();

  String? _selectedCategoryId;
  String _searchQuery = '';
  DateTime? _lastRefreshTime;
  static const _refreshThreshold = Duration(minutes: 5);
  StreamSubscription<Map<String, dynamic>>? _auctionEventSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastRefreshTime = DateTime.now();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });

    final socketService = SocketService();
    _auctionEventSubscription = socketService.auctionEventStream.listen((_) {
      if (mounted) {
        context.read<AuctionBloc>().add(RefreshAuctions());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _auctionEventSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshIfNeeded();
    }
  }

  void _refreshIfNeeded() {
    final now = DateTime.now();
    if (_lastRefreshTime == null ||
        now.difference(_lastRefreshTime!) > _refreshThreshold) {
      context.read<AuctionBloc>().add(RefreshAuctions());
      context.read<CategoryBloc>().add(GetCategories());
      _lastRefreshTime = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<AuctionBloc>().add(RefreshAuctions());
          context.read<CategoryBloc>().add(GetCategories());
          _lastRefreshTime = DateTime.now();
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
                final filteredAuctions = state is AuctionLoaded
                    ? _filterAuctions(state.auctions)
                    : <dynamic>[];
                final randomAuctions = _pickRandomAuctions(filteredAuctions, 4);

                return SliverToBoxAdapter(
                  child: _buildHorizontalAuctionSection(
                    title: 'Các phiên đấu giá',
                    auctions: randomAuctions,
                    state: state,
                    seeAllRoute: AppRoutes.auctionList,
                    emptyMessage: _buildAllAuctionsEmptyMessage(),
                  ),
                );
              },
            ),
            _buildAuctionGridSection(
              title: 'Phiên đang diễn ra',
              seeAllRoute: '${AppRoutes.auctionList}?status=active',
              emptyMessage: _buildSectionEmptyMessageByType('active'),
              auctionSelector: (loadedState) =>
                  _filterAuctions(loadedState.activeAuctions),
            ),
            _buildAuctionGridSection(
              title: 'Phiên sắp diễn ra',
              seeAllRoute: '${AppRoutes.auctionList}?status=upcoming',
              emptyMessage: _buildSectionEmptyMessageByType('upcoming'),
              auctionSelector: (loadedState) => _filterAuctions(
                loadedState.auctions.where((auction) {
                  return auction.status.toUpperCase() == 'APPROVED';
                }).toList(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        'BidChain',
        style: AppTextStyles.h2.copyWith(
          color: AppColors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: AppColors.white,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      actions: [
        BlocBuilder<NotificationBloc, NotificationState>(
          builder: (context, state) {
            return IconButton(
              icon: Badge(
                backgroundColor: Colors.red,
                isLabelVisible: state.unreadCount > 0,
                label: Text('${state.unreadCount}'),
                child: const Icon(
                  Icons.notifications_outlined,
                  color: AppColors.black,
                ),
              ),
              onPressed: () {
                context.push(AppRoutes.notifications);
              },
            );
          },
        ),
      ],
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

  Widget _buildHorizontalAuctionSection({
    required String title,
    required List<dynamic> auctions,
    required AuctionState state,
    required String emptyMessage,
    required String seeAllRoute,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(
            title: title,
            onSeeAllTap: () => context.go(seeAllRoute),
          ),
        ),
        const SizedBox(height: 16),
        if (state is AuctionLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: CircularProgressIndicator(color: AppColors.black),
          )
        else if (auctions.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _buildSectionEmptyState(emptyMessage),
          )
        else
          SizedBox(
            height: 310,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: auctions.length,
              itemBuilder: (context, index) {
                final auction = auctions[index];
                return Container(
                  width: 180,
                  margin: EdgeInsets.only(
                    right: index < auctions.length - 1 ? 12 : 0,
                  ),
                  child: _buildAuctionCard(auction),
                );
              },
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildAuctionGridSection({
    required String title,
    required String seeAllRoute,
    required String emptyMessage,
    required List<dynamic> Function(AuctionLoaded) auctionSelector,
  }) {
    return BlocBuilder<AuctionBloc, AuctionState>(
      builder: (context, state) {
        if (state is AuctionLoading) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.black),
              ),
            ),
          );
        }

        if (state is AuctionError) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Column(
                children: [
                  _buildSectionHeader(title, seeAllRoute),
                  const SizedBox(height: 16),
                  _buildSectionEmptyState(state.message),
                ],
              ),
            ),
          );
        }

        if (state is AuctionLoaded) {
          final auctions = auctionSelector(state);

          return SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    title: title,
                    onSeeAllTap: () => context.go(seeAllRoute),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              if (auctions.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    child: _buildSectionEmptyState(emptyMessage),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.57,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final auction = auctions[index];
                      return _buildAuctionCard(auction);
                    }, childCount: auctions.length),
                  ),
                ),
            ],
          );
        }

        return const SliverToBoxAdapter(child: SizedBox.shrink());
      },
    );
  }

  Widget _buildSectionHeader(String title, String route) {
    return SectionHeader(
      title: title,
      onSeeAllTap: () => context.go(route),
    );
  }

  Widget _buildSectionEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.greyLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.tertiary),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, color: AppColors.grey, size: 32),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAuctionCard(dynamic auction) {
    return AuctionCard(
      auctionId: auction.auctionId,
      title: auction.title,
      imageUrl: auction.images.isNotEmpty ? auction.images.first : null,
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
        context.go('${AppRoutes.auctionDetail}/${auction.auctionId}');
      },
    );
  }

  List<dynamic> _filterAuctions(List<dynamic> auctions) {
    var filteredAuctions = List.of(auctions);

    if (_selectedCategoryId != null) {
      filteredAuctions = filteredAuctions
          .where((auction) => auction.categoryId == _selectedCategoryId)
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

    return filteredAuctions;
  }

  String _buildAllAuctionsEmptyMessage() {
    if (_searchQuery.isNotEmpty) {
      return 'Chưa có phiên đấu giá phù hợp với từ khóa tìm kiếm';
    }
    if (_selectedCategoryId != null) {
      return 'Chưa có phiên đấu giá trong danh mục này';
    }
    return 'Hiện chưa có phiên đấu giá nào';
  }

  String _buildSectionEmptyMessageByType(String type) {
    if (_searchQuery.isNotEmpty) {
      return 'Không tìm thấy phiên đấu giá cho "$_searchQuery"';
    }
    if (_selectedCategoryId != null) {
      return 'Không có phiên đấu giá nào trong danh mục này';
    }
    if (type == 'upcoming') {
      return 'Hiện chưa có phiên đấu giá sắp diễn ra';
    }
    return 'Hiện chưa có phiên đấu giá đang diễn ra';
  }

  IconData _getCategoryIcon(String categoryName) {
    final name = categoryName.toLowerCase();

    if (name.contains('điện tử') ||
        name.contains('điện thoại') ||
        name.contains('laptop')) {
      return Icons.devices;
    } else if (name.contains('thời trang') ||
        name.contains('quần áo') ||
        name.contains('giày')) {
      return Icons.checkroom;
    } else if (name.contains('nghệ thuật') ||
        name.contains('tranh') ||
        name.contains('tác phẩm')) {
      return Icons.palette;
    } else if (name.contains('đồ cổ') || name.contains('sưu tầm')) {
      return Icons.stars;
    } else if (name.contains('xe') ||
        name.contains('phương tiện') ||
        name.contains('ô tô') ||
        name.contains('xe máy')) {
      return Icons.directions_car;
    } else if (name.contains('thủ công') ||
        name.contains('mỹ nghệ') ||
        name.contains('handmade') ||
        name.contains('gốm')) {
      return Icons.handyman;
    } else if (name.contains('sách') || name.contains('book')) {
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

  List<dynamic> _pickRandomAuctions(List<dynamic> auctions, int count) {
    final shuffled = List.of(auctions)..shuffle(_random);
    return shuffled.take(count).toList();
  }
}
