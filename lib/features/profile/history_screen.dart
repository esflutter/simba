import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/order_display.dart';
import '../../core/utils/realtime_throttle.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/orders_repository.dart';
import '../../data/remote/pocketbase_client.dart' show pocketbaseProvider;
import '../orders/order_card.dart';

enum _Tab { posted, executed }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen>
    with WidgetsBindingObserver {
  /// Выбранная вкладка. Nullable до первого build — там вычислится
  /// дефолтная по текущей роли (по тому же правилу, что и в «Моих заказах»:
  /// если включено «Готов помочь», открываем «Я исполнитель» сразу).
  _Tab? _tab;
  // Юзер сам тапнул по табу — больше не пересчитываем дефолт при ребилдах.
  bool _userPickedTab = false;
  // Дефолтная вкладка уже вычислена по загруженным данным и зафиксирована.
  // Без этого флага дефолт пересчитывался на каждом ребилде, и realtime-
  // событие, поменявшее баланс пустых/непустых списков, перекидывало
  // активную вкладку под пальцем пользователя.
  bool _defaultApplied = false;

  /// PB realtime-подписка на коллекцию orders. Когда какой-то заказ
  /// переходит в completed/cancelled — он должен мгновенно появиться
  /// в Истории, без pull-to-refresh.
  Future<void> Function()? _ordersUnsub;

  /// Throttle realtime-событий: первое событие обновляет Историю сразу,
  /// всплеск последующих склеивается в один догоняющий перезапрос.
  final _ordersThrottle = RealtimeThrottle();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeOrders());
  }

  Future<void> _subscribeOrders() async {
    if (!mounted) return;
    final pb = ref.read(pocketbaseProvider);
    if (pb == null) return;
    try {
      final unsub = await pb.collection('orders').subscribe('*', (_) {
        if (!mounted) return;
        // Throttle: первое событие обновляет Историю сразу (заказ
        // завершён/отменён — появляется в реальном времени), а поток
        // чужих событий по '*' склеиваем в один догоняющий запрос.
        _ordersThrottle.run(() {
          if (!mounted) return;
          ref.invalidate(myOrdersStreamProvider);
        });
      });
      if (!mounted) {
        await unsub();
        return;
      }
      _ordersUnsub = unsub;
    } catch (_) {/* нет WebSocket — История продолжит работать без realtime */}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ordersThrottle.dispose();
    final unsub = _ordersUnsub;
    _ordersUnsub = null;
    if (unsub != null) {
      // ignore: discarded_futures
      unsub();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // При возврате из фона — освежаем «Мои заказы»: пока юзер был
    // свёрнут, заказы могли быть завершены/отменены другой стороной
    // или авто-кроном.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(myOrdersStreamProvider);
    }
  }

  /// Дефолтная вкладка при первом открытии Истории.
  ///
  /// Та же логика, что и в «Моих заказах»: текущая роль важнее, чем
  /// просто «открыть посты». Если юзер включил «Готов помочь», ему
  /// логичнее видеть свою исполнительскую историю сразу. Если в роли
  /// пусто, но в другой что-то есть — открываем непустую.
  _Tab _defaultTab({
    required Iterable<Order> posted,
    required Iterable<Order> executed,
    required UserRole role,
  }) {
    final preferred =
        role == UserRole.executor ? _Tab.executed : _Tab.posted;
    final preferredList =
        preferred == _Tab.executed ? executed : posted;
    if (preferredList.isNotEmpty) return preferred;
    final fallbackList = preferred == _Tab.executed ? posted : executed;
    if (fallbackList.isNotEmpty) {
      return preferred == _Tab.executed ? _Tab.posted : _Tab.executed;
    }
    return preferred;
  }

  @override
  Widget build(BuildContext context) {
    // .select — иначе любая мутация AppState ребилдит весь экран истории.
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
    // Берём «мои заказы» из репозитория (live) и отдельно отслеживаем
    // три фазы: loading → спиннер, error → state с кнопкой «попробовать
    // снова», data → реальный список. Раньше на error мы тихо падали
    // на пустой мок-стейт, и юзер с реальной историей видел экран
    // «Здесь будет отображаться…» — невозможно отличить от настоящей
    // пустоты, никак нельзя повторить запрос.
    final asyncMine = ref.watch(myOrdersStreamProvider);
    final hasError = asyncMine.hasError;
    final isLoading = asyncMine.isLoading && !asyncMine.hasValue;
    final myId = myUserId ?? 'me';

    // По новой схеме (per-side completion, без awaitingPayment как отдельной
    // ветки) заказ попадает в историю стороны, как только она отметила
    // свою часть — независимо от того, отметила ли другая. Также сюда
    // включаем `cancelled` (схема: «Заказ исчезает» / «возвращается в ленту»
    // — это историческое событие для соответствующей стороны).
    //
    // Размещённые: я был заказчиком, и либо я отметил «работа выполнена»
    // (workConfirmedAt != null), либо заказ отменён.
    bool isCustomerHistory(Order o) =>
        (o.customerId == myId || o.customerId == 'me') &&
        (o.isCompletedByCustomer || o.status == OrderStatus.cancelled);
    List<Order> mockPosted() =>
        mockMyOrders.where(isCustomerHistory).toList();
    final List<Order>? posted = asyncMine.when(
      data: (xs) => xs.where(isCustomerHistory).toList(),
      loading: () => null,
      error: (_, _) => mockPosted(),
    );

    // Выполненные: я был исполнителем, и я отметил «оплата получена»
    // (paymentReceivedAt != null), либо заказ отменён уже после accept.
    bool isExecutorHistory(Order o) =>
        (o.executorId == myId || o.executorId == 'me') &&
        (o.isCompletedByExecutor || o.status == OrderStatus.cancelled);
    List<Order> mockExecuted() =>
        mockOrders.where(isExecutorHistory).toList();
    final List<Order>? executed = asyncMine.when(
      data: (xs) => xs.where(isExecutorHistory).toList(),
      loading: () => null,
      error: (_, _) => mockExecuted(),
    );

    // Дефолтную вкладку вычисляем по роли и непустым спискам и фиксируем
    // ОДИН раз — как только данные загрузились (не во время спиннера).
    // После этого она меняется только по тапу пользователя. Раньше дефолт
    // пересчитывался на каждом ребилде, пока юзер не тапнул, и realtime-
    // обновление могло перекинуть активную вкладку на ходу.
    if (!_userPickedTab && !_defaultApplied && !isLoading) {
      _tab = _defaultTab(
        posted: posted ?? const <Order>[],
        executed: executed ?? const <Order>[],
        role: myRole,
      );
      _defaultApplied = true;
    }
    final tab = _tab ?? _defaultTab(
      posted: posted ?? const <Order>[],
      executed: executed ?? const <Order>[],
      role: myRole,
    );

    final list = tab == _Tab.posted ? posted : executed;
    final groups = _groupByDate(list ?? const <Order>[]);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── White header ──
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 44.h,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        child: const AppBackButton(),
                      ),
                    ),
                    Center(
                      child: Text(
                        'История заказов',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w600,
                          height: 1.29,
                          letterSpacing: -0.43,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Segmented tabs ──
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
            child: _SegmentedTabs(
              value: tab,
              onChanged: (t) => setState(() {
                _tab = t;
                _userPickedTab = true;
              }),
            ),
          ),
          // ── Body ──
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : hasError && (list == null || list.isEmpty)
                ? _HistoryError(
                    onRetry: () => ref.invalidate(myOrdersStreamProvider),
                  )
                : (list == null || list.isEmpty)
                ? _EmptyHistory(
                    subtitle: tab == _Tab.posted
                        ? 'Здесь будет отображаться история заказов, размещённых вами в качестве заказчика'
                        : 'Здесь будет отображаться история заказов, выполненных вами в качестве исполнителя',
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      16.w,
                      16.h,
                      16.w,
                      MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    itemCount: groups.length,
                    itemBuilder: (_, gi) {
                      final g = groups[gi];
                      return Padding(
                        padding: EdgeInsets.only(bottom: 16.h),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              g.label,
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                                height: 1.54,
                              ),
                            ),
                            SizedBox(height: 12.h),
                            ...List.generate(g.orders.length, (i) {
                              final o = g.orders[i];
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: i == g.orders.length - 1 ? 0 : 8.h,
                                ),
                                child: _HistoryOrderTile(
                                  order: o,
                                  categoryName: categoryNameOf(o),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Дата, по которой заказ попал в историю: момент завершения/отмены, а не
  /// создания. Берём самую позднюю из меток завершения (заказчик подтвердил
  /// работу / исполнитель отметил оплату / заказ завершён), для отменённых
  /// без меток — дату создания как запасной вариант. Раньше история
  /// сортировалась и группировалась по дате создания, и свежезавершённый
  /// старый заказ оказывался внизу списка под датой создания.
  DateTime _historyDate(Order o) {
    DateTime d = o.createdAt;
    for (final t in [
      o.completedAt,
      o.paymentReceivedAt,
      o.workConfirmedAt,
      o.workDoneAt,
    ]) {
      if (t != null && t.isAfter(d)) d = t;
    }
    return d;
  }

  List<_DateGroup> _groupByDate(List<Order> orders) {
    final sorted = [...orders]
      ..sort((a, b) => _historyDate(b).compareTo(_historyDate(a)));
    final groups = <String, List<Order>>{};
    for (final o in sorted) {
      // toLocal(): даты в БД — UTC; без перевода в локаль ночные заказы
      // попадали бы в группу «вчера/завтра».
      final key = DateFormat('yyyy-MM-dd').format(_historyDate(o).toLocal());
      groups.putIfAbsent(key, () => []).add(o);
    }
    return groups.entries
        .map((e) => _DateGroup(
              label: _labelForDate(_historyDate(e.value.first).toLocal()),
              orders: e.value,
            ))
        .toList();
  }

  String _labelForDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    // Для прошлогодних заказов добавляем год — иначе «5 марта» двухлетней
    // давности неотличимо от «5 марта» текущего года. Порог 365 дней —
    // календарный год; для високосного года разница в 1 день не критична.
    final showYear = d.year != now.year;
    final pattern = showYear ? 'd MMMM yyyy' : 'd MMMM';
    final fmt = DateFormat(pattern, 'ru_RU').format(d);
    if (diff == 0) return 'Сегодня, ${DateFormat('d MMMM', 'ru_RU').format(d)}';
    if (diff == 1) return 'Вчера, ${DateFormat('d MMMM', 'ru_RU').format(d)}';
    return fmt;
  }
}

class _DateGroup {
  _DateGroup({required this.label, required this.orders});
  final String label;
  final List<Order> orders;
}

/// Карточка заказа в истории. Раньше под ней висела CTA-строка
/// «Оставить отзыв» с собственной иконкой звезды — она дублировала
/// функционал, который доступен в деталях заказа. По продуктовому
/// решению эту строку убрали из истории: единственный путь — открыть
/// карточку заказа и нажать кнопку там.
class _HistoryOrderTile extends ConsumerWidget {
  const _HistoryOrderTile({
    required this.order,
    required this.categoryName,
  });

  final Order order;
  final String categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OrderCard(
      order: order,
      categoryName: categoryName,
      showTime: false,
      onTap: () => context.push('/order/${order.id}?mode=mine'),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.value, required this.onChanged});
  final _Tab value;
  final ValueChanged<_Tab> onChanged;

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
              active: value == _Tab.posted,
              onTap: () => onChanged(_Tab.posted),
            ),
          ),
          Expanded(
            child: _Segment(
              label: 'Я исполнитель',
              active: value == _Tab.executed,
              onTap: () => onChanged(_Tab.executed),
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

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Icon(
              IconsaxPlusLinear.clipboard_text,
              size: 80.r,
              color: AppColors.primary,
            ),
            SizedBox(height: 24.h),
            Text(
              'Нет заказов',
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
              subtitle,
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
    );
  }
}


class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(IconsaxPlusLinear.cloud_cross,
                size: 64.r, color: AppColors.textTertiary),
            SizedBox(height: 16.h),
            Text(
              'Не удалось загрузить историю',
              textAlign: TextAlign.center,
              style: AppText.h3(),
            ),
            SizedBox(height: 8.h),
            Text(
              'Проверьте подключение к интернету и попробуйте снова.',
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.textSecondary),
            ),
            SizedBox(height: 16.h),
            SizedBox(
              width: 200.w,
              child: PrimaryButton(label: 'Попробовать снова', onPressed: onRetry),
            ),
          ],
        ),
      ),
    );
  }
}
