import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../create_order/create_order_screen.dart';
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
      CreateOrderScreen(),
      MyOrdersScreen(),
      ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: _BottomBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(appControllerProvider.select((s) => s.role));
    final firstLabel = role == UserRole.executor ? 'Заказы' : 'Лента';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64.h,
          child: Row(
            children: [
              _Tab(label: firstLabel, icon: IconsaxPlusLinear.clipboard_text, active: index == 0, onTap: () => onChanged(0)),
              _Tab(
                label: 'Создать',
                icon: IconsaxPlusLinear.add_circle,
                active: index == 1,
                onTap: () => onChanged(1),
                accent: true,
              ),
              _Tab(label: 'Мои заказы', icon: IconsaxPlusLinear.archive_tick, active: index == 2, onTap: () => onChanged(2)),
              _Tab(label: 'Профиль', icon: IconsaxPlusLinear.user, active: index == 3, onTap: () => onChanged(3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.accent = false,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 36.r,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26.r, color: color),
            SizedBox(height: 2.h),
            Text(label, style: AppText.tab(color: color, weight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
