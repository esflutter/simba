import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_card.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';

class RolePickerScreen extends ConsumerWidget {
  const RolePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: const Alignment(0, 0.5),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image.asset(
                      'assets/images/role_hero.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RoleCard(
                    title: 'Нужна помощь',
                    subtitle: 'Разместить заказ на услугу',
                    onTap: () {
                      ref.read(appControllerProvider.notifier).setRole(UserRole.customer);
                      context.go('/home/my');
                    },
                  ),
                  SizedBox(height: 8.h),
                  _RoleCard(
                    title: 'Готов помочь',
                    subtitle: 'Найти заказ на услугу',
                    onTap: () {
                      ref.read(appControllerProvider.notifier).setRole(UserRole.executor);
                      context.go('/home/orders');
                    },
                  ),
                  SizedBox(height: 66.h),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.title, required this.subtitle, required this.onTap});
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      padding: EdgeInsets.only(top: 16.h, left: 24.w, right: 24.w, bottom: 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.h4(color: AppColors.primary)),
          SizedBox(height: 12.h),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$subtitle ',
                  style: AppText.body(color: Colors.black.withValues(alpha: 0.60))
                      .copyWith(height: 1.39),
                ),
                TextSpan(
                  text: '→',
                  style: AppText.body(color: AppColors.primary).copyWith(height: 1.39),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
