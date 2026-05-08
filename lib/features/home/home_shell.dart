import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/bottom_tab_bar.dart';
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

  int _tabFromName(String t) {
    switch (t) {
      case 'create':
        return 1;
      case 'my':
        return 2;
      case 'profile':
        return 3;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    const screens = <Widget>[
      FeedScreen(),
      CreateServiceTypeScreen(),
      MyOrdersScreen(),
      ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: BottomTabBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}
