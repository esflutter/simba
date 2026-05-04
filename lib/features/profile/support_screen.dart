import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/primary_button.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: Row(
                children: [
                  const AppBackButton(),
                  Expanded(child: Center(child: Text('Связаться с нами', style: AppText.h4()))),
                  SizedBox(width: 40.w),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Column(
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Мы на связи', style: AppText.h4()),
                          SizedBox(height: 8.h),
                          Text(
                            'Напишите нам в мессенджере — отвечаем в рабочее время.',
                            style: AppText.body(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16.h),
                    PrimaryButton(
                      label: 'Telegram',
                      icon: const Icon(IconsaxPlusLinear.send_2),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Откроем мессенджер...')),
                        );
                      },
                    ),
                    SizedBox(height: 12.h),
                    SecondaryButton(
                      label: 'WhatsApp',
                      icon: const Icon(IconsaxPlusLinear.message),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
