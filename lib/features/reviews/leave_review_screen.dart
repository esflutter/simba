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
  int _rating = 0;
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
      barrierColor: Colors.black.withValues(alpha: 0.40),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Container(
          width: 313.w,
          padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(24.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56.r,
                height: 56.r,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Icon(Icons.check_rounded, color: Colors.white, size: 36.r, weight: 700),
              ),
              SizedBox(height: 16.h),
              Text(
                'Спасибо за оценку!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.40,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Ваш отзыв будет опубликован в аккаунте исполнителя / заказчика',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.60),
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.33,
                ),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Material(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10.r),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10.r),
                    onTap: () {
                      Navigator.of(dialogCtx).pop();
                      context.pop();
                    },
                    child: SizedBox(
                      width: double.infinity,
                      height: 36.h,
                      child: Center(
                        child: Text(
                          'Ок',
                          style: TextStyle(
                            color: const Color(0xFFF5F5F5),
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w600,
                            height: 1.29,
                            letterSpacing: -0.40,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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
                  Text(
                    'Как вам заказ?',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.29,
                      letterSpacing: -0.43,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Positioned(
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.pop(),
                      child: Padding(
                        padding: EdgeInsets.all(8.r),
                        child: Icon(
                          Icons.close_rounded,
                          color: AppColors.primary,
                          size: 24.r,
                        ),
                      ),
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
                                  filled
                                      ? IconsaxPlusBold.star_1
                                      : IconsaxPlusLinear.star_1,
                                  size: 56.r,
                                  color: filled
                                      ? AppColors.star
                                      : Colors.black.withValues(alpha: 0.30),
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
