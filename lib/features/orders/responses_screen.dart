import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/order_responses_repository.dart';
import '../../data/remote/orders_repository.dart';

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                child: const AppBackButton(),
              ),
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
                      separatorBuilder: (_, _) => SizedBox(height: 16.h),
                      itemBuilder: (_, i) {
                        final u = users[i];
                        return _ResponseCard(
                          user: u,
                          onTap: () =>
                              context.push('/order/$orderId/user/${u.id}'),
                          onDecline: () async {
                            final isLast = users.length == 1;
                            try {
                              await ref
                                  .read(orderResponsesRepositoryProvider)
                                  .decline(orderId, u.id);
                              if (!context.mounted) return;
                              ref.invalidate(myOrdersStreamProvider);
                              AppToast.show(context, 'Исполнитель отклонён');
                              if (isLast) context.pop();
                            } catch (_) {
                              if (!context.mounted) return;
                              AppToast.show(
                                context,
                                'Ошибка. Попробуйте позже',
                              );
                            }
                          },
                          onAccept: () async {
                            try {
                              await ref
                                  .read(orderResponsesRepositoryProvider)
                                  .accept(orderId, u.id);
                              if (!context.mounted) return;
                              ref.invalidate(myOrdersStreamProvider);
                              AppToast.show(context, 'Исполнитель принят');
                              // pushReplacement, а не go: go сбрасывает стек
                              // и /home/orders уходит — потом back из заказа
                              // не работает. Заменяем responses на профиль,
                              // сохраняя [home, order, profile] в стеке.
                              context.pushReplacement(
                                '/order/$orderId/user/${u.id}',
                              );
                            } catch (_) {
                              if (!context.mounted) return;
                              AppToast.show(
                                context,
                                'Ошибка. Попробуйте позже',
                              );
                            }
                          },
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

class _ResponseCard extends StatelessWidget {
  const _ResponseCard({
    required this.user,
    required this.onTap,
    required this.onDecline,
    required this.onAccept,
  });

  final AppUser user;
  final VoidCallback onTap;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16.r),
              topRight: Radius.circular(16.r),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
              child: Row(
                children: [
                  Container(
                    width: 56.r,
                    height: 56.r,
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: user.photoPath != null
                        ? (user.photoPath!.startsWith('http')
                            ? Image.network(user.photoPath!, fit: BoxFit.cover)
                            : Image.file(File(user.photoPath!),
                                fit: BoxFit.cover))
                        : Icon(
                            IconsaxPlusLinear.user,
                            color: AppColors.primary,
                            size: 32.r,
                          ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                            height: 1.50,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Image.asset(
                              'assets/images/icon_ranking.webp',
                              width: 16.r,
                              height: 16.r,
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              user.rating
                                  .toStringAsFixed(1)
                                  .replaceAll('.', ','),
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w400,
                                height: 1.50,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Image.asset(
                    'assets/images/icon_chevron_right.webp',
                    width: 24.r,
                    height: 24.r,
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 1,
            margin: EdgeInsets.symmetric(horizontal: 16.w),
            color: const Color(0x33787878),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
            child: Row(
              children: [
                Expanded(
                  child: _ResponseAction(
                    label: 'Отклонить',
                    background: AppColors.surfaceVariant,
                    color: AppColors.error,
                    onTap: onDecline,
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: _ResponseAction(
                    label: 'Принять',
                    background: AppColors.primary,
                    color: const Color(0xFFF5F5F5),
                    onTap: onAccept,
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
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          height: 36.h,
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 17.sp,
                fontWeight: FontWeight.w600,
                height: 1.29,
                letterSpacing: -0.40,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
