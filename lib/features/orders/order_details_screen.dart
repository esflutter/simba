import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/openfreemap_view.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';

class OrderDetailsScreen extends ConsumerWidget {
  const OrderDetailsScreen({super.key, required this.orderId, required this.mode});

  final String orderId;
  final String mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final all = [...state.myOrders, ...state.orders];
    final order = all.firstWhere(
      (o) => o.id == orderId,
      orElse: () => state.myOrders.isNotEmpty ? state.myOrders.first : state.orders.first,
    );
    final isCustomer = order.customerId == 'me';
    final isMine = isCustomer;
    final hasMyResponse = order.responses.contains('me');
    final category = MockData.categories.firstWhere(
      (c) => c.id == order.categoryId,
      orElse: () => MockData.categories.last,
    );

    final statusBadge =
        _badgeForStatus(order, isCustomer: isCustomer, hasMyResponse: hasMyResponse);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: const AppBackButton(),
                ),
                const Spacer(),
                if (statusBadge != null)
                  Padding(
                    padding: EdgeInsets.only(right: 16.w),
                    child: statusBadge,
                  ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                children: [
                  Text(order.title, style: AppText.h2()),
                  SizedBox(height: 8.h),
                  Text('${order.priceRub} ₽',
                      style: AppText.h4(color: AppColors.primary)),
                  SizedBox(height: 16.h),
                  _Field('Способ оплаты', 'Наличные'),
                  SizedBox(height: 12.h),
                  _Field('Категория работ', category.name),
                  SizedBox(height: 12.h),
                  _Field(
                    'Время начала работы',
                    order.scheduledAt != null
                        ? DateFormat('dd.MM.yyyy HH:mm').format(order.scheduledAt!)
                        : 'Как можно скорее',
                  ),
                  SizedBox(height: 12.h),
                  _Field('Комментарий', order.description),
                  SizedBox(height: 12.h),
                  _Field('Адрес', order.address),
                  SizedBox(height: 12.h),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20.r),
                      child: SizedBox(
                        height: 160.h,
                        child: OpenFreeMapView(
                          initialCenter: order.location,
                          initialZoom: 14,
                          interactive: false,
                          markers: [
                            OpenFreeMapMarker(
                              id: order.id,
                              point: order.location,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (order.photoPaths.isNotEmpty) ...[
                    SizedBox(height: 16.h),
                    Text('Фото', style: AppText.h4()),
                    SizedBox(height: 8.h),
                    SizedBox(
                      height: 96.h,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: order.photoPaths.length,
                        separatorBuilder: (_, _) => SizedBox(width: 8.w),
                        itemBuilder: (_, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(12.r),
                          child: Image.network(order.photoPaths[i], width: 96.w, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ],
                  if (order.executorId != null && order.executorId != 'me' && isMine) ...[
                    SizedBox(height: 16.h),
                    Text('Исполнитель', style: AppText.h4()),
                    SizedBox(height: 8.h),
                    _ExecutorCard(executorId: order.executorId!, orderId: order.id),
                  ],
                  SizedBox(height: 24.h),
                  ..._buildActions(context, ref, order, isMine, hasMyResponse),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context, WidgetRef ref, Order order, bool isMine, bool hasMyResponse) {
    final ctrl = ref.read(appControllerProvider.notifier);
    final widgets = <Widget>[];

    if (isMine) {
      switch (order.status) {
        case OrderStatus.open:
          widgets.add(PrimaryButton(
            label: 'Смотреть отклики (${order.responses.length})',
            onPressed: () => context.push('/order/${order.id}/responses'),
          ));
          widgets.add(SizedBox(height: 12.h));
          widgets.add(SecondaryButton(
            label: 'Отменить заказ',
            color: AppColors.error,
            onPressed: () => _confirmCancel(context, ctrl, order.id),
          ));
          break;
        case OrderStatus.accepted:
          widgets.add(_StatusBanner(
            color: AppColors.primarySoft,
            textColor: AppColors.primary,
            label: 'Исполнитель найден. Дождитесь завершения работы.',
          ));
          break;
        case OrderStatus.awaitingPayment:
          widgets.add(PrimaryButton(
            label: 'Подтвердить и оплатить наличными',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Передайте наличные исполнителю. Он подтвердит получение.'),
                ),
              );
            },
          ));
          break;
        case OrderStatus.completed:
          widgets.add(PrimaryButton(
            label: 'Оставить отзыв',
            onPressed: () => context.push('/order/${order.id}/review'),
          ));
          break;
        case OrderStatus.cancelled:
          widgets.add(_StatusBanner(
            color: AppColors.surfaceVariant,
            textColor: AppColors.textSecondary,
            label: 'Заказ отменён.',
          ));
          break;
      }
    } else {
      switch (order.status) {
        case OrderStatus.open:
          if (hasMyResponse) {
            widgets.add(_StatusBanner(
              color: AppColors.primarySoft,
              textColor: AppColors.primary,
              label: 'Отклик отправлен. Дождитесь решения заказчика.',
            ));
          } else {
            widgets.add(PrimaryButton(
              label: 'Откликнуться на заказ',
              onPressed: () {
                ctrl.takeOrderAsExecutor(order.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Отклик отправлен')),
                );
              },
            ));
          }
          break;
        case OrderStatus.accepted:
          if (order.executorId == 'me') {
            widgets.add(PrimaryButton(
              label: 'Работа выполнена',
              onPressed: () => ctrl.markWorkDone(order.id, inMyOrders: false),
            ));
          } else {
            widgets.add(_StatusBanner(
              color: AppColors.surfaceVariant,
              textColor: AppColors.textSecondary,
              label: 'Заказ принят другим исполнителем.',
            ));
          }
          break;
        case OrderStatus.awaitingPayment:
          widgets.add(PrimaryButton(
            label: 'Оплата получена',
            onPressed: () => ctrl.confirmPayment(order.id, inMyOrders: false),
          ));
          break;
        case OrderStatus.completed:
          widgets.add(PrimaryButton(
            label: 'Оставить отзыв',
            onPressed: () => context.push('/order/${order.id}/review'),
          ));
          break;
        case OrderStatus.cancelled:
          break;
      }
    }
    return widgets;
  }

  void _confirmCancel(BuildContext context, AppController ctrl, String id) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        insetPadding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64.r,
                height: 64.r,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Icon(IconsaxPlusLinear.close_circle, color: Colors.white, size: 38.r),
              ),
              SizedBox(height: 16.h),
              Text('Отменить заказ?', style: AppText.h4(), textAlign: TextAlign.center),
              SizedBox(height: 8.h),
              Text(
                'Все данные о заказе будут потеряны',
                style: AppText.body(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20.h),
              PrimaryButton(
                label: 'Отменить заказ',
                onPressed: () {
                  ctrl.cancelOrder(id);
                  Navigator.of(dialogCtx).pop();
                  context.pop();
                },
              ),
              SizedBox(height: 8.h),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(16.r),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16.r),
                    onTap: () => Navigator.of(dialogCtx).pop(),
                    child: Container(
                      height: 56.h,
                      alignment: Alignment.center,
                      child: Text('Отмена',
                          style: AppText.button(color: AppColors.textPrimary)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.body(color: AppColors.textSecondary)),
        SizedBox(height: 4.h),
        Text(value, style: AppText.bodyLarge()),
      ],
    );
  }
}

