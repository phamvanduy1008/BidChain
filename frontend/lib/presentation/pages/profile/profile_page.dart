import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/routes/app_routes.dart';
import '../../../core/network/dio_client.dart';
import '../../widgets/text/expandable_text.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_state.dart';
import '../../bloc/auth/auth_event.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final DioClient _dioClient = DioClient();
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      final response = await _dioClient.get('/user/me/stats');
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _stats = response.data as Map<String, dynamic>;
        });
      }
    } catch (e) {
      debugPrint('Error fetching stats: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthInitialState) {
          context.go(AppRoutes.login);
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state is AuthSuccessState) {
            final user = state.user;

            return Scaffold(
              backgroundColor: AppColors.white,
              body: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // ==================== HEADER ====================
                      SizedBox(
                        height: 180,
                        child: Stack(
                          children: [
                            // Cover Background
                            Container(
                              height: 140,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.accent.withOpacity(0.9),
                                    AppColors.accent.withOpacity(0.65),
                                  ],
                                ),
                              ),
                            ),

                            // Avatar
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Center(
                                child: Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    CircleAvatar(
                                      radius: 58,
                                      backgroundColor: Colors.white,
                                      child: CircleAvatar(
                                        radius: 52,
                                        backgroundColor: AppColors.greyLight,
                                        backgroundImage: user.avatar != null &&
                                                user.avatar!.isNotEmpty
                                            ? NetworkImage(user.avatar!)
                                            : null,
                                        child: (user.avatar == null ||
                                                user.avatar!.isEmpty)
                                            ? const Icon(
                                                Icons.person_rounded,
                                                size: 55,
                                                color: AppColors.accent,
                                              )
                                            : null,
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 6,
                                      right: 6,
                                      child: GestureDetector(
                                        onTap: () =>
                                            context.push(AppRoutes.editProfile),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: AppColors.accent,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 3,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.25),
                                                blurRadius: 8,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.edit,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Username
                      Text(
                        user.username,
                        style: AppTextStyles.h2.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      // Location
                      if (user.city != null ||
                          user.district != null ||
                          user.ward != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 18,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  [
                                    user.ward,
                                    user.district,
                                    user.city,
                                  ].whereType<String>().join(', '),
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.grey,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 24),

                      // Bio Section
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Giới thiệu',
                              style: AppTextStyles.h4.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: ExpandableInlineText(
                                text: user.bio?.isNotEmpty == true
                                    ? user.bio!
                                    : user.fullName.isNotEmpty
                                        ? user.fullName
                                        : 'Chưa có mô tả',
                                maxLines: 4,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  height: 1.6,
                                  color: AppColors.greyDark,
                                ),
                                readMoreStyle: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Stats Section
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thống kê',
                              style: AppTextStyles.h4.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 1.12,
                              children: [
                                _buildStatCard(
                                  Icons.gavel_rounded,
                                  '${_stats?['auctions'] ?? 0}',
                                  'Phiên đấu giá',
                                ),
                                _buildStatCard(
                                  Icons.local_offer_rounded,
                                  '${_stats?['bids'] ?? 0}',
                                  'Lượt đặt giá',
                                ),
                                _buildStatCard(
                                  Icons.emoji_events_rounded,
                                  '${_stats?['wins'] ?? 0}',
                                  'Đã thắng',
                                ),
                                _buildStatCard(
                                  Icons.percent_rounded,
                                  '${_stats?['successRate'] ?? 0}%',
                                  'Tỷ lệ thành công',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Logout Button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: TextButton.icon(
                            icon: const Icon(Icons.logout_rounded,
                                color: Colors.redAccent),
                            label: Text(
                              'Đăng xuất',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: AppColors.error.withOpacity(0.08),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: AppColors.error.withOpacity(0.3),
                                ),
                              ),
                            ),
                            onPressed: () => _showLogoutConfirmDialog(context),
                          ),
                        ),
                      ),

                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              ),
            );
          }

          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }

  // Stat Card Widget
  Widget _buildStatCard(IconData icon, String value, String label) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: AppColors.accent),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTextStyles.h2.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.grey,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Đăng xuất',
          style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Bạn có chắc chắn muốn đăng xuất khỏi tài khoản?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Hủy',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.grey,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthBloc>().add(const AuthLogoutEvent());
            },
            child: Text(
              'Đăng xuất',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
