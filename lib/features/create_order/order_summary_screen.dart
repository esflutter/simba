import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import 'order_draft.dart';

const _minPrice = 100;

class OrderSummaryScreen extends ConsumerStatefulWidget {
  const OrderSummaryScreen({super.key});

  @override
  ConsumerState<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends ConsumerState<OrderSummaryScreen> {
  late TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    final d = ref.read(orderDraftProvider);
    _priceCtrl = TextEditingController(text: d.priceRub == 0 ? '' : d.priceRub.toString());
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(orderDraftProvider);
    final price = int.tryParse(_priceCtrl.text) ?? 0;
    final canContinue = price >= _minPrice;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              child: const AppBackButton(),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Text('Параметры', style: AppText.h1()),
            ),
            SizedBox(height: 16.h),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                children: [
                  _DateTimeRow(),
                  SizedBox(height: 12.h),
                  AppTextField(
                    label: 'Стоимость, ₽',
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    onChanged: (v) {
                      final n = int.tryParse(v) ?? 0;
                      ref.read(orderDraftProvider.notifier).update(priceRub: n);
                      setState(() {});
                    },
                  ),
                  SizedBox(height: 4.h),
                  Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: Text(
                      'Минимальная стоимость заказа $_minPrice ₽',
                      style: AppText.caption(color: AppColors.textSecondary),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  AppCard(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Способ оплаты',
                            style: AppText.caption(color: AppColors.textSecondary)),
                        SizedBox(height: 6.h),
                        Row(
                          children: [
                            Icon(IconsaxPlusLinear.wallet_2,
                                color: AppColors.primary, size: 22.r),
                            SizedBox(width: 8.w),
                            Text('Наличные исполнителю',
                                style: AppText.bodyLarge()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              child: PrimaryButton(
                label: 'Опубликовать заказ',
                onPressed: canContinue
                    ? () {
                        _publish(context, ref, draft);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _publish(BuildContext context, WidgetRef ref, OrderDraft draft) {
    final city = ref.read(appControllerProvider).selectedCity;
    final loc = draft.location ?? city.center;
    final id = MockData.generateOrderId();
    final order = Order(
      id: id,
      customerId: 'me',
      categoryId: draft.categoryId!,
      title: draft.title,
      description: draft.description,
      address: draft.address.isEmpty ? city.name : draft.address,
      location: loc,
      priceRub: draft.priceRub,
      status: OrderStatus.open,
      createdAt: DateTime.now(),
      scheduledAt: draft.scheduledAt,
      asap: draft.asap,
      photoPaths: draft.photoPaths,
      forOtherPhone: draft.forOtherPhone,
    );
    ref.read(appControllerProvider.notifier).createOrder(order);
    ref.read(orderDraftProvider.notifier).reset();
    context.go('/create/done');
  }
}

class _DateTimeRow extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DateTimeRow> createState() => _DateTimeRowState();
}

class _DateTimeRowState extends ConsumerState<_DateTimeRow> {
  @override
  Widget build(BuildContext context) {
    final d = ref.watch(orderDraftProvider);
    final label = d.asap
        ? 'Как можно скорее'
        : d.scheduledAt == null
            ? 'Указать дату и время'
            : DateFormat('dd.MM.yyyy HH:mm').format(d.scheduledAt!);
    return Column(
      children: [
        AppCard(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.primary,
            title: Text('Как можно скорее', style: AppText.bodyLarge()),
            value: d.asap,
            onChanged: (v) {
              ref.read(orderDraftProvider.notifier).update(asap: v, clearScheduled: v);
            },
          ),
        ),
        if (!d.asap) ...[
          SizedBox(height: 12.h),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16.r),
            child: InkWell(
              borderRadius: BorderRadius.circular(16.r),
              onTap: () async {
                final now = DateTime.now();
                final date = await showDatePicker(
                  context: context,
                  initialDate: d.scheduledAt ?? now,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (date == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(d.scheduledAt ?? now),
                );
                if (time == null) return;
                final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                ref.read(orderDraftProvider.notifier).update(scheduledAt: dt);
              },
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                child: Row(
                  children: [
                    Icon(IconsaxPlusLinear.calendar, color: AppColors.primary, size: 20.r),
                    SizedBox(width: 12.w),
                    Expanded(child: Text(label, style: AppText.bodyLarge())),
                    Icon(IconsaxPlusLinear.arrow_right_3, color: AppColors.primary, size: 22.r),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
