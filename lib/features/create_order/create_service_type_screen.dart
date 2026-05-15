import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_card.dart';

class CreateServiceTypeScreen extends StatelessWidget {
  const CreateServiceTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 47.h, 16.w, 8.h),
                child: Text(
                  'Создать заказ',
                  style: AppText.h1().copyWith(
                    height: 1.21,
                    letterSpacing: 0.40,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 105.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TypeCard(
                  iconAsset: 'assets/images/service_for_self.webp',
                  title: 'Для себя',
                  subtitle: 'Я буду заказчиком услуги',
                  onTap: () => context.push('/create?for=self'),
                ),
                SizedBox(height: 8.h),
                _TypeCard(
                  iconAsset: 'assets/images/service_for_other.webp',
                  title: 'Для другого',
                  subtitle: 'Заказ для другого человека',
                  onTap: () => context.push('/create?for=other'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String iconAsset;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      padding: EdgeInsets.only(top: 16.h, left: 24.w, right: 24.w, bottom: 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(iconAsset, width: 48.r, height: 48.r),
          SizedBox(height: 16.h),
          Text(title, style: AppText.h4(color: AppColors.primary)),
          SizedBox(height: 8.h),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$subtitle ',
                  style: AppText.bodySmall(color: Colors.black.withValues(alpha: 0.60)),
                ),
                // Webp-стрелка из Figma вместо текстового символа '→'.
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Image.asset(
                    'assets/images/icon_arrow_forward.webp',
                    width: 16.r,
                    height: 16.r,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
