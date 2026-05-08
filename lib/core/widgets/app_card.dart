import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderRadius,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(16.r);
    final bg = color ?? AppColors.surface;
    final body = Padding(
      padding: padding ?? EdgeInsets.all(16.w),
      child: child,
    );
    if (onTap == null) {
      return Container(
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: body,
      );
    }
    return Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(borderRadius: radius, onTap: onTap, child: body),
    );
  }
}

class CategoryChip extends StatelessWidget {
  const CategoryChip(this.label, {super.key, this.dense = false});

  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (dense) {
      // Figma «Мои заказы» style: компактный чип внутри карточки.
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w400,
            color: AppColors.primary,
            height: 1.33,
          ),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(40.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13.sp,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
