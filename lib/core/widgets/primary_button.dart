import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
    this.height,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool expanded;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final btn = Material(
      color: disabled ? AppColors.disabledBg : AppColors.primary,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: onPressed,
        child: Container(
          height: height ?? 50.h,
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                IconTheme.merge(
                  data: IconThemeData(
                    color: disabled ? AppColors.disabledFg : AppColors.textOnPrimary,
                    size: 20.r,
                  ),
                  child: icon!,
                ),
                SizedBox(width: 8.w),
              ],
              Text(
                label,
                style: AppText.button(
                  color: disabled ? AppColors.disabledFg : AppColors.textOnPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          height: 50.h,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                IconTheme.merge(
                  data: IconThemeData(color: c, size: 20.r),
                  child: icon!,
                ),
                SizedBox(width: 8.w),
              ],
              Text(label, style: AppText.button(color: c)),
            ],
          ),
        ),
      ),
    );
  }
}
