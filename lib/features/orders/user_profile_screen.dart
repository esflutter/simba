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
                  _UserHeaderCard(name: user.name, phone: user.phone, accepted: accepted),
                  SizedBox(height: 12.h),
                  Row(
                    children: [
                      Expanded(
                        child: _ContactButton(
                          label: 'Написать',
                          background: AppColors.surface,
                          color: AppColors.textPrimary,
                          onTap: () {},
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: _ContactButton(
                          label: 'Позвонить',
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
                    child: Text('Отзывы', style: AppText.h4()),
                  ),
                  SizedBox(height: 8.h),
                  if (reviews.isEmpty)
                    AppCard(
                      child: Text('Пока нет отзывов',
                          style: AppText.body(color: AppColors.textSecondary)),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18.r,
                                    backgroundColor: AppColors.primarySoft,
                                    child: Icon(IconsaxPlusLinear.user, color: AppColors.primary, size: 22.r),
                                  ),
                                  SizedBox(width: 10.w),
                                  Text(userById(r.fromUserId).name,
                                      style: AppText.body(weight: FontWeight.w600)),
                                ],
                              ),
                              SizedBox(height: 8.h),
                              Row(
                                children: [
                                  ...List.generate(
                                    5,
                                    (i) => Icon(IconsaxPlusBold.star_1,
                                        size: 16.r,
                                        color: i < r.rating
                                            ? AppColors.star
                                            : AppColors.divider),
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    DateFormat('dd.MM.yyyy').format(r.createdAt),
                                    style: AppText.bodySmall(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8.h),
                              Text(r.comment,
                                  style: AppText.body(color: AppColors.textSecondary)),
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
}

class _UserHeaderCard extends StatelessWidget {
  const _UserHeaderCard({required this.name, required this.phone, required this.accepted});
  final String name;
  final String phone;
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
      child: Row(
        children: [
          Container(
            width: 80.r,
            height: 80.r,
            decoration: const BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: Icon(IconsaxPlusLinear.user, color: AppColors.primary, size: 48.r),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (accepted)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Исполнитель принят',
                            style: AppText.bodySmall(color: Colors.white, weight: FontWeight.w500)),
                        SizedBox(width: 6.w),
                        Icon(IconsaxPlusLinear.close_circle, color: Colors.white, size: 14.r),
                      ],
                    ),
                  ),
                if (accepted) SizedBox(height: 8.h),
                Text(name, style: AppText.h4()),
                SizedBox(height: 2.h),
                Text(phone, style: AppText.body(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.label,
    required this.background,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: onTap,
        child: Container(
          height: 56.h,
          alignment: Alignment.center,
          child: Text(label, style: AppText.button(color: color)),
        ),
      ),
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
              style: AppText.h2(),
            ),
            SizedBox(width: 8.w),
            ...List.generate(
              5,
              (i) => Icon(
                IconsaxPlusBold.star_1,
                size: 22.r,
                color: i < filledStars ? AppColors.star : AppColors.divider,
              ),
            ),
          ],
        ),
        SizedBox(height: 4.h),
        Text('$total отзывов', style: AppText.body(color: AppColors.textSecondary)),
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
                    size: 14.r,
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
                      backgroundColor: AppColors.divider,
                      color: AppColors.star,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                SizedBox(
                  width: 24.w,
                  child: Text(
                    '${distribution[stars] ?? 0}',
                    style: AppText.body(color: AppColors.textSecondary),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
