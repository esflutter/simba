import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../theme/app_colors.dart';

/// Пилюля с текущим городом в шапке. Тап — открывает экран выбора города.
class CityPill extends StatelessWidget {
  const CityPill({super.key, required this.cityName});

  final String cityName;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(8.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(8.r),
        onTap: () => context.push('/city'),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8.w, 4.h, 10.w, 4.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                IconsaxPlusLinear.location,
                size: 16.r,
                color: AppColors.primary,
              ),
              SizedBox(width: 4.w),
              Flexible(
                child: Text(
                  cityName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.43,
                    letterSpacing: 0.10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
