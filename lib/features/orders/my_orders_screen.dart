import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/order_display.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/orders_repository.dart';
import 'order_card.dart';

enum _MyTab { customer, executor }

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  /// Выбранная вкладка. Nullable до первого build — там вычислится
  /// дефолтная (по самому свежему заказу или, если оба списка пусты,
  /// по выбранной роли при регистрации).
  _MyTab? _tab;
  // Юзер тапнул по табу — больше не пересчитываем default при новых данных.
  bool _userPickedTab = false;

  /// По умолчанию: если есть заказы — открываем вкладку с самым свежим
  /// `created`. Если в обеих ролях пусто — используем роль из стейта
  /// (которую юзер выбрал на role_picker при регистрации).
  _MyTab _defaultTab({
    required Iterable<Order> mine,
    required Iterable<Order> asExecutor,
    required UserRole role,
  }) {
    final mineLast = mine.isEmpty
        ? null
        : mine.map((o) => o.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final execLast = asExecutor.isEmpty
        ? null
        : asExecutor
            .map((o) => o.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    if (mineLast != null && execLast != null) {
      return mineLast.isAfter(execLast) ? _MyTab.customer : _MyTab.executor;
    }
    if (mineLast != null) return _MyTab.customer;
    if (execLast != null) return _MyTab.executor;
    return role == UserRole.executor ? _MyTab.executor : _MyTab.customer;
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
    final mine = myOrders
        .where((o) =>
            o.customerId == myId &&
            !o.isExpiredOpen &&
            // Заказы, провисевшие 30 дней без исполнителя, по продукту
            // удаляются полностью — прячем их и в «Моих заказах», чтобы
            // заказчик не видел призрак протухшего заказа.
            !o.isStaleOpenWithoutExecutor &&
            o.status != OrderStatus.cancelled &&
            !o.isCompletedByCustomer)
        .toList();
    // asExecutor — заказы, в которых я исполнитель и я ещё не отметил
    // оплату полученной.
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

    // _tab кэшируется на StatefulWidget, но _defaultTab выбирает по
    // ПОСЛЕДНИМ заказам в каждой роли. До этого таб устанавливался ОДИН
    // раз и не обновлялся, когда асинхронные данные приходили позже —
    // например, после онбординга у юзера всегда оказывалась вкладка
    // «Я заказчик», даже если у него уже была работа в роли исполнителя.
    //
    // Считаем «исходную» вкладку только пока юзер сам не переключал
    // вручную (_userPickedTab=false): при поступлении свежих данных
    // дефолт пересчитывается, после первого тапа — фиксируется.
    if (!_userPickedTab) {
      _tab = _defaultTab(mine: mine, asExecutor: asExecutor, role: myRole);
    }
    final tab = _tab ??= _defaultTab(
      mine: mine,
      asExecutor: asExecutor,
      role: myRole,
    );

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
                } catch (_) {}
              },
              child: isInitialLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
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
