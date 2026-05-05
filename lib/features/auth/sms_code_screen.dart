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
  String _code = '';
  Timer? _timer;
  int _seconds = 20;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _seconds = 20);
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
    super.dispose();
  }

  String get _timerText {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _code.length == 6;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppBackButton(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 24.h),
                      Center(
                        child: Icon(IconsaxPlusLinear.sms_tracking, size: 80.r, color: AppColors.primary),
                      ),
                      SizedBox(height: 24.h),
                      Center(child: Text('Отправили код', style: AppText.h2())),
                      SizedBox(height: 8.h),
                      Text(
                        'Мы отправили SMS с кодом активации на ваш телефон ${widget.phone}',
                        textAlign: TextAlign.center,
                        style: AppText.body(color: AppColors.textSecondary),
                      ),
                      SizedBox(height: 24.h),
                      MaterialPinField(
                        length: 6,
                        autoFocus: true,
                        keyboardType: TextInputType.number,
                        theme: MaterialPinTheme(
                          shape: MaterialPinShape.outlined,
                          cellSize: Size(48.w, 56.h),
                          borderRadius: BorderRadius.circular(12.r),
                          borderWidth: 1.4,
                          focusedBorderWidth: 1.4,
                          entryAnimation: MaterialPinAnimation.fade,
                          borderColor: AppColors.divider,
                          focusedBorderColor: AppColors.primary,
                          filledBorderColor: AppColors.primary,
                          fillColor: AppColors.surface,
                          focusedFillColor: AppColors.surface,
                          filledFillColor: AppColors.surface,
                          cursorColor: AppColors.primary,
                        ),
                        onChanged: (v) => setState(() => _code = v),
                      ),
                      SizedBox(height: 16.h),
                      Row(
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            onPressed: _seconds == 0 ? _startTimer : null,
                            child: Text(
                              'Отправить код повторно',
                              style: AppText.body(
                                color: _seconds == 0 ? AppColors.primary : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (_seconds > 0)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(_timerText, style: AppText.body(color: AppColors.primary, weight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              PrimaryButton(
                label: 'Далее',
                onPressed: canContinue
                    ? () {
                        ref.read(appControllerProvider.notifier).completeAuth(phone: widget.phone);
                        context.go('/auth/profile');
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
