import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/remote/auth_repository.dart';

/// Форма ввода 4-значного OTP-кода. Длина диктуется SMS Aero Mobile
/// Authorization API — 4 цифры фиксированно (в LK не настраивается).
///
/// В live-режиме экран приходит сюда либо с экрана SIM-PUSH ожидания
/// (sessionId не null), либо напрямую от PhoneScreen в моках (sessionId
/// null, проверка по phone+code, любые 4 цифры кроме `0000`).
class SmsCodeScreen extends ConsumerStatefulWidget {
  const SmsCodeScreen({
    super.key,
    required this.phone,
    this.sessionId,
  });

  final String phone;

  /// session_id из Mobile Authorization. В моках не передаётся.
  final String? sessionId;

  @override
  ConsumerState<SmsCodeScreen> createState() => _SmsCodeScreenState();
}

class _SmsCodeScreenState extends ConsumerState<SmsCodeScreen> {
  // Длина кода фиксированно 4. См. документацию SMS Aero Mobile Authorization:
  // `code must be 4 numbers` — серверная сторона не принимает другую длину.
  static const int _codeLength = 4;
  static const int _timerSeconds = 60;
  static const _errorColor = Color(0xFFFF5F57);
  static const _errorBorderColor = Color(0x7FFF383C);

  Key _pinKey = UniqueKey();
  String _code = '';
  String? _sessionId;
  bool _hasError = false;
  String? _errorText;
  bool _showResent = false;
  bool _isVerifying = false;
  bool _isResending = false;
  Timer? _timer;
  Timer? _errorTimer;
  int _seconds = _timerSeconds;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _startTimer(resetPin: false);
  }

  void _startTimer({bool resetPin = true}) {
    _timer?.cancel();
    setState(() {
      _seconds = _timerSeconds;
      _code = '';
      _hasError = false;
      _errorText = null;
      if (resetPin) {
        _pinKey = UniqueKey();
        _showResent = true;
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds <= 0) {
        t.cancel();
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _errorTimer?.cancel();
    super.dispose();
  }

  String get _timerText {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _verifyErrorMessage(String? code, DateTime? lockedUntil) {
    switch (code) {
      case 'code_invalid':
        return 'Неверный код';
      case 'code_expired':
      case 'session_expired':
        return 'Код устарел. Запросите новый';
      case 'session_consumed':
        return 'Код уже использован. Запросите новый';
      case 'session_not_found':
        return 'Сессия не найдена. Начните заново';
      case 'phone_mismatch':
        return 'Несовпадение номера. Начните заново';
      case 'phone_locked':
        return _formatLockMessage(lockedUntil);
      case 'rate_limited':
        return 'Слишком много попыток. Попробуйте позже';
      case 'network':
        return 'Нет подключения';
      default:
        return 'Неверный код';
    }
  }

  String _formatLockMessage(DateTime? until) {
    if (until == null) {
      return 'Слишком много попыток. Попробуйте позже.';
    }
    final remaining = until.difference(DateTime.now());
    if (remaining.inMinutes > 0) {
      final m = remaining.inMinutes;
      return 'Слишком много попыток. Попробуйте через $m ${_pluralMin(m)}.';
    }
    final s = remaining.inSeconds > 0 ? remaining.inSeconds : 0;
    return 'Слишком много попыток. Попробуйте через $s ${_pluralSec(s)}.';
  }

  String _resendErrorMessage(String? code, int? retryAfter) {
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
    if (_isVerifying) return;
    setState(() => _isVerifying = true);
    try {
      final auth = ref.read(authRepositoryProvider);
      final result = await auth.verifyOtpDetailed(
        sessionId: _sessionId,
        phone: widget.phone,
        code: _code,
      );
      if (!mounted) return;
      if (!result.ok) {
        final msg = _verifyErrorMessage(result.errorCode, result.lockedUntil);
        _errorTimer?.cancel();
        setState(() {
          _code = '';
          _hasError = true;
          _errorText = msg;
          _showResent = false;
          _pinKey = UniqueKey();
        });
        // phone_locked / session_expired — НЕ скрываем ошибку через 2.2с:
        // юзер должен ясно увидеть сообщение. Остальные — авто-скрытие.
        final persistent = result.errorCode == 'phone_locked' ||
            result.errorCode == 'session_expired' ||
            result.errorCode == 'session_consumed' ||
            result.errorCode == 'session_not_found';
        if (!persistent) {
          _errorTimer = Timer(const Duration(milliseconds: 2200), () {
            if (mounted) {
              setState(() {
                _hasError = false;
                _errorText = null;
              });
            }
          });
        }
        return;
      }
      if (!mounted) return;
      context.go(postAuthRoute(ref, isNewUser: result.isNewUser));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _onResend() async {
    if (_isResending || _seconds > 0) return;
    setState(() => _isResending = true);
    try {
      final auth = ref.read(authRepositoryProvider);
      if (auth.isLive) {
        final result = await auth.sendOtpDetailed(widget.phone);
        if (!mounted) return;
        if (!result.ok) {
          AppToast.show(
            context,
            _resendErrorMessage(result.errorCode, result.retryAfter),
          );
          return;
        }
        // Live-режим: новая SMS-сессия, обновляем sessionId. Status может
        // прийти 'pending' (SIM-PUSH в процессе) — но юзер уже на форме
        // ввода кода, не возвращаем его на waiting-экран. Он либо введёт
        // код из SMS, либо это и есть SIM-PUSH (тогда poll бы тут пригодился,
        // но проще пусть юзер дождётся SMS — fallback гарантирован через ~30с).
        setState(() => _sessionId = result.sessionId);
      }
      if (!mounted) return;
      _startTimer();
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  static TextStyle get _statusTextStyle => AppText.bodySmall(
        color: _errorColor,
      ).copyWith(letterSpacing: 0.25, height: 1.43);

  @override
  Widget build(BuildContext context) {
    final canContinue = _code.length == _codeLength && !_isVerifying;
    final borderColor = _hasError ? _errorBorderColor : AppColors.divider;
    final activeBorderColor = _hasError ? _errorBorderColor : AppColors.primary;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: Offset(-8.r, 0),
                  child: const AppBackButton(),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 24.h),
                      Center(
                        child: Icon(IconsaxPlusLinear.sms_tracking, size: 80.r, color: AppColors.primary),
                      ),
                      SizedBox(height: 24.h),
                      Text(
                        'Введите код',
                        style: AppText.h2().copyWith(letterSpacing: -0.10),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'Мы отправили SMS с кодом на номер ${widget.phone}',
                        textAlign: TextAlign.center,
                        style: AppText.body().copyWith(
                          color: Colors.black.withValues(alpha: 0.60),
                          height: 1.38,
                        ),
                      ),
                      SizedBox(height: 28.h),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final gap = 8.w;
                          // 4 ячейки, шире чем 6 при той же ширине экрана.
                          // Visual: ~64×64px на Pixel 9, в Figma-стиле SimbA.
                          final cellW = (constraints.maxWidth - (_codeLength - 1) * gap) / _codeLength;
                          final cellSize = cellW.clamp(48.0, 72.0);
                          return Center(
                            child: SizedBox(
                              width: cellSize * _codeLength + gap * (_codeLength - 1),
                              child: MaterialPinField(
                                key: _pinKey,
                                length: _codeLength,
                                autoFocus: true,
                                keyboardType: TextInputType.number,
                                theme: MaterialPinTheme(
                                  shape: MaterialPinShape.outlined,
                                  cellSize: Size(cellSize, 64.h),
                                  spacing: gap,
                                  borderRadius: BorderRadius.circular(12.r),
                                  borderWidth: 1,
                                  focusedBorderWidth: 1.5,
                                  entryAnimation: MaterialPinAnimation.fade,
                                  borderColor: borderColor,
                                  focusedBorderColor: activeBorderColor,
                                  filledBorderColor: activeBorderColor,
                                  fillColor: AppColors.surface,
                                  focusedFillColor: AppColors.surface,
                                  filledFillColor: AppColors.surface,
                                  textStyle: AppText.h2().copyWith(fontWeight: FontWeight.w400),
                                  cursorColor: AppColors.primary,
                                ),
                                onChanged: (v) {
                                  setState(() => _code = v);
                                  // Автосабмит при наборе всех 4 цифр.
                                  if (v.length == _codeLength && !_isVerifying) {
                                    _onNext();
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: 24.h),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _hasError
                            ? Text(
                                _errorText ?? 'Неверный код',
                                key: const ValueKey('error'),
                                textAlign: TextAlign.center,
                                style: _statusTextStyle,
                              )
                            : _showResent
                                ? Text(
                                    'Новый код отправлен',
                                    key: const ValueKey('resent'),
                                    textAlign: TextAlign.center,
                                    style: _statusTextStyle.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                  )
                                : const SizedBox.shrink(key: ValueKey('none')),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _seconds > 0
                    ? Row(
                        key: const ValueKey('timer'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Отправить код повторно',
                            style: AppText.body(
                              color: AppColors.textSecondary,
                              weight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(width: 16.w),
                          Container(
                            padding: EdgeInsets.all(8.r),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Text(
                              _timerText,
                              style: AppText.body(color: AppColors.primary),
                            ),
                          ),
                        ],
                      )
                    : SecondaryButton(
                        key: const ValueKey('resend'),
                        label: _isResending
                            ? 'Отправляем…'
                            : 'Отправить код повторно',
                        height: 43.h,
                        onPressed: _isResending ? null : _onResend,
                      ),
              ),
              SizedBox(height: 16.h),
              _SubmitButton(
                isBusy: _isVerifying,
                onPressed: canContinue ? _onNext : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.isBusy, required this.onPressed});

  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!isBusy) {
      return PrimaryButton(label: 'Далее', onPressed: onPressed);
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
