import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/backend_error.dart';
import '../../core/utils/date_time_formatters.dart';
import '../../core/utils/messenger_launcher.dart';
import '../../core/utils/plural_ru.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/order_responses_repository.dart';
import '../../data/remote/orders_repository.dart';
import '../../data/remote/pocketbase_client.dart' show pocketbaseProvider;
import '../../data/remote/users_repository.dart';
import '../reviews/reviews_providers.dart' show reviewsForUserAsRoleProvider;
import 'order_details_screen.dart' show orderByIdProvider;
import 'responses_screen.dart' show pendingExecutorIdsProvider;

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key, required this.userId, this.orderId});
  final String userId;
  final String? orderId;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  /// PB realtime-подписка на конкретный заказ (если открыли профиль из
  /// контекста заказа). Без неё: смотришь карточку исполнителя, заказ
  /// в это время отменяется или принимается — кнопки «Позвонить»/«Написать»
  /// остаются как ни в чём не бывало.
  Future<void> Function()? _orderUnsub;

  /// PB realtime-подписка на коллекцию reviews для отображаемого юзера.
  /// Без неё рейтинг и список отзывов не освежаются, если кто-то третий
  /// в этот момент оставляет отзыв этому юзеру.
  Future<void> Function()? _reviewsUnsub;

  @override
  void initState() {
    super.initState();
    final orderId = widget.orderId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (orderId != null) _subscribeOrder(orderId);
      _subscribeReviews();
    });
  }

  Future<void> _subscribeOrder(String orderId) async {
    if (!mounted) return;
    final pb = ref.read(pocketbaseProvider);
    if (pb == null) return;
    // Гостю realtime не нужен: серверные правила всё равно не пришлют ему
    // ни одного события. Не открываем лишний сокет (как и в деталях заказа).
    if (!pb.authStore.isValid) return;
    try {
      final unsub = await pb.collection('orders').subscribe(orderId, (_) {
        if (!mounted) return;
        ref.invalidate(orderByIdProvider(orderId));
        ref.invalidate(pendingExecutorIdsProvider(orderId));
      });
      if (!mounted) {
        await unsub();
        return;
      }
      _orderUnsub = unsub;
    } catch (_) {/* WebSocket недоступен — не критично */}
  }

  Future<void> _subscribeReviews() async {
    if (!mounted) return;
    final pb = ref.read(pocketbaseProvider);
    if (pb == null) return;
    // Гостю realtime не нужен (отзывы он и так не читает) — сокет не открываем.
    if (!pb.authStore.isValid) return;
    final targetUserId = widget.userId;
    try {
      final unsub = await pb.collection('reviews').subscribe('*', (e) {
        if (!mounted) return;
        final rec = e.record;
        if (rec == null) {
          ref.invalidate(reviewsForUserAsRoleProvider);
          // И публичный профиль тоже — рейтинг пересчитывается бэк-хуком.
          ref.invalidate(publicUserProvider(targetUserId));
          return;
        }
        if (rec.getStringValue('to_user') == targetUserId) {
          ref.invalidate(reviewsForUserAsRoleProvider);
          ref.invalidate(publicUserProvider(targetUserId));
        }
      });
      if (!mounted) {
        await unsub();
        return;
      }
      _reviewsUnsub = unsub;
    } catch (_) {/* WS недоступен — норм */}
  }

  @override
  void dispose() {
    final unsubOrder = _orderUnsub;
    _orderUnsub = null;
    if (unsubOrder != null) {
      // ignore: discarded_futures
      unsubOrder();
    }
    final unsubReviews = _reviewsUnsub;
    _reviewsUnsub = null;
    if (unsubReviews != null) {
      // ignore: discarded_futures
      unsubReviews();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.userId;
    final orderId = widget.orderId;
    // .select — иначе любой setRole/createOrder ребилдит профиль контрагента.
    final mockReviews = ref.watch(
      appControllerProvider.select((s) => s.reviews),
    );
    final mockMyOrders = ref.watch(
      appControllerProvider.select((s) => s.myOrders),
    );
    final mockOrders = ref.watch(
      appControllerProvider.select((s) => s.orders),
    );
    // Заказ берём из orderByIdProvider — это «живой» запрос к PB, который
    // подписан на realtime (см. _subscribeOrder выше). Раньше тут была
    // только локальная выборка из mockMyOrders/mockOrders, и в live-режиме
    // после принятия исполнителя order оказывался null — из-за этого
    // canContact считался false и кнопки «Позвонить / Написать» не
    // показывались, хотя статус заказа уже сменился на accepted.
    //
    // Mock-списки оставляем как fallback для мок-режима и на время загрузки
    // (asyncOrder.isLoading) — иначе экран мигает пустыми кнопками.
    final asyncOrder = orderId == null
        ? const AsyncValue<Order?>.data(null)
        : ref.watch(orderByIdProvider(orderId));
    final orderFromMock = orderId == null
        ? null
        : [...mockMyOrders, ...mockOrders]
            .cast<Order?>()
            .firstWhere((o) => o?.id == orderId, orElse: () => null);
    final order = asyncOrder.maybeWhen(
      data: (o) => o ?? orderFromMock,
      orElse: () => orderFromMock,
    );
    // В какой роли смотрим этого пользователя: заказчик (он автор заказа) —
    // иначе исполнитель (откликнувшийся / принятый). От роли зависит, какой
    // рейтинг и какие отзывы показываем, чтобы цифры совпадали и со списком
    // откликов, и между собой (рейтинг ↔ распределение «звёзд»).
    final viewedRole = (order != null && order.customerId == userId)
        ? UserRole.customer
        : UserRole.executor;
    // Отзывы о пользователе ИМЕННО в этой роли (live → PB, иначе мок-fallback).
    // На loading возвращаем null → ниже рендерим спиннер вместо «Нет отзывов».
    final asyncReviews = ref.watch(
        reviewsForUserAsRoleProvider((userId: userId, role: viewedRole)));
    final List<Review>? reviewsOrNull = asyncReviews.when(
      data: (xs) => xs,
      loading: () => null,
      error: (_, _) =>
          mockReviews.where((r) => r.toUserId == userId).toList(),
    );
    final reviews = reviewsOrNull ?? const <Review>[];
    // Имя/фото берём в первую очередь из expand'а Order (PB live-mode), и
    // только fall-back на справочник моков. До фикса userById возвращал
    // demoCurrentUser («Иван Иванов») для любого незнакомого PB-id, что в
    // проде сводило профиль контрагента к одной и той же мок-карточке.
    final nameFromOrder = order == null
        ? null
        : (order.customerId == userId
            ? order.customerName
            : order.executorId == userId
                ? order.executorName
                : null);
    final photoFromOrder = order == null
        ? null
        : (order.customerId == userId
            ? order.customerPhotoUrl
            : order.executorId == userId
                ? order.executorPhotoUrl
                : null);
    // Тянем публичный профиль из PB: имя, фото, рейтинги, has_tools/has_transport.
    // На моке провайдер вернёт `userById(userId)` (или null для неизвестного id).
    final asyncPublic = ref.watch(publicUserProvider(userId));
    final publicUser = asyncPublic.maybeWhen(data: (u) => u, orElse: () => null);
    final mockUser = userById(userId);
    final user = publicUser ??
        mockUser ??
        AppUser(
          id: userId,
          name: nameFromOrder ?? 'Без имени',
          phone: '',
          photoPath: photoFromOrder,
        );
    // Если есть данные из Order — они побеждают (свежие из expand'а).
    final displayName = (nameFromOrder != null && nameFromOrder.isNotEmpty)
        ? nameFromOrder
        : user.name;
    final displayPhoto = photoFromOrder ?? user.photoPath;
    // Гость (просмотр каталога без входа) не может загрузить список отзывов —
    // коллекция reviews требует авторизацию. Чтобы не показывать честно
    // отрецензированного заказчика как «Нет отзывов», ниже выводим
    // агрегированный рейтинг (имя+рейтинг приходят из публичной ручки), а
    // тексты отзывов оставляем за входом.
    final pbAuth = ref.watch(pocketbaseProvider);
    final isGuest = pbAuth != null && !pbAuth.authStore.isValid;
    // Источник правды по «является ли этот юзер кандидатом на мой заказ» —
    // pendingExecutorIdsProvider (живой запрос к order_responses). В live
    // маппер не наполняет `order.responses` (избегаем N+1), и проверка через
    // него всегда давала false → кнопки «Принять/Отклонить» не появлялись
    // на профиле исполнителя, когда заказчик заходил из экрана откликов.
    // Тот же шаблон бага, что мы починили в счётчике откликов.
    final pendingIdsAsync = orderId == null
        ? const AsyncValue<List<String>>.data(<String>[])
        : ref.watch(pendingExecutorIdsProvider(orderId));
    final isInPendingFromServer = pendingIdsAsync.maybeWhen(
      data: (ids) => ids.contains(userId),
      orElse: () => false,
    );
    final isPendingCandidate = order != null &&
        order.status == OrderStatus.open &&
        (isInPendingFromServer || order.responses.contains(userId));
    // Контакты доступны от момента match'а и до полной отмены.
    // Это включает все промежуточные состояния (accepted, awaitingPayment,
    // completed) — у заказа уже есть исполнитель, обе стороны должны
    // видеть телефоны и иметь возможность связаться. До этого
    // completed-фаза скрывала кнопки, и юзер не мог дозвониться, если,
    // например, исполнитель отметил оплату, а в физическом мире
    // оказались проблемы.
    //
    // Скрывается ТОЛЬКО когда заказ ещё не принят (open) или отменён
    // полностью (cancelled) — связываться не с кем или нечем.
    final canContact = order != null &&
        order.status != OrderStatus.open &&
        order.status != OrderStatus.cancelled &&
        (order.customerId == userId || order.executorId == userId) &&
        // Сервер открывает телефон по завершённому заказу только 14 дней.
        // Зеркалим это правило, иначе кнопки «Позвонить/Написать» висят
        // вечно, а после 14 дней тап по ним ничего не даёт (403 contact_locked).
        !(order.status == OrderStatus.completed &&
            (order.completedAt == null ||
                DateTime.now().difference(order.completedAt!).inDays >= 14));

    final ratingDistribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in reviews) {
      ratingDistribution[r.rating] = (ratingDistribution[r.rating] ?? 0) + 1;
    }
    // Рейтинг берём из агрегата ПО РОЛИ — он совпадает со списком откликов
    // (там тоже агрегат по роли исполнителя), а отзывы/распределение ниже
    // теперь тоже отфильтрованы по этой роли, поэтому всё согласовано.
    final avgRating = user.ratingFor(viewedRole);

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
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16.w,
                  8.h,
                  16.w,
                  isPendingCandidate
                      ? 0
                      : 16.h + MediaQuery.viewPaddingOf(context).bottom,
                ),
                children: [
                  AppCard(
                    padding: EdgeInsets.all(16.w),
                    borderRadius: BorderRadius.circular(10.r),
                    child: Row(
                      children: [
                        Container(
                          width: 56.r,
                          height: 56.r,
                          decoration: const BoxDecoration(
                            color: AppColors.background,
                            shape: BoxShape.circle,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Builder(builder: (_) {
                            final fallback = Icon(
                              IconsaxPlusLinear.user,
                              color: AppColors.primary,
                              size: 32.r,
                            );
                            if (displayPhoto == null) return fallback;
                            if (displayPhoto.startsWith('http')) {
                              return AppNetworkImage(
                                url: displayPhoto,
                                width: 56.r,
                                height: 56.r,
                                fallback: fallback,
                              );
                            }
                            return Image.file(
                              File(displayPhoto),
                              fit: BoxFit.cover,
                              // 56r ≈ 168px. Без cap-а аватар 1024×1024
                              // декодится целиком под кружок 56lp.
                              cacheWidth: 168,
                              cacheHeight: 168,
                              errorBuilder: (_, _, _) => fallback,
                            );
                          }),
                        ),
                        SizedBox(width: 16.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 20.sp,
                                        fontWeight: FontWeight.w600,
                                        height: 1.20,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (user.hasTools) ...[
                                    SizedBox(width: 8.w),
                                    Image.asset(
                                      'assets/images/icon_tools.png',
                                      width: 16.r,
                                      height: 16.r,
                                    ),
                                  ],
                                  if (user.hasTransport) ...[
                                    SizedBox(width: 8.w),
                                    Image.asset(
                                      'assets/images/icon_transport.png',
                                      width: 20.r,
                                      height: 16.r,
                                    ),
                                  ],
                                ],
                              ),
                              if (canContact) ...[
                                SizedBox(height: 4.h),
                                Consumer(builder: (context, ref, _) {
                                  final args = ContactPhoneArgs(
                                    userId: userId,
                                    orderId: orderId!,
                                  );
                                  final phoneAsync =
                                      ref.watch(contactPhoneProvider(args));
                                  final phone = phoneAsync.maybeWhen(
                                    data: (p) => p ?? user.phone,
                                    orElse: () => user.phone,
                                  );
                                  return Text(
                                    phone,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.w600,
                                      height: 1.50,
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canContact) ...[
                    SizedBox(height: 8.h),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      child: Consumer(builder: (context, ref, _) {
                        final args = ContactPhoneArgs(
                          userId: userId,
                          orderId: orderId!,
                        );
                        final phone = ref
                            .watch(contactPhoneProvider(args))
                            .maybeWhen(
                              data: (p) => p ?? user.phone,
                              orElse: () => user.phone,
                            );
                        return Row(
                          children: [
                            Expanded(
                              child: _ContactButton(
                                label: 'Написать',
                                background: AppColors.surface,
                                color: AppColors.textPrimary,
                                onTap: () => _showContactSheet(context, phone),
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: _ContactButton(
                                label: 'Позвонить',
                                background: AppColors.primary,
                                // Белый текст на синем — нормальный
                                // контраст. До этого тут был #F5F5F5
                                // (фоновый серый), и надпись почти
                                // не читалась.
                                color: AppColors.surface,
                                onTap: () => _callPhone(phone),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ],
                  SizedBox(height: 8.h),
                  Text(
                    'Отзывы',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.54,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  if (reviewsOrNull == null)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 64.h),
                      child: const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      ),
                    )
                  else if (reviews.isEmpty &&
                      isGuest &&
                      user.reviewsCountFor(viewedRole) > 0)
                    // Гость: список отзывов недоступен (нужен вход), но
                    // агрегированный рейтинг (по роли) показать можем — иначе
                    // отрецензированный пользователь выглядел бы как «Нет отзывов».
                    AppCard(
                      padding: EdgeInsets.all(12.w),
                      borderRadius: BorderRadius.circular(10.r),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                formatRating(user.ratingFor(viewedRole)),
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 20.sp,
                                  fontWeight: FontWeight.w700,
                                  height: 1.20,
                                ),
                              ),
                              SizedBox(width: 4.w),
                              ...List.generate(
                                5,
                                (i) => Padding(
                                  padding:
                                      EdgeInsets.only(right: i == 4 ? 0 : 2.w),
                                  child: Image.asset(
                                    i < user.ratingFor(viewedRole).round()
                                        ? 'assets/images/icon_ranking.webp'
                                        : 'assets/images/icon_star_empty.webp',
                                    width: 20.r,
                                    height: 20.r,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            '${user.reviewsCountFor(viewedRole)} '
                            '${pluralReviews(user.reviewsCountFor(viewedRole))}',
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.60),
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w400,
                              height: 1.38,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            'Тексты отзывов открываются после входа',
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.60),
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w400,
                              height: 1.38,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (reviews.isEmpty)
                    // Empty-state центрируем по оставшейся высоте экрана,
                    // а не приклеиваем к заголовку «Отзывы» сверху. Раньше
                    // звезда висела сразу под заголовком, а ниже зияла
                    // большая пустая полоса — выглядело так, будто
                    // подсказка случайно «улетела вверх».
                    LayoutBuilder(
                      builder: (ctx, constraints) {
                        // Высота от низа заголовка «Отзывы» до края
                        // экрана: ListView отдаёт нам maxHeight=∞ (он
                        // вертикально-скроллящийся), поэтому считаем
                        // через MediaQuery.
                        final media = MediaQuery.of(ctx);
                        final available = media.size.height -
                            media.viewPadding.top -
                            // Запас на шапку, карточку контакта и
                            // заголовок «Отзывы». Подобрано визуально
                            // под дизайн 360×800.
                            340.h;
                        final minHeight = available > 240.h ? available : 240.h;
                        return SizedBox(
                          height: minHeight,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  IconsaxPlusLinear.star_1,
                                  size: 80.r,
                                  color: AppColors.star,
                                ),
                                SizedBox(height: 24.h),
                                Text(
                                  'Нет отзывов',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 20.sp,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                    letterSpacing: -0.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  else ...[
                    AppCard(
                      padding: EdgeInsets.all(12.w),
                      borderRadius: BorderRadius.circular(10.r),
                      child: _RatingSummary(
                        average: avgRating,
                        total: reviews.length,
                        distribution: ratingDistribution,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    // На большом количестве отзывов (100+) разворачивать всё
                    // сразу через spread дорого: каждая карточка декодит
                    // аватарку и считает свой layout. Показываем порциями,
                    // подгрузка — по тапу пользователя.
                    _ReviewsList(reviews: reviews),
                  ],
                ],
              ),
            ),
          if (isPendingCandidate)
            // isPendingCandidate ⇒ orderId != null (см. выше), фиксируем это
            // в локальную не-nullable переменную, чтобы closure'ам не нужно
            // было дописывать `!` к orderId — анализатор иначе ругается на
            // лишние non-null assertions.
            Builder(builder: (_) {
              final safeOrderId = orderId!;
              return _CandidateActionBar(
                onAccept: () async {
                  try {
                    await ref
                        .read(orderResponsesRepositoryProvider)
                        .accept(safeOrderId, userId);
                    if (!context.mounted) return;
                    ref.invalidate(myOrdersStreamProvider);
                    ref.invalidate(myExecutorOrdersProvider);
                    ref.invalidate(feedOrdersProvider);
                    ref.invalidate(pendingExecutorIdsProvider(safeOrderId));
                    ref.invalidate(orderByIdProvider(safeOrderId));
                    AppToast.show(context, 'Исполнитель принят');
                    // После принятия остальные отклики автоматически отклонены —
                    // экран откликов под нами теперь пустой. Чистим стек,
                    // чтобы back с профиля вёл на детали заказа, а не на
                    // пустой экран откликов.
                    //
                    // Раньше pop + pushReplacement шли подряд в одном
                    // кадре: pop уже анимировал уход профиля, а
                    // pushReplacement пытался заменить уже снимающийся
                    // top — на медленных устройствах ловилось «голое»
                    // состояние навигатора. Откладываем второй вызов
                    // через postFrame, чтобы он отработал ПОСЛЕ того,
                    // как pop успел снять верхний слой.
                    if (context.canPop()) context.pop();
                    final navTarget = '/order/$safeOrderId/user/$userId';
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!context.mounted) return;
                      context.pushReplacement(navTarget);
                    });
                  } on OrderResponseGoneException {
                    // Исполнитель отозвал отклик параллельно — не показывать
                    // ложный «принят». Перерисуем экран, чтобы скрыть кнопку.
                    if (!context.mounted) return;
                    ref.invalidate(pendingExecutorIdsProvider(safeOrderId));
                    ref.invalidate(orderByIdProvider(safeOrderId));
                    AppToast.show(context, 'Этот отклик уже недоступен');
                  } catch (e) {
                    // Конкретная причина важнее обезличенного «Ошибка»:
                    // лимиты, city_mismatch, заказ уже в другом статусе —
                    // юзер должен понимать что произошло.
                    if (!context.mounted) return;
                    AppToast.show(context, humanizeBackendError(e));
                  }
                },
                onDecline: () async {
                  // Источник правды по живым откликам — pendingExecutorIdsProvider
                  // (отдельный запрос к order_responses). `order.responses` от
                  // маппера в live-режиме всегда пуст: responses не expand'ятся
                  // в основном запросе заказа. Из-за этого `wasLast` всегда был
                  // false → после отклонения последнего исполнителя через карточку
                  // профиля экран откликов под нами оставался открытым с пустым
                  // списком, юзеру приходилось жать «назад» ещё раз вручную.
                  final pendingBefore = await ref
                      .read(pendingExecutorIdsProvider(safeOrderId).future)
                      .catchError((_) => const <String>[]);
                  final wasLast = pendingBefore.length == 1 &&
                      pendingBefore.contains(userId);
                  try {
                    await ref
                        .read(orderResponsesRepositoryProvider)
                        .decline(safeOrderId, userId);
                    if (!context.mounted) return;
                    ref.invalidate(myOrdersStreamProvider);
                    ref.invalidate(myExecutorOrdersProvider);
                    ref.invalidate(feedOrdersProvider);
                    ref.invalidate(pendingExecutorIdsProvider(safeOrderId));
                    ref.invalidate(orderByIdProvider(safeOrderId));
                    AppToast.show(context, 'Исполнитель отклонён');
                    if (context.canPop()) context.pop();
                    if (wasLast && context.canPop()) context.pop();
                  } on OrderResponseGoneException {
                    if (!context.mounted) return;
                    ref.invalidate(pendingExecutorIdsProvider(safeOrderId));
                    ref.invalidate(orderByIdProvider(safeOrderId));
                    AppToast.show(context, 'Этот отклик уже недоступен');
                  } catch (e) {
                    // Конкретная причина важнее обезличенного «Ошибка»:
                    // лимиты, city_mismatch, заказ уже в другом статусе —
                    // юзер должен понимать что произошло.
                    if (!context.mounted) return;
                    AppToast.show(context, humanizeBackendError(e));
                  }
                },
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showContactSheet(BuildContext context, String phone) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactSheet(phone: phone),
    );
  }

  Future<void> _callPhone(String phone) async {
    final sanitized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (sanitized.isEmpty) {
      if (mounted) AppToast.show(context, 'Номер телефона недоступен');
      return;
    }
    final uri = Uri.parse('tel:$sanitized');
    try {
      // canLaunchUrl + проверка результата launchUrl — без них на
      // устройствах без SIM (планшеты, эмуляторы) тап «Позвонить»
      // молча ничего не делал, пользователь не понимал, что не работает.
      final can = await canLaunchUrl(uri);
      if (!can) {
        if (!mounted) return;
        AppToast.show(context, 'На устройстве нет приложения для звонков');
        return;
      }
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        AppToast.show(context, 'Не удалось открыть набор номера');
      }
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Не удалось открыть набор номера');
    }
  }
}

class _CandidateActionBar extends StatefulWidget {
  const _CandidateActionBar({required this.onAccept, required this.onDecline});
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  @override
  State<_CandidateActionBar> createState() => _CandidateActionBarState();
}

class _CandidateActionBarState extends State<_CandidateActionBar> {
  // Какое действие сейчас выполняется ('accept'/'decline'/null). Нужно,
  // чтобы показать крутилку именно на нажатой кнопке, а вторую — погасить.
  String? _busyAction;

  Future<void> _run(String kind, Future<void> Function() action) async {
    if (_busyAction != null) return;
    setState(() => _busyAction = kind);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionBarButton(
                label: 'Принять',
                background: AppColors.primary,
                textColor: AppColors.surface,
                busy: _busyAction == 'accept',
                onTap: _busyAction != null
                    ? null
                    : () => _run('accept', widget.onAccept),
              ),
              SizedBox(height: 8.h),
              _ActionBarButton(
                label: 'Отклонить',
                background: AppColors.surfaceVariant,
                textColor: AppColors.error,
                busy: _busyAction == 'decline',
                onTap: _busyAction != null
                    ? null
                    : () => _run('decline', widget.onDecline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBarButton extends StatelessWidget {
  const _ActionBarButton({
    required this.label,
    required this.background,
    required this.textColor,
    required this.onTap,
    this.busy = false,
  });
  final String label;
  final Color background;
  final Color textColor;
  final VoidCallback? onTap;

  /// `true` — по этой кнопке идёт запрос: сохраняем активный цвет и
  /// показываем крутилку вместо текста.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    // Нажатая кнопка (busy) остаётся в активном цвете со спиннером; вторая,
    // просто отключённая на время запроса, гаснет серым.
    final active = busy || !disabled;
    return Material(
      color: active ? background : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 50.h,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 22.r,
                    height: 22.r,
                    child: CircularProgressIndicator(
                      color: textColor,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: disabled ? AppColors.textTertiary : textColor,
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

class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.label,
    required this.background,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color color;
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
          // 48dp — стандартный минимум touch-target. Раньше 36 — кнопки
          // «Написать»/«Позвонить» были слишком маленькие для пальца.
          height: 48.h,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: color,
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

class _ContactSheet extends StatelessWidget {
  const _ContactSheet({required this.phone});

  /// Телефон контрагента (в любом формате — `+7 (900)…` либо E.164).
  /// MessengerLauncher сам приведёт строку к цифрам.
  final String phone;

  /// Открыть мессенджер через [launcher] и закрыть шторку. На отказ
  /// (приложение не установлено + web-fallback не сработал) показываем
  /// тост — раньше тут был молчаливый `pop()`, юзер не понимал, что
  /// произошло.
  Future<void> _open(
    BuildContext sheetContext,
    Future<bool> Function() launcher,
    String labelOnFail,
  ) async {
    final ok = await launcher();
    if (!sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    if (!ok) {
      AppToast.show(sheetContext, '$labelOnFail не открылся');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(15.r)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(
                    'assets/images/icon_messages.webp',
                    width: 24.r,
                    height: 24.r,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Написать',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.29,
                    ),
                  ),
                  const Spacer(),
                  // 44×44 — минимум touch-target для крестика sheet'а.
                  SizedBox(
                    width: 44.r,
                    height: 44.r,
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).pop(),
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
              SizedBox(height: 16.h),
              Container(height: 1, color: AppColors.divider),
              SizedBox(height: 22.h),
              Row(
                children: [
                  _Messenger(
                    label: 'WhatsApp',
                    asset: 'assets/images/icon_whatsapp.webp',
                    enabled: hasPhone,
                    onTap: () => _open(
                      context,
                      () => MessengerLauncher.openWhatsApp(phone),
                      'WhatsApp',
                    ),
                  ),
                  SizedBox(width: 28.w),
                  _Messenger(
                    label: 'Telegram',
                    asset: 'assets/images/icon_telegram.webp',
                    enabled: hasPhone,
                    onTap: () => _open(
                      context,
                      () => MessengerLauncher.openTelegram(phone: phone),
                      'Telegram',
                    ),
                  ),
                  SizedBox(width: 28.w),
                  _Messenger(
                    // У MAX нет ссылки/схемы «открыть диалог по номеру»
                    // (диплинки только на чаты/каналы/ботов, поиск по номеру —
                    // ручной внутри приложения), поэтому здесь вместо MAX —
                    // SMS: системное приложение сообщений по номеру. В шторке
                    // поддержки MAX остаётся (там контакт — username/ссылка).
                    label: 'SMS',
                    icon: Icons.sms_rounded,
                    iconBg: const Color(0xFF34C759),
                    enabled: hasPhone,
                    onTap: () => _open(
                      context,
                      () => MessengerLauncher.openSms(phone),
                      'SMS',
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
            ],
          ),
        ),
      ),
    );
  }
}

class _Messenger extends StatelessWidget {
  const _Messenger({
    required this.label,
    required this.onTap,
    this.asset,
    this.icon,
    this.iconBg,
    this.enabled = true,
  }) : assert(asset != null || icon != null);

  final String label;

  /// Логотип мессенджера (webp) — для WhatsApp/Telegram/MAX.
  final String? asset;

  /// Глиф в цветной плитке — для каналов без webp-логотипа (SMS).
  final IconData? icon;
  final Color? iconBg;
  final VoidCallback onTap;

  /// `false` → иконка приглушена, тап игнорируется. Используется, когда
  /// у контакта нет телефона (или для шторки поддержки не настроен
  /// соответствующий канал в Env).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Widget glyph = icon != null
        ? Container(
            width: 60.r,
            height: 60.r,
            decoration: BoxDecoration(
              color: iconBg ?? AppColors.primary,
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Icon(icon, color: Colors.white, size: 32.r),
          )
        : Image.asset(asset!, width: 60.r, height: 60.r);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            glyph,
            SizedBox(height: 5.h),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                height: 1.18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({
    required this.average,
    required this.total,
    required this.distribution,
  });

  final double average;
  final int total;
  final Map<int, int> distribution;

  @override
  Widget build(BuildContext context) {
    final filledStars = average.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              formatRating(average),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                height: 1.20,
              ),
            ),
            SizedBox(width: 4.w),
            ...List.generate(
              5,
              (i) => Padding(
                padding: EdgeInsets.only(right: i == 4 ? 0 : 2.w),
                child: Image.asset(
                  i < filledStars
                      ? 'assets/images/icon_ranking.webp'
                      : 'assets/images/icon_star_empty.webp',
                  width: 20.r,
                  height: 20.r,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 4.h),
        Text(
          '$total ${_pluralReviews(total)}',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.60),
            fontSize: 13.sp,
            fontWeight: FontWeight.w400,
            height: 1.38,
          ),
        ),
        SizedBox(height: 8.h),
        for (final stars in [5, 4, 3, 2, 1]) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ...List.generate(
                5,
                (i) => Padding(
                  padding: EdgeInsets.only(right: i == 4 ? 0 : 1.w),
                  child: Image.asset(
                    i < stars
                        ? 'assets/images/icon_ranking.webp'
                        : 'assets/images/icon_star_empty.webp',
                    width: 14.r,
                    height: 14.r,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.r),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : (distribution[stars] ?? 0) / total,
                    minHeight: 8.h,
                    backgroundColor: AppColors.surfaceVariant,
                    color: AppColors.star,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              SizedBox(
                width: 24.w,
                child: Text(
                  '${distribution[stars] ?? 0}',
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.38,
                  ),
                ),
              ),
            ],
          ),
          if (stars > 1) SizedBox(height: 8.h),
        ],
      ],
    );
  }

  String _pluralReviews(int n) {
    final lastTwo = n % 100;
    if (lastTwo >= 11 && lastTwo <= 14) return 'отзывов';
    final last = n % 10;
    if (last == 1) return 'отзыв';
    if (last >= 2 && last <= 4) return 'отзыва';
    return 'отзывов';
  }
}

class _ReviewItem extends StatelessWidget {
  const _ReviewItem({required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) {
    // Приоритет: имя/фото из expand.from_user (live PB) → локальный мок-юзер
    // → «Пользователь». Раньше использовали только userById, который для
    // PB-id ничего не находит, и все отзывы становились «Пользователь».
    final author = userById(review.fromUserId);
    final authorName = review.fromUserName.isNotEmpty
        ? review.fromUserName
        : (author?.name ?? 'Без имени');
    final authorPhoto = (review.fromUserPhotoUrl != null &&
            review.fromUserPhotoUrl!.isNotEmpty)
        ? review.fromUserPhotoUrl
        : author?.photoPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32.r,
              height: 32.r,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: Builder(builder: (_) {
                final fallback = Icon(
                  IconsaxPlusLinear.user,
                  color: AppColors.primary,
                  size: 20.r,
                );
                if (authorPhoto == null) return fallback;
                if (authorPhoto.startsWith('http')) {
                  return AppNetworkImage(
                    url: authorPhoto,
                    width: 32.r,
                    height: 32.r,
                    fallback: fallback,
                  );
                }
                return Image.file(
                  File(authorPhoto),
                  fit: BoxFit.cover,
                  // 32r ≈ 96px — авторская аватарка отзыва небольшая.
                  cacheWidth: 96,
                  cacheHeight: 96,
                  errorBuilder: (_, _, _) => fallback,
                );
              }),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                authorName,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.33,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ...List.generate(
              5,
              (i) => Padding(
                padding: EdgeInsets.only(right: i == 4 ? 0 : 1.w),
                child: Image.asset(
                  i < review.rating
                      ? 'assets/images/icon_ranking.webp'
                      : 'assets/images/icon_star_empty.webp',
                  width: 14.r,
                  height: 14.r,
                ),
              ),
            ),
            SizedBox(width: 4.w),
            Text(
              DateFormat('dd.MM.yyyy', 'ru_RU')
                  .format(review.createdAt.toLocal()),
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.60),
                fontSize: 12.sp,
                fontWeight: FontWeight.w400,
                height: 1.33,
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        // Лимит на 5 строк — длинные отзывы (до 1000 символов) делали
        // карточку слишком высокой и ломали ритмику списка.
        Text(
          review.comment,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w400,
            height: 1.38,
          ),
        ),
        if (review.tags.isNotEmpty) ...[
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 6.h,
            children: review.tags
                .map(
                  (t) => Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      reviewTagLabel(t),
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

/// Список отзывов с подгрузкой по запросу. Спред-разворот через
/// `...reviews.map(...)` строил все карточки сразу, что на 100+ отзывах
/// заметно тормозило открытие профиля и съедало память. Здесь рендерим
/// первую порцию, остальное — по тапу «Показать ещё».
class _ReviewsList extends StatefulWidget {
  const _ReviewsList({required this.reviews});
  final List<Review> reviews;

  @override
  State<_ReviewsList> createState() => _ReviewsListState();
}

class _ReviewsListState extends State<_ReviewsList> {
  static const int _initialBatch = 20;
  static const int _incrementBatch = 20;
  int _visible = _initialBatch;

  @override
  Widget build(BuildContext context) {
    final total = widget.reviews.length;
    final shown = _visible.clamp(0, total);
    final hasMore = shown < total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < shown; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: AppCard(
              padding: EdgeInsets.all(12.w),
              borderRadius: BorderRadius.circular(12.r),
              child: _ReviewItem(review: widget.reviews[i]),
            ),
          ),
        if (hasMore)
          Padding(
            padding: EdgeInsets.only(top: 4.h, bottom: 16.h),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10.r),
              child: InkWell(
                borderRadius: BorderRadius.circular(10.r),
                onTap: () => setState(() {
                  _visible = (shown + _incrementBatch).clamp(0, total);
                }),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  alignment: Alignment.center,
                  child: Text(
                    'Показать ещё (${total - shown})',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
