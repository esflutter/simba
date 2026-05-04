import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../data/mock/mock_data.dart';
import 'order_draft.dart';

class SelectCategoryScreen extends ConsumerWidget {
  const SelectCategoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              child: Row(
                children: [
                  const AppBackButton(),
                  Expanded(
                    child: Center(child: Text('Категория', style: AppText.h4())),
                  ),
                  SizedBox(width: 40.w),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.all(16.w),
                itemCount: MockData.categories.length,
                separatorBuilder: (_, _) => SizedBox(height: 8.h),
                itemBuilder: (_, i) {
                  final c = MockData.categories[i];
                  return AppCard(
                    onTap: () {
                      ref.read(orderDraftProvider.notifier).update(categoryId: c.id);
                      context.pop();
                    },
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 18.h),
                    child: Text(c.name, style: AppText.bodyLarge()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
