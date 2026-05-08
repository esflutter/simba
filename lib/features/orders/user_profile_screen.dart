import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../data/mock/app_state.dart';

class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId, this.orderId});
  final String userId;
  final String? orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = userById(userId);
    final allReviews = ref.watch(appControllerProvider).reviews;
    final reviews = allReviews
        .where((r) => r.toUserId == userId || r.toUserId == 'me')
        .toList();
    final accepted = orderId != null;

    final ratingDistribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in reviews) {
      ratingDistribution[r.rating] = (ratingDistribution[r.rating] ?? 0) + 1;
    }
    final maxCount = ratingDistribution.values.fold<int>(
      0,
      (p, c) => c > p ? c : p,
    );
    final avgRating = reviews.isEmpty
        ? user.rating
        : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              child: const AppBackButton(),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                children: [
                  AppCard(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                    child: Row(
                      children: [
                        Container(
                          width: 56.r,
                          height: 56.r,
                          decoration: const BoxDecoration(
                            color: AppColors.background,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            IconsaxPlusLinear.user,
                            color: AppColors.primary,
                            size: 32.r,
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (accepted)
                                Container(
                                  margin: EdgeInsets.only(bottom: 4.h),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.w,
                                    vertical: 2.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(16.r),
                                  ),
                                  child: Text(
                                    'Исполнитель принят',
                                    style: AppText.caption(
                                      color: Colors.white,
                                      weight: FontWeight.w500,
                                    ).copyWith(height: 1.33),
                                  ),
                                ),
                              Text(
                                user.name,
                                style: AppText.h3().copyWith(height: 1.20),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                user.phone,
                                style: AppText.body(weight: FontWeight.w600)
                                    .copyWith(height: 1.50),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Expanded(
                        child: _ContactButton(
                          label: 'Написать',
                          icon: IconsaxPlusLinear.message_text_1,
                          background: AppColors.surface,
                          color: AppColors.textPrimary,
                          onTap: () => _showContactSheet(context, user.phone),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: _ContactButton(
                          label: 'Позвонить',
                          icon: IconsaxPlusLinear.call,
                          background: AppColors.primary,
                          color: Colors.white,
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  Padding(
                    padding: EdgeInsets.only(left: 4.w),
                    child: Text(
                      'Отзывы',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        height: 1.54,
                      ),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  if (reviews.isEmpty)
                    AppCard(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32.h),
                        child: Column(
                          children: [
                            Icon(
                              IconsaxPlusLinear.star,
                              size: 56.r,
                              color: AppColors.textTertiary,
                            ),
                            SizedBox(height: 12.h),
                            Text(
                              'Нет отзывов',
                              style: AppText.body(color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    AppCard(
                      child: _RatingSummary(
                        average: avgRating,
                        total: reviews.length,
                        distribution: ratingDistribution,
                        maxCount: maxCount,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    ...reviews.map(
                      (r) => Padding(
                        padding: EdgeInsets.only(bottom: 8.h),
                        child: AppCard(
                          padding: EdgeInsets.all(12.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16.r,
                                    backgroundColor: AppColors.primarySoft,
                                    child: Icon(
                                      IconsaxPlusLinear.user,
                                      color: AppColors.primary,
                                      size: 18.r,
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    userById(r.fromUserId).name,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w600,
                                      height: 1.40,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8.h),
                              Row(
                                children: [
                                  ...List.generate(
                                    5,
                                    (i) => Padding(
                                      padding: EdgeInsets.only(right: 2.w),
                                      child: Icon(
                                        IconsaxPlusBold.star_1,
                                        size: 14.r,
                                        color: i < r.rating
                                            ? AppColors.star
                                            : AppColors.divider,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    DateFormat('dd.MM.yyyy').format(r.createdAt),
                                    style: AppText.caption(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8.h),
                              Text(
                                r.comment,
                                style: AppText.bodySmall(
                                  color: AppColors.textSecondary,
                                ).copyWith(height: 1.40),
                              ),
                              if (r.tags.isNotEmpty) ...[
                                SizedBox(height: 8.h),
                                Wrap(
                                  spacing: 8.w,
                                  runSpacing: 6.h,
                                  children: r.tags.map((t) => CategoryChip(t)).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContactSheet(BuildContext context, String phone) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactSheet(phone: phone),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color color;
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
          height: 36.h,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18.r),
              SizedBox(width: 6.w),
              Text(
                label,
                style: AppText.bodyLarge(color: color, weight: FontWeight.w600)
                    .copyWith(letterSpacing: -0.40),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactSheet extends StatelessWidget {
  const _ContactSheet({required this.phone});
  final String phone;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14.r),
              ),
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _MessengerIcon(label: 'WhatsApp', color: const Color(0xFF25D366), icon: Icons.chat),
                        _MessengerIcon(label: 'Telegram', color: const Color(0xFF26A5E4), icon: Icons.send_rounded),
                        _MessengerIcon(label: 'MAX', color: const Color(0xFFFF8D28), icon: Icons.flash_on),
                      ],
                    ),
                  ),
                  Container(height: 0.5.h, color: AppColors.divider),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    child: Text(
                      phone,
                      style: AppText.bodyLarge(color: AppColors.primary)
                          .copyWith(letterSpacing: -0.40),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8.h),
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14.r),
              child: InkWell(
                borderRadius: BorderRadius.circular(14.r),
                onTap: () => Navigator.of(context).pop(),
                child: SizedBox(
                  width: double.infinity,
                  height: 56.h,
                  child: Center(
                    child: Text(
                      'Cancel',
                      style: AppText.bodyLarge(
                        color: AppColors.primary,
                        weight: FontWeight.w600,
                      ).copyWith(letterSpacing: -0.40),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessengerIcon extends StatelessWidget {
  const _MessengerIcon({required this.label, required this.color, required this.icon});
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56.r,
          height: 56.r,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 28.r),
        ),
        SizedBox(height: 4.h),
        Text(
          label,
          style: AppText.caption(color: AppColors.textSecondary)
              .copyWith(height: 1.33),
        ),
      ],
    );
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({
    required this.average,
    required this.total,
    required this.distribution,
    required this.maxCount,
  });

  final double average;
  final int total;
  final Map<int, int> distribution;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final filledStars = average.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              average.toStringAsFixed(1).replaceAll('.', ','),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                height: 1.20,
              ),
            ),
            SizedBox(width: 8.w),
            ...List.generate(
              5,
              (i) => Padding(
                padding: EdgeInsets.only(right: 2.w),
                child: Icon(
                  IconsaxPlusBold.star_1,
                  size: 18.r,
                  color: i < filledStars ? AppColors.star : AppColors.divider,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 4.h),
        Text(
          '$total ${_pluralReviews(total)}',
          style: AppText.bodySmall(color: AppColors.textSecondary)
              .copyWith(height: 1.38),
        ),
        SizedBox(height: 12.h),
        for (final stars in [5, 4, 3, 2, 1])
          Padding(
            padding: EdgeInsets.only(bottom: 6.h),
            child: Row(
              children: [
                ...List.generate(
                  5,
                  (i) => Icon(
                    IconsaxPlusBold.star_1,
                    size: 12.r,
                    color: i < stars ? AppColors.star : AppColors.divider,
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4.r),
                    child: LinearProgressIndicator(
                      value: maxCount == 0 ? 0 : (distribution[stars] ?? 0) / maxCount,
                      minHeight: 8.h,
                      backgroundColor: AppColors.surfaceVariant,
                      color: AppColors.star,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                SizedBox(
                  width: 24.w,
                  child: Text(
                    '${distribution[stars] ?? 0}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _pluralReviews(int n) {
    final lastTwo = n % 100;
    if (lastTwo >= 11 && lastTwo <= 14) return 'отзывов';
    final last = n % 10;
    if (last == 1) return 'отзыв';
    if (last >= 2 && last <= 4) return 'отзыва';
    return 'отзывов';
  }
}