Widget? _badgeForStatus(
  Order order, {
  required bool isCustomer,
  required bool hasMyResponse,
}) {
  switch (order.status) {
    case OrderStatus.accepted:
      return const _StatusBadge('Исполнитель найден');
    case OrderStatus.awaitingPayment:
      return _StatusBadge(isCustomer ? 'Подтвердите оплату' : 'Ожидает оплаты');
    case OrderStatus.completed:
      return const _StatusBadge('Завершён');
    case OrderStatus.cancelled:
      return const _StatusBadge('Отменён', color: AppColors.error);
    case OrderStatus.open:
      if (!isCustomer && hasMyResponse) {
        return const _StatusBadge('Отклик отправлен');
      }
      return null;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.label, {this.color = AppColors.primary});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Text(
        label,
        style: AppText.bodySmall(color: Colors.white, weight: FontWeight.w500),
      ),
    );
  }
}

class _ExecutorCard extends StatelessWidget {
  const _ExecutorCard({required this.executorId, required this.orderId});
  final String executorId;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final user = userById(executorId);
    return AppCard(
      onTap: () => context.push('/order/$orderId/user/$executorId'),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        children: [
          Container(
            width: 56.r,
            height: 56.r,
            decoration: const BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: Icon(IconsaxPlusLinear.user, color: AppColors.primary, size: 32.r),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: AppText.h4()),
                SizedBox(height: 2.h),
                Text(user.phone, style: AppText.body(color: AppColors.textSecondary)),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Icon(IconsaxPlusBold.star_1, color: AppColors.star, size: 14.r),
                    SizedBox(width: 4.w),
                    Text(
                      user.rating.toStringAsFixed(1).replaceAll('.', ','),
                      style: AppText.bodySmall(weight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(IconsaxPlusLinear.arrow_right_3, color: AppColors.primary, size: 22.r),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.color, required this.textColor, required this.label});
  final Color color;
  final Color textColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppText.body(color: textColor, weight: FontWeight.w500),
      ),
    );
  }
}
