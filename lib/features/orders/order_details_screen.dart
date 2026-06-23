import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/system_bar_style.dart';
import '../../core/utils/auth_gate.dart';
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
import '../../data/remote/cities_repository.dart';
import '../../data/remote/pocketbase_client.dart';
import '../reviews/leave_review_screen.dart';
import '../reviews/reviews_providers.dart';
import 'responses_screen.dart' show pendingExecutorIdsProvider;

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
  // Сетевая ошибка должна пробрасываться наружу через AsyncError, а не
  // молча превращаться в false. Иначе при флапе сети кнопка «Откликнуться»
  // снова показывается активной, юзер жмёт повторно — сервер отдаёт
  // unique-violation. В UI ниже учитываем `.hasError` и блокируем
  // кнопку, чтобы не подставить юзера.
  final ids = await ref
      .read(orderResponsesRepositoryProvider)
      .pendingExecutorIds(args.orderId);
  return ids.contains(args.executorId);
});

/// Статус отклика текущего исполнителя на заказ. Нужен чтобы различать
/// «отклик в работе» (pending — баннер «Отклик отправлен») от «отклик
/// уже отклонён» (declined — баннер «Отклик не выбран», кнопка повторно
/// откликнуться не показывается). Без этого после отклонения заказчиком
/// исполнитель видит активную кнопку «Откликнуться» и жмёт её повторно —
/// сервер ругается unique-violation, а юзер не понимает почему.
final _myResponseStatusProvider = FutureProvider.autoDispose
    .family<String?, ({String orderId, String executorId})>((ref, args) async {
  if (args.executorId.isEmpty || args.executorId == 'me') return null;
  // Без blanket-catch: ошибку отдаём наверх, чтобы кнопка повторного
  // отклика блокировалась при неизвестном статусе (а не показывалась
  // отклонённому исполнителю при сбое сети). 404 «отклика нет» репозиторий
  // уже сам приводит к null.
  return ref
      .read(orderResponsesRepositoryProvider)
      .myResponseStatus(args.orderId, args.executorId);
});

class OrderDetailsScreen extends ConsumerStatefulWidget {
  const OrderDetailsScreen({super.key, required this.orderId, required this.mode});

  final String orderId;
  final String mode;

  @override
  ConsumerState<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen>
    with WidgetsBindingObserver {
  /// PocketBase realtime-подписка на запись заказа. Когда другая сторона
  /// меняет состояние (заказчик принял отклик, исполнитель отметил
  /// «оплата получена» и т.п.) сервер шлёт push по WebSocket, клиент
  /// инвалидирует провайдер и UI перерисовывается без ручного refresh.
  ///
  /// Хранится как функция-отписчик, которую возвращает `pb.collection.subscribe`.
  /// Вызываем её в dispose, иначе соединение остаётся открытым до GC.
  Future<void> Function()? _unsubscribe;

  /// Параллельная подписка на коллекцию order_responses. Без неё счётчик
  /// «Смотреть отклики (N)» у заказчика не растёт в реалтайме при новом
  /// отклике: создание order_responses не меняет саму запись orders,
  /// поэтому первая подписка (на orders) события не получает.
  Future<void> Function()? _unsubscribeResponses;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Подписку поднимаем в postFrame, чтобы `ref.read(pocketbaseProvider)`
    // не дёргался до полной готовности дерева провайдеров. На моках pb=null,
    // подписки не будет — это нормально.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribe();
      _subscribeResponses();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Пока приложение было в фоне, WebSocket realtime отключался и события
    // (например, новый отклик) терялись — поэтому, придя по пушу «появился
    // отклик», заказчик видел счётчик откликов 0 и заказ в старом статусе,
    // пока вручную не перезаходил. На возврате в приложение перечитываем
    // заказ и счётчик откликов, чтобы данные были свежими сразу.
    if (state == AppLifecycleState.resumed && mounted) {
      final pb = ref.read(pocketbaseProvider);
      if (pb == null || !pb.authStore.isValid) return;
      ref.invalidate(orderByIdProvider(widget.orderId));
      ref.invalidate(pendingExecutorIdsProvider(widget.orderId));
    }
  }

