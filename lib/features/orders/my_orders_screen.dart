import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/backend_error.dart';
import '../../core/utils/order_display.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/auth_repository.dart' show authRepositoryProvider;
import '../../data/remote/orders_repository.dart';
import 'order_card.dart';

enum _MyTab { customer, executor }

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen>
    with WidgetsBindingObserver {
  /// Выбранная вкладка. Nullable до первого build — там вычислится
  /// дефолтная (по самому свежему заказу или, если оба списка пусты,
  /// по выбранной роли при регистрации).
  _MyTab? _tab;
  // Юзер тапнул по табу — больше не пересчитываем default при новых данных.
  bool _userPickedTab = false;

  // Кэш отфильтрованных списков. build() здесь дёргается на каждый тап по
  // табу, на каждое realtime-событие (инвалидация провайдеров) и на любое
  // изменение полей, на которые подписан .select. Без кэша оба .where()
  // прогонялись бы заново каждый раз. Ключ собран из identity-хэшей
  // исходных списков, их длин, myId и минутного «бакета» времени.
  List<Order>? _cachedMine;
  List<Order>? _cachedAsExecutor;
  int? _cachedListKey;

  (List<Order>, List<Order>) _filterLists({
    required List<Order> myOrders,
    required List<Order>? remoteExecutor,
    required List<Order> mockOrders,
    required String myId,
  }) {
    final timeBucket = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final key = Object.hash(
      identityHashCode(myOrders),
      myOrders.length,
      identityHashCode(remoteExecutor),
      remoteExecutor?.length ?? -1,
      identityHashCode(mockOrders),
      mockOrders.length,
      myId,
      timeBucket,
    );
    if (_cachedListKey == key &&
        _cachedMine != null &&
        _cachedAsExecutor != null) {
      return (_cachedMine!, _cachedAsExecutor!);
    }
    final mine = myOrders
        .where((o) =>
            o.customerId == myId &&
            !o.isExpiredOpen &&
            !o.isStaleOpenWithoutExecutor &&
            o.status != OrderStatus.cancelled &&
            !o.isCompletedByCustomer)
        .toList();
    final asExecutor = (remoteExecutor ??
            mockOrders
                .where((o) =>
                    o.executorId == myId &&
                    o.status != OrderStatus.cancelled &&
                    !o.isCompletedByExecutor &&
                    (o.status == OrderStatus.accepted ||
                        o.status == OrderStatus.awaitingPayment))
                .toList())
        .where((o) => !o.isCompletedByExecutor)
        .toList();
    _cachedListKey = key;
    _cachedMine = mine;
    _cachedAsExecutor = asExecutor;
    return (mine, asExecutor);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // realtime-подписка на заказы — единая на всё приложение (см.
    // ordersRealtimeProvider, поднимается на главном экране). Раньше этот
    // экран держал свою подписку на orders/*; теперь обновления статусов
    // приходят централизованно, без дубля.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Возврат из фона — могли что-то пропустить (push'и через ws
      // не получим, пока приложение свёрнуто). Освежаем оба списка.
      ref.invalidate(myOrdersStreamProvider);
      ref.invalidate(myExecutorOrdersProvider);
      // Превентивный refresh-token — если приложение лежало в фоне
      // долго и Supabase/PB JWT TTL прошёл, первый запрос упёрся бы
      // в 401 + withAuthRetry (видно скрытый «лаг»). В ленте такая же
      // защита уже есть, тут добавляем для симметрии.
      // ignore: discarded_futures
      ref.read(authRepositoryProvider).tryRefreshAuth();
    }
  }

  /// Дефолтная вкладка при первом открытии экрана.
  ///
  /// Правило: текущая роль (state.role) важнее, чем свежесть заказов.
  /// Если юзер ВКЛЮЧИЛ «Готов помочь» (role=executor), он явно «в
  /// режиме исполнителя» — ему логично сразу видеть свои принятые
  /// заказы, а не размещённые. Симметрично: customer-режим открывает
  /// «Я заказчик» по умолчанию.
  ///
  /// Если в роли пусто — даём шанс другой роли (если там что-то есть),
  /// иначе остаёмся на роли по умолчанию (пустой состоянием с CTA-кнопкой
  /// «Создать заказ» / «Перейти к ленте»).
  _MyTab _defaultTab({
    required Iterable<Order> mine,
    required Iterable<Order> asExecutor,
    required UserRole role,
  }) {
    final preferred =
        role == UserRole.executor ? _MyTab.executor : _MyTab.customer;
    final preferredList =
        preferred == _MyTab.executor ? asExecutor : mine;
    if (preferredList.isNotEmpty) return preferred;
    // Предпочтительная вкладка пуста — если в другой что-то есть,
    // открываем её, чтобы юзер не пялился на пустой экран.
    final fallbackList = preferred == _MyTab.executor ? mine : asExecutor;
    if (fallbackList.isNotEmpty) {
      return preferred == _MyTab.executor ? _MyTab.customer : _MyTab.executor;
    }
    // Обе пусты — остаёмся на предпочтительной (там CTA-empty-state).
    return preferred;
  }

  @override
  Widget build(BuildContext context) {
    // Берём только реально нужные поля AppState через .select, иначе
    // setRole/createOrder ребилдят таб-переключатель и список целиком.
    final myUserId = ref.watch(
      appControllerProvider.select((s) => s.user?.id),
    );
    final myRole = ref.watch(appControllerProvider.select((s) => s.role));
    final mockMyOrders = ref.watch(
      appControllerProvider.select((s) => s.myOrders),
    );
    final mockOrders = ref.watch(
      appControllerProvider.select((s) => s.orders),
    );
    // Различаем loading и data: пока запрос не вернулся, isInitialLoading
    // = true → ниже рендерим спиннер вместо empty-state с CTA-кнопками,
    // чтобы экран не мигал «У вас пока нет заказов» до прихода данных.
    final asyncMine = ref.watch(myOrdersStreamProvider);
    final asyncExec = ref.watch(myExecutorOrdersProvider);
    final remoteOrders = asyncMine.maybeWhen(
          data: (xs) => xs,
          orElse: () => null,
        );
    final remoteExecutor = asyncExec.maybeWhen(
          data: (xs) => xs,
          orElse: () => null,
        );
    final isInitialLoading =
        (asyncMine.isLoading && !asyncMine.hasValue) ||
            (asyncExec.isLoading && !asyncExec.hasValue);
    final hasError = asyncMine.hasError || asyncExec.hasError;
    final myId = myUserId ?? 'me';
    final myOrders = remoteOrders ?? mockMyOrders;
    // mine — заказы, где Я ЗАКАЗЧИК (customerId == myId). По новой схеме
    // (без awaitingPayment как отдельной ветки) заказ остаётся в «активных»
    // у заказчика, пока он сам не отметил «работа выполнена» и заказ не
    // отменён. Симметрично для исполнителя — по isCompletedByExecutor.
    //
    // Раньше фильтр был только по статусу. myOrdersStreamProvider в
    // live-режиме возвращает заказы и customer-, и executor-стороны (один
    // запрос с OR). Без явной проверки customer'а заказы попадали в обе
    // вкладки одновременно.
    // Фильтрация вынесена в кэширующий помощник: «мои» (где я заказчик, ещё
    // не завершён/не отменён) и «как исполнитель» (принятые, оплату не
    // отметил) пересчитываются только при смене входных данных или раз в
    // минуту (протухание по времени), а не на каждый ребилд.
    final (mine, asExecutor) = _filterLists(
      myOrders: myOrders,
      remoteExecutor: remoteExecutor,
      mockOrders: mockOrders,
      myId: myId,
    );

    // Дефолтная вкладка фиксируется ОДИН раз на основе текущей роли
    // и того, что есть в обоих списках на момент готовности данных.
    // Раньше пересчитывалось при каждом приходе свежих данных от двух
    // потоков (myOrdersStreamProvider + myExecutorOrdersProvider), и
    // юзер видел, как вкладка визуально прыгает на 0.5 секунды.
    //
    // Условие фиксации: оба провайдера загружены (hasValue) ИЛИ
    // пользователь сам уже тапнул по табу. До этого момента используем
    // предварительный дефолт по роли — он не «прыгает», потому что роль
    // в state.user стабильна.
    final asyncDataReady = asyncMine.hasValue && asyncExec.hasValue;
    if (_tab == null || (!_userPickedTab && asyncDataReady)) {
      final newTab =
          _defaultTab(mine: mine, asExecutor: asExecutor, role: myRole);
      if (_tab != newTab) {
        // Используем addPostFrameCallback — иначе мутация state из build
        // нарушает Flutter-инвариант и в редких сценариях даёт «двойной
        // ребилд». Сам _tab локальная переменная для отрисовки текущего
        // кадра считается ниже из newTab.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_userPickedTab) return;
          if (_tab == newTab) return;
          setState(() => _tab = newTab);
        });
      }
    }
    // Для отрисовки текущего кадра: если _tab ещё null (первый build до
    // получения данных) — выводим вкладку по роли без всяких прыжков.
    final tab = _tab ??
        (myRole == UserRole.executor ? _MyTab.executor : _MyTab.customer);

    final visible = tab == _MyTab.customer ? mine : asExecutor;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 47.h, 16.w, 16.h),
                child: Text(
                  'Мои заказы',
                  style: AppText.h1().copyWith(
                    height: 1.21,
                    letterSpacing: 0.40,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
            child: _RoleTabs(
              value: tab,
              onChanged: (t) => setState(() {
                _tab = t;
                _userPickedTab = true;
              }),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                ref.invalidate(myOrdersStreamProvider);
                ref.invalidate(myExecutorOrdersProvider);
                try {
                  await Future.wait([
                    ref.read(myOrdersStreamProvider.future),
                    ref.read(myExecutorOrdersProvider.future),
                  ]);
                } catch (e) {
                  if (!context.mounted) return;
                  AppToast.error(context, humanizeBackendError(e));
                }
              },
              child: isInitialLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : (hasError && visible.isEmpty)
                  ? LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 32.w),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.cloud_off_rounded,
                                      size: 64.r,
                                      color: AppColors.textSecondary),
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
                                    onPressed: () {
                                      ref.invalidate(myOrdersStreamProvider);
                                      ref.invalidate(myExecutorOrdersProvider);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : visible.isEmpty
                  ? LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: _EmptyMyOrders(
                            tab: tab,
                            onCreate: () => context.go('/home/create'),
                            onFindOrder: () => context.go('/home/orders'),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => SizedBox(height: 16.h),
                      itemBuilder: (_, i) {
                        final o = visible[i];
                        return OrderCard(
                          order: o,
                          categoryName: categoryNameOf(o),
                          onTap: () =>
                              context.push('/order/${o.id}?mode=mine'),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleTabs extends StatelessWidget {
  const _RoleTabs({required this.value, required this.onChanged});
  final _MyTab value;
  final ValueChanged<_MyTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.h,
      padding: EdgeInsets.all(2.r),
      decoration: BoxDecoration(
        color: const Color(0x1E787880),
        borderRadius: BorderRadius.circular(9.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              label: 'Я заказчик',
              active: value == _MyTab.customer,
              onTap: () => onChanged(_MyTab.customer),
            ),
          ),
          Expanded(
            child: _Segment(
              label: 'Я исполнитель',
              active: value == _MyTab.executor,
              onTap: () => onChanged(_MyTab.executor),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(7.r),
          border: active
              ? Border.all(
                  width: 0.5,
                  color: Colors.black.withValues(alpha: 0.04),
                )
              : null,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 1,
                    offset: const Offset(0, 3),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.primary : AppColors.textPrimary,
              fontSize: 13.sp,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              height: 1.38,
              letterSpacing: -0.08,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyMyOrders extends StatelessWidget {
  const _EmptyMyOrders({
    required this.tab,
    required this.onCreate,
    required this.onFindOrder,
  });

  final _MyTab tab;
  final VoidCallback onCreate;
  final VoidCallback onFindOrder;

  @override
  Widget build(BuildContext context) {
    final isCustomer = tab == _MyTab.customer;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/tab_my_active.webp',
              width: 80.r,
              height: 80.r,
            ),
            SizedBox(height: 24.h),
            Text(
              isCustomer
                  ? 'Нет активных заказов'
                  : 'Нет заказов на выполнение',
              textAlign: TextAlign.center,
              style: AppText.h3().copyWith(
                height: 1.25,
                letterSpacing: -0.45,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              isCustomer
                  ? 'Здесь будут заказы, размещённые Вами'
                  : 'Здесь будут заказы, которые Вы приняли в качестве исполнителя',
              textAlign: TextAlign.center,
              style: AppText.bodyLarge(
                color: Colors.black.withValues(alpha: 0.60),
              ).copyWith(height: 1.29, letterSpacing: -0.40),
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16.r),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16.r),
                  onTap: isCustomer ? onCreate : onFindOrder,
                  child: SizedBox(
                    height: 44.h,
                    child: Center(
                      child: Text(
                        isCustomer ? 'Создать заказ' : 'Найти заказ',
                        style: AppText.bodyLarge(
                          color: AppColors.background,
                          weight: FontWeight.w600,
                        ).copyWith(height: 1.29, letterSpacing: -0.40),
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
