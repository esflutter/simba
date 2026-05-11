import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import 'order_card.dart';

class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  String _categoryName(String id) =>
      MockData.categories.firstWhere((c) => c.id == id, orElse: () => MockData.categories.last).name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final mine = state.myOrders.where((o) =>
        !o.isExpiredOpen &&
        (o.status == OrderStatus.open || o.status == OrderStatus.accepted));
    final asExecutor = state.orders.where((o) =>
        o.executorId == 'me' &&
        (o.status == OrderStatus.accepted ||
            o.status == OrderStatus.awaitingPayment));
    final orders = [...mine, ...asExecutor];

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
                padding: EdgeInsets.fromLTRB(16.w, 47.h, 16.w, 8.h),
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
          SizedBox(height: 16.h),
          Expanded(
            child: orders.isEmpty
                ? _EmptyMyOrders(onCreate: () => context.go('/home/create'))
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => SizedBox(height: 16.h),
                    itemBuilder: (_, i) {
                      final o = orders[i];
                      return OrderCard(
                        order: o,
                        categoryName: _categoryName(o.categoryId),
                        onTap: () => context.push('/order/${o.id}?mode=mine'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMyOrders extends StatelessWidget {
  const _EmptyMyOrders({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
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
              'Нет активных заказов',
              textAlign: TextAlign.center,
              style: AppText.h3().copyWith(
                height: 1.25,
                letterSpacing: -0.45,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'Здесь будет отображаться список ваших активных заказов',
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
                  onTap: onCreate,
                  child: SizedBox(
                    height: 44.h,
                    child: Center(
                      child: Text(
                        'Создать заказ',
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
