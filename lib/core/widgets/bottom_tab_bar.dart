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
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70.h,
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
    final color = active ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 36.r,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SizedBox(height: 10.h),
            Image.asset(
              active ? iconAssetActive : iconAsset,
              width: 28.r,
              height: 28.r,
            ),
            SizedBox(height: 7.h),
            Text(
              label,
              style: AppText.tab(color: color, weight: FontWeight.w500)
                  .copyWith(height: 1.45, letterSpacing: -0.40),
            ),
            SizedBox(height: 10.h),
          ],
        ),
      ),
    );
  }
}
