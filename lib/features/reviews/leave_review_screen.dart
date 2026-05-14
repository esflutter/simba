import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/pocketbase_client.dart';
import '../../data/remote/reviews_repository.dart';
import '../orders/order_details_screen.dart' show orderByIdProvider;
import '../reviews/reviews_providers.dart';

/// Маппинг отображаемое RU-имя → id (slug) тега, как он лежит в коллекции
/// `review_tags` (см. seed-миграцию 1700000007_seed_reference.js). На бэке
/// сторятся именно slug-и, поэтому отправлять русские строки нельзя.
const Map<String, String> _tagSlugByRu = {
  'Вежливый': 'polite',
  'Аккуратный': 'accurate',
  'Надёжный': 'reliable',
  'Пунктуальный': 'punctual',
  'Внимательный': 'attentive',
  'Опытный': 'experienced',
  'Быстрый': 'fast',
  'Дружелюбный': 'friendly',
};

/// Срок оставления отзыва (дней с момента создания/завершения заказа).
const int kReviewDeadlineDays = 30;

/// Открывает шторку «Оставить отзыв» снизу экрана.
Future<void> showLeaveReviewSheet(BuildContext context, String orderId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.40),
    builder: (_) => _LeaveReviewGate(orderId: orderId),
  );
}

/// Гейт: подгружает заказ через `orderByIdProvider`, валидирует
/// (заказ существует, отзыв ещё в окне 30 дней) и решает, какой
/// контент показать в шторке.
class _LeaveReviewGate extends ConsumerWidget {
  const _LeaveReviewGate({required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncOrder = ref.watch(orderByIdProvider(orderId));
    return asyncOrder.when(
      data: (order) {
        if (order == null) return const _NotFoundView();
        // Источник правды — order.completedAt (заполнен бэком при переходе
        // в status=completed, см. `onRecordUpdate("orders")`). Если бэк не
        // вернул эту дату (старые записи, моки) — fallback на best-effort
        // лестницу: payment_received_at → scheduledAt → createdAt.
        // toLocal(): для согласованности с UI-форматированием — даты в
        // БД хранятся в UTC, сравниваем по локальному времени.
        final completedAt = (order.completedAt ??
                order.paymentReceivedAt ??
                order.workDoneAt ??
                order.scheduledAt ??
                order.createdAt)
            .toLocal();
        final daysPassed = DateTime.now().difference(completedAt).inDays;
        if (daysPassed > kReviewDeadlineDays) {
          return const _DeadlineExpiredView();
        }
        return _LeaveReviewSheet(order: order);
      },
      loading: () => const _LoadingView(),
      error: (_, _) => const _LoadFailedView(),
    );
  }
}

/// Обёртка для статусных видов (loading/error/expired) — повторяет
/// фоновые скругления шторки, чтобы экран не "прыгал".
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(15.r)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: child,
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      child: SizedBox(
        height: 120.h,
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
    );
  }
}

