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
        child: Container(
          // 32dp — высота совпадает с соседним тумблером «Готов помочь»
          // в шапке ленты (см. feed_screen `_Header`), чтобы оба контрола
          // в Row были одной высоты. БЕЗ `alignment` — иначе при обёртке
          // CityPill в Expanded+Align внутри Row он растягивался во всю
          // ширину доступного места; контролы должны ужиматься по
          // содержимому, центрирование высоты обеспечивается Padding'ом.
          constraints: BoxConstraints(minHeight: 32.h),
          padding: EdgeInsets.fromLTRB(8.w, 6.h, 10.w, 6.h),
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
