import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_time_formatters.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/remote/orders_repository.dart';
import 'order_draft.dart';
import 'select_payment_method_screen.dart';

const _minPrice = 100;

class OrderSummaryScreen extends ConsumerStatefulWidget {
  const OrderSummaryScreen({super.key});

  @override
  ConsumerState<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends ConsumerState<OrderSummaryScreen> {
  late TextEditingController _priceCtrl;
  late TextEditingController _dateCtrl;
  late TextEditingController _timeCtrl;

  @override
  void initState() {
    super.initState();
    final d = ref.read(orderDraftProvider);
    _priceCtrl = TextEditingController(text: formatRub(d.priceRub));
    _dateCtrl = TextEditingController(
      text: d.scheduledAt == null ? '' : DateFormat('dd.MM.yyyy').format(d.scheduledAt!),
    );
    _timeCtrl = TextEditingController(
      text: d.scheduledAt == null ? '' : DateFormat('HH:mm').format(d.scheduledAt!),
    );
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  void _syncSchedule() {
    final date = parseRuDate(_dateCtrl.text);
    final time = parseRuTime(_timeCtrl.text);
    DateTime? dt;
    if (date != null) {
      dt = DateTime(date.year, date.month, date.day, time?.hour ?? 0, time?.minute ?? 0);
    }
    ref.read(orderDraftProvider.notifier).update(
          scheduledAt: dt,
          asap: dt == null,
          clearScheduled: dt == null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(orderDraftProvider);
    final price = int.tryParse(_priceCtrl.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final canContinue =
        price >= _minPrice && (draft.paymentMethod?.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    child: const AppBackButton(),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
                    child: Text(
                      'Создать заказ',
                      style: AppText.h1().copyWith(
                        height: 1.21,
                        letterSpacing: 0.40,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              children: [
                AppTextField(
                  label: 'Дата (опционально)',
                  hint: 'ДД.ММ.ГГГГ',
                  controller: _dateCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [DateMaskFormatter()],
                  onChanged: (_) => _syncSchedule(),
                ),
                SizedBox(height: 16.h),
                AppTextField(
                  label: 'Время (опционально)',
                  hint: 'ЧЧ:ММ',
                  controller: _timeCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [TimeMaskFormatter()],
                  onChanged: (_) => _syncSchedule(),
                ),
                SizedBox(height: 16.h),
                AppTextField(
                  label: 'Стоимость работы',
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RubFormatter()],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  onChanged: (v) {
                    final n = int.tryParse(v.replaceAll(RegExp(r'\D'), '')) ?? 0;
                    ref.read(orderDraftProvider.notifier).update(priceRub: n);
                    setState(() {});
                  },
                ),
                SizedBox(height: 4.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Text(
                    'Минимальная стоимость заказа составляет $_minPrice рублей',
                    style: AppText.caption(
                      color: Colors.black.withValues(alpha: 0.60),
                    ).copyWith(height: 1.33),
                  ),
                ),
                SizedBox(height: 16.h),
                _PaymentMethod(
                  value: draft.paymentMethod ?? 'Укажите способ оплаты',
                  onTap: () async {
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      useSafeArea: true,
                      builder: (_) => ClipRRect(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(20.r)),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.92,
                          child: const SelectPaymentMethodScreen(),
                        ),
                      ),
                    );
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              child: PrimaryButton(
                label: 'Создать заказ',
                onPressed: canContinue ? () => _publish(context, ref, draft) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _publish(BuildContext context, WidgetRef ref, OrderDraft draft) async {
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
    // Если бэкенд подключён — отправляем в PB; репозиторий сам зеркалит
    // в мок-состояние через AppController при отсутствии PB.
    final photoFiles = draft.photoPaths
        .map((p) => File(p))
        .where((f) => f.existsSync())
        .toList();
    try {
      await ref
          .read(ordersRepositoryProvider)
          .create(draft: order, photoFiles: photoFiles);
      // Обновляем стрим «Моих заказов», чтобы новый заказ появился сразу.
      ref.invalidate(myOrdersStreamProvider);
    } catch (e) {
      // Мягкий фоллбэк: записываем в локальный стейт даже при ошибке PB,
      // чтобы пользователь видел заказ в «Моих заказах».
      ref.read(appControllerProvider.notifier).createOrder(order);
    }
    ref.read(orderDraftProvider.notifier).reset();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      builder: (ctx) => const _OrderCreatedDialog(),
    );
    if (!context.mounted) return;
    context.go('/home/my');
  }
}

class _OrderCreatedDialog extends StatelessWidget {
  const _OrderCreatedDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Container(
        width: 313.w,
        padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(24.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/tick_square.webp',
              width: 56.r,
              height: 56.r,
            ),
            SizedBox(height: 16.h),
            Text(
              'Заказ создан!',
              textAlign: TextAlign.center,
              style: AppText.h3().copyWith(height: 1.40),
            ),
            SizedBox(height: 8.h),
            Text(
              'Заказ будет отображаться в ленте исполнителей и в разделе “Мои заказы”',
              textAlign: TextAlign.center,
              style: AppText.body().copyWith(
                fontSize: 15.sp,
                color: Colors.black.withValues(alpha: 0.60),
                height: 1.33,
              ),
            ),
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Material(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10.r),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10.r),
                  onTap: () => Navigator.of(context).pop(),
                  child: SizedBox(
                    width: double.infinity,
                    height: 36.h,
                    child: Center(
                      child: Text(
                        'Ок',
                        textAlign: TextAlign.center,
                        style: AppText.bodyLarge(
                          color: AppColors.background,
                          weight: FontWeight.w600,
                        ).copyWith(
                          height: 1.29,
                          letterSpacing: -0.40,
                        ),
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

class _PaymentMethod extends StatelessWidget {
  const _PaymentMethod({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 56.h),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            child: Row(
              children: [
                Icon(IconsaxPlusLinear.wallet_2, color: AppColors.primary, size: 24.r),
                SizedBox(width: 16.w),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(color: AppColors.textPrimary).copyWith(height: 1.50),
                  ),
                ),
                SizedBox(width: 16.w),
                Icon(IconsaxPlusLinear.arrow_right_3, color: AppColors.primary, size: 24.r),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
