import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/backend_error.dart';
import '../../core/utils/client_uid.dart';
import '../../core/utils/date_time_formatters.dart';
import '../../core/utils/plural_ru.dart' show pluralRubles;
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/remote/orders_repository.dart';
import 'order_draft.dart';
import 'select_payment_method_screen.dart';

// Минимум/максимум суммы — из общих констант `kPriceMin`/`kPriceMax`
// в `core/utils/date_time_formatters.dart`, чтобы UI-валидация, фильтр
// feed-парсера и схема бэка ходили от одного значения.

class OrderSummaryScreen extends ConsumerStatefulWidget {
  const OrderSummaryScreen({super.key});

  @override
  ConsumerState<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends ConsumerState<OrderSummaryScreen> {
  late TextEditingController _priceCtrl;
  late TextEditingController _dateCtrl;
  late TextEditingController _timeCtrl;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    final d = ref.read(orderDraftProvider);
    _priceCtrl = TextEditingController(text: formatRub(d.priceRub));
    _dateCtrl = TextEditingController(
      text: d.scheduledAt == null
          ? ''
          : DateFormat('dd.MM.yyyy', 'ru_RU').format(d.scheduledAt!),
    );
    _timeCtrl = TextEditingController(
      text: d.scheduledAt == null
          ? ''
          : DateFormat('HH:mm', 'ru_RU').format(d.scheduledAt!),
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

  /// Текущая цена из контроллера (строка → int), безопасный фолбэк 0.
  int get _priceRub =>
      int.tryParse(_priceCtrl.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  /// Полная валидация перед публикацией. Кнопка дизейблится, если хоть одно
  /// условие не выполнено: категория, адрес + координаты, цена в диапазоне
  /// [kPriceMin .. kPriceMax], выбран способ оплаты, и `scheduledAt` (если
  /// введён) — не в прошлом. Потолок 99 999 999 ₽ — формальный (чтобы
  /// не лезли 10-значные суммы по ошибке), реалистично не достижим.
  bool get _canPublish {
    final draft = ref.read(orderDraftProvider);
    final p = _priceRub;
    final s = draft.scheduledAt;
    final scheduledOk = s == null || !s.isBefore(DateTime.now());
    return !_isPublishing &&
        draft.categoryId != null &&
        draft.address.trim().isNotEmpty &&
        draft.location != null &&
        p >= kPriceMin &&
        p <= kPriceMax &&
        scheduledOk &&
        (draft.paymentMethod?.isNotEmpty ?? false);
  }

  /// Полный ли DD.MM.YYYY и HH:mm одновременно введены. Используется только
  /// для подсказки ошибки «дата в прошлом» — пока юзер заполняет одну
  /// половину, ругаться рано.
  bool get _scheduleFullyEntered =>
      parseRuDate(_dateCtrl.text) != null &&
      parseRuTime(_timeCtrl.text) != null;

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(orderDraftProvider);
    final canContinue = _canPublish;

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
                // Подсказка про прошлое время — показываем, только когда обе
                // части (дата + время) полностью введены и итог уже в прошлом.
                // Не ругаемся, пока юзер ещё допечатывает.
                if (_scheduleFullyEntered &&
                    draft.scheduledAt != null &&
                    draft.scheduledAt!.isBefore(DateTime.now())) ...[
                  SizedBox(height: 4.h),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: Text(
                      'Дата и время уже прошли',
                      style: AppText.caption(color: AppColors.error)
                          .copyWith(height: 1.33),
                    ),
                  ),
                ],
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
                    'Минимальная стоимость заказа — $kPriceMin ${pluralRubles(kPriceMin)}',
                    style: AppText.caption(
                      color: Colors.black.withValues(alpha: 0.60),
                    ).copyWith(height: 1.33),
                  ),
                ),
                SizedBox(height: 16.h),
                _PaymentMethod(
                  // draft.paymentMethod хранит dbValue (cash/cashless_transfer)
                  // — конвертируем в RU-label для отображения. Раньше
                  // хранился сам label, при ребрендинге подписи старый
                  // черновик ломался в `PaymentMethodMapping.fromLabel`.
                  value: draft.paymentMethod != null
                      ? PaymentMethodMapping
                          .fromDbValue(draft.paymentMethod)
                          .label
                      : 'Укажите способ оплаты',
                  isPlaceholder: draft.paymentMethod == null,
                  onTap: _isPublishing
                      ? () {}
                      : () async {
                          await showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            useSafeArea: true,
                            builder: (_) => ClipRRect(
                              borderRadius:
                                  BorderRadius.vertical(top: Radius.circular(20.r)),
                              child: SizedBox(
                                height: MediaQuery.sizeOf(context).height * 0.92,
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
              child: _PublishButton(
                isBusy: _isPublishing,
                onPressed: canContinue ? () => _publish(context, ref, draft) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _publish(BuildContext context, WidgetRef ref, OrderDraft draft) async {
    if (_isPublishing) return;
    // Жёсткие предварительные проверки. Дублируют _canPublish, но защищают
    // на случай, если кто-то обошёл UI-блокировку (например, гонка после
    // bottom-sheet адреса). Лучше показать тост, чем создать «фантомный»
    // заказ без координат, который не покажется в ленте исполнителям.
    if (draft.location == null) {
      AppToast.show(context, 'Укажите адрес');
      return;
    }
    if (draft.address.trim().isEmpty) {
      AppToast.show(context, 'Укажите адрес');
      return;
    }
    if (draft.categoryId == null) {
      AppToast.show(context, 'Выберите категорию');
      return;
    }
    final price = _priceRub;
    if (price < kPriceMin) {
      AppToast.show(context, 'Минимальная цена $kPriceMin ₽');
      return;
    }
    if (price > kPriceMax) {
      AppToast.show(context, 'Максимальная цена ${formatRub(kPriceMax)}');
      return;
    }
    // Финальный city-guard: даже если в _onMapTap прошли Phase 1+2, тут
    // ещё раз проверяем что точка действительно близко к центру выбранного
    // города (например, пользователь мог сменить город уже после выбора
    // адреса — тогда `draft.location` останется в прежнем городе).
    final city = ref.read(appControllerProvider).selectedCity;
    final distanceKm = const Distance().as(
      LengthUnit.Kilometer,
      draft.location!,
      city.center,
    );
    if (distanceKm > city.boundsRadiusKm * 1.5) {
      AppToast.show(
        context,
        'Адрес вне города ${city.name}. Уточните адрес или смените город.',
      );
      return;
    }
    // Если у города есть FIAS, draft обязан иметь совпадающий FIAS.
    // Иначе — отказ публикации (заказ без верифицированного города не годится:
    // выбор маркера без reverse-geocode или ручной редит сейчас не разрешён).
    if (city.dadataFiasId != null && city.dadataFiasId!.isNotEmpty) {
      if (draft.cityFiasId == null || draft.cityFiasId!.isEmpty) {
        AppToast.show(
          context,
          'Адрес не подтверждён. Выберите из подсказок или коснитесь карты ещё раз.',
        );
        return;
      }
      if (draft.cityFiasId != city.dadataFiasId) {
        AppToast.show(context, 'Адрес не в вашем городе');
        return;
      }
    }
    setState(() => _isPublishing = true);
    try {
      final id = MockData.generateOrderId();
      // customer_id: при live-флоу `OrdersRepository.create()` сам подставит
      // `pb.authStore.record.id`, наш локальный объект не уходит дальше
      // мок-AppController (см. ниже invalidate myOrders/feed). На моках
      // (без бэка) берём id из state.user. Старый хардкод `'me'` ломал
      // фильтр «мои заказы» при гибридных режимах.
      final appState = ref.read(appControllerProvider);
      final myId = appState.user?.id ?? 'me';
      // city_id фиксируем в момент создания — это immutable-привязка к городу,
      // в котором заказ был размещён. Даже если заказчик потом переключит
      // selectedCityId, старые заказы остаются в своём городе (исполнители
      // прежнего города продолжают их видеть в ленте).
      final order = Order(
        id: id,
        customerId: myId,
        cityId: appState.selectedCity.id,
        categoryId: draft.categoryId!,
        title: draft.title,
        description: draft.description,
        address: draft.address,
        location: draft.location!,
        priceRub: draft.priceRub,
        status: OrderStatus.open,
        createdAt: DateTime.now(),
        scheduledAt: draft.scheduledAt,
        asap: draft.asap,
        photoPaths: draft.photoPaths,
        forOtherPhone: draft.forOtherPhone,
        // draft.paymentMethod хранит уже dbValue; mappings.fromDbValue
        // прямо ему соответствует. fromLabel оставлен в коде для
        // обратной совместимости со старыми prefs-черновиками
        // (если у юзера в кэше остался label — мы его не парсим как
        // dbValue, и упадём в default=cash).
        paymentMethod: PaymentMethodMapping.fromDbValue(draft.paymentMethod),
      );
      final photoFiles = draft.photoPaths
          .map((p) => File(p))
          .where((f) => f.existsSync())
          .toList();
      // Создаём заказ; при ошибке НЕ показываем «Заказ создан!» — иначе
      // у пользователя складывается ложное впечатление успеха, а заказ
      // в фид к исполнителям так и не попал.
      //
      // UUID для идемпотентности хранится в самом черновике — это
      // переживает уход с экрана. Если юзер тапнул «Опубликовать»,
      // получил timeout, нажал назад, вернулся через минуту и тапнул
      // снова — UUID тот же, сервер вернёт уже созданный заказ (или
      // отобьёт constraint violation, и репозиторий найдёт его в БД).
      // После успешной публикации reset() черновика обнулит UUID
      // вместе со всем остальным.
      final draftCtrl = ref.read(orderDraftProvider.notifier);
      var uid = ref.read(orderDraftProvider).clientUid;
      if (uid == null || uid.isEmpty) {
        uid = generateClientUid();
        draftCtrl.update(clientUid: uid);
      }
      await ref
          .read(ordersRepositoryProvider)
          .create(draft: order, photoFiles: photoFiles, clientUid: uid);
      // Успех — обновляем мои заказы и ленту исполнителей.
      ref.invalidate(myOrdersStreamProvider);
      ref.invalidate(myExecutorOrdersProvider);
      ref.invalidate(feedOrdersProvider);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.40),
        builder: (ctx) => const _OrderCreatedDialog(),
      );
      // Reset делаем ПОСЛЕ закрытия попапа: пока юзер смотрит «Заказ
      // создан!», экран summary под попапом не должен ребилдиться с
      // плейсхолдерами на полях — иначе сквозь барьер видно, как
      // выбранный способ оплаты внезапно превращается в «Укажите
      // способ оплаты». До reset clientUid в драфте остаётся прежним,
      // повторный submit ловится серверной идемпотентностью.
      ref.read(orderDraftProvider.notifier).reset();
      if (!context.mounted) return;
      context.go('/home/my');
    } catch (e) {
      // При ошибке остаёмся на экране, показываем юзеру конкретику
      // через humanizeBackendError — лимиты публикаций, city_mismatch,
      // размер фото, нет сети — всё переводится в дружелюбный русский.
      // До этого тут был обычный «Не удалось создать заказ» без
      // подсказки, что именно сломалось.
      //
      // Отдельный случай — таймаут / обрыв соединения. Multipart-тело
      // могло уйти на сервер до того, как клиент потерял связь, и
      // заказ уже создан. Если юзер просто увидит «не получилось» и
      // тапнет ещё раз — получит дубль в БД. Подсказываем зайти в
      // «Мои заказы» прежде чем повторять.
      if (!context.mounted) return;
      final s = e.toString();
      final maybeCreated = s.contains('TimeoutException') ||
          s.contains('SocketException') ||
          s.contains('Failed host lookup');
      AppToast.show(
        context,
        maybeCreated
            ? 'Сервер не ответил вовремя. Заказ мог создаться — проверьте «Мои заказы» перед повтором.'
            : humanizeBackendError(e),
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

}

class _PublishButton extends StatelessWidget {
  const _PublishButton({required this.isBusy, required this.onPressed});

  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!isBusy) {
      return PrimaryButton(label: 'Создать заказ', onPressed: onPressed);
    }
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16.r),
        child: SizedBox(
          height: 50.h,
          child: Center(
            child: SizedBox(
              width: 22.r,
              height: 22.r,
              child: const CircularProgressIndicator(
                color: AppColors.surface,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
      ),
    );
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
                    // 48dp — стандартный минимум touch-target.
                    height: 48.h,
                    child: Center(
                      child: Text(
                        'Ок',
                        textAlign: TextAlign.center,
                        // Белый текст на синем — нормальный контраст.
                        // Раньше тут стоял background (#F5F5F5) — серый,
                        // плохо читался на синей кнопке.
                        style: AppText.bodyLarge(
                          color: AppColors.surface,
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
  const _PaymentMethod({
    required this.value,
    required this.onTap,
    this.isPlaceholder = false,
  });

  final String value;
  final VoidCallback onTap;
  // true пока юзер не выбрал способ оплаты — текст рисуем полупрозрачным,
  // как стандартный плейсхолдер. Иначе «Укажите способ оплаты» чёрным
  // выглядит как уже заполненное поле.
  final bool isPlaceholder;

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
                    style: AppText.body(
                      color: isPlaceholder
                          ? Colors.black.withValues(alpha: 0.60)
                          : AppColors.textPrimary,
                    ).copyWith(height: 1.50),
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
