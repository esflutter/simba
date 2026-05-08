import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_card.dart';
import '../../data/mock/app_state.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appControllerProvider.select((s) => s.user));
    if (user == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 47.h, 16.w, 8.h),
                child: Text(
                  'Профиль',
                  style: AppText.h1().copyWith(
                    height: 1.21,
                    letterSpacing: 0.40,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
              children: [
                AppCard(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      _Avatar(photoPath: user.photoPath),
                      InkResponse(
                        onTap: () => context.push('/profile/edit'),
                        child: Padding(
                          padding: EdgeInsets.all(4.r),
                          child: Icon(IconsaxPlusLinear.edit_2,
                              color: AppColors.primary, size: 22.r),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  Text(user.name.isEmpty ? 'Пользователь' : user.name, style: AppText.h4()),
                  if (user.rating > 0) ...[
                    SizedBox(height: 4.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(IconsaxPlusBold.star_1, color: AppColors.star, size: 18.r),
                        SizedBox(width: 4.w),
                        Text(
                          user.rating.toStringAsFixed(1).replaceAll('.', ','),
                          style: AppText.body(weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _MenuItem(
              icon: IconsaxPlusLinear.clipboard_text,
              label: 'История заказов',
              onTap: () => context.push('/profile/history'),
            ),
            SizedBox(height: 8.h),
            _MenuItem(
              icon: IconsaxPlusLinear.star,
              label: 'Отзывы',
              onTap: () => context.push('/profile/reviews'),
            ),
            SizedBox(height: 8.h),
            _MenuItem(
              icon: IconsaxPlusLinear.support,
              label: 'Связаться с нами',
              onTap: () => context.push('/profile/support'),
            ),
            SizedBox(height: 32.h),
            _MenuItem(
              icon: IconsaxPlusLinear.logout,
              label: 'Выйти из аккаунта',
              onTap: () => _confirmLogout(context, ref),
            ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text('Выйти из аккаунта?', style: AppText.h4()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Назад', style: AppText.body(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(appControllerProvider.notifier).logout();
              Navigator.of(context).pop();
              context.go('/onboarding');
            },
            child: Text('Выйти', style: AppText.body(color: AppColors.error, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.photoPath});
  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120.r,
      height: 120.r,
      decoration: const BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: photoPath != null
          ? Image.file(File(photoPath!), fit: BoxFit.cover)
          : Center(child: Icon(IconsaxPlusLinear.user, size: 80.r, color: AppColors.primary)),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22.r),
          SizedBox(width: 12.w),
          Expanded(child: Text(label, style: AppText.bodyLarge())),
          Icon(IconsaxPlusLinear.arrow_right_3, color: AppColors.primary, size: 22.r),
        ],
      ),
    );
  }
}
