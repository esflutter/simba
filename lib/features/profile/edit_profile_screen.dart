import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../data/mock/app_state.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

const _educationNotSpecified = 'Не указано';
const _educationOptions = [
  'Среднее общее',
  'Среднее профессиональное',
  'Неполное высшее',
  'Высшее',
  _educationNotSpecified,
];

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _name;
  String _education = '';
  String? _photoPath;
  bool _hasTools = false;
  bool _hasTransport = false;

  @override
  void initState() {
    super.initState();
    final u = ref.read(appControllerProvider).user!;
    _name = TextEditingController(text: u.name);
    _education = u.education;
    _photoPath = u.photoPath;
    _hasTools = u.hasTools;
    _hasTransport = u.hasTransport;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final f = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (f != null) setState(() => _photoPath = f.path);
    } catch (_) {}
  }

  bool _educationOpen = false;

  void _toggleEducation() {
    setState(() => _educationOpen = !_educationOpen);
  }

  void _pickEducationOption(String option) {
    setState(() {
      _education = option;
      _educationOpen = false;
    });
  }

  bool get _canSave {
    final user = ref.read(appControllerProvider).user;
    if (user == null) return false;
    final nameChanged = _name.text.trim() != user.name && _name.text.trim().isNotEmpty;
    final eduChanged = _education != user.education;
    final photoChanged = _photoPath != user.photoPath;
    final toolsChanged = _hasTools != user.hasTools;
    final transportChanged = _hasTransport != user.hasTransport;
    return nameChanged ||
        eduChanged ||
        photoChanged ||
        toolsChanged ||
        transportChanged;
  }

  void _save() {
    ref.read(appControllerProvider.notifier).completeProfile(
          name: _name.text,
          photoPath: _photoPath,
          education: _education,
          hasTools: _hasTools,
          hasTransport: _hasTransport,
        );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Header (white, with back + centered title)
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 44.h,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        child: const AppBackButton(),
                      ),
                    ),
                    Center(
                      child: Text(
                        'Редактирование',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w600,
                          height: 1.29,
                          letterSpacing: -0.43,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 24.h, 16.w, 16.h),
              child: Column(
                children: [
                  // Avatar 100×100 (камера уже встроена в webp)
                  Center(
                    child: GestureDetector(
                      onTap: _pickPhoto,
                      child: _photoPath != null
                          ? Container(
                              width: 100.r,
                              height: 100.r,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.file(File(_photoPath!), fit: BoxFit.cover),
                            )
                          : Image.asset(
                              'assets/images/avatar_default.webp',
                              width: 100.r,
                              height: 100.r,
                              fit: BoxFit.contain,
                            ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  AppTextField(
                    label: 'Имя / Никнейм',
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                  ),
                  SizedBox(height: 16.h),
                  _EducationField(
                    value: _education,
                    expanded: _educationOpen,
                    onTap: _toggleEducation,
                    onPick: _pickEducationOption,
                  ),
                  SizedBox(height: 16.h),
                  _CheckRow(
                    label: 'Наличие инструмента',
                    value: _hasTools,
                    onChanged: (v) => setState(() => _hasTools = v),
                  ),
                  SizedBox(height: 16.h),
                  _CheckRow(
                    label: 'Наличие транспорта',
                    value: _hasTransport,
                    onChanged: (v) => setState(() => _hasTransport = v),
                  ),
                ],
              ),
            ),
          ),
          // Save button
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              child: _SaveButton(enabled: _canSave, onTap: _save),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: () => onChanged(!value),
        child: SizedBox(
          height: 56.h,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                _CheckBox(value: value),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w400,
                      height: 1.50,
                      letterSpacing: -0.31,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.value});
  final bool value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22.r,
      height: 22.r,
      decoration: BoxDecoration(
        color: value ? AppColors.primary : Colors.transparent,
        border: Border.all(
          color: value ? AppColors.primary : AppColors.textTertiary,
          width: 2.0,
        ),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: value
          ? Icon(
              Icons.check_rounded,
              size: 18.r,
              color: Colors.white,
              shadows: const [Shadow(color: Colors.white, blurRadius: 2)],
            )
          : null,
    );
  }
}

class _EducationField extends StatelessWidget {
  const _EducationField({
    required this.value,
    required this.expanded,
    required this.onTap,
    required this.onPick,
  });
  final String value;
  final bool expanded;
  final VoidCallback onTap;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final hasValue = value.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            child: Container(
              constraints: BoxConstraints(minHeight: 56.h),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Образование',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.60),
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w400,
                            height: 1.33,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          hasValue ? value : 'Выберите уровень',
                          style: TextStyle(
                            color: hasValue
                                ? Colors.black
                                : Colors.black.withValues(alpha: 0.30),
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w400,
                            height: 1.31,
                            letterSpacing: -0.31,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 24.r,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(height: 1, color: AppColors.divider),
                      for (final option in _educationOptions)
                        InkWell(
                          onTap: () => onPick(option),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 12.h,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option,
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 16.sp,
                                      fontWeight: option == value
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      height: 1.31,
                                      letterSpacing: -0.31,
                                    ),
                                  ),
                                ),
                                if (option == value)
                                  Icon(
                                    Icons.check_rounded,
                                    color: AppColors.primary,
                                    size: 20.r,
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.primary : const Color(0x1E767680),
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: double.infinity,
          height: 50.h,
          child: Center(
            child: Text(
              'Сохранить',
              style: TextStyle(
                color: enabled ? Colors.white : const Color(0x4C3C3C43),
                fontSize: 17.sp,
                fontWeight: enabled ? FontWeight.w600 : FontWeight.w400,
                height: 1.29,
                letterSpacing: -0.43,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
