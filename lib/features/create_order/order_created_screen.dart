import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';

class OrderCreatedScreen extends StatelessWidget {
  const OrderCreatedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96.r,
                height: 96.r,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
                child: Icon(IconsaxPlusLinear.tick_circle, size: 56.r, color: Colors.white),
              ),
              SizedBox(height: 24.h),
              Text('Заказ создан', style: AppText.h2()),
              SizedBox(height: 8.h),
              Text(
                'Мы уведомили исполнителей рядом. Откликам можно следить в разделе «Мои заказы».',
                textAlign: TextAlign.center,
                style: AppText.body(color: AppColors.textSecondary),
              ),
              const Spacer(flex: 2),
              PrimaryButton(
                label: 'К моим заказам',
                onPressed: () => context.go('/home/my'),
              ),
              SizedBox(height: 12.h),
              SecondaryButton(
                label: 'На главный',
                onPressed: () => context.go('/home/orders'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
