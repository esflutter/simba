import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class BottomTabBar extends StatelessWidget {
  const BottomTabBar({
    super.key,
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(width: 1, color: Color(0xFFEFEFF0)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64.h,
          child: Row(
            children: [
              _Tab(
                label: 'Заказы',
                iconAsset: 'assets/images/tab_orders.webp',
                iconAssetActive: 'assets/images/tab_orders_active.webp',
                active: index == 0,
                onTap: () => onChanged(0),
              ),
              _Tab(
                label: 'Создать',
                iconAsset: 'assets/images/tab_create.webp',
                iconAssetActive: 'assets/images/tab_create_active.webp',
                active: index == 1,
                onTap: () => onChanged(1),
              ),
              _Tab(
                label: 'Мои заказы',
                iconAsset: 'assets/images/tab_my.webp',
                iconAssetActive: 'assets/images/tab_my_active.webp',
                active: index == 2,
                onTap: () => onChanged(2),
              ),
              _Tab(
                label: 'Профиль',
                iconAsset: 'assets/images/tab_profile.webp',
                iconAssetActive: 'assets/images/tab_profile_active.webp',
                active: index == 3,
                onTap: () => onChanged(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.iconAsset,
    required this.iconAssetActive,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String iconAsset;
  final String iconAssetActive;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : Colors.black.withValues(alpha: 0.60);
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 36.r,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 56.w,
              height: 32.h,
              child: Center(
                child: Image.asset(
                  active ? iconAssetActive : iconAsset,
                  width: 24.r,
                  height: 24.r,
                ),
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.tab(color: color, weight: FontWeight.w500)
                  .copyWith(height: 1.45, letterSpacing: -0.40),
            ),
          ],
        ),
      ),
    );
  }
}
