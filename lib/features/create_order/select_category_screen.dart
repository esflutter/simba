import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../data/mock/mock_data.dart';
import '../../data/remote/categories_repository.dart';
import 'order_draft.dart';

class SelectCategoryScreen extends ConsumerWidget {
  const SelectCategoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: Column(
              children: [
                SizedBox(height: 4.h),
                Center(
                  child: Container(
                    width: 36.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: const Color(0x4C3C3C43),
                      borderRadius: BorderRadius.circular(2.5.r),
                    ),
                  ),
                ),
                SizedBox(height: 4.h),
                SizedBox(
                  height: 36.h,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: Text(
                          'Категория',
                          style: AppText.bodyLarge(weight: FontWeight.w600).copyWith(
                            letterSpacing: -0.43,
                            height: 1.29,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.w),
                          child: const AppBackButton(),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 4.h),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          Expanded(
            child: Builder(builder: (context) {
              final categories = ref.watch(categoriesProvider).maybeWhen(
                    data: (xs) => xs,
                    orElse: () => MockData.categories,
                  );
              return ListView.separated(
              padding: EdgeInsets.fromLTRB(
                16.w,
                0,
                16.w,
                16.h + MediaQuery.viewPaddingOf(context).bottom,
              ),
              itemCount: categories.length,
              separatorBuilder: (_, _) => SizedBox(height: 8.h),
              itemBuilder: (_, i) {
                final c = categories[i];
                return Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16.r),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16.r),
                    onTap: () {
                      ref.read(orderDraftProvider.notifier).update(categoryId: c.id);
                      context.pop();
                    },
                    child: SizedBox(
                      height: 48.h,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20.w),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(c.name, style: AppText.bodyLarge()),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
            }),
          ),
        ],
      ),
    );
  }
}
