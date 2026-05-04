import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../orders/order_card.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  String _categoryName(String id) =>
      MockData.categories.firstWhere((c) => c.id == id, orElse: () => MockData.categories.last).name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(appControllerProvider).myOrders
        .where((o) => o.status == OrderStatus.completed || o.status == OrderStatus.cancelled)
        .toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: Row(
                children: [
                  const AppBackButton(),
                  Expanded(child: Center(child: Text('История заказов', style: AppText.h4()))),
                  SizedBox(width: 40.w),
                ],
              ),
            ),
            Expanded(
              child: all.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(IconsaxPlusLinear.clipboard_text, size: 60.r, color: AppColors.textTertiary),
                          SizedBox(height: 12.h),
                          Text('История пуста', style: AppText.h4()),
                          SizedBox(height: 4.h),
                          Text('Завершённые заказы появятся здесь',
                              style: AppText.body(color: AppColors.textSecondary)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.all(16.w),
                      itemCount: all.length,
                      separatorBuilder: (_, _) => SizedBox(height: 12.h),
                      itemBuilder: (_, i) => OrderCard(
                        order: all[i],
                        categoryName: _categoryName(all[i].categoryId),
                        onTap: () => context.push('/order/${all[i].id}?mode=mine'),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
