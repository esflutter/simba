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
import '../../core/utils/plural_ru.dart' show formatRetryAfter, pluralMin, pluralSec;
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
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

class _SmsCodeScreenState extends ConsumerState<SmsCodeScreen>
    with WidgetsBindingObserver {
  // Длина кода фиксированно 4. См. документацию SMS Aero Mobile Authorization:
  // `code must be 4 numbers` — серверная сторона не принимает другую длину.
  static const int _codeLength = 4;
  static const int _timerSeconds = 60;
  // Раньше тут был кастомный красный 0xFFFF5F57, не соответствующий
  // палитре. Используем общий токен ошибки + полупрозрачный его вариант
  // для рамки подсветки.
  static const _errorColor = AppColors.error;
  static final _errorBorderColor = AppColors.error.withValues(alpha: 0.50);

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

  /// Абсолютный момент, когда можно резендить. Храним именно дату — Timer
  /// в background-режиме на iOS приостанавливается, а на Android может
  /// тикать неравномерно; пересчёт от now-времени единственный надёжный
  /// способ показать остаток без скачков после возврата из бэкграунда.
  DateTime? _resendAvailableAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionId = widget.sessionId;
    _startTimer(resetPin: false);
  }

  void _startTimer({bool resetPin = true}) {
    _timer?.cancel();
    final target = DateTime.now().add(const Duration(seconds: _timerSeconds));
    setState(() {
      _resendAvailableAt = target;
      _seconds = _timerSeconds;
      _code = '';
      _hasError = false;
      _errorText = null;
      if (resetPin) {
        _pinKey = UniqueKey();
        _showResent = true;
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) => _tick());
  }

  /// Один шаг таймера. Источник правды — `_resendAvailableAt`; здесь только
  /// перевычисляем остаток. Это позволяет правильно вести себя после
  /// возврата из бэкграунда (см. didChangeAppLifecycleState).
  void _tick() {
    final target = _resendAvailableAt;
    if (target == null) {
      _timer?.cancel();
      return;
    }
    final remaining = target.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      _timer?.cancel();
      if (mounted) setState(() => _seconds = 0);
    } else {
      if (mounted && _seconds != remaining) {
        setState(() => _seconds = remaining);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // На resume пересчитываем остаток от абсолютной точки. Если время
      // уже истекло — отменяем таймер и обновляем UI на «можно резендить».
      final target = _resendAvailableAt;
      if (target == null) return;
      final remaining = target.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        _timer?.cancel();
        if (mounted) setState(() => _seconds = 0);
      } else {
        if (mounted) setState(() => _seconds = remaining);
        // Если периодический таймер был приостановлен системой (iOS), сам
        // перезапустится с тика выше — но на всякий случай гарантируем,
        // что он жив.
        _timer ??=
            Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      return 'Слишком много попыток. Попробуйте через $m ${pluralMin(m)}.';
    }
    final s = remaining.inSeconds > 0 ? remaining.inSeconds : 0;
    return 'Слишком много попыток. Попробуйте через $s ${pluralSec(s)}.';
  }

  String _resendErrorMessage(String? code, int? retryAfter) {
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
    if (_isVerifying) return;
    setState(() => _isVerifying = true);
    try {
      final auth = ref.read(authRepositoryProvider);
      final result = await auth.verifyOtpDetailed(
        sessionId: _sessionId,
        phone: widget.phone,
        code: _code,
      );
      // ВАЖНО: verifyOtpDetailed уже залогинил юзера через _consumeAuthEnvelope
      // (PB authStore + AppController.state.user). Если экран unmounted между
      // запросом и ответом — мы не можем просто return, иначе юзер залогинен,
      // но застрял на phone-экране. Используем routerProvider напрямую.
      if (!mounted) {
        if (result.ok) {
          ref
              .read(routerProvider)
              .go(postAuthRoute(ref, isNewUser: result.isNewUser));
        }
        return;
      }
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
      // Существующий юзер логинится снова — регистрация на этом
      // устройстве считается завершённой. Помечаем онбординг
      // просмотренным заранее, чтобы дальше он не появлялся даже
      // при logout. Для нового юзера флаг ставится в конце role-picker
      // (там завершение регистрации).
      if (!result.isNewUser) {
        await ref.read(appControllerProvider.notifier).markOnboardingSeen();
        if (!mounted) return;
      }
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

  /// Подтверждение случайного «назад» при наполовину введённом коде.
  /// За каждый OTP реально платится поставщику SMS — нельзя позволить
  /// случайному жесту/тапу системной кнопки стереть код и форсировать
  /// повторный resend.
  Future<bool> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Прервать ввод кода?'),
        content: const Text(
          'Введённые цифры удалятся. Для новой попытки придётся ждать '
          'таймер и запрашивать SMS заново.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _code.length == _codeLength && !_isVerifying;
    final borderColor = _hasError ? _errorBorderColor : AppColors.divider;
    final activeBorderColor = _hasError ? _errorBorderColor : AppColors.primary;

    return PopScope(
      // Блокируем pop только при незавершённой попытке: введённые цифры
      // или активная верификация. Пустое поле — выходим без вопроса.
      canPop: _code.isEmpty && !_isVerifying,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!mounted) return;
        final shouldLeave = await _confirmLeave();
        if (!shouldLeave) return;
        if (!context.mounted) return;
        if (context.canPop()) context.pop();
      },
      child: Scaffold(
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
                          // 4 ячейки, делаем СТРОГО квадратные. Когда было
                          // 6 ячеек, пропорции диктовали свою ширину; для 4-х
                          // ширина по умолчанию вылазит слишком большой и
                          // ячейки выглядят растянутыми. Поэтому жёстко
                          // ограничиваем максимум и приравниваем высоту.
                          final cellW = (constraints.maxWidth - (_codeLength - 1) * gap) / _codeLength;
                          final cellSize = cellW.clamp(48.0, 56.0);
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
                                  cellSize: Size(cellSize, cellSize),
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
                                  // Figma даёт 28sp для 6-ячеек дизайна.
                                  // У нас 4 ячейки, ячейка пропорционально
                                  // шире (~64-72px), поэтому шрифт увеличен
                                  // до 32sp — иначе цифра выглядит «маленькой»
                                  // в просторной ячейке. Inter / w400.
                                  // height не задаём: с 0.79 цифра прижималась
                                  // к верху ячейки (Flutter применяет height
                                  // к bounding-box символа, baseline смещается).
                                  textStyle: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontFamily: 'Inter',
                                    fontSize: 32.sp,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  cursorColor: AppColors.primary,
                                ),
                                onChanged: (v) {
                                  setState(() => _code = v);
                                  // Автосабмита нет: пользователь сам жмёт
                                  // «Далее». Кнопка активируется, когда
                                  // _code.length == _codeLength.
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
                            // Figma: 16/Inter/w500/1.38. В неактивном
                            // состоянии (бежит таймер) — серый, активном —
                            // primary; геометрия одинаковая в обоих.
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontFamily: 'Inter',
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w500,
                              height: 1.38,
                            ),
                          ),
                          SizedBox(width: 16.w),
                          Container(
                            padding: EdgeInsets.all(8.r),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
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
                        // Figma: 16/Inter/w500/1.38/#1369CD — стандартный
                        // AppText.button (17/w400/1.2) не совпадал.
                        textStyle: TextStyle(
                          color: AppColors.primary,
                          fontFamily: 'Inter',
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w500,
                          height: 1.38,
                        ),
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
