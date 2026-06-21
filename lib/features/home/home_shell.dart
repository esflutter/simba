import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/auth_gate.dart';
import '../../core/widgets/bottom_tab_bar.dart';
import '../../data/mock/app_state.dart';
import '../../data/remote/orders_repository.dart' show ordersRealtimeProvider;
import '../create_order/create_service_type_screen.dart';
import '../orders/feed_screen.dart';
import '../orders/my_orders_screen.dart';
import '../profile/profile_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.initialTab = 'orders'});
  final String initialTab;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = _tabFromName(widget.initialTab);
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() => _index = _tabFromName(widget.initialTab));
    }
  }

  static const _tabNames = ['orders', 'create', 'my', 'profile'];

  int _tabFromName(String t) {
    final i = _tabNames.indexOf(t);
    return i < 0 ? 0 : i;
  }

  static String _gateReason(int i) => i == 1
      ? 'создать заказ'
      : i == 2
          ? 'открыть свои заказы'
          : 'открыть профиль';

  @override
  Widget build(BuildContext context) {
    // Единая realtime-подписка на заказы на всё время сессии (пока главный
    // экран жив). Обновляет ленту, «Мои заказы» и список исполнителя на
    // любой вкладке — вместо двух отдельных подписок в этих экранах.
    ref.watch(ordersRealtimeProvider);

    // Гость видит только ленту; на остальные вкладки перейти не может (тап
    // уводит на мягкий вход). Под guest держим заглушки — экраны
    // «Создать/Мои/Профиль» завязаны на профиль и гостю не нужны (и не
    // строятся off-stage с user == null).
    final isGuest = ref.watch(
      appControllerProvider.select((s) => s.user == null),
    );
    final List<Widget> screens = isGuest
        ? const [
            FeedScreen(),
            SizedBox.shrink(),
            SizedBox.shrink(),
            SizedBox.shrink(),
          ]
        : const [
            FeedScreen(),
            CreateServiceTypeScreen(),
            MyOrdersScreen(),
            ProfileScreen(),
          ];

    return PopScope(
      // На первой вкладке (лента) системная «Назад» выходит из приложения —
      // это штатно. На остальных вкладках «Назад» не выходит, а возвращает
      // на первую: переключение вкладок идёт через go() (замена маршрута),
      // без истории, поэтому сами вкладки «назад» не отыгрывают, и без этого
      // перехвата «Назад» с любой вкладки закрывала приложение.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) context.go('/home/${_tabNames[0]}');
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: screens),
        bottomNavigationBar: BottomTabBar(
          index: _index,
          onChanged: (i) {
            // Гость: вкладки «Создать/Мои/Профиль» — за входом. Останется
            // на ленте, если отменит вход.
            if (isGuest && i != 0) {
              requireAuth(context, ref, reason: _gateReason(i));
              return;
            }
            context.go('/home/${_tabNames[i]}');
          },
        ),
      ),
    );
  }
}
