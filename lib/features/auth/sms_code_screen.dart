import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';

class SmsCodeScreen extends ConsumerStatefulWidget {
  const SmsCodeScreen({super.key, required this.phone});
  final String phone;

  @override
  ConsumerState<SmsCodeScreen> createState() => _SmsCodeScreenState();
}

class _SmsCodeScreenState extends ConsumerState<SmsCodeScreen> {
  Key _pinKey = UniqueKey();
  String _code = '';
  bool _hasError = false;
  bool _showResent = false;
  Timer? _timer;
  Timer? _errorTimer;
  int _seconds = 20;

  static const _timerSeconds = 59;
  static const _errorColor = Color(0xFFFF5F57);
  static const _errorBorderColor = Color(0x7FFF383C);

  @override
  void initState() {
    super.initState();
    _startTimer(resetPin: false);
  }

  void _startTimer({bool resetPin = true}) {
    _timer?.cancel();
    setState(() {
      _seconds = _timerSeconds;
      _code = '';
      _hasError = false;
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

  void _onNext() {
    if (_code == '000000') {
      _errorTimer?.cancel();
      setState(() {
        _code = '';
        _hasError = true;
        _showResent = false;
        _pinKey = UniqueKey();
      });
      _errorTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _hasError = false);
      });
      return;
    }
    ref.read(appControllerProvider.notifier).completeAuth(phone: widget.phone);
    context.go('/auth/profile');
  }

  static TextStyle get _statusTextStyle => AppText.bodySmall(
        color: _errorColor,
      ).copyWith(letterSpacing: 0.25, height: 1.43);

  @override
  Widget build(BuildContext context) {
    final canContinue = _code.length == 6;
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
                        'Отправили код',
                        style: AppText.h2().copyWith(letterSpacing: -0.10),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'Мы отправили SMS с кодом активации на ваш телефон ${widget.phone}',
                        textAlign: TextAlign.center,
                        style: AppText.body().copyWith(
                          color: Colors.black.withValues(alpha: 0.60),
                          height: 1.38,
                        ),
                      ),
                      SizedBox(height: 28.h),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final gap = 4.w;
                          final cellW = (constraints.maxWidth - 5 * gap) / 6;
                          return MaterialPinField(
                            key: _pinKey,
                            length: 6,
                            autoFocus: true,
                            keyboardType: TextInputType.number,
                            theme: MaterialPinTheme(
                              shape: MaterialPinShape.outlined,
                              cellSize: Size(cellW, 56.h),
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
                            onChanged: (v) => setState(() => _code = v),
                          );
                        },
                      ),
                      SizedBox(height: 24.h),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _hasError
                            ? Text(
                                'Неверный код',
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
                        label: 'Отправить код повторно',
                        height: 43.h,
                        onPressed: _startTimer,
                      ),
              ),
              SizedBox(height: 16.h),
              PrimaryButton(
                label: 'Далее',
                onPressed: canContinue ? _onNext : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
