import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/remote/auth_repository.dart';

/// Экран ожидания SIM-PUSH (Mobile ID). Юзер ввёл номер на [PhoneScreen],
/// бэк через SMS Aero инициировал push-уведомление от оператора связи.
/// Здесь мы поллим статус сессии каждые [_pollInterval] секунд:
///
/// - `verified` — Mobile ID push сработал. Бэк уже сделал siteverify
///   и вернул PB JWT в ответе /status; авторизация завершена → редирект.
/// - `otp_required` — SIM-PUSH не доступен (нет Mobile ID на тарифе / не
///   доставлен), SMS Aero отправил 4-значный код в SMS → переход на
///   [SmsCodeScreen] с тем же sessionId.
/// - `rejected` — юзер нажал «Отмена» в SIM-PUSH диалоге → возврат.
/// - timeout/expired — возврат на ввод номера.
///
/// Maximum [_maxWait] секунд опроса — если за это время ничего не произошло,
/// тоже скидываем юзера на форму ввода кода как fallback.
class SimPushWaitingScreen extends ConsumerStatefulWidget {
  const SimPushWaitingScreen({
    super.key,
    required this.sessionId,
    required this.phone,
  });

  final String sessionId;
  final String phone;

  @override
  ConsumerState<SimPushWaitingScreen> createState() =>
      _SimPushWaitingScreenState();
}

class _SimPushWaitingScreenState extends ConsumerState<SimPushWaitingScreen>
    with SingleTickerProviderStateMixin {
  // Полл-интервал: 1.5с — компромисс между отзывчивостью и нагрузкой на бэк
  // (каждый GET status это HTTP-запрос в midsdk.smsaero.ru).
  static const Duration _pollInterval = Duration(milliseconds: 1500);
  // Максимум 60 секунд ожидания SIM-PUSH. Дольше нет смысла — оператор уже
  // должен был ответить или fallback на SMS должен сработать.
  static const Duration _maxWait = Duration(seconds: 60);

  Timer? _pollTimer;
  Timer? _maxWaitTimer;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Сразу первый poll, дальше по таймеру.
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
    _maxWaitTimer = Timer(_maxWait, _onMaxWaitElapsed);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _maxWaitTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_completed || !mounted) return;
    final auth = ref.read(authRepositoryProvider);
    final result = await auth.pollMidStatus(widget.sessionId);
    if (_completed || !mounted) return;
    if (result.ok && result.status == 'verified') {
      _stop();
      context.go(postAuthRoute(ref, isNewUser: result.isNewUser));
      return;
    }
    if (result.ok && result.status == 'otp_required') {
      _stop();
      // Переходим на форму ввода 4-значного кода. Replace, чтобы при
      // нажатии «назад» юзер не возвращался на этот экран ожидания.
      context.pushReplacement(
        '/auth/sms?session_id=${Uri.encodeComponent(widget.sessionId)}'
        '&phone=${Uri.encodeComponent(widget.phone)}',
      );
      return;
    }
    if (result.ok && result.status == 'rejected') {
      _stop();
      AppToast.show(context, 'Подтверждение отклонено');
      context.pop();
      return;
    }
    if (!result.ok) {
      final code = result.errorCode ?? 'unknown';
      if (code == 'session_expired' ||
          code == 'session_consumed' ||
          code == 'session_not_found') {
        _stop();
        AppToast.show(context, 'Сессия истекла, попробуйте ещё раз');
        context.pop();
        return;
      }
      // network / rate_limited / unknown — продолжаем поллить (transient).
    }
    // Прочие статусы (pending) — ждём следующего интервала.
  }

  void _stop() {
    _completed = true;
    _pollTimer?.cancel();
    _maxWaitTimer?.cancel();
  }

  void _onMaxWaitElapsed() {
    if (_completed || !mounted) return;
    _stop();
    // Fallback: за 60с ничего не произошло. Возможно, SIM-PUSH не дошёл и
    // юзер ждёт SMS. Открываем форму ввода кода — он сам введёт OTP,
    // если SMS придёт (или нажмёт «Назад»).
    context.pushReplacement(
      '/auth/sms?session_id=${Uri.encodeComponent(widget.sessionId)}'
      '&phone=${Uri.encodeComponent(widget.phone)}',
    );
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
              Align(
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: Offset(-8.r, 0),
                  child: const AppBackButton(),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _pulse,
                        child: Container(
                          width: 120.r,
                          height: 120.r,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withValues(alpha: 0.10),
                          ),
                          child: Icon(
                            IconsaxPlusLinear.mobile,
                            size: 56.r,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      SizedBox(height: 32.h),
                      Text(
                        'Подтвердите вход',
                        style: AppText.h2().copyWith(letterSpacing: -0.10),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 9.h),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        child: Text(
                          'На ${widget.phone} придёт системное уведомление от оператора связи. Нажмите «Подтвердить» — войдём автоматически. Если уведомление не пришло, через несколько секунд предложим ввести код из SMS.',
                          textAlign: TextAlign.center,
                          style: AppText.body().copyWith(
                            color: Colors.black.withValues(alpha: 0.60),
                            height: 1.38,
                          ),
                        ),
                      ),
                      SizedBox(height: 28.h),
                      SizedBox(
                        width: 24.r,
                        height: 24.r,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary.withValues(alpha: 0.6),
                        ),
                      ),
                      SizedBox(height: 16.h),
                    ],
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
