import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/openfreemap_view.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import 'order_card.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _mapMode = false;

  String _categoryName(String id) =>
      MockData.categories.firstWhere((c) => c.id == id, orElse: () => MockData.categories.last).name;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final isExecutor = state.role == UserRole.executor;
    final orders = state.orders.where((o) => o.status == OrderStatus.open).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(
            title: 'Заказы',
            onSwitchRole: () {
              ref.read(appControllerProvider.notifier).setRole(
                    isExecutor ? UserRole.customer : UserRole.executor,
                  );
            },
            roleCta: isExecutor ? 'Готов помочь' : 'Нужна помощь',
            roleActive: isExecutor,
          ),
          Expanded(
              child: Stack(
                children: [
                  if (!_mapMode)
                    _ListView(orders: orders, categoryNameOf: _categoryName)
                  else
                    _MapView(orders: orders, center: state.selectedCity.center),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16.h,
                    child: Center(
                      child: _ToggleViewButton(
                        isMap: _mapMode,
                        onTap: () => setState(() => _mapMode = !_mapMode),
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
    required this.onSwitchRole,
    required this.roleCta,
    required this.roleActive,
  });

  final String title;
  final VoidCallback onSwitchRole;
  final String roleCta;
  final bool roleActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Material(
                color: roleActive ? AppColors.primary : AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12.r),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12.r),
                  onTap: onSwitchRole,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                    child: Text(
                      roleCta,
                      style: AppText.body(
                        color: roleActive ? Colors.white : AppColors.primary,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
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
                  Icon(IconsaxPlusLinear.search_normal_1, size: 26.r, color: AppColors.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({required this.orders, required this.categoryNameOf});
  final List<Order> orders;
  final String Function(String) categoryNameOf;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(IconsaxPlusLinear.archive, size: 64.r, color: AppColors.textTertiary),
              SizedBox(height: 12.h),
              Text('Пока нет открытых заказов',
                  style: AppText.h4(), textAlign: TextAlign.center),
              SizedBox(height: 6.h),
              Text(
                'Скоро появятся новые. Загляните позже.',
                style: AppText.body(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 100.h),
      itemCount: orders.length,
      separatorBuilder: (_, _) => SizedBox(height: 12.h),
      itemBuilder: (_, i) {
        final o = orders[i];
        return OrderCard(
          order: o,
          categoryName: categoryNameOf(o.categoryId),
          onTap: () => context.push('/order/${o.id}?mode=feed'),
        );
      },
    );
  }
}

class _MapView extends StatelessWidget {
  const _MapView({required this.orders, required this.center});
  final List<Order> orders;
  final LatLng center;

  @override
  Widget build(BuildContext context) {
    return OpenFreeMapView(
      initialCenter: center,
      initialZoom: 12,
      markers: [
        for (final o in orders)
          OpenFreeMapMarker(
            id: o.id,
            point: o.location,
            color: _markerColor(o),
          ),
      ],
      onMarkerTap: (id) => context.push('/order/$id?mode=feed'),
    );
  }

  Color _markerColor(Order o) {
    switch (o.status) {
      case OrderStatus.open:
        return AppColors.markerRed;
      case OrderStatus.accepted:
        return AppColors.markerOrange;
      case OrderStatus.completed:
        return AppColors.markerGreen;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _ToggleViewButton extends StatelessWidget {
  const _ToggleViewButton({required this.isMap, required this.onTap});
  final bool isMap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(28.r),
      elevation: 4,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(28.r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isMap ? IconsaxPlusLinear.menu : IconsaxPlusLinear.map, size: 20.r, color: Colors.white),
              SizedBox(width: 8.w),
              Text(isMap ? 'Список' : 'Карта',
                  style: AppText.button(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
