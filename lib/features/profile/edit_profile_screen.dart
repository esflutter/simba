import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _name;
  late TextEditingController _phone;
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    final u = ref.read(appControllerProvider).user!;
    _name = TextEditingController(text: u.name);
    _phone = TextEditingController(text: u.phone);
    _photoPath = u.photoPath;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
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
                      SizedBox(height: 8.h),
                      Text('Редактировать', style: AppText.h2()),
                      SizedBox(height: 24.h),
                      Center(
                        child: GestureDetector(
                          onTap: _pickPhoto,
                          child: Stack(
                            children: [
                              Container(
                                width: 130.r,
                                height: 130.r,
                                decoration: const BoxDecoration(
                                  color: AppColors.surface,
                                  shape: BoxShape.circle,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _photoPath != null
                                    ? Image.file(File(_photoPath!), fit: BoxFit.cover)
                                    : Icon(IconsaxPlusLinear.user, size: 76.r, color: AppColors.primary),
                              ),
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  width: 36.r,
                                  height: 36.r,
                                  decoration:
                                      const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                  child: Icon(IconsaxPlusLinear.camera, size: 20.r, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 24.h),
                      AppTextField(label: 'Имя / Nickname', controller: _name, onChanged: (_) => setState(() {})),
                      SizedBox(height: 12.h),
                      AppTextField(label: 'Телефон', controller: _phone, enabled: false),
                      SizedBox(height: 24.h),
                    ],
                  ),
                ),
              ),
              PrimaryButton(
                label: 'Сохранить',
                onPressed: () {
                  ref.read(appControllerProvider.notifier).completeProfile(
                        name: _name.text,
                        photoPath: _photoPath,
                      );
                  context.pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
