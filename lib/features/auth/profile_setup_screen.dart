import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _ctrl = TextEditingController();
  String? _photoPath;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final f = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (f != null) setState(() => _photoPath = f.path);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _ctrl.text.trim().isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 16.h),
                      Center(child: Text('Регистрация', style: AppText.h2())),
                      SizedBox(height: 8.h),
                      Center(
                        child: Text('Заполните данные о себе',
                            style: AppText.body(color: AppColors.textSecondary)),
                      ),
                      SizedBox(height: 24.h),
                      Center(
                        child: GestureDetector(
                          onTap: _pickPhoto,
                          child: _photoPath != null
                              ? Container(
                                  width: 100.r,
                                  height: 100.r,
                                  decoration: const BoxDecoration(shape: BoxShape.circle),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.file(File(_photoPath!), fit: BoxFit.cover),
                                )
                              : Image.asset(
                                  'assets/images/avatar_photo.webp',
                                  width: 100.r,
                                  height: 100.r,
                                ),
                        ),
                      ),
                      SizedBox(height: 24.h),
                      AppTextField(
                        label: 'Имя / Никнейм',
                        controller: _ctrl,
                        onChanged: (_) => setState(() {}),
                      ),
                      SizedBox(height: 24.h),
                    ],
                  ),
                ),
              ),
              PrimaryButton(
                label: 'Далее',
                onPressed: canContinue
                    ? () {
                        ref.read(appControllerProvider.notifier).completeProfile(
                              name: _ctrl.text,
                              photoPath: _photoPath,
                            );
                        context.go('/auth/role');
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
