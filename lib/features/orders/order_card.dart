import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_time_formatters.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';

class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.categoryName,
    required this.onTap,
    this.showTime = true,
  });

  final Order order;
  final String categoryName;
  final VoidCallback onTap;
  final bool showTime;

  String get _whenLabel {
    if (order.scheduledAt != null) {
      return DateFormat('dd.MM.yyyy').format(order.scheduledAt!);
    }
    return order.asap ? 'Как можно быстрее' : 'Не указано';
  }

  String get _priceLabel => formatRub(order.priceRub);

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.all(16.w),
      borderRadius: BorderRadius.circular(12.r),
      child: SizedBox(
        height: 142.h - 32.h, // 142.h total − vertical padding (16.h × 2)
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CategoryChip(categoryName, dense: true),
                  ),
                ),
                SizedBox(width: 8.w),
                Text(
                  '→',
                  style: AppText.body(color: AppColors.primary)
                      .copyWith(height: 1.0, fontSize: 18.sp),
                ),
              ],
            ),
            Text(
              order.title,
              style: AppText.h3().copyWith(height: 1.20),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              order.address,
              style: AppText.bodySmall(
                color: Colors.black.withValues(alpha: 0.60),
              ).copyWith(height: 1.40),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: showTime
                      ? Text(
                          _whenLabel,
                          style: AppText.body(weight: FontWeight.w500)
                              .copyWith(height: 1.40),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : const SizedBox.shrink(),
                ),
                SizedBox(width: 8.w),
                Text(
                  _priceLabel,
                  style: AppText.body(
                    color: AppColors.primary,
                    weight: FontWeight.w600,
                  ).copyWith(height: 1.40),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