class _LoadFailedView extends StatelessWidget {
  const _LoadFailedView();

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 8.h),
          Text(
            'Не удалось загрузить заказ',
            textAlign: TextAlign.center,
            style: AppText.h3(),
          ),
          SizedBox(height: 16.h),
          PrimaryButton(
            label: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _NotFoundView extends StatelessWidget {
  const _NotFoundView();

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 8.h),
          Text(
            'Заказ не найден',
            textAlign: TextAlign.center,
            style: AppText.h3(),
          ),
          SizedBox(height: 16.h),
          PrimaryButton(
            label: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _DeadlineExpiredView extends StatelessWidget {
  const _DeadlineExpiredView();

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 8.h),
          Text(
            'Срок оставления отзыва истёк',
            textAlign: TextAlign.center,
            style: AppText.h3(),
          ),
          SizedBox(height: 8.h),
          Text(
            'Отзыв можно оставить в течение $kReviewDeadlineDays дней '
            'после завершения заказа.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.60),
              fontSize: 15.sp,
              fontWeight: FontWeight.w400,
              height: 1.33,
            ),
          ),
          SizedBox(height: 16.h),
          PrimaryButton(
            label: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _LeaveReviewSheet extends ConsumerStatefulWidget {
  const _LeaveReviewSheet({required this.order});
  final Order order;

  @override
  ConsumerState<_LeaveReviewSheet> createState() => _LeaveReviewSheetState();
}

class _LeaveReviewSheetState extends ConsumerState<_LeaveReviewSheet> {
  int _rating = 0;
  final Set<String> _tags = {};
  final _ctrl = TextEditingController();
  bool _isSubmitting = false;

  // Локальный список RU-меток тегов — рендерим в Wrap. Раньше брался
  // из MockData.reviewTags; маппим через _tagSlugByRu на бэкенд-id.
  static const List<String> _ruTags = [
    'Вежливый',
    'Аккуратный',
    'Надёжный',
    'Пунктуальный',
    'Внимательный',
    'Опытный',
    'Быстрый',
    'Дружелюбный',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit(BuildContext submitContext) async {
    if (_isSubmitting) return;
    // Определяем, кому мы оставляем отзыв: если customer — отзыв
    // идёт исполнителю; если executor — заказчику. Используем реальный
    // id текущего юзера: PB authStore приоритетнее, т.к. state.user
    // восстанавливается из prefs асинхронно.
    final pb = ref.read(pocketbaseProvider);
    final pbUserId = pb?.authStore.record?.id;
    final stateUserId =
        ref.read(appControllerProvider.select((s) => s.user?.id));
    final myId = pbUserId ?? stateUserId ?? 'me';
    final order = widget.order;
    final isCustomerReviewing = order.customerId == myId;
    final recipientRole = isCustomerReviewing ? 'исполнителя' : 'заказчика';
    final recipientId =
        isCustomerReviewing ? (order.executorId ?? '') : order.customerId;
    // Тэги: на бэке хранятся slug-и (polite/accurate/...). UI оперирует
    // русскими подписями — конвертируем здесь. Незнакомые подписи
    // фильтруем, чтобы не отправить мусор и не словить 400.
    final slugTags = _tags
        .map((ru) => _tagSlugByRu[ru])
        .whereType<String>()
        .toList();

    setState(() => _isSubmitting = true);
    try {
      // Сначала идёт live-вызов: если сервер вернёт ошибку (например
      // дубликат отзыва или истёк дедлайн), пользователь увидит тост
      // и сможет исправить ввод.
      await ref.read(reviewsRepositoryProvider).create(
            orderId: order.id,
            toUserId: recipientId,
            rating: _rating,
            comment: _ctrl.text.trim(),
            tags: slugTags,
          );
      // Зеркало в локальный стейт делаем ТОЛЬКО когда PB не подключён
      // (мок-режим): иначе после live-успеха получаем дубль отзыва в
      // `state.reviews`, который потом подмешивается в fallback-ветке
      // `reviewsForUserProvider`.
      if (pb == null) {
        ref.read(appControllerProvider.notifier).addReview(
              orderId: order.id,
              toUserId: recipientId,
              rating: _rating,
              comment: _ctrl.text.trim(),
              tags: _tags.toList(),
            );
      }
      // Инвалидируем связанные провайдеры — отзыв должен сразу
      // появиться на профиле получателя, а у себя в «деталях заказа»
      // спрятать кнопку «Оставить отзыв».
      ref.invalidate(reviewsForUserProvider(recipientId));
      ref.invalidate(reviewsByOrderProvider(order.id));
      ref.invalidate(orderByIdProvider(order.id));
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Не удалось отправить отзыв');
      setState(() => _isSubmitting = false);
      return;
    }
    if (!mounted) return;
    setState(() => _isSubmitting = false);

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
    final canSubmit = _rating > 0 && !_isSubmitting;
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
                        onTap: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
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
                        onTap: _isSubmitting
                            ? null
                            : () => setState(() => _rating = i + 1),
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
                    enabled: !_isSubmitting,
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
                  children: _ruTags.map((t) {
                    final selected = _tags.contains(t);
                    return GestureDetector(
                      onTap: _isSubmitting
                          ? null
                          : () => setState(() {
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
                  label: _isSubmitting ? 'Отправка…' : 'Оставить отзыв',
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
