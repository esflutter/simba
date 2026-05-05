import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppText {
  AppText._();

  static TextStyle _i({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textPrimary,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.inter(
        fontSize: size.sp,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle h1({Color color = AppColors.textPrimary}) =>
      _i(size: 34, weight: FontWeight.w700, color: color, height: 1.15);

  static TextStyle h2({Color color = AppColors.textPrimary}) =>
      _i(size: 24, weight: FontWeight.w600, color: color, height: 1.2);

  static TextStyle h3({Color color = AppColors.textPrimary}) =>
      _i(size: 20, weight: FontWeight.w600, color: color, height: 1.25);

  static TextStyle h4({Color color = AppColors.textPrimary}) =>
      _i(size: 18, weight: FontWeight.w600, color: color, height: 1.3);

  static TextStyle bodyLarge({Color color = AppColors.textPrimary, FontWeight weight = FontWeight.w400}) =>
      _i(size: 17, weight: weight, color: color, height: 1.3);

  static TextStyle body({Color color = AppColors.textPrimary, FontWeight weight = FontWeight.w400}) =>
      _i(size: 16, weight: weight, color: color, height: 1.35);

  static TextStyle bodySmall({Color color = AppColors.textPrimary, FontWeight weight = FontWeight.w400}) =>
      _i(size: 14, weight: weight, color: color, height: 1.4);

  static TextStyle caption({Color color = AppColors.textSecondary, FontWeight weight = FontWeight.w400}) =>
      _i(size: 12, weight: weight, color: color, height: 1.35);

  static TextStyle button({Color color = AppColors.textOnPrimary}) =>
      _i(size: 17, weight: FontWeight.w400, color: color, height: 1.2);

  static TextStyle tab({Color color = AppColors.textSecondary, FontWeight weight = FontWeight.w500}) =>
      _i(size: 11, weight: weight, color: color, height: 1.2);

  static TextStyle get splashTitle =>
      GoogleFonts.jost(fontSize: 64.sp, fontWeight: FontWeight.w700, color: AppColors.textOnPrimary, height: 1.10);
}