  Future<void> _subscribe() async {
    if (!mounted) return;
    final pb = ref.read(pocketbaseProvider);
    if (pb == null) return;
    // Гость (без валидного токена) realtime не подписывается: коллекция orders
    // закрыта правилом для анонима, событий он всё равно не получит. Деталь
    // заказа гость смотрит статично.
    if (!pb.authStore.isValid) return;
    try {
      final unsub = await pb.collection('orders').subscribe(
        widget.orderId,
        (_) {
          if (!mounted) return;
          // Перечитываем ТОЛЬКО уникальное для этого экрана: саму запись
          // заказа и счётчик ожидающих откликов. Три списка (лента, мои
          // заказы, мои как исполнитель) на том же потоке orders/* уже
          // инвалидирует глобальная подписка ordersRealtimeProvider — она
          // жива, пока в стеке навигатора лежит главный экран (заказ всегда
          // открывается через push ПОВЕРХ него). Раньше эти три списка
          // дёргались дважды на каждое событие (и без троттлинга).
          ref.invalidate(orderByIdProvider(widget.orderId));
          ref.invalidate(pendingExecutorIdsProvider(widget.orderId));
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

  Future<void> _subscribeResponses() async {
    if (!mounted) return;
    final pb = ref.read(pocketbaseProvider);
    if (pb == null) return;
    // Гостю realtime откликов не нужен — сервер всё равно не пришлёт событий,
    // а кнопок «принять/отклонить» у него нет. Не открываем лишний сокет.
    if (!pb.authStore.isValid) return;
    try {
      // PB-rules уже фильтруют события order_responses по правилу
      // «order_ref.customer == auth.id || executor == auth.id». На клиенте
      // дополнительно отбрасываем чужие записи (например, мои собственные
      // отклики на другие заказы как исполнитель), чтобы лишний раз не
      // дёргать запрос.
      final unsub = await pb.collection('order_responses').subscribe('*', (e) {
        if (!mounted) return;
        final rec = e.record;
        if (rec == null) {
          // delete без record — на всякий случай инвалидируем.
          ref.invalidate(pendingExecutorIdsProvider(widget.orderId));
          return;
        }
        if (rec.getStringValue('order_ref') == widget.orderId) {
          ref.invalidate(pendingExecutorIdsProvider(widget.orderId));
        }
      });
      if (!mounted) {
        await unsub();
        return;
      }
      _unsubscribeResponses = unsub;
    } catch (_) {/* нет WS — счётчик обновится при следующем visit */}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final unsub = _unsubscribe;
    _unsubscribe = null;
    if (unsub != null) {
      // ignore: discarded_futures
      unsub();
    }
    final unsubR = _unsubscribeResponses;
    _unsubscribeResponses = null;
    if (unsubR != null) {
      // ignore: discarded_futures
      unsubR();
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
    // Детали заказа — не каталог, поэтому к адресу добавляем город.
    final orderCityName = ref.watch(cityNamesProvider)[order.cityId];
    final addressWithCity = (orderCityName != null &&
            orderCityName.isNotEmpty &&
            order.address.isNotEmpty)
        ? '$orderCityName, ${order.address}'
        : order.address;
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
    // Статус отклика — null/pending/accepted/declined/withdrawn. Нужен
    // чтобы отделить «отклик ещё в работе» от «отклик уже отклонён»: во
    // втором случае нельзя снова жать «Откликнуться». Запрашиваем только
    // когда заказ open и я — потенциальный исполнитель.
    final myResponseStatusAsync = needHasResponseCheck
        ? ref.watch(
            _myResponseStatusProvider(
              (orderId: order.id, executorId: myId),
            ),
          )
        : null;
    final myResponseStatus = myResponseStatusAsync?.maybeWhen(
      data: (s) => s,
      orElse: () => null,
    );
    final myResponseDeclined = myResponseStatus == 'declined';

    // Пока грузится ЛЮБАЯ из двух проверок (есть ли активный отклик / какой
    // у него статус) и нет закэшированного значения — реального состояния
    // мы не знаем и активную кнопку «Откликнуться» не показываем. Раньше
    // учитывалась только первая проверка: если статус ещё грузился или упал,
    // уже отклонённый исполнитель на миг видел активную кнопку и повторным
    // тапом создавал новый отклик (до серверного лимита в 3 цикла).
    final respLoading = (hasMyResponseAsync?.isLoading ?? false) &&
        !(hasMyResponseAsync?.hasValue ?? false);
    final statusLoading = (myResponseStatusAsync?.isLoading ?? false) &&
        !(myResponseStatusAsync?.hasValue ?? false);
    final isCheckingMyResponse =
        needHasResponseCheck && (respLoading || statusLoading);
    // Сетевая ошибка любой из проверок — активную кнопку тоже не показываем:
    // тап дал бы 400 (отклик уже создан) либо дубль для отклонённого. Лучше
    // нейтральное «не удалось проверить».
    final respErr = (hasMyResponseAsync?.hasError ?? false) &&
        !(hasMyResponseAsync?.hasValue ?? false);
    final statusErr = (myResponseStatusAsync?.hasError ?? false) &&
        !(myResponseStatusAsync?.hasValue ?? false);
    final hasMyResponseCheckFailed = needHasResponseCheck &&
        !isCheckingMyResponse &&
        (respErr || statusErr);

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
                _AddressBlock(
                  address: addressWithCity,
                  location: order.location,
                  hasValidLocation: order.hasValidLocation,
                ),
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
              hasMyResponseCheckFailed,
              myResponseDeclined,
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
    bool hasMyResponseCheckFailed,
    bool myResponseDeclined,
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
    final hasMyReview = reviewsAsync.when(
      data: (list) => list.any((r) => r.fromUserId == myId),
      loading: () => true,
      // Ошибка бывает только в live (в моке провайдер не бросает).
      // Трактуем её как «состояние неизвестно»: считаем, что отзыв уже
      // есть, и кнопку «Оставить отзыв» НЕ показываем. Иначе на плохой
      // связи она снова появлялась бы по уже отрецензированному заказу, а
      // повторная отправка молча отбрасывалась бы сервером.
      error: (_, _) => true,
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
      // Гость может смотреть карточку, но откликнуться — только после входа.
      if (!requireAuth(context, ref, reason: 'откликнуться на заказ')) return;
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
        // Счётчик берём из pendingExecutorIdsProvider — это отдельный
        // запрос к order_responses, который реально знает количество
        // активных откликов. `order.responses.length` от маппера всегда
        // 0, потому что responses не expand'ятся в основном запросе
        // заказа (избегаем N+1). Раньше кнопка вечно показывала «(0)»,
        // хотя при тапе открывался список с откликами.
        final pendingAsync = ref.watch(pendingExecutorIdsProvider(order.id));
        final pendingCount = pendingAsync.maybeWhen(
          data: (ids) => ids.length,
          orElse: () => order.responses.length,
        );
        widgets.add(_ResponsesButton(
          count: pendingCount,
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
      } else if (order.canCancelByCustomer()) {
        // Отмена доступна, только если время не наступило И ни одна
        // FSM-метка не выставлена (условие совпадает с серверным). Голый
        // !isTimeArrived при рассинхроне часов устройства мог показать
        // «Отменить» на заказе с уже отмеченной работой → тап давал ошибку.
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
      if (hasMyResponseCheckFailed) {
        // Сетевая ошибка проверки. Активную кнопку «Откликнуться»
        // показывать опасно: вдруг отклик уже создан, и повторный create
        // упрётся в unique-индекс на сервере (400). Показываем
        // нейтральный баннер с подсказкой потянуть-обновить.
        widgets.add(_StatusBanner(
          color: AppColors.surfaceVariant,
          textColor: AppColors.textSecondary,
          // Экран деталей заказа не реализует pull-to-refresh, поэтому не
          // обещаем жест «потяните вниз» (его тут нет). Подсказываем рабочий
          // способ — переоткрыть заказ.
          label: 'Не удалось проверить отклик. Откройте заказ заново',
        ));
        return widgets;
      }
      if (hasMyResponse) {
        widgets.add(_StatusBanner(
          color: AppColors.primarySoft,
          textColor: AppColors.primary,
          label: 'Отклик отправлен',
        ));
      } else if (myResponseDeclined) {
        // Отдельный текст «Заказчик выбрал другого исполнителя» —
        // даёт честное объяснение, а не маскировка через «Отклик
        // отправлен». Раньше для declined показывался pending-баннер,
        // юзер видел противоречивый сигнал (ему уже отказали пушем,
        // а тут «жду ответа»). Цвет — surfaceVariant, текст —
        // textSecondary: визуально нейтрально, не «успех», но и не
        // ошибка. Повторно откликнуться нельзя (серверный
        // unique-индекс), кнопка вообще не показывается.
        widgets.add(_StatusBanner(
          color: AppColors.surfaceVariant,
          textColor: AppColors.textSecondary,
          label: 'Заказчик выбрал другого исполнителя',
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
    } else if (order.canCancelByExecutor()) {
      // Симметрично заказчику: отмена только до наступления времени и до
      // любой FSM-метки (как на сервере), а не по голому !isTimeArrived.
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
    // Возвращает true только если бэк действительно отменил заказ.
    // Раньше doCancel() возвращал Future<void>, ловил ошибку, показывал
    // тост — но дальше всё равно срабатывал context.pop(), и юзер
    // вылетал из деталей с ощущением «отменил», хотя заказ остался
    // активным на сервере.
    Future<bool> doCancel() async {
      try {
        await ref.read(ordersRepositoryProvider).cancel(id);
        if (!context.mounted) return true;
        ref.invalidate(myOrdersStreamProvider);
        ref.invalidate(myExecutorOrdersProvider);
        ref.invalidate(feedOrdersProvider);
        return true;
      } catch (e) {
        if (!context.mounted) return false;
        AppToast.show(context, humanizeBackendError(e));
        return false;
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
                  // после РЕАЛЬНОГО успеха pop'аем экран. Раньше pop вызывался
                  // безусловно — юзер уходил с экрана даже когда бэк отклонил
                  // отмену, и думал что отменил, хотя заказ остался активным.
                  Navigator.of(dialogCtx).pop();
                  final ok = await doCancel();
                  if (!context.mounted) return;
                  if (ok) context.pop();
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
  const _AddressBlock({
    required this.address,
    required this.location,
    this.hasValidLocation = true,
  });
  final String address;
  final LatLng location;

  /// Координаты осмысленны (не 0,0 от битой записи). Если нет — прячем
  /// карту-превью и кнопку маршрута, показываем только текст адреса,
  /// чтобы не вести пользователя «в океан».
  final bool hasValidLocation;

  /// Открывает адрес в внешней карте. На Android — через системный
  /// `geo:` интент, который показывает стандартный диалог «Открыть в»
  /// со всеми установленными у пользователя картами (Яндекс, 2ГИС,
  /// Google Maps, OsmAnd и т.д.). На iOS — Apple Maps (Apple не даёт
  /// сторонним приложениям показывать системный chooser).
  ///
  /// Раньше тут была наша собственная bottom-sheet шторка с явным
  /// списком 3-4 карт — но это всегда отставало от реального набора
  /// у юзера (поставил yandex/2gis — не было в нашем списке) и было
  /// «лишним кликом». Системный chooser Android — то, к чему юзер
  /// привычен в других приложениях.
  Future<void> _openMapPicker(BuildContext context) async {
    final lat = location.latitude;
    final lng = location.longitude;
    final encodedAddr = Uri.encodeComponent(address);

    // Android: стандартный `geo:` интент. launchUrl с
    // LaunchMode.externalApplication заставляет систему показать диалог
    // выбора приложения среди всех зарегистрировавших handler для этой
    // схемы (Яндекс.Карты, 2ГИС, Google Maps, OsmAnd, MAPS.ME и т.д.).
    // Формат `q=lat,lng(метка)` — Android-стандарт: в открытой карте
    // сразу появится маркер с подписью адреса, кнопка «Маршрут» в
    // каждом приложении своя.
    //
    // iOS: системного chooser'а для карт нет, Apple ограничивает.
    // Отдаём в Apple Maps (она встроена везде). Если у пользователя
    // установлено Яндекс/2ГИС/Google Maps и они зарегистрировали
    // ассоциацию с maps.apple.com — iOS откроет в выбранном.
    final Uri uri;
    if (Platform.isAndroid) {
      uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($encodedAddr)');
    } else {
      uri = Uri.parse(
          'https://maps.apple.com/?ll=$lat,$lng&q=$encodedAddr&daddr=$lat,$lng');
    }

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        AppToast.error(context, 'Не удалось открыть карту');
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.error(context, 'Не удалось открыть карту');
      }
    }
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
    // Координаты битые (0,0) — показываем только текст адреса без карты
    // и маршрута, чтобы не вести в океан. В норме сюда не попадаем:
    // сервер валидирует координаты при создании заказа.
    if (!hasValidLocation) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Адрес'),
          SizedBox(height: 12.h),
          Row(
            children: [
              Icon(IconsaxPlusLinear.location,
                  color: AppColors.primary, size: 18.r),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  address.isNotEmpty ? address : 'Адрес не указан',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.60,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      );
    }
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
            onTap: () => _openMapPicker(context),
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

class _PartyCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final mockUser = userById(userId);
    final name = (nameFromOrder != null && nameFromOrder!.isNotEmpty)
        ? nameFromOrder!
        : (mockUser?.name ?? 'Без имени');
    final photoPath = photoUrlFromOrder ?? mockUser?.photoPath;
    return InkWell(
      onTap: () {
        // Профиль заказчика открыт и гостю — обезличенная карточка (имя,
        // фото, рейтинг) без телефона и точного адреса. Действия, которые
        // требуют входа (звонок, отклик), гейтятся отдельно на своих экранах.
        context.push('/order/$orderId/user/$userId');
      },
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
                    // width/height обязательны: без них AppNetworkImage
                    // декодирует фото в полном размере (фото профиля в PB
                    // бывает ~1024px) в кружок 56px — лишние мегабайты в
                    // памяти. Локальная ветка ниже уже ограничена.
                    return AppNetworkImage(
                      url: photoPath,
                      width: 56.r,
                      height: 56.r,
                      fallback: fallback,
                    );
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
    if (!_busy) {
      return PrimaryButton(label: widget.label, onPressed: _run);
    }
    // На время сетевого запроса показываем крутилку вместо текста. Раньше
    // кнопка просто гасла (onPressed=null) без сигнала «идёт работа», и на
    // медленной связи это читалось как «зависло» — юзер жал повторно.
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16.r),
        child: SizedBox(
          height: 50.h,
          child: Center(
            child: SizedBox(
              width: 22.r,
              height: 22.r,
              child: const CircularProgressIndicator(
                color: AppColors.surface,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
      ),
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
    // Фуллскрин-галерея: тёмный фон → нужны светлые иконки статус-бара,
    // иначе значки времени и батареи сливаются с чёрным.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: simbaSystemBarStyle(
        navBarColor: AppColors.textPrimary,
        navIconBrightness: Brightness.light,
        statusIconBrightness: Brightness.light,
      ),
      child: Scaffold(
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
      ),
    );
  }
}
