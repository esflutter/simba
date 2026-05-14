import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_time_formatters.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/openfreemap_view.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/order_responses_repository.dart';
import '../../data/remote/orders_repository.dart';
import '../../data/remote/pocketbase_client.dart';
import '../reviews/leave_review_screen.dart';
import '../reviews/reviews_providers.dart';

/// Future-провайдер одного заказа по id. На моках `OrdersRepository.get`
/// сам ищет заказ в локальном AppState, на live — делает запрос к PB.
final orderByIdProvider =
    FutureProvider.autoDispose.family<Order?, String>((ref, id) async {
  return ref.read(ordersRepositoryProvider).get(id);
});

/// Проверяет, есть ли у текущего исполнителя pending-отклик на заказ.
/// В live `order.responses` не наполняется маппером, поэтому без
/// отдельного запроса кнопка «Откликнуться» дублировалась бы — даже
/// если PB уже знает наш отклик. Используем
/// `OrderResponsesRepository.pendingExecutorIds`.
final _hasMyResponseProvider = FutureProvider.autoDispose
    .family<bool, ({String orderId, String executorId})>((ref, args) async {
  if (args.executorId.isEmpty || args.executorId == 'me') {
    // На моках поле `responses` корректно показывает отклик локально —
    // отдельный запрос не нужен.
    return false;
  }
  try {
    final ids = await ref
        .read(orderResponsesRepositoryProvider)
        .pendingExecutorIds(args.orderId);
    return ids.contains(args.executorId);
  } catch (_) {
    return false;
  }
});

class OrderDetailsScreen extends ConsumerWidget {
  const OrderDetailsScreen({super.key, required this.orderId, required this.mode});

