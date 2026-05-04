import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../data/mock/app_state.dart';

class ResponsesScreen extends ConsumerWidget {
  const ResponsesScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final order = state.myOrders.firstWhere(
      (o) => o.id == orderId,
      orElse: () => state.myOrders.first,
    );
    final users = order.responses.map(userById).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              child: const AppBackButton(),
            ),
            Expanded(
              child: users.isEmpty
                  ? Center(
                      child: Text(
                        'Откликов пока нет',
                        style: AppText.body(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                      itemCount: users.length,
                      separatorBuilder: (_, _) => SizedBox(height: 12.h),
                      itemBuilder: (_, i) {
                        final u = users[i];
                        return AppCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              InkWell(
                                onTap: () => context.push('/order/$orderId/user/${u.id}'),
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(20.r),
                                  topRight: Radius.circular(20.r),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 14.h),
                                  child: Row(
                                    children: [
                                      _Avatar(),
                                      SizedBox(width: 12.w),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(u.name, style: AppText.h4()),
                                            SizedBox(height: 4.h),
                                            Row(
                                              children: [
                                                Icon(IconsaxPlusBold.star_1, color: AppColors.star, size: 16.r),
                                                SizedBox(width: 4.w),
                                                Text(
                                                  u.rating
                                                      .toStringAsFixed(1)
                                                      .replaceAll('.', ','),
                                                  style: AppText.body(weight: FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(IconsaxPlusLinear.arrow_right_3,
                                          color: AppColors.primary, size: 22.r),
                                    ],
                                  ),
                                ),
                              ),
                              Container(height: 1, color: AppColors.divider),
                              Padding(
                                padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _ResponseAction(
                                        label: 'Отклонить',
                                        background: AppColors.surfaceVariant,
                                        color: AppColors.error,
                                        onTap: () {},
                                      ),
                                    ),
                                    SizedBox(width: 12.w),
                                    Expanded(
                                      child: _ResponseAction(
                                        label: 'Принять',
                                        background: AppColors.primary,
                                        color: Colors.white,
                                        onTap: () {
                                          ref
                                              .read(appControllerProvider.notifier)
                                              .acceptResponse(orderId, u.id);
                                          context.pop();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48.r,
      height: 48.r,
      decoration: const BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
      ),
      child: Icon(IconsaxPlusLinear.user, color: AppColors.primary, size: 28.r),
    );
  }
}

class _ResponseAction extends StatelessWidget {
  const _ResponseAction({
    required this.label,
    required this.background,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(14.r),
        onTap: onTap,
        child: Container(
          height: 48.h,
          alignment: Alignment.center,
          child: Text(label, style: AppText.button(color: color)),
        ),
      ),
    );
  }
}
