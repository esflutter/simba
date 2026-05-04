import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../theme/app_colors.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onTap, this.color});

  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      radius: 24.r,
      onTap: onTap ??
          () {
            if (context.canPop()) {
              context.pop();
            } else {
              Navigator.of(context).maybePop();
            }
          },
      child: Padding(
        padding: EdgeInsets.all(8.r),
        child: Icon(IconsaxPlusLinear.arrow_left_2, size: 26.r, color: color ?? AppColors.primary),
      ),
    );
  }
}
