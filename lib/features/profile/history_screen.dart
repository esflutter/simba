import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_back_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/remote/orders_repository.dart';
import '../orders/order_card.dart';

enum _Tab { posted, executed }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _Tab _tab = _Tab.posted;

  String _categoryName(String id) => MockData.categories
      .firstWhere((c) => c.id == id, orElse: () => MockData.categories.last)
      .name;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    // Берём «мои заказы» из репозитория (live) с fallback на мок-стейт.
    // Репозиторий уже возвращает заказы и как заказчика, и как исполнителя
    // (см. `OrdersRepository.myOrders()`).
    final asyncMine = ref.watch(myOrdersStreamProvider);
    final liveMine = asyncMine.asData?.value;
    final myId = state.user?.id ?? 'me';

    // Размещённые: заказы, которые я создал как заказчик и завершил со
    // своей стороны (статус awaitingPayment, либо completed).
    final mockPosted = state.myOrders
        .where((o) =>
            o.status == OrderStatus.awaitingPayment ||
            o.status == OrderStatus.completed)
        .toList();
    final livePosted = liveMine
        ?.where((o) =>
            (o.customerId == myId || o.customerId == 'me') &&
            (o.status == OrderStatus.awaitingPayment ||
                o.status == OrderStatus.completed))
        .toList();
    final posted = (livePosted == null || livePosted.isEmpty)
        ? mockPosted
        : livePosted;

    // Выполненные: заказы, в которых я был исполнителем и они завершены.
    // Отдельного `myExecutorOrders()` нет — берём из общего `myOrders()`.
    final mockExecuted = state.orders
        .where((o) =>
            o.executorId == 'me' && o.status == OrderStatus.completed)
        .toList();
    final liveExecuted = liveMine
        ?.where((o) =>
            (o.executorId == myId || o.executorId == 'me') &&
            o.status == OrderStatus.completed)
        .toList();
    final executed = (liveExecuted == null || liveExecuted.isEmpty)
        ? mockExecuted
        : liveExecuted;

    final list = _tab == _Tab.posted ? posted : executed;
    final groups = _groupByDate(list);

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
                          color: Colors.black,
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
              value: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
          // ── Body ──
          Expanded(
            child: list.isEmpty
                ? _EmptyHistory(
                    subtitle: _tab == _Tab.posted
                        ? 'Здесь будет отображаться история заказов, размещённых Вами в качестве заказчика'
                        : 'Здесь будет отображаться история заказов, выполненных Вами в качестве исполнителя',
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      16.w,
                      16.h,
                      16.w,
                      MediaQuery.of(context).viewPadding.bottom,
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
                                child: OrderCard(
                                  order: o,
                                  categoryName: _categoryName(o.categoryId),
                                  showTime: false,
                                  onTap: () => context
                                      .push('/order/${o.id}?mode=mine'),
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

  List<_DateGroup> _groupByDate(List<Order> orders) {
    final sorted = [...orders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final groups = <String, List<Order>>{};
    for (final o in sorted) {
      final key = DateFormat('yyyy-MM-dd').format(o.createdAt);
      groups.putIfAbsent(key, () => []).add(o);
    }
    return groups.entries
        .map((e) => _DateGroup(label: _labelForDate(e.value.first.createdAt), orders: e.value))
        .toList();
  }

  String _labelForDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    final fmt = DateFormat('d MMMM', 'ru_RU').format(d);
    if (diff == 0) return 'Сегодня, $fmt';
    if (diff == 1) return 'Вчера, $fmt';
    return fmt;
  }
}

class _DateGroup {
  _DateGroup({required this.label, required this.orders});
  final String label;
  final List<Order> orders;
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
              label: 'Размещённые',
              active: value == _Tab.posted,
              onTap: () => onChanged(_Tab.posted),
            ),
          ),
          Expanded(
            child: _Segment(
              label: 'Выполненные',
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
          color: active ? Colors.white : Colors.transparent,
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
              color: active ? AppColors.primary : Colors.black,
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
                color: Colors.black,
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
