import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.obscure = false,
    this.suffix,
    this.inputFormatters,
    this.onChanged,
    this.onTap,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction,
    this.onSubmitted,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
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
  final VoidCallback? onTap;
  final bool autofocus;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;
  final TextCapitalization textCapitalization;

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
    const showFloating = true;
    final labelColor = hasFocus ? AppColors.primary : const Color(0x99000000);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _focus.requestFocus();
        widget.onTap?.call();
      },
      child: Container(
        constraints: BoxConstraints(minHeight: 56.h),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16.r),
        ),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
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
                        ? AppText.caption(color: labelColor)
                        : AppText.bodyLarge(color: labelColor),
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
                    maxLength: widget.maxLength,
                    textCapitalization: widget.textCapitalization,
                    inputFormatters: widget.inputFormatters,
                    onChanged: widget.onChanged,
                    onTap: widget.onTap,
                    textInputAction: widget.textInputAction,
                    onSubmitted: widget.onSubmitted,
                    cursorColor: AppColors.primary,
                    style: AppText.bodyLarge(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                      hintText: widget.hint,
                      hintStyle: AppText.body(color: Colors.black.withValues(alpha: 0.30))
                          .copyWith(height: 1.31, letterSpacing: -0.31),
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
      ),
    );
  }
}
