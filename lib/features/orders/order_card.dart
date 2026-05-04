import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.categoryName, required this.onTap});

  final Order order;
  final String categoryName;
  final VoidCallback onTap;

  String get _whenLabel {
    if (order.scheduledAt != null) {
      return DateFormat('dd.MM.yyyy').format(order.scheduledAt!);
    }
    return order.asap ? 'Как можно быстрее' : 'Не указано';
  }

  String get _priceLabel =>
      '${NumberFormat('#,###', 'ru_RU').format(order.priceRub).replaceAll(',', ',')} ₽';

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.all(16.w),
      borderRadius: BorderRadius.circular(12.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryChip(categoryName),
              const Spacer(),
              Icon(IconsaxPlusLinear.arrow_right_3, color: AppColors.primary, size: 22.r),
            ],
          ),
          SizedBox(height: 8.h),
          Text(order.title,
              style: AppText.h3(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          SizedBox(height: 4.h),
          Text(order.address,
              style: AppText.body(color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: Text(_whenLabel,
                    style: AppText.bodyLarge(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              SizedBox(width: 8.w),
              Text(_priceLabel,
                  style: AppText.bodyLarge(
                    color: AppColors.primary,
                    weight: FontWeight.w600,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}
