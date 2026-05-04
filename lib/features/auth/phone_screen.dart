import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/primary_button.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _ctrl = TextEditingController();
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

  @override
  Widget build(BuildContext context) {
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
                        child: Icon(IconsaxPlusLinear.call, size: 80.r, color: AppColors.primary),
                      ),
                      SizedBox(height: 24.h),
                      Center(child: Text('Введите номер телефона', style: AppText.h2(), textAlign: TextAlign.center)),
                      SizedBox(height: 8.h),
                      Text(
                        'На указанный номер отправим SMS с кодом',
                        textAlign: TextAlign.center,
                        style: AppText.body(color: AppColors.textSecondary),
                      ),
                      SizedBox(height: 24.h),
                      AppTextField(
                        label: 'Номер телефона',
                        controller: _ctrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_RuPhoneFormatter()],
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: Row(
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
                            width: 1.6,
                          ),
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: _agreed
                            ? Icon(Icons.check, size: 16.r, color: Colors.white)
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
                              style: AppText.caption(color: AppColors.primary),
                            ),
                            const TextSpan(text: ' и '),
                            TextSpan(
                              text: 'Политикой конфиденциальности',
                              style: AppText.caption(color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              PrimaryButton(
                label: 'Далее',
                onPressed: _valid
                    ? () => context.push('/auth/sms?phone=${Uri.encodeComponent(_ctrl.text)}')
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('8')) d = '7${d.substring(1)}';
    if (!d.startsWith('7') && d.isNotEmpty) d = '7$d';
    if (d.length > 11) d = d.substring(0, 11);
    final buf = StringBuffer();
    if (d.isNotEmpty) buf.write('+7');
    if (d.length > 1) buf.write(' (${d.substring(1, d.length.clamp(1, 4))}');
    if (d.length >= 4) buf.write(')');
    if (d.length >= 5) buf.write(' ${d.substring(4, d.length.clamp(4, 7))}');
    if (d.length >= 8) buf.write('-${d.substring(7, d.length.clamp(7, 9))}');
    if (d.length >= 10) buf.write('-${d.substring(9, d.length.clamp(9, 11))}');
    final t = buf.toString();
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}
