import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/mock_data.dart';

class LeaveReviewScreen extends ConsumerStatefulWidget {
  const LeaveReviewScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<LeaveReviewScreen> createState() => _LeaveReviewScreenState();
}

class _LeaveReviewScreenState extends ConsumerState<LeaveReviewScreen> {
  int _rating = 5;
  final Set<String> _tags = {};
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        insetPadding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64.r,
                height: 64.r,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Icon(IconsaxPlusLinear.tick_circle, color: Colors.white, size: 38.r),
              ),
              SizedBox(height: 16.h),
              Text('Спасибо за оценку!', style: AppText.h4(), textAlign: TextAlign.center),
              SizedBox(height: 8.h),
              Text(
                'Ваш отзыв будет опубликован в аккаунте исполнителя / заказчика',
                style: AppText.body(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20.h),
              PrimaryButton(
                label: 'Ок',
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  context.pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _rating > 0;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 16.h),
              Stack(
                alignment: Alignment.center,
                children: [
                  Text('Как вам заказ?',
                      style: AppText.h4(),
                      textAlign: TextAlign.center),
                  Positioned(
                    right: 0,
                    child: IconButton(
                      icon: Icon(IconsaxPlusLinear.close_circle,
                          color: AppColors.primary, size: 24.r),
                      onPressed: () => context.pop(),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 24.h),
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(5, (i) {
                            final filled = i < _rating;
                            return GestureDetector(
                              onTap: () => setState(() => _rating = i + 1),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6.w),
                                child: Icon(
                                  IconsaxPlusBold.star_1,
                                  size: 56.r,
                                  color: filled ? AppColors.star : AppColors.divider,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      SizedBox(height: 24.h),
                      Container(
                        height: 140.h,
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        child: TextField(
                          controller: _ctrl,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          cursorColor: AppColors.primary,
                          style: AppText.bodyLarge(),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText: 'Поделитесь впечатлением о заказе',
                            hintStyle: AppText.bodyLarge(color: AppColors.textTertiary),
                          ),
                        ),
                      ),
                      SizedBox(height: 16.h),
                      Wrap(
                        spacing: 8.w,
                        runSpacing: 8.h,
                        children: MockData.reviewTags.map((t) {
                          final selected = _tags.contains(t);
                          return GestureDetector(
                            onTap: () => setState(() {
                              selected ? _tags.remove(t) : _tags.add(t);
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.background,
                                borderRadius: BorderRadius.circular(40.r),
                              ),
                              child: Text(
                                t,
                                style: AppText.body(
                                  color: selected ? Colors.white : AppColors.textPrimary,
                                  weight: FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      SizedBox(height: 16.h),
                    ],
                  ),
                ),
              ),
              PrimaryButton(
                label: 'Оставить отзыв',
                onPressed: canSubmit ? () => _submit(context) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
