import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
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

  String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// В release-сборке принимаем только мобильные RU-номера: 11 цифр,
  /// начинающиеся с `79` (городские/стационарные `8 4xx…` отсекаем — SMS
  /// на них не уйдёт).
  /// В debug-сборке (Android Studio Run) — любые `+7xxxxxxxxxx`, чтобы
  /// работали тестовые номера типа `+71111111111` / `+70000000000` для
  /// dev-режима бэка с кодом `1234`.
  bool get _phoneOk {
    final d = _digits(_ctrl.text);
    if (d.length != 11) return false;
    if (kReleaseMode) return d.startsWith('79');
    return d.startsWith('7');
  }

  bool get _valid => _phoneOk && _agreed;

  /// Текст подсказки, который рассказывает юзеру, почему кнопка «Далее» не
  /// активна. Раньше при невалидном номере или незажатой галочке кнопка
  /// просто была серой — юзер не понимал, что не так.
  String? get _blockerHint {
    if (!_phoneOk) return null; // ничего не показываем пока ввод не закончен
    if (!_agreed) return 'Подтвердите согласие, чтобы продолжить';
    return null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Маппинг error-кодов от auth-репозитория → текст для пользователя.
  /// `retryAfter` приходит в секундах из AuthResult. Если значение > 60 —
  /// форматируем в минутах с правильной плюрализацией.
  String _errorMessage(String? code, int? retryAfter) {
    switch (code) {
      case 'rate_limited':
        return 'Слишком много попыток. Попробуйте через ${_formatRetry(retryAfter)}.';
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

  /// Плюрализация для русского: сек/мин с правильным окончанием.
  String _formatRetry(int? retryAfter) {
    final s = retryAfter ?? 60;
    if (s >= 60) {
      final m = s ~/ 60;
      return '$m ${_pluralMin(m)}';
    }
    return '$s ${_pluralSec(s)}';
  }

  String _pluralSec(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'секунду';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'секунды';
    return 'секунд';
  }

  String _pluralMin(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'минуту';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'минуты';
    return 'минут';
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _isSending ? null : () => setState(() => _agreed = !_agreed),
                    child: Container(
                      margin: EdgeInsets.only(top: 2.h),
                      width: 22.r,
                      height: 22.r,
                      decoration: BoxDecoration(
                        color: _agreed ? AppColors.primary : Colors.transparent,
                        border: Border.all(
                          color: _agreed ? AppColors.primary : AppColors.textTertiary,
                          width: 2.0,
                        ),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: _agreed
                          ? Icon(
  Icons.check_rounded,
  size: 18.r,
  color: Colors.white,
  shadows: const [Shadow(color: Colors.white, blurRadius: 2)],
)
                          : null,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: AppText.caption(color: AppColors.textSecondary),
                        children: [
                          const TextSpan(text: 'Согласен(а) с '),
                          TextSpan(
                            text: 'Условиями использования',
                            style: AppText.caption(color: AppColors.primary).copyWith(
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.primary,
                            ),
                          ),
                          const TextSpan(text: ' и '),
                          TextSpan(
                            text: 'Политикой конфиденциальности',
                            style: AppText.caption(color: AppColors.primary).copyWith(
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
              if (_blockerHint != null) ...[
                SizedBox(height: 8.h),
                Text(
                  _blockerHint!,
                  textAlign: TextAlign.center,
                  style: AppText.caption(color: AppColors.error),
                ),
              ],
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
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
