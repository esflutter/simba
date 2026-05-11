import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';

/// Открывает шторку «Оставить отзыв» снизу экрана.
Future<void> showLeaveReviewSheet(BuildContext context, String orderId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.40),
    builder: (_) => _LeaveReviewSheet(orderId: orderId),
  );
}

class _LeaveReviewSheet extends ConsumerStatefulWidget {
  const _LeaveReviewSheet({required this.orderId});
  final String orderId;

  @override
  ConsumerState<_LeaveReviewSheet> createState() => _LeaveReviewSheetState();
}

class _LeaveReviewSheetState extends ConsumerState<_LeaveReviewSheet> {
  int _rating = 0;
  final Set<String> _tags = {};
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    // Определяем, кому мы оставляем отзыв: если 'me' — заказчик, отзыв
    // идёт исполнителю; иначе — заказчику.
    final state = ref.read(appControllerProvider);
    final order = [...state.myOrders, ...state.orders].firstWhere(
      (o) => o.id == widget.orderId,
      orElse: () => state.myOrders.isNotEmpty
          ? state.myOrders.first
          : state.orders.first,
    );
    final isCustomerReviewing = order.customerId == 'me';
    final recipientRole = isCustomerReviewing ? 'исполнителя' : 'заказчика';
    final recipientId =
        isCustomerReviewing ? (order.executorId ?? '') : order.customerId;
    // Сохраняем отзыв в стейт, чтобы кнопка «Оставить отзыв» больше не
    // отображалась на странице этого заказа.
    ref.read(appControllerProvider.notifier).addReview(
          orderId: order.id,
          toUserId: recipientId,
          rating: _rating,
          comment: _ctrl.text.trim(),
          tags: _tags.toList(),
        );

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
              Image.asset(
                'assets/images/tick_square.webp',
                width: 56.r,
                height: 56.r,
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
                'Ваш отзыв будет опубликован в аккаунте $recipientRole',
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
                      Navigator.of(context).pop();
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
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      // Поднимаем шторку над клавиатурой.
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(15.r)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 8.h),
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
                        onTap: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: EdgeInsets.all(6.r),
                          child: Icon(
                            Icons.close_rounded,
                            color: AppColors.primary,
                            size: 20.r,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
                          padding: EdgeInsets.symmetric(horizontal: 4.w),
                          child: Image.asset(
                            filled
                                ? 'assets/images/icon_review_star_filled.webp'
                                : 'assets/images/icon_review_star_empty.webp',
                            width: 48.r,
                            height: 48.r,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                SizedBox(height: 24.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: AppColors.primary,
                    style: AppText.bodyLarge(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      counterText: '',
                      hintText: 'Поделитесь впечатлением о заказе',
                      hintStyle: AppText.body(
                        color: Colors.black.withValues(alpha: 0.30),
                      ).copyWith(height: 1.31, letterSpacing: -0.31),
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
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Text(
                          t,
                          style: AppText.bodySmall(
                            color: selected ? Colors.white : AppColors.textPrimary,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: 16.h),
                PrimaryButton(
                  label: 'Оставить отзыв',
                  onPressed: canSubmit ? () => _submit(context) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
