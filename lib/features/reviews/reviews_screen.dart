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

class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(appControllerProvider).reviews;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: Row(
                children: [
                  const AppBackButton(),
                  Expanded(child: Center(child: Text('Отзывы', style: AppText.h4()))),
                  SizedBox(width: 40.w),
                ],
              ),
            ),
            Expanded(
              child: reviews.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(IconsaxPlusLinear.star, size: 60.r, color: AppColors.textTertiary),
                          SizedBox(height: 12.h),
                          Text('Пока без отзывов', style: AppText.h4()),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.all(16.w),
                      itemCount: reviews.length,
                      separatorBuilder: (_, _) => SizedBox(height: 12.h),
                      itemBuilder: (_, i) {
                        final r = reviews[i];
                        final author = userById(r.fromUserId);
                        return AppCard(
                          borderRadius: BorderRadius.circular(12.r),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18.r,
                                    backgroundColor: AppColors.primarySoft,
                                    child: Icon(IconsaxPlusLinear.user, color: AppColors.primary, size: 20.r),
                                  ),
                                  SizedBox(width: 10.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(author.name, style: AppText.body(weight: FontWeight.w600)),
                                        Text(
                                          DateFormat('dd.MM.yyyy').format(r.createdAt),
                                          style: AppText.caption(color: AppColors.textTertiary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: List.generate(
                                      5,
                                      (i) => Icon(
                                        IconsaxPlusBold.star_1,
                                        size: 14.r,
                                        color: i < r.rating ? AppColors.star : AppColors.divider,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10.h),
                              Text(r.comment, style: AppText.body()),
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
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
