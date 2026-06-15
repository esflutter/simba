import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/plural_ru.dart' show formatRetryAfter;
import '../../core/utils/ru_phone_formatter.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/remote/auth_repository.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _ctrl = TextEditingController(text: '+7');
  bool _agreed = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Не даём поставить курсор/выделение перед «+7» — префикс читается
    // как часть подложки, попытка туда тапнуть и начать печатать ломает
    // форматирование (формат предполагает, что цифры идут СТРОГО после +7).
    _ctrl.addListener(_clampCursorAfterPrefix);
  }

  void _clampCursorAfterPrefix() {
    final sel = _ctrl.selection;
    if (!sel.isValid) return;
    const prefixLen = 2; // длина «+7»
    if (sel.start >= prefixLen && sel.end >= prefixLen) return;
    final text = _ctrl.text;
    final clamped = TextSelection(
      baseOffset: sel.baseOffset < prefixLen ? text.length : sel.baseOffset,
      extentOffset: sel.extentOffset < prefixLen ? text.length : sel.extentOffset,
    );
    if (clamped != sel) {
      _ctrl.selection = clamped;
    }
  }

  String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Принимаем 11 цифр, начинающихся с `7`. В release ограничиваем
  /// мобильными `79xxxxxxxxx` (городские/стационарные `8 4xx…` отсекаем
  /// — SMS на них не уйдёт), НО оставляем дырку для тестовых номеров
  /// `+7Xddddddddd`, где X∈{1,2,3} и все 9 цифр одинаковые — те же,
  /// которые бэк пропускает в mock-режим с пином `1234`. Так prod-APK
  /// можно тестировать без реальных SMS.
  bool get _phoneOk {
    final d = _digits(_ctrl.text);
    if (d.length != 11) return false;
    if (!d.startsWith('7')) return false;
    if (!kReleaseMode) return true;
    if (d.startsWith('79')) return true;
    final x = d[1];
    if (x != '1' && x != '2' && x != '3') return false;
    final first = d[2];
    for (int i = 3; i < d.length; i++) {
      if (d[i] != first) return false;
    }
    return true;
  }

  bool get _valid => _phoneOk && _agreed;

  @override
  void dispose() {
    _ctrl.removeListener(_clampCursorAfterPrefix);
    _ctrl.dispose();
    super.dispose();
  }

  /// Маппинг error-кодов от auth-репозитория → текст для пользователя.
  /// `retryAfter` приходит в секундах из AuthResult. Форматирование
  /// сек/мин с RU-плюрализацией — общий хелпер [formatRetryAfter] в
  /// `core/utils/plural_ru.dart` (раньше эта же формула была скопирована
  /// сюда и в sms_code_screen).
  String _errorMessage(String? code, int? retryAfter) {
    switch (code) {
      case 'rate_limited':
        return 'Слишком много попыток. Попробуйте через ${formatRetryAfter(retryAfter)}.';
      case 'phone_unavailable':
        return 'Этот номер недоступен';
      case 'sms_provider_failed':
        return 'SMS-провайдер временно недоступен';
      case 'network':
        return 'Нет подключения';
      default:
        return 'Не удалось отправить SMS';
    }
  }

  Future<void> _onNext() async {
    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      final phone = _ctrl.text;
      final auth = ref.read(authRepositoryProvider);
      if (auth.isLive) {
        final result = await auth.sendOtpDetailed(phone);
        if (!mounted) return;
        if (!result.ok) {
          AppToast.show(context, _errorMessage(result.errorCode, result.retryAfter));
          return;
        }
        // SMS Aero Mobile Authorization вернул session_id.
        //
        // ВРЕМЕННО (2026-05-14): SIM-PUSH экран ожидания (`/auth/sms-waiting`)
        // выключен — переходим сразу на форму ввода 4-значного кода. Решение
        // оставлять ли вообще SIM-PUSH в продукте пока не принято; пока
        // оставляем простой flow «телефон → код». Если решим вернуть push —
        // раскомментировать ветку `status == 'pending'` ниже.
        final sessionId = result.sessionId ?? '';
        final encPhone = Uri.encodeComponent(phone);
        final encSid = Uri.encodeComponent(sessionId);
        context.push('/auth/sms?session_id=$encSid&phone=$encPhone');
        // if (result.status == 'otp_required') {
        //   context.push('/auth/sms?session_id=$encSid&phone=$encPhone');
        // } else {
        //   context.push('/auth/sms-waiting?session_id=$encSid&phone=$encPhone');
        // }
      } else {
        // Mock-режим: бэка нет, переходим сразу на форму ввода — там
        // принимается любой 4-значный код кроме `0000`.
        if (!mounted) return;
        context.push('/auth/sms?phone=${Uri.encodeComponent(phone)}');
      }
    } catch (e) {
      // Репозиторий переводит сетевые ошибки в errorCode, но редкое
      // исключение (битое тело ответа) долетит сюда — без catch оно
      // молча гасилось бы в finally, и кнопка просто переставала
      // реагировать без объяснения.
      if (mounted) {
        AppToast.show(context, 'Не удалось отправить SMS. Попробуйте ещё раз');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 62.h),
                      Center(
                        child: Icon(IconsaxPlusLinear.call, size: 80.r, color: AppColors.primary),
                      ),
                      SizedBox(height: 24.h),
                      Text('Введите номер телефона', style: AppText.h2().copyWith(letterSpacing: -0.10), textAlign: TextAlign.center),
                      SizedBox(height: 9.h),
                      Text(
                        'На указанный номер отправим SMS с кодом',
                        textAlign: TextAlign.center,
                        style: AppText.body().copyWith(
                          color: Colors.black.withValues(alpha: 0.60),
                          height: 1.38,
                        ),
                      ),
                      SizedBox(height: 28.h),
                      AppTextField(
                        label: 'Номер телефона',
                        controller: _ctrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [RuPhoneFormatter()],
                        onChanged: (_) => setState(() {}),
                        autofocus: true,
                        enabled: !_isSending,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              // Чекбокс согласия. Тап работает как по самому квадратику,
              // так и по тексту рядом — раньше клик мимо квадратика 22×22
              // игнорировался, и было непонятно, что галочка вообще
              // переключается. На сами TextSpan'ы ссылок recognizer не
              // навешен, отдельных переходов на «Условия / Политику» нет,
              // так что общий GestureDetector конфликтов не вызывает.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _isSending
                    ? null
                    : () => setState(() => _agreed = !_agreed),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: EdgeInsets.only(top: 2.h),
                      width: 22.r,
                      height: 22.r,
                      decoration: BoxDecoration(
                        color:
                            _agreed ? AppColors.primary : Colors.transparent,
                        border: Border.all(
                          color: _agreed
                              ? AppColors.primary
                              : AppColors.textTertiary,
                          width: 2.0,
                        ),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: _agreed
                          ? Icon(
                              Icons.check_rounded,
                              size: 18.r,
                              color: AppColors.surface,
                              shadows: const [
                                Shadow(
                                  color: AppColors.surface,
                                  blurRadius: 2,
                                ),
                              ],
                            )
                          : null,
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style:
                              AppText.caption(color: AppColors.textSecondary),
                          children: [
                            const TextSpan(text: 'Согласен(а) с '),
                            TextSpan(
                              text: 'Условиями использования',
                              style: AppText.caption(color: AppColors.primary)
                                  .copyWith(
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.primary,
                              ),
                            ),
                            const TextSpan(text: ' и '),
                            TextSpan(
                              text: 'Политикой конфиденциальности',
                              style: AppText.caption(color: AppColors.primary)
                                  .copyWith(
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 18.h),
              _PhoneNextButton(
                isSending: _isSending,
                onPressed: (_valid && !_isSending) ? _onNext : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// PrimaryButton с возможностью показать индикатор вместо текста.
/// Выделено в отдельный виджет, чтобы не править общий PrimaryButton —
/// он используется по всему приложению.
class _PhoneNextButton extends StatelessWidget {
  const _PhoneNextButton({required this.isSending, required this.onPressed});

  final bool isSending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!isSending) {
      return PrimaryButton(label: 'Далее', onPressed: onPressed);
    }
    // Индикатор поверх отключённой кнопки — сохраняет высоту/радиус как у PrimaryButton.
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
