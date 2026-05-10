import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/mock/app_state.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final user = state.user;
    if (user == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    // Считаем рейтинг из реальных отзывов на «me», а не из user.rating
    // (он у новых пользователей 0).
    final myReviews = state.reviews.where((r) => r.toUserId == 'me').toList();
    final computedRating = myReviews.isEmpty
        ? 0.0
        : myReviews.map((r) => r.rating).reduce((a, b) => a + b) /
            myReviews.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
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
          // ── Body ──
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
              children: [
                _ProfileCard(
                  user: user,
                  rating: computedRating,
                  reviewsCount: myReviews.length,
                  onEdit: () => context.push('/profile/edit'),
                ),
                SizedBox(height: 16.h),
                _MenuItem(
                  icon: IconsaxPlusLinear.clipboard_text,
                  label: 'История заказов',
                  onTap: () => context.push('/profile/history'),
                ),
                SizedBox(height: 8.h),
                _MenuItem(
                  iconAsset: 'assets/images/icon_star_outline.webp',
                  label: 'Отзывы',
                  onTap: () => context.push('/profile/reviews'),
                ),
                SizedBox(height: 8.h),
                _MenuItem(
                  iconAsset: 'assets/images/icon_support.webp',
                  label: 'Связаться с нами',
                  onTap: () => _showContactSheet(context),
                ),
                SizedBox(height: 8.h),
                _MenuItem(
                  icon: IconsaxPlusLinear.logout,
                  label: 'Выйти из аккаунта',
                  onTap: () => _confirmLogout(context, ref),
                ),
                SizedBox(height: 8.h),
                _MenuItem(
                  icon: IconsaxPlusLinear.trash,
                  label: 'Удалить аккаунт',
                  onTap: () => _confirmDeleteAccount(context, ref),
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
      barrierColor: Colors.black.withValues(alpha: 0.20),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Container(
          width: 313.w,
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                IconsaxPlusLinear.logout,
                color: AppColors.primary,
                size: 56.r,
              ),
              SizedBox(height: 16.h),
              Text(
                'Вы уверены, что хотите выйти из аккаунта?',
                textAlign: TextAlign.center,
                style: AppText.h3(color: const Color(0xFF111827))
                    .copyWith(height: 1.40),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Column(
                  children: [
                    _LogoutDialogButton(
                      label: 'Выйти',
                      background: AppColors.primary,
                      textColor: Colors.white,
                      onTap: () {
                        ref.read(appControllerProvider.notifier).logout();
                        Navigator.of(dialogCtx).pop();
                        context.go('/onboarding');
                      },
                    ),
                    SizedBox(height: 8.h),
                    _LogoutDialogButton(
                      label: 'Отмена',
                      background: AppColors.surfaceVariant,
                      textColor: const Color(0xFF111827),
                      onTap: () => Navigator.of(dialogCtx).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showContactSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SupportSheet(),
    );
  }

  void _confirmDeleteAccount(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.20),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Container(
          width: 313.w,
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                IconsaxPlusLinear.trash,
                color: AppColors.primary,
                size: 56.r,
              ),
              SizedBox(height: 16.h),
              Text(
                'Удалить аккаунт?',
                textAlign: TextAlign.center,
                style: AppText.h3(color: const Color(0xFF111827))
                    .copyWith(height: 1.40),
              ),
              SizedBox(height: 8.h),
              Text(
                'Все ваши данные, заказы и отзывы будут безвозвратно удалены',
                textAlign: TextAlign.center,
                style: AppText.body().copyWith(
                  fontSize: 15.sp,
                  color: Colors.black.withValues(alpha: 0.60),
                  height: 1.33,
                ),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Column(
                  children: [
                    _LogoutDialogButton(
                      label: 'Удалить',
                      background: AppColors.primary,
                      textColor: Colors.white,
                      onTap: () {
                        // TODO: реальное удаление аккаунта (Supabase RPC).
                        // Пока имитируем выходом — данные локального mock-стейта
                        // не сохранятся между запусками.
                        ref.read(appControllerProvider.notifier).logout();
                        Navigator.of(dialogCtx).pop();
                        context.go('/onboarding');
                      },
                    ),
                    SizedBox(height: 8.h),
                    _LogoutDialogButton(
                      label: 'Отмена',
                      background: AppColors.surfaceVariant,
                      textColor: const Color(0xFF111827),
                      onTap: () => Navigator.of(dialogCtx).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.user,
    required this.rating,
    required this.reviewsCount,
    required this.onEdit,
  });
  final dynamic user;
  final double rating;
  final int reviewsCount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final hasTools = user.hasTools as bool;
    final hasTransport = user.hasTransport as bool;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
      ),
      padding: EdgeInsets.symmetric(vertical: 16.h),
      child: Stack(
        children: [
          Column(
            children: [
              _Avatar(photoPath: user.photoPath as String?),
              SizedBox(height: 16.h),
              Text(
                (user.name as String).isEmpty ? 'Пользователь' : user.name as String,
                textAlign: TextAlign.center,
                style: AppText.h3().copyWith(height: 1.10),
              ),
              if ((user.phone as String).isNotEmpty) ...[
                SizedBox(height: 4.h),
                Text(
                  user.phone as String,
                  textAlign: TextAlign.center,
                  style: AppText.bodySmall().copyWith(
                    color: Colors.black.withValues(alpha: 0.60),
                    height: 1.57,
                  ),
                ),
              ],
              SizedBox(height: 4.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (hasTools) ...[
                    Image.asset(
                      'assets/images/icon_tools.png',
                      width: 16.r,
                      height: 16.r,
                    ),
                    SizedBox(width: 24.w),
                  ],
                  if (hasTransport) ...[
                    Image.asset(
                      'assets/images/icon_transport.png',
                      width: 20.r,
                      height: 16.r,
                    ),
                    SizedBox(width: 24.w),
                  ],
                  Image.asset(
                    'assets/images/icon_ranking.webp',
                    width: 16.r,
                    height: 16.r,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    reviewsCount == 0
                        ? '—'
                        : rating.toStringAsFixed(1).replaceAll('.', ','),
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall(weight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 4.w,
            top: -8.h,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onEdit,
                child: Padding(
                  padding: EdgeInsets.all(12.r),
                  child: Image.asset(
                    'assets/images/icon_edit.webp',
                    width: 24.r,
                    height: 24.r,
                  ),
                ),
              ),
            ),
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
      width: 100.r,
      height: 100.r,
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: photoPath != null
          ? Image.file(File(photoPath!), fit: BoxFit.cover)
          : Center(
              child: Icon(IconsaxPlusLinear.user, size: 64.r, color: AppColors.primary),
            ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    this.icon,
    this.iconAsset,
    required this.label,
    required this.onTap,
  }) : assert(icon != null || iconAsset != null,
            'either icon or iconAsset must be provided');

  final IconData? icon;
  final String? iconAsset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          height: 56.h,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                SizedBox(
                  width: 24.r,
                  height: 24.r,
                  child: iconAsset != null
                      ? Image.asset(iconAsset!, width: 24.r, height: 24.r)
                      : Icon(icon, color: AppColors.primary, size: 24.r),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Text(
                    label,
                    style: AppText.body(weight: FontWeight.w500)
                        .copyWith(height: 1.50),
                  ),
                ),
                SizedBox(width: 16.w),
                Icon(
                  IconsaxPlusLinear.arrow_right_3,
                  color: AppColors.primary,
                  size: 24.r,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoutDialogButton extends StatelessWidget {
  const _LogoutDialogButton({
    required this.label,
    required this.background,
    required this.textColor,
    required this.onTap,
  });
  final String label;
  final Color background;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 36.h,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 17.sp,
                fontWeight: FontWeight.w600,
                height: 1.29,
                letterSpacing: -0.40,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportSheet extends StatelessWidget {
  const _SupportSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(15.r)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(
                    'assets/images/icon_support.webp',
                    width: 24.r,
                    height: 24.r,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Связаться с нами',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.29,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: EdgeInsets.all(6.r),
                      child: Icon(
                        Icons.close_rounded,
                        color: AppColors.primary,
                        size: 20.r,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              Container(height: 1, color: AppColors.divider),
              SizedBox(height: 22.h),
              Row(
                children: [
                  _SupportMessenger(
                    label: 'WhatsApp',
                    asset: 'assets/images/icon_whatsapp.webp',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  SizedBox(width: 28.w),
                  _SupportMessenger(
                    label: 'Telegram',
                    asset: 'assets/images/icon_telegram.webp',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  SizedBox(width: 28.w),
                  _SupportMessenger(
                    label: 'MAX',
                    asset: 'assets/images/icon_max.webp',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportMessenger extends StatelessWidget {
  const _SupportMessenger({
    required this.label,
    required this.asset,
    required this.onTap,
  });

  final String label;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(asset, width: 60.r, height: 60.r),
          SizedBox(height: 5.h),
          Text(
            label,
            style: TextStyle(
              color: Colors.black,
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              height: 1.18,
            ),
          ),
        ],
      ),
    );
  }
}
