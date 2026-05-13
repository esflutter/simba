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

  String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  bool get _valid {
    final d = _digits(_ctrl.text);
    return d.length == 11 && _agreed;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onNext() async {
    final phone = _ctrl.text;
    final auth = ref.read(authRepositoryProvider);
    // Если бэкенд подключён — отправляем OTP; иначе сразу переходим
    // на экран кода с мок-проверкой.
    if (auth.isLive) {
      final ok = await auth.sendOtp(phone);
      if (!mounted) return;
      if (!ok) {
        AppToast.show(context, 'Не удалось отправить SMS');
        return;
      }
    }
    if (!mounted) return;
    context.push('/auth/sms?phone=${Uri.encodeComponent(phone)}');
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
                    onTap: () => setState(() => _agreed = !_agreed),
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
              SizedBox(height: 18.h),
              PrimaryButton(
                label: 'Далее',
                onPressed: _valid ? _onNext : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

