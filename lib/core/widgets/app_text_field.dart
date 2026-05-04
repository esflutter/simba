import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.obscure = false,
    this.suffix,
    this.inputFormatters,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.hint,
    this.textInputAction,
    this.onSubmitted,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? minLines;
  final bool obscure;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focus;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _ctrl = widget.controller ?? TextEditingController();
    _focus.addListener(() => setState(() {}));
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasFocus = _focus.hasFocus;
    final hasText = _ctrl.text.isNotEmpty;
    final showFloating = hasFocus || hasText;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Stack(
              children: [
                AnimatedAlign(
                  alignment: showFloating ? Alignment.topLeft : Alignment.centerLeft,
                  duration: const Duration(milliseconds: 150),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: showFloating
                        ? AppText.caption(
                            color: hasFocus ? AppColors.primary : AppColors.textSecondary,
                          )
                        : AppText.bodyLarge(color: AppColors.textTertiary),
                    child: Text(widget.label),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: showFloating ? 18.h : 0),
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    autofocus: widget.autofocus,
                    enabled: widget.enabled,
                    keyboardType: widget.keyboardType,
                    obscureText: widget.obscure,
                    maxLines: widget.maxLines,
                    minLines: widget.minLines,
                    inputFormatters: widget.inputFormatters,
                    onChanged: widget.onChanged,
                    textInputAction: widget.textInputAction,
                    onSubmitted: widget.onSubmitted,
                    cursorColor: AppColors.primary,
                    style: AppText.bodyLarge(),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: showFloating ? widget.hint : null,
                      hintStyle: AppText.bodyLarge(color: AppColors.textTertiary),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.suffix != null) ...[
            SizedBox(width: 8.w),
            widget.suffix!,
          ],
        ],
      ),
    );
  }
}
