import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
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
            Padding(
              padding: EdgeInsets.fromLTRB(8.w, 4.h, 8.w, 0),
              child: const AppBackButton(),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Column(
                  children: [
                    const Spacer(),
                    AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Image.asset(
                            'assets/images/role_hero.webp',
                            fit: BoxFit.contain,
                          ),
                          Padding(
                            padding: EdgeInsets.only(bottom: 8.h),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Text('Заказчик',
                                    style: AppText.body(
                                      color: AppColors.primary,
                                      weight: FontWeight.w700,
                                    )),
                                SizedBox(width: 60.w),
                                Text('Исполнитель',
                                    style: AppText.body(
                                      color: AppColors.primary,
                                      weight: FontWeight.w700,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              child: Column(
                children: [
                  _RoleCard(
                    title: 'Нужна помощь',
                    subtitle: 'Разместить заказ на услугу',
                    onTap: () {
                      ref.read(appControllerProvider.notifier).setRole(UserRole.customer);
                      context.go('/home/my');
                    },
                  ),
                  SizedBox(height: 12.h),
                  _RoleCard(
                    title: 'Готов помочь',
                    subtitle: 'Найти заказ на услугу',
                    onTap: () {
                      ref.read(appControllerProvider.notifier).setRole(UserRole.executor);
                      context.go('/home/orders');
                    },
                  ),
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
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.h4(color: AppColors.primary)),
                SizedBox(height: 4.h),
                Text(subtitle,
                    style: AppText.body(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Icon(IconsaxPlusLinear.arrow_right_3, color: AppColors.primary, size: 22.r),
        ],
      ),
    );
  }
}
