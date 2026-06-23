import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/utils/backend_error.dart';
import '../../core/utils/order_display.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/city_pill.dart';
import '../../core/widgets/openfreemap_view.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/remote/auth_repository.dart';
import '../../data/remote/orders_repository.dart';
import '../../data/remote/pocketbase_client.dart' show pocketbaseProvider;
import 'order_card.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen>
    with WidgetsBindingObserver {
  bool _mapMode = false;

  /// Тиковый таймер для перерисовки ленты раз в минуту. Без него
  /// заказы, у которых scheduledAt прошёл (`isExpiredOpen=true`) или
  /// которым 30+ дней без исполнителя (`isStaleOpenWithoutExecutor`),
  /// оставались на экране до следующего push-события или ручного
  /// pull-to-refresh. Юзер тапал, получал 404 от сервера.
  Timer? _tickTimer;

  /// Счётчик минутных тиков для периодической переотправки координат
  /// исполнителя (раз в 15 минут), чтобы он не выпадал из push-сегмента
  /// «заказ рядом» по протуханию last_location_at.
  int _locationTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // realtime-подписка на заказы — единая на всё приложение (см.
    // ordersRealtimeProvider, поднимается на главном экране). Раньше лента
    // держала свою подписку на orders/*; теперь обновления приходят
    // централизованно. Тиковый таймер ниже оставляем — он про протухание
    // заказов по времени, не про realtime.
    _tickTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      // Лента (со списком заказов, где важно протухание по времени)
      // показывается только исполнителю. В режиме заказчика экран —
      // статичная заглушка «Готов помочь выключен», там пересчитывать
      // нечего: пропускаем тик, чтобы не дёргать фильтр/маркеры вхолостую
      // и не будить виджет, когда вкладка вообще не на экране.
      final isExecutor =
          ref.read(appControllerProvider).role == UserRole.executor;
      if (isExecutor) setState(() {});
      // Раз в 15 минут, пока «Готов помочь» включён, переотправляем
      // координаты — иначе last_location_at протухает за 6ч и пуши
      // «заказ рядом» перестают приходить, хотя тумблер включён.
      if (++_locationTick >= 15) {
        _locationTick = 0;
        ref
            .read(appControllerProvider.notifier)
            .refreshExecutorLocationIfActive();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    _tickTimer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Освежаем ленту: пока юзер был свёрнут, могли появиться новые
    // заказы / отмениться старые. Раньше показывался ровно тот же
    // снапшот, что и при сворачивании. Также инвалидируем
    // myOrders/Executor — на «Готов помочь» актуальный список нужен.
    ref.invalidate(feedOrdersProvider);
    ref.invalidate(myOrdersStreamProvider);
    ref.invalidate(myExecutorOrdersProvider);
    // Гость (не вошёл) не имеет сессии — обновлять или терять нечего. Без
    // этой проверки tryRefreshAuth у гостя вернёт false, и блок ниже увёл бы
    // его на /auth/phone (без gate, без кнопки «назад»), то есть гость
    // выпадал из каталога при первом же сворачивании приложения. Ленту выше
    // мы уже освежили — этого гостю достаточно.
    if (ref.read(appControllerProvider).user == null) return;
    // Вернулись в приложение — если исполнитель активен, сразу освежаем
    // координаты (last_location_at), чтобы не выпасть из пушей о заказах.
    ref.read(appControllerProvider.notifier).refreshExecutorLocationIfActive();
    // Проактивно дёргаем refresh-токен: если он истёк пока юзер был
    // в фоне, без этого первый запрос упирался бы в 401 и юзера
    // выкидывало на /auth/phone уже после действия. Теперь — сразу
    // пробуем обновить; если refresh не получилось, tryRefreshAuth
    // внутри сам вызывает logout (state.user → null). После этого
    // явно отправляем на /auth/phone, иначе redirect-guard сработает
    // только при следующей навигации, и юзер сидит на Feed с пустым
    // именем до своего следующего действия.
    final auth = ref.read(authRepositoryProvider);
    if (auth.isLive) {
      auth.tryRefreshAuth().then((ok) {
        if (!mounted || ok) return;
        // ВАЖНО: одного факта `ok == false` мало для редиректа на /auth.
        // Сценарий: юзер запросил permission на геолокацию → Android
        // сворачивает приложение на показ диалога → resumed → этот
        // hook → tryRefreshAuth уходит в сеть → пока ждём, юзер
        // успевает нажать «Назад» на диалоге → resumed второй раз →
        // dedup внутри tryRefreshAuth возвращает true мгновенно, но
        // первый запрос ещё в полёте и может вернуть false из-за
        // race. Без двойной проверки (state.user == null И PB-токен
        // невалидный) юзер вылетает на ввод телефона прямо с открытой
        // ленты. Теперь редирект — только если ОБА условия выполнены.
        final user = ref.read(appControllerProvider).user;
        final pb = ref.read(pocketbaseProvider);
        final tokenValid = pb?.authStore.isValid ?? false;
        if (user == null && !tokenValid) {
          context.go('/auth/phone');
        }
      });
    }
  }

  /// Кэш отфильтрованной и отсортированной ленты. На каждую перерисовку
  /// (например, при тапе по табу или вводе в city-pill) фильтр+сортировка
  /// заново — на 500+ заказах заметно. Ключ собран из identity-хэша
  /// исходного списка плюс фильтрующих полей: если хоть одно изменилось,
  /// пересчитываем; иначе отдаём прошлый результат.
  List<Order>? _cachedOrders;
  int? _cachedKey;

  List<Order> _buildFilteredOrders({
    required List<Order> source,
    required String? selectedCityId,
    required String? myId,
  }) {
    // В ключ кэша входит минутный «бакет» текущего времени. Без него
    // фильтр isExpiredOpen / isStaleOpenWithoutExecutor отдавал бы
    // прежний результат, даже когда заказ уже должен исчезнуть по
    // времени (scheduledAt прошёл, или прошло 30 дней без исполнителя).
    // Юзер видел зомби-заказ, тапал, получал 404 от сервера. Минута —
    // компромисс: пересчёт раз в минуту дешёвый, а UX-сдвиг меньше
    // минуты для протухания заказа незаметен.
    final timeBucket = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final key = Object.hash(
      identityHashCode(source),
      source.length,
      selectedCityId,
      myId,
      timeBucket,
    );
    if (_cachedKey == key && _cachedOrders != null) return _cachedOrders!;
    final filtered = source
        .where((o) =>
            o.status == OrderStatus.open &&
            !o.isExpiredOpen &&
            !o.isStaleOpenWithoutExecutor &&
            (selectedCityId == null ||
                o.cityId == null ||
                o.cityId == selectedCityId) &&
            (myId == null || o.customerId != myId))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _cachedKey = key;
    _cachedOrders = filtered;
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    // Подписываемся точечно через .select, иначе любой setRole/addReview
    // /createOrder ребилдит весь FeedScreen, включая фильтрацию ленты и
    // карту. Берём только те поля, что реально нужны экрану.
    final isExecutor = ref.watch(
      appControllerProvider.select((s) => s.role == UserRole.executor),
    );
    // Гость видит каталог (ленту) независимо от роли; любое действие на этом
    // экране (переключить режим, открыть карточку) уводит на мягкий вход.
    final isGuest = ref.watch(
      appControllerProvider.select((s) => s.user == null),
    );
    final selectedCity = ref.watch(
      appControllerProvider.select((s) => s.selectedCity),
    );
    final selectedCityId = ref.watch(
      appControllerProvider.select((s) => s.selectedCityId),
    );
    final myId = ref.watch(
      appControllerProvider.select((s) => s.user?.id),
    );
    final mockOrders = ref.watch(
      appControllerProvider.select((s) => s.orders),
    );
    // Если бэкенд подключён — берём фид из PB, иначе из мок-стейта.
    final remoteFeed = ref.watch(feedOrdersProvider).maybeWhen(
          data: (xs) => xs,
          orElse: () => null,
        );
    final source = remoteFeed ?? mockOrders;
    // Фильтры в ленте: open, не expired, не stale-30d, мой город, не свой.
    // Сортировка — от новых к старым (бизнес-требование).
    // Сама фильтрация инкапсулирована в _buildFilteredOrders с кэшем —
    // на каждый ребилд при том же source/city/myId возвращается готовый
    // список без повторного прохода. На 500+ заказах разница ощутима.
    final orders = _buildFilteredOrders(
      source: source,
      selectedCityId: selectedCityId,
      myId: myId,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(
            title: 'Заказы',
            cityName: selectedCity.name,
            onSwitchRole: () async {
              // Переключение режима пишет в профиль — действие за входом.
              if (!requireAuth(context, ref, reason: 'переключить режим')) {
                return;
              }
              final goingActive = !isExecutor;
              ref.read(appControllerProvider.notifier).setRole(
                    goingActive ? UserRole.executor : UserRole.customer,
                  );
              // При переходе в исполнителя — проверяем доступ к геолокации.
              // Без него `users_private.last_lat/lng` пустые → push-сегмент
              // `new_order_nearby` юзера НЕ включит, и заказы рядом не будут
              // приходить. Показываем тост, чтобы юзер понимал и сам открыл
              // настройки приложения.
              if (goingActive) {
                final initialPerm = await Geolocator.checkPermission();
                LocationPermission perm = initialPerm;
                // Флаг «попап с запросом разрешения был только что показан
                // и юзер выдал доступ». Только в этом моменте мы вправе
                // сами поменять выбранный город по реальному
                // местоположению — иначе авто-переключение перетёрло бы
                // вручную выбранный город каждый раз при включении
                // режима «Готов помочь».
                bool permissionJustGranted = false;
                if (perm == LocationPermission.denied) {
                  perm = await Geolocator.requestPermission();
                  if (!context.mounted) return;
                  final granted = perm == LocationPermission.always ||
                      perm == LocationPermission.whileInUse;
                  if (granted) {
                    permissionJustGranted = true;
                  } else {
                    AppToast.show(
                      context,
                      'Без доступа к геолокации мы не сможем '
                      'присылать заказы рядом',
                    );
                  }
                } else if (perm == LocationPermission.deniedForever) {
                  if (!context.mounted) return;
                  AppToast.show(
                    context,
                    'Геолокация запрещена в настройках — '
                    'заказы рядом приходить не будут',
                  );
                }
                // Авто-смена города ТОЛЬКО если попап только что показали
                // и юзер выдал доступ. Если разрешение было выдано раньше
                // — не трогаем город (юзер мог выбрать вручную не тот, в
                // котором физически находится; уважаем его выбор).
                if (permissionJustGranted) {
                  try {
                    final pos = await Geolocator.getCurrentPosition(
                      locationSettings: const LocationSettings(
                        accuracy: LocationAccuracy.medium,
                        timeLimit: Duration(seconds: 8),
                      ),
                    );
                    if (!context.mounted) return;
                    final detected = MockData.nearestCityFor(
                      LatLng(pos.latitude, pos.longitude),
                    );
                    final currentId =
                        ref.read(appControllerProvider).selectedCityId;
                    if (detected != null && detected.id != currentId) {
                      ref
                          .read(appControllerProvider.notifier)
                          .setCity(detected.id);
                      AppToast.show(
                        context,
                        'Город изменён на «${detected.name}» по геолокации',
                      );
                    }
                  } catch (_) {
                    // Таймаут GPS, отсутствие сигнала и т.п. — молча
                    // пропускаем. Юзер увидит прежний город и сможет
                    // поменять его вручную через picker.
                  }
                }
              }
            },
            roleCta: isExecutor ? 'Готов помочь' : 'Не готов помочь',
            roleActive: isExecutor,
            // Лупу поиска прячем когда фид пустой — искать всё равно нечего.
            showSearch: isExecutor && orders.isNotEmpty,
          ),
          Expanded(
              child: (!isExecutor && !isGuest)
                  ? const _PausedState()
                  : Stack(
                      children: [
                        // IndexedStack вместо if/else: оба виджета остаются
                        // смонтированными, скрытый — просто off-stage. При
                        // переключении «Список ↔ Карта» карта НЕ
                        // пересоздаётся и не перезагружает векторные тайлы;
                        // переключение становится моментальным. До этого
                        // условный рендеринг каждый раз убивал _MapView и
                        // строил новый — отсюда индикатор загрузки на 2–3
                        // секунды при каждом возврате.
                        IndexedStack(
                          index: _mapMode ? 1 : 0,
                          sizing: StackFit.expand,
                          children: [
                            _ListView(
                              orders: orders,
                              categoryNameOf: categoryNameOf,
                            ),
                            _MapView(
                              orders: orders,
                              active: _mapMode,
                              center: selectedCity.center,
                              onMarkerTap: (id) {
                                // Просмотр доступен и гостю (каталог без входа).
                                context.push('/order/$id?mode=feed');
                              },
                            ),
                          ],
                        ),
                        // Переключатель «Карта/Список» показываем всегда:
                        // это control режима просмотра, а не «открыть заказы».
                        // Если в городе пусто — у списка есть своё empty-state
                        // с фразой про «загляните позже / создайте сами»,
                        // там это понятнее, чем смотреть на голую карту.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 8.h,
                          child: Center(
                            child: _ToggleViewButton(
                              isMap: _mapMode,
                              onTap: () =>
                                  setState(() => _mapMode = !_mapMode),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.cityName,
    required this.onSwitchRole,
    required this.roleCta,
    required this.roleActive,
    this.showSearch = true,
  });

  final String title;
  final String cityName;
  final VoidCallback onSwitchRole;
  final String roleCta;
  final bool roleActive;
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: CityPill(cityName: cityName),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  DecoratedBox(
                decoration: BoxDecoration(
                  color: roleActive ? AppColors.primary : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(8.r),
                  boxShadow: roleActive
                      ? [
                          BoxShadow(
                            color: const Color(0x11000000),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8.r),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8.r),
                    onTap: onSwitchRole,
                    // 32dp — компактная высота, совпадает с CityPill слева.
                    child: Container(
                      constraints: BoxConstraints(minHeight: 32.h),
                      alignment: Alignment.center,
                      padding:
                          EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                      child: Text(
                        roleCta,
                        style: TextStyle(
                          color: roleActive
                              ? AppColors.background
                              : AppColors.primary,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                          height: 1.43,
                          letterSpacing: 0.10,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
                ],
              ),
              SizedBox(height: 4.h),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppText.h1().copyWith(
                        height: 1.21,
                        letterSpacing: 0.40,
                      ),
                    ),
                  ),
                  if (roleActive && showSearch)
                    // 48×48 — Material/Android минимум touch-target. Сама
                    // иконка остаётся 26dp, но прозрачная область вокруг
                    // расширена до 48 — пальцем попадать стало проще.
                    SizedBox(
                      width: 48.r,
                      height: 48.r,
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => context.push('/search'),
                          child: Icon(
                            IconsaxPlusLinear.search_normal_1,
                            size: 26.r,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListView extends ConsumerWidget {
  const _ListView({required this.orders, required this.categoryNameOf});
  final List<Order> orders;
  final String Function(Order) categoryNameOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // RefreshIndicator вокруг любого виджета требует scroll-семантики, поэтому
    // даже на пустом состоянии оборачиваем в AlwaysScrollableScrollPhysics
    // ListView — иначе свайп вниз не сработает.
    Future<void> doRefresh() async {
      ref.invalidate(feedOrdersProvider);
      // Дожидаемся подгрузки нового списка, чтобы спиннер не схлопывался
      // мгновенно — иначе UX-обман «обновили? точно?». При ошибке —
      // тост с конкретной причиной (нет сети, сервер 5xx). Раньше
      // catch (_) {} проглатывал, и юзер видел «обновил»-крутилку,
      // которая исчезала без сигнала.
      try {
        await ref.read(feedOrdersProvider.future);
      } catch (e) {
        if (!context.mounted) return;
        AppToast.error(context, humanizeBackendError(e));
      }
    }

    if (orders.isEmpty) {
      // Если фид ещё грузится, не показываем «Пока нет заказов» — иначе
      // после онбординга он мигает на доли секунды до подгрузки реальных
      // данных. Показываем нейтральный спиннер до первого ответа.
      final feedAsync = ref.watch(feedOrdersProvider);
      if (feedAsync.isLoading && !feedAsync.hasValue) {
        return const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        );
      }
      // Ошибка сети/сервера и при этом нет данных — отдельное состояние с
      // кнопкой «Повторить». Раньше при сбое лента выглядела как «заказов
      // нет» (особенно заметно гостю — это его главный экран).
      if (feedAsync.hasError && !feedAsync.hasValue) {
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: doRefresh,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            size: 64.r, color: AppColors.textSecondary),
                        SizedBox(height: 16.h),
                        Text(
                          'Не удалось загрузить заказы',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            letterSpacing: -0.45,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Проверьте подключение к интернету и попробуйте снова',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15.sp,
                            height: 1.3,
                          ),
                        ),
                        SizedBox(height: 24.h),
                        PrimaryButton(
                          label: 'Повторить',
                          expanded: false,
                          onPressed: () => ref.invalidate(feedOrdersProvider),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: doRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32.w),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/tab_orders_active.webp',
                        width: 80.r,
                        height: 80.r,
                      ),
                      SizedBox(height: 24.h),
                      Text(
                        'Пока нет открытых заказов',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          letterSpacing: -0.45,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Загляните позже или '),
                            TextSpan(
                              text: 'создайте заказ самостоятельно',
                              style: TextStyle(color: AppColors.primary),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  // Гость — на мягкий вход, как и остальные
                                  // действия, а не молчаливый отскок роутером.
                                  if (!requireAuth(context, ref,
                                      reason: 'создать заказ')) {
                                    return;
                                  }
                                  context.go('/home/create');
                                },
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.60),
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w400,
                          height: 1.29,
                          letterSpacing: -0.40,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: doRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 56.h),
        itemCount: orders.length,
        separatorBuilder: (_, _) => SizedBox(height: 12.h),
        itemBuilder: (_, i) {
          final o = orders[i];
          return OrderCard(
            order: o,
            categoryName: categoryNameOf(o),
            // Каталог: все заказы одного выбранного города — город в адресе
            // не дублируем.
            showCity: false,
            onTap: () {
              // Просмотр заказа доступен и гостю (каталог без входа).
              // Вход требуется только на действиях внутри карточки.
              context.push('/order/${o.id}?mode=feed');
            },
          );
        },
      ),
    );
  }
}

class _MapView extends ConsumerStatefulWidget {
  const _MapView({
    required this.orders,
    required this.active,
    required this.center,
    this.onMarkerTap,
  });
  final List<Order> orders;

  /// Видна ли карта прямо сейчас (активная вкладка IndexedStack). Карта
  /// остаётся смонтированной и в скрытом состоянии, поэтому build дёргается
  /// на любой ребилд ленты. При active == false не пересобираем список
  /// маркеров — переиспользуем последний (состояние карты не теряется).
  final bool active;
  final LatLng center;
  final ValueChanged<String>? onMarkerTap;

  @override
  ConsumerState<_MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<_MapView> {
  /// Последнее известное местоположение пользователя. Используем как
  /// стартовый центр карты, если permission уже выдан. Если нет —
  /// остаёмся на центре выбранного города (см. widget.center).
  LatLng? _myLocation;

  /// Bootstrap делаем один раз за жизненный цикл виджета: иначе при
  /// каждом ребилде (а карта ребилдится на любой мутации AppState)
  /// мы бы дёргали Geolocator повторно и заново предлагали авто-смену
  /// города, перезатирая ручной выбор пользователя.
  bool _bootstrapped = false;

  /// Последний собранный список маркеров. Пока карта скрыта
  /// (widget.active == false), не пересобираем его на каждый ребилд ленты.
  List<OpenFreeMapMarker> _markers = const [];

  @override
  void initState() {
    super.initState();
    _bootstrapMyLocation();
  }

  @override
  void didUpdateWidget(_MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Юзер вручную переключил город (через city-pill в шапке) →
    // widget.center сменился. Стираем cached _myLocation, чтобы карта
    // переехала к центру нового города и не висела на старой точке.
    // OpenFreeMapView внутри сам анимирует переход (см. didUpdateWidget
    // там) — нам достаточно отдать ему новый initialCenter.
    if (oldWidget.center != widget.center) {
      if (_myLocation != null) {
        setState(() => _myLocation = null);
      }
    }
  }

  Future<void> _bootstrapMyLocation() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null || !mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      if (mounted) setState(() => _myLocation = here);
      // Если фактическая точка попадает в ДРУГОЙ поддерживаемый город — не
      // меняем молча (как было раньше), а предлагаем сменить попапом.
      // nearestCityFor вернёт null, когда точка не входит в радиус ни одного
      // города из списка приложения (область, село, далёкий регион) — тогда
      // менять не на что, ничего не предлагаем. Решение за пользователем,
      // спрашиваем один раз за сессию (гард _bootstrapped).
      final detected = MockData.nearestCityFor(here);
      final currentId = ref.read(appControllerProvider).selectedCityId;
      if (detected != null && detected.id != currentId) {
        await _offerCitySwitch(detected);
      }
    } catch (_) {/* нет GPS / сервис выключен — оставляем центр города */}
  }

  /// Попап «вы в другом городе». Показывается только если фактическая точка
  /// относится к городу из списка приложения и он не совпадает с выбранным.
  /// Меняем город только по явному согласию пользователя.
  Future<void> _offerCitySwitch(City detected) async {
    if (!mounted) return;
    final switchIt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сменить город?'),
        content: Text(
          'Похоже, вы сейчас в городе «${detected.name}», а выбран другой. '
          'Показывать заказы для «${detected.name}»?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Оставить'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Сменить'),
          ),
        ],
      ),
    );
    if (switchIt == true && mounted) {
      ref.read(appControllerProvider.notifier).setCity(detected.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Только заказы с валидной геоточкой попадают на карту (в ленте это
    // всегда open-заказы). Маркеры одинаковые — пин без окраски по статусу.
    // Маркеры пересобираем только когда карта видна. При скрытой карте
    // build всё равно вызывается (IndexedStack держит виджет живым), но
    // гонять map/toList по всем заказам и пересчитывать ключ слоя смысла
    // нет. При переключении на карту build приходит с active == true в том
    // же кадре, поэтому к показу маркеры всегда свежие.
    if (widget.active) {
      _markers = widget.orders
          .map((o) => OpenFreeMapMarker(
                id: o.id,
                point: o.location,
              ))
          .toList();
    }
    final markers = _markers;
    // Приоритет: пользовательская позиция (если permission выдан) →
    // центр выбранного города.
    final initialCenter = _myLocation ?? widget.center;
    final initialZoom = _myLocation != null ? 13.0 : 11.0;
    return OpenFreeMapView(
      markers: markers,
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      showMyLocation: true,
      showZoomControls: true,
      onMarkerTap: widget.onMarkerTap,
    );
  }
}

class _ToggleViewButton extends StatelessWidget {
  const _ToggleViewButton({required this.isMap, required this.onTap});
  final bool isMap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0x11000000),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(8.r),
          onTap: onTap,
          child: SizedBox(
            width: 183.w,
            height: 32.h,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  isMap
                      ? 'assets/images/icon_list.webp'
                      : 'assets/images/icon_map.webp',
                  width: 20.r,
                  height: 20.r,
                ),
                SizedBox(width: 6.w),
                Text(
                  isMap ? 'Список' : 'Карта',
                  style: TextStyle(
                    color: AppColors.background,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.43,
                    letterSpacing: 0.10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PausedState extends StatelessWidget {
  const _PausedState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              IconsaxPlusLinear.pause,
              size: 80.r,
              color: AppColors.primary,
            ),
            SizedBox(height: 24.h),
            Text(
              'Поиск заказов отключён',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                height: 1.25,
                letterSpacing: -0.45,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'Нажмите кнопку вверху экрана, чтобы включить поиск заказов.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.60),
                fontSize: 17.sp,
                fontWeight: FontWeight.w400,
                height: 1.29,
                letterSpacing: -0.40,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
