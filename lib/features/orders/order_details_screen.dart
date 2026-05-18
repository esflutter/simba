import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_time_formatters.dart';
import '../../core/utils/backend_error.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_network_image.dart';
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

class OrderDetailsScreen extends ConsumerStatefulWidget {
  const OrderDetailsScreen({super.key, required this.orderId, required this.mode});

  final String orderId;
  final String mode;

  @override
  ConsumerState<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen> {
  /// PocketBase realtime-подписка на запись заказа. Когда другая сторона
  /// меняет состояние (заказчик принял отклик, исполнитель отметил
  /// «оплата получена» и т.п.) сервер шлёт push по WebSocket, клиент
  /// инвалидирует провайдер и UI перерисовывается без ручного refresh.
  ///
  /// Хранится как функция-отписчик, которую возвращает `pb.collection.subscribe`.
  /// Вызываем её в dispose, иначе соединение остаётся открытым до GC.
  Future<void> Function()? _unsubscribe;

  @override
  void initState() {
    super.initState();
    // Подписку поднимаем в postFrame, чтобы `ref.read(pocketbaseProvider)`
    // не дёргался до полной готовности дерева провайдеров. На моках pb=null,
    // подписки не будет — это нормально.
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  Future<void> _subscribe() async {
    if (!mounted) return;
    final pb = ref.read(pocketbaseProvider);
    if (pb == null) return;
    try {
      final unsub = await pb.collection('orders').subscribe(
        widget.orderId,
        (_) {
          if (!mounted) return;
          // Сервер сообщил об изменении этого заказа — перечитываем
          // основной провайдер + смежные (отклики, моя лента).
          ref.invalidate(orderByIdProvider(widget.orderId));
          ref.invalidate(myOrdersStreamProvider);
          ref.invalidate(myExecutorOrdersProvider);
        },
      );
      if (!mounted) {
        await unsub();
        return;
      }
      _unsubscribe = unsub;
    } catch (_) {
      // Сеть/WebSocket не поднялся — это не критика, экран продолжит
      // работать с явным refresh. Просто не получим realtime-апдейтов.
    }
  }

  @override
  void dispose() {
    final unsub = _unsubscribe;
    _unsubscribe = null;
    if (unsub != null) {
      // ignore: discarded_futures
      unsub();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncOrder = ref.watch(orderByIdProvider(widget.orderId));
    return asyncOrder.when(
      data: (order) {
        if (order == null) {
          return _NotFoundScreen(
            onRetry: () => ref.invalidate(orderByIdProvider(widget.orderId)),
          );
        }
        return _OrderDetailsBody(
          orderId: widget.orderId,
          mode: widget.mode,
          order: order,
        );
      },
      loading: () => const _LoadingScreen(),
      error: (_, _) => _LoadFailedScreen(
        onRetry: () => ref.invalidate(orderByIdProvider(widget.orderId)),
      ),
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
  const _NotFoundScreen({this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _ErrorScreenScaffold(
      message: 'Заказ не найден',
      onRetry: onRetry,
    );
  }
}

class _LoadFailedScreen extends StatelessWidget {
  const _LoadFailedScreen({this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _ErrorScreenScaffold(
      message: 'Не удалось загрузить заказ',
      onRetry: onRetry,
    );
  }
}

class _ErrorScreenScaffold extends StatelessWidget {
  const _ErrorScreenScaffold({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: AppText.h3(),
                    ),
                    if (onRetry != null) ...[
                      SizedBox(height: 16.h),
                      PrimaryButton(label: 'Повторить', onPressed: onRetry!),
                    ],
                  ],
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
    // Заказчику этот запрос не нужен — он сам себе откликаться не может.
    // Также не нужен исполнителю когда заказ уже не `open` (после accept
    // у других исполнителей кнопка «Откликнуться» всё равно скрыта, а
    // assigned executor видит другие CTA). Раньше провайдер дёргался
    // всегда и делал лишний запрос на бэк.
    final needHasResponseCheck =
        !isCustomer && order.status == OrderStatus.open;
    final hasMyResponseAsync = needHasResponseCheck
        ? ref.watch(
            _hasMyResponseProvider((orderId: order.id, executorId: myId)),
          )
        : null;
    final hasMyResponse = !needHasResponseCheck
        ? hasMyResponseFromOrder
        : (hasMyResponseAsync?.maybeWhen(
              data: (v) => v,
              orElse: () => hasMyResponseFromOrder,
            ) ??
            hasMyResponseFromOrder);
    // Пока проверка отклика грузится в первый раз и у нас нет даже
    // ранее закэшированного значения — мы НЕ знаем, отвечал ли уже
    // исполнитель. В этот момент нельзя показывать активную кнопку
    // «Откликнуться», иначе при открытии экрана с уже отправленным
    // откликом кнопка кратко моргает синей и потом превращается в
    // серый баннер «Отклик отправлен».
    final isCheckingMyResponse = needHasResponseCheck &&
        (hasMyResponseAsync?.isLoading ?? false) &&
        !(hasMyResponseAsync?.hasValue ?? false);

    // City-guard: deep-link мог открыть заказ из чужого города
    // (push-уведомление, history, шаринг). Баннер «Откликаться нельзя»
    // имеет смысл только когда заказ ещё открыт и пользователь к нему
    // никак не привязан. В истории исполнителя на собственном заказе
    // (executorId == myId) баннер был бы ложным — он уже отработал заказ
    // и «откликаться» там нечего; то же — для accepted/completed/cancelled.
    final selectedCityId =
        ref.watch(appControllerProvider.select((s) => s.selectedCityId));
    final isForeignCity = !isMine &&
        order.status == OrderStatus.open &&
        order.executorId != myId &&
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
            ? DateFormat('dd.MM.yyyy HH:mm', 'ru_RU')
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
                        final placeholder = Container(
                          width: 96.w,
                          color: AppColors.surfaceVariant,
                          child: Icon(
                            IconsaxPlusLinear.image,
                            color: AppColors.textTertiary,
                          ),
                        );
                        // Превью кликабельны: тап открывает полноэкранную
                        // галерею с pinch-zoom и свайпом между фото.
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              fullscreenDialog: true,
                              builder: (_) => _PhotoGalleryPage(
                                paths: order.photoPaths,
                                initialIndex: i,
                              ),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12.r),
                            child: isUrl
                                ? AppNetworkImage(
                                    url: path,
                                    width: 96.w,
                                    fallback: placeholder,
                                  )
                                : Image.file(
                                    File(path),
                                    width: 96.w,
                                    fit: BoxFit.cover,
                                    // cacheWidth — даунсэмплинг при декодировании,
                                    // чтобы 4K-фото из камеры не держало в heap
                                    // мегабайты ради 96px-миниатюры.
                                    cacheWidth: (192.w).round(),
                                    errorBuilder: (_, _, _) => placeholder,
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
                  _PartyCard(
                    userId: order.executorId!,
                    orderId: order.id,
                    nameFromOrder: order.executorName,
                    photoUrlFromOrder: order.executorPhotoUrl,
                  ),
                ],
                if (!isMine) ...[
                  SizedBox(height: 16.h),
                  _FieldLabel('Заказчик'),
                  SizedBox(height: 4.h),
                  _PartyCard(
                    userId: order.customerId,
                    orderId: order.id,
                    nameFromOrder: order.customerName,
                    photoUrlFromOrder: order.customerPhotoUrl,
                  ),
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
              isCheckingMyResponse,
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
    bool isCheckingMyResponse,
  ) {
    // Источник правды по отзывам — `reviewsByOrderProvider`. В live-режиме
    // `state.reviews` маппером не наполняется, и hasMyReview через локальный
    // стейт остался бы false даже после успешной отправки — кнопка «Оставить
    // отзыв» дублировалась бы, повторный клик ловил бы 4xx от бэка.
    //
    // Пока запрос грузится — считаем, что отзыв уже есть. Так кнопка
    // «Оставить отзыв» не мигнёт на доли секунды при открытии экрана,
    // если на самом деле юзер уже оставлял отзыв.
    final reviewsAsync = ref.watch(reviewsByOrderProvider(order.id));
    // .select — иначе любая мутация AppState ребилдит _buildActions.
    final reviewsLocal = ref.watch(
      appControllerProvider.select((s) => s.reviews),
    );
    final hasMyReview = reviewsAsync.when(
      data: (list) => list.any((r) => r.fromUserId == myId),
      loading: () => true,
      error: (_, _) => reviewsLocal
          .any((r) => r.orderId == order.id && r.fromUserId == myId),
    );
    final widgets = <Widget>[];

    // Заказчик отмечает «Отметить работу выполненной».
    // Передаём весь Order, чтобы репозиторий мог дозаполнить work_done_by_executor_at,
    // если он ещё пустой — иначе бэк-хук не сможет схлопнуть FSM в `completed`.
    Future<void> confirmWork() async {
      try {
        await ref.read(ordersRepositoryProvider).confirmWork(order);
        if (!context.mounted) return;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(myExecutorOrdersProvider);
        ref.invalidate(feedOrdersProvider);
        ref.invalidate(orderByIdProvider(order.id));
        // Уведомление в стиле приложения: без него юзер не видит, что
        // действие сработало — карточка просто пропадает из «Мои заказы»
        // в историю молча. Плашка появляется сверху, через 3 секунды
        // сама уезжает.
        AppToast.show(context, 'Заказ завершён');
      } catch (e) {
        if (!context.mounted) return;
        AppToast.show(context, humanizeBackendError(e));
      }
    }

    // Исполнитель отмечает «Отметить оплату полученной».
    Future<void> confirmPaymentReceived() async {
      try {
        await ref
            .read(ordersRepositoryProvider)
            .confirmPaymentReceived(order);
        if (!context.mounted) return;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(myExecutorOrdersProvider);
        ref.invalidate(feedOrdersProvider);
        ref.invalidate(orderByIdProvider(order.id));
        AppToast.show(context, 'Заказ завершён');
      } catch (e) {
        if (!context.mounted) return;
        AppToast.show(context, humanizeBackendError(e));
      }
    }

    // Исполнитель возвращает заказ в ленту.
    Future<void> cancelAsExecutor() async {
      try {
        await ref
            .read(ordersRepositoryProvider)
            .cancelAsExecutor(order.id);
        if (!context.mounted) return;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(myExecutorOrdersProvider);
        ref.invalidate(feedOrdersProvider);
        ref.invalidate(orderByIdProvider(order.id));
        AppToast.show(context, 'Заказ возвращён в ленту');
      } catch (e) {
        if (!context.mounted) return;
        AppToast.show(context, humanizeBackendError(e));
      }
    }

    Future<void> respond() async {
      try {
        await ref.read(orderResponsesRepositoryProvider).respond(order.id);
        if (!context.mounted) return;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(myExecutorOrdersProvider);
        ref.invalidate(feedOrdersProvider);
        ref.invalidate(orderByIdProvider(order.id));
        ref.invalidate(
          _hasMyResponseProvider((orderId: order.id, executorId: myId)),
        );
        // Дожидаемся, пока провайдер с проверкой отклика подтянет свежее
        // значение. Без этого кнопка успевает мигнуть «снова активной»
        // между концом запроса и моментом, когда родитель получит
        // hasMyResponse=true и заменит кнопку на серый баннер
        // «Отклик отправлен». Таймаут — чтобы кнопка не висла навсегда
        // при потере сети между запросами; следующий ребилд всё равно
        // подхватит свежие данные, когда они придут.
        try {
          await ref.read(
            _hasMyResponseProvider(
              (orderId: order.id, executorId: myId),
            ).future,
          ).timeout(const Duration(seconds: 4));
        } catch (_) {/* timeout / network error — не критично */}
        if (!context.mounted) return;
        AppToast.show(context, 'Отклик отправлен');
      } catch (e) {
        if (!context.mounted) return;
        AppToast.show(context, humanizeBackendError(e));
      }
    }

    // ── ЗАКАЗЧИК (isMine) ────────────────────────────────────────────────
    if (isMine) {
      if (order.status == OrderStatus.cancelled) {
        return widgets;
      }
      if (order.status == OrderStatus.open) {
        widgets.add(_ResponsesButton(
          count: order.responses.length,
          onTap: () => context.push('/order/${order.id}/responses'),
        ));
        widgets.add(SizedBox(height: 16.h));
        widgets.add(_CancelOrderButton(
          onTap: () => _confirmCancel(context, ref, order.id),
        ));
        return widgets;
      }
      // status == accepted | awaitingPayment | completed — единый блок
      // правой части схемы. awaitingPayment в новой схеме отображается
      // как обычный accepted с уже выставленным workDoneAt у исполнителя.
      if (order.isCompletedByCustomer) {
        // Заказчик уже отметил «работа выполнена» → доступен отзыв.
        if (!hasMyReview) {
          widgets.add(PrimaryButton(
            label: 'Оставить отзыв',
            onPressed: () => showLeaveReviewSheet(context, order.id),
          ));
        }
        return widgets;
      }
      // Заказчик ещё не отметил.
      if (order.isTimeArrived) {
        // Время наступило (или ASAP) — кнопка отметки. Отмены здесь нет
        // (по схеме: левая ветка — до времени, правая — после).
        widgets.add(_AsyncPrimaryButton(
          label: 'Отметить работу выполненной',
          onPressed: confirmWork,
        ));
      } else {
        // Время ещё не наступило — доступна только отмена.
        widgets.add(_CancelOrderButton(
          onTap: () => _confirmCancel(context, ref, order.id),
        ));
      }
      return widgets;
    }

    // ── ИСПОЛНИТЕЛЬ / СТОРОННИЙ (не isMine) ─────────────────────────────
    if (order.status == OrderStatus.cancelled) {
      return widgets;
    }
    if (order.status == OrderStatus.open) {
      if (isForeignCity) {
        widgets.add(_StatusBanner(
          color: AppColors.surfaceVariant,
          textColor: AppColors.textSecondary,
          label: 'Заказ из другого города',
        ));
        return widgets;
      }
      if (isCheckingMyResponse) {
        // Резервируем место кнопки, пока не пришёл ответ «отвечал ли
        // уже исполнитель»: без этого активная синяя «Откликнуться»
        // успела бы мигнуть до того, как мы поймём, что отклик уже
        // отправлен — и поверх рисуется баннер.
        widgets.add(SizedBox(height: 48.h));
        return widgets;
      }
      if (hasMyResponse) {
        widgets.add(_StatusBanner(
          color: AppColors.primarySoft,
          textColor: AppColors.primary,
          label: 'Отклик отправлен',
        ));
      } else if (order.isExpiredOpen) {
        widgets.add(_StatusBanner(
          color: AppColors.surfaceVariant,
          textColor: AppColors.textSecondary,
          label: 'Срок выполнения уже истёк',
        ));
      } else if (order.isStaleOpenWithoutExecutor) {
        // Заказ висел больше 30 дней без выбранного исполнителя — по
        // продукту он удаляется. Если по какой-то причине исполнитель
        // всё ещё видит его в деталях (старый кэш, бэк-крон не успел),
        // объясняем, почему отклик не примут.
        widgets.add(_StatusBanner(
          color: AppColors.surfaceVariant,
          textColor: AppColors.textSecondary,
          label: 'Заказ устарел и больше не активен',
        ));
      } else {
        widgets.add(_AsyncPrimaryButton(
          label: 'Откликнуться на заказ',
          onPressed: respond,
        ));
      }
      return widgets;
    }
    // accepted / awaitingPayment / completed для не-владельца.
    if (order.executorId != myId) {
      widgets.add(_StatusBanner(
        color: AppColors.surfaceVariant,
        textColor: AppColors.textSecondary,
        label: 'Заказ принят другим исполнителем',
      ));
      return widgets;
    }
    // Я — принятый исполнитель.
    if (order.isCompletedByExecutor) {
      if (!hasMyReview) {
        widgets.add(PrimaryButton(
          label: 'Оставить отзыв',
          onPressed: () => showLeaveReviewSheet(context, order.id),
        ));
      }
      return widgets;
    }
    if (order.isTimeArrived) {
      widgets.add(_AsyncPrimaryButton(
        label: 'Отметить оплату полученной',
        onPressed: confirmPaymentReceived,
      ));
    } else {
      widgets.add(_CancelOrderButton(
        onTap: () => _confirmCancelExecutor(
          context,
          ref,
          order.id,
          cancelAsExecutor,
        ),
      ));
    }
    return widgets;
  }

  void _confirmCancel(BuildContext context, WidgetRef ref, String id) {
    Future<void> doCancel() async {
      try {
        await ref.read(ordersRepositoryProvider).cancel(id);
        if (!context.mounted) return;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(myExecutorOrdersProvider);
        ref.invalidate(feedOrdersProvider);
      } catch (e) {
        if (!context.mounted) return;
        AppToast.show(context, humanizeBackendError(e));
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
            color: AppColors.surface,
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
                    painter: _XPainter(color: AppColors.surface, strokeWidth: 3.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Отменить заказ?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
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
                textColor: AppColors.surface,
                onTap: () async {
                  // Сначала закрываем диалог, потом ждём cancel, и только
                  // после успеха pop'аем экран. Раньше doCancel() шло без
                  // await и context.pop() вызывался синхронно — если cancel
                  // упал, тост ошибки летел на уже dispose'нутый экран.
                  Navigator.of(dialogCtx).pop();
                  await doCancel();
                  if (!context.mounted) return;
                  context.pop();
                },
              ),
              SizedBox(height: 8.h),
              _DialogActionButton(
                label: 'Отмена',
                background: AppColors.surfaceVariant,
                textColor: AppColors.textPrimary,
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
            color: AppColors.surface,
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
                    painter: _XPainter(color: AppColors.surface, strokeWidth: 3.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Отменить выполнение?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
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
                textColor: AppColors.surface,
                onTap: () async {
                  Navigator.of(dialogCtx).pop();
                  await doCancel();
                },
              ),
              SizedBox(height: 8.h),
              _DialogActionButton(
                label: 'Не отменять',
                background: AppColors.surfaceVariant,
                textColor: AppColors.textPrimary,
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
          // 48dp — стандартный минимум touch-target.
          height: 48.h,
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
                style: AppText.bodyLarge(color: AppColors.surface, weight: FontWeight.w600)
                    .copyWith(letterSpacing: -0.40),
              ),
              SizedBox(width: 10.w),
              Container(
                constraints: BoxConstraints(minWidth: 24.r),
                height: 24.r,
                padding: EdgeInsets.symmetric(horizontal: 6.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
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

  Future<void> _openExternalMap() async {
    final lat = location.latitude;
    final lng = location.longitude;
    // Пытаемся передать в карты СРАЗУ маршрут (от текущего положения к
    // адресу заказа), а не просто точку. Тогда нативное приложение карт
    // (Яндекс/2ГИС/Google Maps/Apple Maps) открывает экран с готовым
    // построенным маршрутом, и юзеру остаётся нажать «В путь». До этого
    // мы открывали просто точку, и человек вручную нажимал «Маршрут».
    //
    // Текущие координаты берём через Geolocator, но только если
    // разрешение уже есть — иначе не дёргаем permission popup ради
    // фичи маршрута, спокойно открываем точку (как было раньше).
    double? fromLat;
    double? fromLng;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 5),
          ),
        );
        fromLat = pos.latitude;
        fromLng = pos.longitude;
      }
    } catch (_) {/* нет GPS, таймаут — открываем без origin */}

    // Отдаём координаты системе — она показывает chooser среди
    // установленных приложений карт (Яндекс.Карты, 2ГИС, Google Maps,
    // Apple Maps), пользователь сам выбирает чем строить. Не навязываем
    // порядок.
    //   - iOS: maps://?saddr=...&daddr=... → Apple Maps строит маршрут;
    //     если стоит Яндекс/2ГИС, они тоже зарегистрированы как
    //     обработчики этой схемы и попадут в chooser.
    //   - Android: geo:0,0?q=lat,lng(адрес) — стандарт Android для
    //     показа точки. Для МАРШРУТА используем Google Maps directions
    //     URL (https://www.google.com/maps/dir/) — он открывается во всех
    //     приложениях карт, объявивших intent-filter на этот хост, и
    //     создаёт chooser. Чистый geo:-маршрут Android не стандартизировал.
    final encodedAddr = Uri.encodeComponent(address);
    final hasOrigin = fromLat != null && fromLng != null;

    Uri primary;
    if (Platform.isIOS) {
      primary = hasOrigin
          ? Uri.parse(
              'maps://?saddr=$fromLat,$fromLng&daddr=$lat,$lng&q=$encodedAddr')
          : Uri.parse('maps://?daddr=$lat,$lng&q=$encodedAddr');
    } else {
      primary = hasOrigin
          ? Uri.parse(
              'https://www.google.com/maps/dir/?api=1&origin=$fromLat,$fromLng&destination=$lat,$lng&travelmode=driving')
          : Uri.parse('geo:$lat,$lng?q=$lat,$lng($encodedAddr)');
    }
    try {
      final ok = await launchUrl(primary, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}
    // Жёсткий fallback на случай, если приложений карт нет вообще —
    // открываем веб-Яндекс с уже построенным маршрутом (если знаем
    // origin) или просто точкой назначения.
    try {
      final webUrl = hasOrigin
          ? 'https://yandex.ru/maps/?rtext=$fromLat,$fromLng~$lat,$lng&rtt=auto'
          : 'https://yandex.ru/maps/?rtext=~$lat,$lng&rtt=auto';
      await launchUrl(
        Uri.parse(webUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  void _openFullscreenMap(BuildContext context) {
    // Открываем полноэкранную карту через обычный Navigator.push, без
    // регистрации отдельного route в go_router: эта подстраница нужна
    // только из карточки заказа, deep-link на неё бессмысленен (без
    // location/адреса нечего показывать).
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _OrderLocationFullscreenPage(
          address: address,
          location: location,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Адрес'),
        SizedBox(height: 12.h),
        // Карта-превью прямо в карточке: pan/zoom доступны пальцами,
        // отдельной кнопки «развернуть» нет. Раньше карта была
        // некликабельна и сверху лежала иконка-кнопка — она часто не
        // прожималась из-за конфликта жестов в flutter_map. Теперь
        // ровно один сценарий: щипком приближаешь, пальцем двигаешь.
        // Полноэкранный режим оставлен через тап по строке адреса
        // ниже — для тех, кому нужно больше места.
        ClipRRect(
          borderRadius: BorderRadius.circular(10.r),
          child: SizedBox(
            width: double.infinity,
            height: 170.h,
            child: OpenFreeMapView(
              initialCenter: location,
              initialZoom: 15,
              interactive: true,
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
        // Адрес-строка кликабельна — тап открывает полноэкранную карту.
        // Это запасной путь к фуллскрину, поскольку на самой карте
        // pan/zoom съедают тап.
        InkWell(
          onTap: () => _openFullscreenMap(context),
          borderRadius: BorderRadius.circular(6.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 2.h),
            child: Row(
              children: [
                Icon(IconsaxPlusLinear.location,
                    color: AppColors.primary, size: 18.r),
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
                    // Раньше было maxLines: 1 — длинные адреса с
                    // корпусом/строением обрезались, и исполнитель не
                    // мог дочитать. Квартиры/подъезды в SimbA не
                    // хранятся, но базовый адрес с «д. 12 стр. 3» уже
                    // не влезал на 360px. 2 строки покрывают 99%
                    // реальных адресов.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 12.h),
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8.r),
          child: InkWell(
            borderRadius: BorderRadius.circular(8.r),
            onTap: _openExternalMap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(IconsaxPlusLinear.routing_2,
                      color: AppColors.primary, size: 20.r),
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

/// Полноэкранная карта с маркером заказа. Структура повторяет экран
/// выбора адреса при создании заказа, но в read-only варианте:
///   - белая шапка с pill-индикатором, заголовком «Адрес» и кнопкой
///     назад слева;
///   - карточка-поле с самим адресом (текст слева, иконка локации
///     справа). Поле не редактируется — только показывает значение;
///   - карта во всю оставшуюся высоту: pan/zoom, кнопки `+`/`−` и
///     «моё местоположение» — те же, что в основной ленте;
///   - кнопки «Выбрать» нет (read-only).
class _OrderLocationFullscreenPage extends StatelessWidget {
  const _OrderLocationFullscreenPage({
    required this.address,
    required this.location,
  });

  final String address;
  final LatLng location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Header ── такой же, как в `SelectAddressScreen`: pill +
          // центрированный заголовок «Адрес» + кнопка назад слева.
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
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
                            'Адрес',
                            style: AppText.bodyLarge(weight: FontWeight.w600)
                                .copyWith(
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
          ),
          // ── Адрес-карточка ── визуально как поле ввода (как при выборе
          // адреса), но read-only: текст занимает основное пространство,
          // справа — иконка локации.
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
            child: Container(
              height: 56.h,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      address,
                      style: AppText.body(color: AppColors.textPrimary)
                          .copyWith(height: 1.50),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Icon(
                    IconsaxPlusLinear.location,
                    size: 24.r,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          // ── Карта на оставшуюся высоту ──
          Expanded(
            child: OpenFreeMapView(
              initialCenter: location,
              initialZoom: 15,
              interactive: true,
              showZoomControls: true,
              showMyLocation: true,
              markers: [
                OpenFreeMapMarker(
                  id: 'order',
                  point: location,
                  color: AppColors.markerRed,
                ),
              ],
            ),
          ),
        ],
      ),
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
  const _PartyCard({
    required this.userId,
    required this.orderId,
    this.nameFromOrder,
    this.photoUrlFromOrder,
  });
  final String userId;
  final String orderId;
  // Имя и фото контрагента, пришедшие из expand'а Order (PB live-mode).
  // userById на проде возвращал бы demoCurrentUser ("Иван Иванов") для любого
  // незнакомого id — теперь сначала берём данные из самого заказа, а в
  // mock-окружении fall-back на справочник пользователей.
  final String? nameFromOrder;
  final String? photoUrlFromOrder;

  @override
  Widget build(BuildContext context) {
    final mockUser = userById(userId);
    final name = (nameFromOrder != null && nameFromOrder!.isNotEmpty)
        ? nameFromOrder!
        : (mockUser?.name ?? 'Без имени');
    final photoPath = photoUrlFromOrder ?? mockUser?.photoPath;
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
                child: Builder(builder: (_) {
                  final fallback = Icon(
                    IconsaxPlusLinear.user,
                    color: AppColors.primary,
                    size: 32.r,
                  );
                  if (photoPath == null) return fallback;
                  if (photoPath.startsWith('http')) {
                    return AppNetworkImage(url: photoPath, fallback: fallback);
                  }
                  return Image.file(
                    File(photoPath),
                    fit: BoxFit.cover,
                    cacheWidth: (112.r).round(),
                    cacheHeight: (112.r).round(),
                    errorBuilder: (_, _, _) => fallback,
                  );
                }),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: AppColors.textPrimary,
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

/// Полноэкранный просмотр фото заказа. Свайп между фото по горизонтали,
/// pinch-zoom внутри одного фото (через InteractiveViewer), кнопка
/// «Назад» поверх и счётчик «1 / 5», если фото больше одного.
class _PhotoGalleryPage extends StatefulWidget {
  const _PhotoGalleryPage({
    required this.paths,
    required this.initialIndex,
  });

  final List<String> paths;
  final int initialIndex;

  @override
  State<_PhotoGalleryPage> createState() => _PhotoGalleryPageState();
}

class _PhotoGalleryPageState extends State<_PhotoGalleryPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.textPrimary,
      body: Stack(
        children: [
          // ── Сам PageView с фото ──
          PageView.builder(
            controller: _pageController,
            itemCount: widget.paths.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) {
              final path = widget.paths[i];
              final isUrl = path.startsWith('http://') ||
                  path.startsWith('https://');
              // Pinch-zoom + pan: InteractiveViewer стандартный
              // флаттеровский путь, не тянет тяжёлых зависимостей
              // (photo_view) ради одной фичи.
              final image = isUrl
                  ? AppNetworkImage(
                      url: path,
                      fit: BoxFit.contain,
                    )
                  : Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      // Без cacheWidth — фото в фуллскрине должно
                      // декодиться в фактическом разрешении.
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(
                          IconsaxPlusLinear.image,
                          color: Colors.white54,
                          size: 64,
                        ),
                      ),
                    );
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(child: image),
              );
            },
          ),
          // ── Кнопка «Назад» поверх ──
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: SizedBox(
                      width: 44.r,
                      height: 44.r,
                      child: Icon(
                        IconsaxPlusLinear.arrow_left_2,
                        color: AppColors.surface,
                        size: 22.r,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ── Счётчик «N / M» — только если фото больше одного ──
          if (widget.paths.length > 1)
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.paths.length}',
                      style: TextStyle(
                        color: AppColors.surface,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
