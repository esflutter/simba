import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';

class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref
        .watch(appControllerProvider)
        .reviews
        .where((r) => r.toUserId == 'me')
        .toList();
    final ratingDistribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in reviews) {
      ratingDistribution[r.rating] = (ratingDistribution[r.rating] ?? 0) + 1;
    }
    final avgRating = reviews.isEmpty
        ? 0.0
        : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Header ──
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 44.h,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        child: const AppBackButton(),
                      ),
                    ),
                    Center(
                      child: Text(
                        'Отзывы',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w600,
                          height: 1.29,
                          letterSpacing: -0.43,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Body ──
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16.w,
                16.h,
                16.w,
                MediaQuery.of(context).viewPadding.bottom,
              ),
              children: [
                _RatingSummaryCard(
                  average: avgRating,
                  total: reviews.length,
                  distribution: ratingDistribution,
                ),
                SizedBox(height: 8.h),
                if (reviews.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 64.h),
                    child: Column(
                      children: [
                        Icon(
                          IconsaxPlusBold.star_1,
                          size: 80.r,
                          color: AppColors.star,
                        ),
                        SizedBox(height: 24.h),
                        Text(
                          'Нет отзывов',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            letterSpacing: -0.45,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...reviews.map((r) => Padding(
                        padding: EdgeInsets.only(bottom: 8.h),
                        child: _ReviewCard(review: r),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingSummaryCard extends StatelessWidget {
  const _RatingSummaryCard({
    required this.average,
    required this.total,
    required this.distribution,
  });

  final double average;
  final int total;
  final Map<int, int> distribution;

  @override
  Widget build(BuildContext context) {
    final filledStars = average.round();
    final hasReviews = total > 0;
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                hasReviews
                    ? average.toStringAsFixed(1).replaceAll('.', ',')
                    : '0',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                  height: 1.20,
                ),
              ),
              SizedBox(width: 4.w),
              if (hasReviews)
                ...List.generate(
                  5,
                  (i) => Padding(
                    padding: EdgeInsets.only(right: i == 4 ? 0 : 2.w),
                    child: Image.asset(
                      i < filledStars
                          ? 'assets/images/icon_ranking.webp'
                          : 'assets/images/icon_star_empty.webp',
                      width: 20.r,
                      height: 20.r,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 4.h),
          Text(
            '$total ${_pluralReviews(total)}',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.60),
              fontSize: 13.sp,
              fontWeight: FontWeight.w400,
              height: 1.38,
            ),
          ),
          SizedBox(height: 8.h),
          for (final stars in [5, 4, 3, 2, 1]) ...[
            _DistributionRow(
              filled: stars,
              count: distribution[stars] ?? 0,
              total: total,
            ),
            if (stars > 1) SizedBox(height: 8.h),
          ],
        ],
      ),
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

class _DistributionRow extends StatelessWidget {
  const _DistributionRow({
    required this.filled,
    required this.count,
    required this.total,
  });

  final int filled;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ...List.generate(
          5,
          (i) => Padding(
            padding: EdgeInsets.only(right: i == 4 ? 0 : 1.w),
            child: Image.asset(
              i < filled
                  ? 'assets/images/icon_ranking.webp'
                  : 'assets/images/icon_star_empty.webp',
              width: 14.r,
              height: 14.r,
            ),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : count / total,
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
            '$count',
            softWrap: false,
            overflow: TextOverflow.visible,
            style: GoogleFonts.inter(
              color: Colors.black,
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              height: 1.38,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) {
    final author = userById(review.fromUserId);
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32.r,
                height: 32.r,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  IconsaxPlusLinear.user,
                  color: AppColors.primary,
                  size: 20.r,
                ),
              ),
              SizedBox(width: 4.w),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: 8.w),
                  child: Text(
                    author.name,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.33,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ...List.generate(
                5,
                (i) => Padding(
                  padding: EdgeInsets.only(right: i == 4 ? 0 : 1.w),
                  child: Image.asset(
                    i < review.rating
                        ? 'assets/images/icon_ranking.webp'
                        : 'assets/images/icon_star_empty.webp',
                    width: 14.r,
                    height: 14.r,
                  ),
                ),
              ),
              SizedBox(width: 4.w),
              Text(
                DateFormat('dd.MM.yyyy').format(review.createdAt),
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.60),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.33,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            review.comment,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.60),
              fontSize: 13.sp,
              fontWeight: FontWeight.w400,
              height: 1.38,
            ),
          ),
          if (review.tags.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 6.h,
              children: review.tags
                  .map(
                    (t) => Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
