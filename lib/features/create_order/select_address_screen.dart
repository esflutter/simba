import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import 'order_draft.dart';

const _mockAddresses = <String>[
  'Адрес 1',
  'Адрес 2',
  'Адрес 3',
  'Адрес 4',
  'Адрес 5',
];

class SelectAddressScreen extends ConsumerStatefulWidget {
  const SelectAddressScreen({super.key});

  @override
  ConsumerState<SelectAddressScreen> createState() => _SelectAddressScreenState();
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focus.requestFocus(),
      child: Container(
        height: 56.h,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
        child: Row(
          children: [
            Icon(
              IconsaxPlusLinear.search_normal_1,
              size: 24.r,
              color: Colors.black,
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.controller,
                builder: (_, value, _) {
                  final hasFocus = _focus.hasFocus;
                  final hasText = value.text.isNotEmpty;
                  if (!hasFocus && hasText) {
                    return Text(
                      value.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(color: AppColors.textPrimary)
                          .copyWith(height: 1.50),
                    );
                  }
                  return TextField(
                    focusNode: _focus,
                    controller: widget.controller,
                    onChanged: widget.onChanged,
                    cursorColor: AppColors.primary,
                    style: AppText.body(color: AppColors.textPrimary)
                        .copyWith(height: 1.50),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  );
                },
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (_, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(left: 16.w),
                  child: GestureDetector(
                    onTap: widget.onClear,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      IconsaxPlusLinear.close_circle,
                      size: 24.r,
                      color: AppColors.primary,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectAddressScreenState extends ConsumerState<SelectAddressScreen> {
  late final TextEditingController _ctrl;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: 'Местоположение пользователя');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: Column(
              children: [
                SizedBox(height: 4.h),
                Center(
                  child: Container(
                    width: 36.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: const Color(0x4C3C3C43),
                      borderRadius: BorderRadius.circular(2.5.r),
                    ),
                  ),
                ),
                SizedBox(height: 4.h),
                SizedBox(
                  height: 36.h,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: Text(
                          'Адрес',
                          style: AppText.bodyLarge(weight: FontWeight.w600).copyWith(
                            letterSpacing: -0.43,
                            height: 1.29,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.w),
                          child: const AppBackButton(),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 4.h),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
            child: _SearchField(
              controller: _ctrl,
              onChanged: (v) => setState(() => _showSuggestions = v.isNotEmpty),
              onClear: () => setState(() {
                _ctrl.clear();
                _showSuggestions = false;
              }),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 16.h,
                  bottom: 0,
                  child: ClipRect(
                    child: Image.asset(
                      'assets/images/map_mock.webp',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  right: 8.w,
                  top: 16.h,
                  bottom: 0,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          child: Image.asset(
                            'assets/images/map_zoom.webp',
                            width: 52.r,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          child: Image.asset(
                            'assets/images/map_locate.webp',
                            width: 52.r,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showSuggestions)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 8.h,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16.r),
                        child: Material(
                          color: AppColors.surface,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < _mockAddresses.length; i++)
                                InkWell(
                                  onTap: () => setState(() {
                                    _ctrl.text = _mockAddresses[i];
                                    _showSuggestions = false;
                                    FocusScope.of(context).unfocus();
                                  }),
                                  child: SizedBox(
                                    height: 56.h,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          _mockAddresses[i],
                                          style: AppText.bodyLarge(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.all(16.w),
                      child: PrimaryButton(
                        label: 'Выбрать',
                        height: 50.h,
                        onPressed: () {
                          final city = ref.read(appControllerProvider).selectedCity;
                          final value = _ctrl.text.trim();
                          ref.read(orderDraftProvider.notifier).update(
                                location: city.center,
                                address: value.isEmpty ? 'Точка на карте' : value,
                              );
                          context.pop();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
