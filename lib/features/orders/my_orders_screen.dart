import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

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
    // Заказы, в которых текущий пользователь участвует как заказчик,
    // как принятый исполнитель, либо как откликнувшийся (ждёт решения).
    final mine = state.myOrders.where((o) => o.status != OrderStatus.cancelled);
    final asExecutor = state.orders.where((o) =>
        (o.executorId == 'me' || o.responses.contains('me')) &&
        o.status != OrderStatus.cancelled);
    final orders = [...mine, ...asExecutor];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 12.h),
              Text('Мои заказы', style: AppText.h1()),
              SizedBox(height: 16.h),
              Expanded(
                child: orders.isEmpty
                    ? const _EmptyMyOrders()
                    : ListView.separated(
                        padding: EdgeInsets.only(bottom: 16.h),
                        itemCount: orders.length,
                        separatorBuilder: (_, _) => SizedBox(height: 12.h),
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
        ),
      ),
    );
  }
}

class _EmptyMyOrders extends StatelessWidget {
  const _EmptyMyOrders();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(IconsaxPlusLinear.archive, size: 72.r, color: AppColors.textTertiary),
            SizedBox(height: 16.h),
            Text('Заказов пока нет', style: AppText.h4(), textAlign: TextAlign.center),
            SizedBox(height: 8.h),
            Text(
              'Создайте первый заказ — мы найдём вам исполнителя',
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
