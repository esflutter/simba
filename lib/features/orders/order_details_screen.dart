import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_time_formatters.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
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
    final statusBadge =
        _badgeForStatus(order, isCustomer: isCustomer, hasMyResponse: hasMyResponse);

    final isCompleted = order.status == OrderStatus.completed;
    final isCancelled = order.status == OrderStatus.cancelled;
    final isPast = isCompleted || isCancelled;
    // Для выполненных/отменённых «Как можно скорее» неуместно — показываем
    // дату завершения/создания (как в списке истории).
    final whenLabel = isPast
        ? DateFormat('dd.MM.yyyy', 'ru_RU').format(
            order.scheduledAt ?? order.createdAt,
          )
        : order.scheduledAt != null
            ? DateFormat('dd.MM.yyyy HH:mm').format(order.scheduledAt!)
            : 'Как можно скорее';
    final whenFieldLabel =
        isCompleted ? 'Дата выполнения' : isCancelled ? 'Дата' : 'Время начала работ';
    final paymentLabel = _paymentLabel(order.paymentMethod);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── White header with back button + status badge ──
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(8.w, 4.h, 16.w, 4.h),
                child: Row(
                  children: [
                    const AppBackButton(),
                    const Spacer(),
                    if (statusBadge != null) statusBadge,
                  ],
                ),
              ),
            ),
          ),
          // ── Gray scrollable content ──
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
              children: [
                Text(order.title, style: AppText.h2().copyWith(height: 1.20)),
                SizedBox(height: 16.h),
                Text(
                  formatRub(order.priceRub),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w600,
                    height: 1.40,
                  ),
                ),
                SizedBox(height: 16.h),
                _Field('Способ оплаты', paymentLabel),
                SizedBox(height: 16.h),
                _Field(whenFieldLabel, whenLabel),
                SizedBox(height: 16.h),
                if (order.description.trim().isNotEmpty) ...[
                  _Field('Комментарий', order.description),
                  SizedBox(height: 16.h),
                ],
                _AddressBlock(address: order.address, location: order.location),
                if (order.photoPaths.isNotEmpty) ...[
                  SizedBox(height: 16.h),
                  _FieldLabel('Фото'),
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
                  _FieldLabel('Исполнитель'),
                  SizedBox(height: 8.h),
                  _ExecutorCard(executorId: order.executorId!, orderId: order.id),
                ],
                SizedBox(height: 16.h),
              ],
            ),
          ),
          // ── White sticky action bar ──
          _ActionBar(
            children: _buildActions(context, ref, order, isMine, hasMyResponse),
          ),
        ],
      ),
    );
  }

  String _paymentLabel(PaymentMethod m) {
    switch (m) {
      case PaymentMethod.cash:
        return 'Наличными исполнителю';
    }
  }

  List<Widget> _buildActions(BuildContext context, WidgetRef ref, Order order, bool isMine, bool hasMyResponse) {
    final ctrl = ref.read(appControllerProvider.notifier);
    final widgets = <Widget>[];

    if (isMine) {
      switch (order.status) {
        case OrderStatus.open:
          widgets.add(_ResponsesButton(
            count: order.responses.length,
            onTap: () => context.push('/order/${order.id}/responses'),
          ));
          widgets.add(SizedBox(height: 16.h));
          widgets.add(_CancelOrderButton(
            onTap: () => _confirmCancel(context, ctrl, order.id),
          ));
          break;
        case OrderStatus.accepted:
          widgets.add(PrimaryButton(
            label: 'Работа выполнена',
            onPressed: () => ctrl.markWorkDone(order.id, inMyOrders: true),
          ));
          break;
        case OrderStatus.awaitingPayment:
          widgets.add(PrimaryButton(
            label: 'Подтвердить оплату',
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
      barrierColor: Colors.black.withValues(alpha: 0.40),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Container(
          width: 313.w,
          padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56.r,
                height: 56.r,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Center(
                  child: CustomPaint(
                    size: Size(28.r, 28.r),
                    painter: _XPainter(color: Colors.white, strokeWidth: 4.5.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Отменить заказ?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.40,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Все данные о заказе будут потеряны',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.60),
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.33,
                ),
              ),
              SizedBox(height: 16.h),
              _DialogActionButton(
                label: 'Отменить заказ',
                background: AppColors.primary,
                textColor: Colors.white,
                onTap: () {
                  ctrl.cancelOrder(id);
                  Navigator.of(dialogCtx).pop();
                  context.pop();
                },
              ),
              SizedBox(height: 8.h),
              _DialogActionButton(
                label: 'Отмена',
                background: AppColors.surfaceVariant,
                textColor: Colors.black,
                onTap: () => Navigator.of(dialogCtx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _XPainter extends CustomPainter {
  _XPainter({required this.color, required this.strokeWidth});
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _XPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
    required this.label,
    required this.background,
    required this.textColor,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color textColor;
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
          width: double.infinity,
          height: 36.h,
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
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

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16.r),
          topRight: Radius.circular(16.r),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18.80,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _ResponsesButton extends StatelessWidget {
  const _ResponsesButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 50.h,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Смотреть отклики',
                style: AppText.bodyLarge(color: Colors.white, weight: FontWeight.w600)
                    .copyWith(letterSpacing: -0.40),
              ),
              SizedBox(width: 10.w),
              Container(
                constraints: BoxConstraints(minWidth: 24.r),
                height: 24.r,
                padding: EdgeInsets.symmetric(horizontal: 6.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24.r),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    height: 1.33,
                    letterSpacing: -0.23,
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

class _CancelOrderButton extends StatelessWidget {
  const _CancelOrderButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 50.h,
          child: Center(
            child: Text(
              'Отменить заказ',
              style: AppText.bodyLarge(color: AppColors.error, weight: FontWeight.w600)
                  .copyWith(letterSpacing: -0.40),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressBlock extends StatelessWidget {
  const _AddressBlock({required this.address, required this.location});
  final String address;
  final LatLng location;

  Future<void> _openMap() async {
    final lat = location.latitude;
    final lng = location.longitude;
    // Цепочка попыток: сначала маршрут от моего местоположения,
    // если ничего не открылось — просто координаты места.
    final attempts = <Uri>[
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
      Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
    ];
    for (final uri in attempts) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (_) {
        // переходим к следующему варианту
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Адрес'),
        SizedBox(height: 12.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(10.r),
          child: Image.asset(
            'assets/images/map_mock.webp',
            width: double.infinity,
            height: 170.h,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Icon(IconsaxPlusLinear.location, color: AppColors.primary, size: 18.r),
            SizedBox(width: 6.w),
            Expanded(
              child: Text(
                address,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.60,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8.r),
          child: InkWell(
            borderRadius: BorderRadius.circular(8.r),
            onTap: _openMap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(IconsaxPlusLinear.routing_2, color: AppColors.primary, size: 20.r),
                  SizedBox(width: 6.w),
                  Text(
                    'Построить маршрут',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.33,
                      letterSpacing: -0.23,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: AppColors.primary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w600,
        height: 1.54,
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
        _FieldLabel(label),
        SizedBox(height: 4.h),
        Text(value, style: AppText.body().copyWith(height: 1.50)),
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
              color: AppColors.surfaceVariant,
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
