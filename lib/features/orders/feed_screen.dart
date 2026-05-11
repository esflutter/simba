import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/city_pill.dart';
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
    final orders = state.orders
        .where((o) => o.status == OrderStatus.open && !o.isExpiredOpen)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(
            title: 'Заказы',
            cityName: state.selectedCity.name,
            onSwitchRole: () {
              ref.read(appControllerProvider.notifier).setRole(
                    isExecutor ? UserRole.customer : UserRole.executor,
                  );
            },
            roleCta: isExecutor ? 'Готов помочь' : 'Не готов помочь',
            roleActive: isExecutor,
          ),
          Expanded(
              child: !isExecutor
                  ? const _PausedState()
                  : Stack(
                      children: [
                        if (!_mapMode)
                          _ListView(orders: orders, categoryNameOf: _categoryName)
                        else
                          _MapView(
                            orders: orders,
                            center: state.selectedCity.center,
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 8.h,
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
    required this.cityName,
    required this.onSwitchRole,
    required this.roleCta,
    required this.roleActive,
  });

  final String title;
  final String cityName;
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
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
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
                  if (roleActive)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.push('/search'),
                      child: Padding(
                        padding: EdgeInsets.all(4.r),
                        child: Icon(
                          IconsaxPlusLinear.search_normal_1,
                          size: 26.r,
                          color: AppColors.primary,
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
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 56.h),
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
    return Image.asset(
      'assets/images/map_mock.webp',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
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
                color: Colors.black,
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