  final String orderId;
  final String mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncOrder = ref.watch(orderByIdProvider(orderId));
    return asyncOrder.when(
      data: (order) {
        if (order == null) return _NotFoundScreen();
        return _OrderDetailsBody(orderId: orderId, mode: mode, order: order);
      },
      loading: () => const _LoadingScreen(),
      error: (_, _) => _LoadFailedScreen(),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  child: const AppBackButton(),
                ),
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotFoundScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  child: const AppBackButton(),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                child: Text(
                  'Заказ не найден',
                  textAlign: TextAlign.center,
                  style: AppText.h3(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadFailedScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  child: const AppBackButton(),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                child: Text(
                  'Не удалось загрузить заказ',
                  textAlign: TextAlign.center,
                  style: AppText.h3(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderDetailsBody extends ConsumerWidget {
  const _OrderDetailsBody({
    required this.orderId,
    required this.mode,
    required this.order,
  });

  final String orderId;
  final String mode;
  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Реальный id текущего пользователя. На cold-start state.user
    // восстанавливается из prefs асинхронно, поэтому полагаемся
    // в первую очередь на PB authStore: токен валиден сразу.
    // Без этого гарда `isCustomer` ошибочно становился `false` для
    // заказчика, и ему показывались кнопки исполнителя.
    final pb = ref.watch(pocketbaseProvider);
    final pbUserId = pb?.authStore.record?.id;
    final stateUserId = ref.watch(appControllerProvider.select((s) => s.user?.id));
    final myId = pbUserId ?? stateUserId ?? 'me';
    final isCustomer = order.customerId == myId;
    final isMine = isCustomer;
    // В live `order.responses` может быть пуст (маппер не подгружает),
    // поэтому дополнительно проверяем через async-провайдер ниже.
    final hasMyResponseFromOrder = order.responses.contains(myId);
    final hasMyResponseAsync = ref.watch(
      _hasMyResponseProvider((orderId: order.id, executorId: myId)),
    );
    final hasMyResponse = hasMyResponseAsync.maybeWhen(
      data: (v) => v,
      orElse: () => hasMyResponseFromOrder,
    );

    // City-guard: deep-link мог открыть заказ из чужого города
    // (push-уведомление, history, шаринг). Исполнителю запрещаем
    // откликаться — бизнес-правило SimbA: только в своём городе.
    // Заказчику свой заказ показываем как обычно, даже если он сменил город
    // после создания (order.cityId зафиксирован в момент создания).
    final selectedCityId =
        ref.watch(appControllerProvider.select((s) => s.selectedCityId));
    final isForeignCity = !isMine &&
        order.cityId != null &&
        selectedCityId != null &&
        order.cityId != selectedCityId;

    final isCompleted = order.status == OrderStatus.completed;
    final isCancelled = order.status == OrderStatus.cancelled;
    final isPast = isCompleted || isCancelled;
    // Для выполненных/отменённых «Как можно скорее» неуместно — показываем
    // дату завершения/создания (как в списке истории).
    // toLocal(): даты в БД хранятся в UTC; без перевода ночные заказы
    // отображались бы со сдвигом на 1 день.
    final whenLabel = isPast
        ? DateFormat('dd.MM.yyyy', 'ru_RU').format(
            (order.scheduledAt ?? order.createdAt).toLocal(),
          )
        : order.scheduledAt != null
            ? DateFormat('dd.MM.yyyy HH:mm')
                .format(order.scheduledAt!.toLocal())
            : 'Как можно скорее';
    final whenFieldLabel =
        isCompleted ? 'Дата выполнения' : isCancelled ? 'Дата' : 'Время начала работ';
    final paymentLabel = order.paymentMethod.label;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── White header with back button ──
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  child: const AppBackButton(),
                ),
              ),
            ),
          ),
          // ── Gray scrollable content ──
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
              children: [
                if (isForeignCity) ...[
                  _StatusBanner(
                    color: AppColors.surfaceVariant,
                    textColor: AppColors.textSecondary,
                    label: 'Заказ из другого города. Откликаться нельзя.',
                  ),
                  SizedBox(height: 16.h),
                ],
                Text(order.title, style: AppText.h2().copyWith(height: 1.20)),
                SizedBox(height: 16.h),
                Text(
                  formatRub(order.priceRub),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w600,
                    height: 1.40,
                  ),
                ),
                SizedBox(height: 16.h),
                _Field('Способ оплаты', paymentLabel),
                SizedBox(height: 16.h),
                _Field(whenFieldLabel, whenLabel),
                SizedBox(height: 16.h),
                if (order.description.trim().isNotEmpty) ...[
                  _Field('Комментарий', order.description),
                  SizedBox(height: 16.h),
                ],
                _AddressBlock(address: order.address, location: order.location),
                if (order.photoPaths.isNotEmpty) ...[
                  SizedBox(height: 16.h),
                  _FieldLabel('Фото'),
                  SizedBox(height: 8.h),
                  SizedBox(
                    height: 96.h,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: order.photoPaths.length,
                      separatorBuilder: (_, _) => SizedBox(width: 8.w),
                      itemBuilder: (_, i) {
                        final path = order.photoPaths[i];
                        final isUrl = path.startsWith('http://') ||
                            path.startsWith('https://');
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12.r),
                          child: isUrl
                              ? Image.network(
                                  path,
                                  width: 96.w,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 96.w,
                                    color: AppColors.surfaceVariant,
                                    child: Icon(
                                      IconsaxPlusLinear.image,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                )
                              : Image.file(
                                  File(path),
                                  width: 96.w,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 96.w,
                                    color: AppColors.surfaceVariant,
                                    child: Icon(
                                      IconsaxPlusLinear.image,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
                ],
                if (order.executorId != null && order.executorId != myId && isMine) ...[
                  SizedBox(height: 16.h),
                  _FieldLabel('Исполнитель'),
                  SizedBox(height: 4.h),
                  _PartyCard(userId: order.executorId!, orderId: order.id),
                ],
                if (!isMine) ...[
                  SizedBox(height: 16.h),
                  _FieldLabel('Заказчик'),
                  SizedBox(height: 4.h),
                  _PartyCard(userId: order.customerId, orderId: order.id),
                ],
              ],
            ),
          ),
          // ── White sticky action bar ──
          _ActionBar(
            children: _buildActions(
              context,
              ref,
              order,
              isMine,
              hasMyResponse,
              myId,
              isForeignCity,
            ),
          ),
        ],
      ),
    );
  }


  List<Widget> _buildActions(
    BuildContext context,
    WidgetRef ref,
    Order order,
    bool isMine,
    bool hasMyResponse,
    String myId,
    bool isForeignCity,
  ) {
    // Источник правды по отзывам — `reviewsByOrderProvider`. В live-режиме
    // `state.reviews` маппером не наполняется, и hasMyReview через локальный
    // стейт остался бы false даже после успешной отправки — кнопка «Оставить
    // отзыв» дублировалась бы, повторный клик ловил бы 4xx от бэка.
    // Pessimistic-fallback на локальный стейт сохранён внутри провайдера.
    final reviewsAsync = ref.watch(reviewsByOrderProvider(order.id));
    final reviewsLocal = ref.watch(appControllerProvider).reviews;
    final hasMyReview = reviewsAsync.maybeWhen(
      data: (list) => list.any((r) => r.fromUserId == myId),
      orElse: () => reviewsLocal
          .any((r) => r.orderId == order.id && r.fromUserId == myId),
    );
    final widgets = <Widget>[];

    Future<void> markWorkDone() async {
      try {
        await ref.read(ordersRepositoryProvider).markWorkDone(order.id);
        if (!context.mounted) return;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(feedOrdersProvider);
        ref.invalidate(orderByIdProvider(order.id));
      } catch (_) {
        if (!context.mounted) return;
        AppToast.show(context, 'Ошибка. Попробуйте позже');
      }
    }

    Future<void> confirmWork() async {
      try {
        await ref.read(ordersRepositoryProvider).confirmWork(order.id);
        if (!context.mounted) return;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(feedOrdersProvider);
        ref.invalidate(orderByIdProvider(order.id));
      } catch (_) {
        if (!context.mounted) return;
        AppToast.show(context, 'Ошибка. Попробуйте позже');
      }
    }

    Future<void> confirmPaymentReceived() async {
      try {
        await ref
            .read(ordersRepositoryProvider)
            .confirmPaymentReceived(order.id);
        if (!context.mounted) return;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(feedOrdersProvider);
        ref.invalidate(orderByIdProvider(order.id));
      } catch (_) {
        if (!context.mounted) return;
        AppToast.show(context, 'Ошибка. Попробуйте позже');
      }
    }

    Future<void> cancelAsExecutor() async {
      try {
        await ref
            .read(ordersRepositoryProvider)
            .cancelAsExecutor(order.id);
        if (!context.mounted) return;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(feedOrdersProvider);
        ref.invalidate(orderByIdProvider(order.id));
        AppToast.show(context, 'Заказ возвращён в ленту');
      } catch (_) {
        if (!context.mounted) return;
        AppToast.show(context, 'Ошибка. Попробуйте позже');
      }
    }

    Future<void> respond() async {
      try {
        await ref.read(orderResponsesRepositoryProvider).respond(order.id);
        if (!context.mounted) return;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(feedOrdersProvider);
        ref.invalidate(orderByIdProvider(order.id));
        ref.invalidate(
          _hasMyResponseProvider((orderId: order.id, executorId: myId)),
        );
        AppToast.show(context, 'Отклик отправлен');
      } catch (_) {
        if (!context.mounted) return;
        AppToast.show(context, 'Ошибка. Попробуйте позже');
      }
    }

    if (isMine) {
      switch (order.status) {
        case OrderStatus.open:
          widgets.add(_ResponsesButton(
            count: order.responses.length,
            onTap: () => context.push('/order/${order.id}/responses'),
          ));
          widgets.add(SizedBox(height: 16.h));
          widgets.add(_CancelOrderButton(
            onTap: () => _confirmCancel(context, ref, order.id),
          ));
          break;
        case OrderStatus.accepted:
          // Заказчик подтверждает выполнение работы (= передал наличные).
          widgets.add(_AsyncPrimaryButton(
            label: 'Подтверждаю работу',
            onPressed: confirmWork,
          ));
          break;
        case OrderStatus.awaitingPayment:
          // Исполнитель ещё не подтвердил получение оплаты — пока заказ
          // не перейдёт в `completed`, отзывы оставлять нельзя (бэк всё равно
          // отклонит). Для заказчика на этом шаге UI — пустой action-bar:
          // он уже нажал «Подтверждаю работу», ждёт исполнителя.
          break;
        case OrderStatus.completed:
          if (!hasMyReview) {
            widgets.add(PrimaryButton(
              label: 'Оставить отзыв',
              onPressed: () => showLeaveReviewSheet(context, order.id),
            ));
          }
          break;
        case OrderStatus.cancelled:
          break;
      }
    } else {
      switch (order.status) {
        case OrderStatus.open:
          if (isForeignCity) {
            // Баннер сверху карточки уже информирует пользователя — кнопку
            // «Откликнуться» в этом случае не показываем вообще.
            break;
          }
          if (hasMyResponse) {
            widgets.add(_StatusBanner(
              color: AppColors.primarySoft,
              textColor: AppColors.primary,
              label: 'Отклик отправлен',
            ));
          } else if (order.isExpiredOpen) {
            // Cron `expire-open-orders` срабатывает раз в 15 минут — между
            // тиками заказ с истёкшей `scheduled_at` всё ещё в open. Прячем
            // кнопку, чтобы исполнитель не упирался в 400 от FSM-валидатора.
            widgets.add(_StatusBanner(
              color: AppColors.surfaceVariant,
              textColor: AppColors.textSecondary,
              label: 'Срок выполнения уже истёк',
            ));
          } else {
            widgets.add(_AsyncPrimaryButton(
              label: 'Откликнуться на заказ',
              onPressed: respond,
            ));
          }
          break;
        case OrderStatus.accepted:
          if (order.executorId == myId) {
            // Исполнитель отмечает «Работа выполнена».
            widgets.add(_AsyncPrimaryButton(
              label: 'Работа выполнена',
              onPressed: markWorkDone,
            ));
            // Кнопка отмены принятого заказа — только до наступления
            // запланированного времени. ASAP-заказы (scheduledAt == null)
            // отменять нельзя: «время = сейчас», уже наступило. Бэк-FSM
            // повторно проверяет это же условие.
            final sched = order.scheduledAt;
            if (sched != null && sched.isAfter(DateTime.now())) {
              widgets.add(SizedBox(height: 12.h));
              widgets.add(_CancelOrderButton(
                onTap: () => _confirmCancelExecutor(
                  context,
                  ref,
                  order.id,
                  cancelAsExecutor,
                ),
              ));
            }
          } else {
            widgets.add(_StatusBanner(
              color: AppColors.surfaceVariant,
              textColor: AppColors.textSecondary,
              label: 'Заказ принят другим исполнителем.',
            ));
          }
          break;
        case OrderStatus.awaitingPayment:
          if (order.executorId == myId) {
            // Заказчик подтвердил работу — исполнитель подтверждает получение оплаты.
            widgets.add(_AsyncPrimaryButton(
              label: 'Оплата получена',
              onPressed: confirmPaymentReceived,
            ));
          }
          break;
        case OrderStatus.completed:
          if (!hasMyReview) {
            widgets.add(PrimaryButton(
              label: 'Оставить отзыв',
              onPressed: () => showLeaveReviewSheet(context, order.id),
            ));
          }
          break;
        case OrderStatus.cancelled:
          break;
      }
    }
    return widgets;
  }

  void _confirmCancel(BuildContext context, WidgetRef ref, String id) {
    Future<void> doCancel() async {
      try {
        await ref.read(ordersRepositoryProvider).cancel(id);
        if (!context.mounted) return;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(feedOrdersProvider);
      } catch (_) {
        if (!context.mounted) return;
        AppToast.show(context, 'Ошибка. Попробуйте позже');
      }
    }

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Container(
          width: 313.w,
          padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56.r,
                height: 56.r,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Center(
                  child: CustomPaint(
                    size: Size(18.r, 18.r),
                    painter: _XPainter(color: Colors.white, strokeWidth: 3.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Отменить заказ?',
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
                'Все данные о заказе будут потеряны',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.60),
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.33,
                ),
              ),
              SizedBox(height: 16.h),
              _DialogActionButton(
                label: 'Отменить заказ',
                background: AppColors.primary,
                textColor: Colors.white,
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  doCancel();
                  context.pop();
                },
              ),
              SizedBox(height: 8.h),
              _DialogActionButton(
                label: 'Отмена',
                background: AppColors.surfaceVariant,
                textColor: Colors.black,
                onTap: () => Navigator.of(dialogCtx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Диалог подтверждения отмены принятого заказа исполнителем.
  /// Текст подбирается под сценарий «заказ вернётся в ленту»: исполнитель
  /// видит, что не «удаляет» заказ, а возвращает его заказчику, и тот
  /// получит уведомление + автоматом-отклонённые отклики снова станут pending.
  void _confirmCancelExecutor(
    BuildContext context,
    WidgetRef ref,
    String orderId,
    Future<void> Function() doCancel,
  ) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Container(
          width: 313.w,
          padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56.r,
                height: 56.r,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Center(
                  child: CustomPaint(
                    size: Size(18.r, 18.r),
                    painter: _XPainter(color: Colors.white, strokeWidth: 3.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Отменить выполнение?',
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
                'Заказ вернётся в ленту, заказчик получит уведомление',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.60),
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.33,
                ),
              ),
              SizedBox(height: 16.h),
              _DialogActionButton(
                label: 'Отменить выполнение',
                background: AppColors.primary,
                textColor: Colors.white,
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  doCancel();
                },
              ),
              SizedBox(height: 8.h),
              _DialogActionButton(
                label: 'Не отменять',
                background: AppColors.surfaceVariant,
                textColor: Colors.black,
                onTap: () => Navigator.of(dialogCtx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _XPainter extends CustomPainter {
  _XPainter({required this.color, required this.strokeWidth});
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _XPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
    required this.label,
    required this.background,
    required this.textColor,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 36.h,
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 17.sp,
                fontWeight: FontWeight.w600,
                height: 1.29,
                letterSpacing: -0.40,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      // Кнопок нет — но без SafeArea контент списка уезжает под системный
      // нав-бар. Оставляем нижний инсет.
      return SafeArea(top: false, child: const SizedBox.shrink());
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16.r),
          topRight: Radius.circular(16.r),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18.80,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _ResponsesButton extends StatelessWidget {
  const _ResponsesButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 50.h,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Смотреть отклики',
                style: AppText.bodyLarge(color: Colors.white, weight: FontWeight.w600)
                    .copyWith(letterSpacing: -0.40),
              ),
              SizedBox(width: 10.w),
              Container(
                constraints: BoxConstraints(minWidth: 24.r),
                height: 24.r,
                padding: EdgeInsets.symmetric(horizontal: 6.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24.r),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    height: 1.33,
                    letterSpacing: -0.23,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CancelOrderButton extends StatelessWidget {
  const _CancelOrderButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 50.h,
          child: Center(
            child: Text(
              'Отменить заказ',
              style: AppText.bodyLarge(color: AppColors.error, weight: FontWeight.w600)
                  .copyWith(letterSpacing: -0.40),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressBlock extends StatelessWidget {
  const _AddressBlock({required this.address, required this.location});
  final String address;
  final LatLng location;

  Future<void> _openMap() async {
    final lat = location.latitude;
    final lng = location.longitude;
    // Цепочка попыток: сначала маршрут от моего местоположения,
    // если ничего не открылось — просто координаты места.
    final attempts = <Uri>[
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
      Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
    ];
    for (final uri in attempts) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (_) {
        // переходим к следующему варианту
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Адрес'),
        SizedBox(height: 12.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(10.r),
          child: SizedBox(
            width: double.infinity,
            height: 170.h,
            child: OpenFreeMapView(
              initialCenter: location,
              initialZoom: 15,
              interactive: false,
              markers: [
                OpenFreeMapMarker(
                  id: 'order',
                  point: location,
                  color: AppColors.markerRed,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Icon(IconsaxPlusLinear.location, color: AppColors.primary, size: 18.r),
            SizedBox(width: 6.w),
            Expanded(
              child: Text(
                address,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.60,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8.r),
          child: InkWell(
            borderRadius: BorderRadius.circular(8.r),
            onTap: _openMap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(IconsaxPlusLinear.routing_2, color: AppColors.primary, size: 20.r),
                  SizedBox(width: 6.w),
                  Text(
                    'Построить маршрут',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.33,
                      letterSpacing: -0.23,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: AppColors.primary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w600,
        height: 1.54,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        SizedBox(height: 4.h),
        Text(value, style: AppText.body().copyWith(height: 1.50)),
      ],
    );
  }
}

class _PartyCard extends StatelessWidget {
  const _PartyCard({required this.userId, required this.orderId});
  final String userId;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final user = userById(userId);
    return InkWell(
      onTap: () => context.push('/order/$orderId/user/$userId'),
      child: SizedBox(
        height: 64.h,
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, 4.h, 16.w, 4.h),
          child: Row(
            children: [
              Container(
                width: 56.r,
                height: 56.r,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: user.photoPath != null
                    ? (user.photoPath!.startsWith('http')
                        ? Image.network(
                            user.photoPath!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              IconsaxPlusLinear.user,
                              color: AppColors.primary,
                              size: 32.r,
                            ),
                          )
                        : Image.file(
                            File(user.photoPath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              IconsaxPlusLinear.user,
                              color: AppColors.primary,
                              size: 32.r,
                            ),
                          ))
                    : Icon(
                        IconsaxPlusLinear.user,
                        color: AppColors.primary,
                        size: 32.r,
                      ),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Text(
                  user.name,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    height: 1.50,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 16.w),
              Icon(
                IconsaxPlusLinear.arrow_right_3,
                color: AppColors.primary,
                size: 24.r,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.color, required this.textColor, required this.label});
  final Color color;
  final Color textColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppText.body(color: textColor, weight: FontWeight.w500),
      ),
    );
  }
}

/// PrimaryButton, который сам блокирует себя на время `onPressed`-future.
/// Защищает от двойного тапа в момент отправки запроса в репозиторий.
class _AsyncPrimaryButton extends StatefulWidget {
  const _AsyncPrimaryButton({required this.label, required this.onPressed});
  final String label;
  final Future<void> Function() onPressed;

  @override
  State<_AsyncPrimaryButton> createState() => _AsyncPrimaryButtonState();
}

class _AsyncPrimaryButtonState extends State<_AsyncPrimaryButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      label: widget.label,
      onPressed: _busy ? null : _run,
    );
  }
}
