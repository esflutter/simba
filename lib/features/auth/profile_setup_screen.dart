import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/remote/pocketbase_client.dart';

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
                          child: SizedBox(
                            width: 100.r,
                            height: 100.r,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 100.r,
                                  height: 100.r,
                                  decoration: const BoxDecoration(
                                    color: AppColors.surfaceVariant,
                                    shape: BoxShape.circle,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _photoPath != null
                                      ? Image.file(
                                          File(_photoPath!),
                                          fit: BoxFit.cover,
                                        )
                                      : Image.asset(
                                          'assets/images/avatar_default.webp',
                                          fit: BoxFit.contain,
                                        ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Image.asset(
                                    'assets/images/icon_camera.webp',
                                    width: 24.r,
                                    height: 24.r,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 24.h),
                      AppTextField(
                        label: 'Имя / Никнейм',
                        controller: _ctrl,
                        onChanged: (_) => setState(() {}),
                        maxLength: 50,
                        textCapitalization: TextCapitalization.words,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              PrimaryButton(
                label: 'Далее',
                onPressed: canContinue
                    ? () async {
                        final name = _ctrl.text.trim();
                        final photoPath = _photoPath;
                        // Локально (моки и UI) — сразу.
                        ref.read(appControllerProvider.notifier).completeProfile(
                              name: name,
                              photoPath: photoPath,
                            );
                        // Отправляем на сервер, если PB подключён и юзер есть.
                        // Ошибка не блокирует переход — моки уже сработали.
                        try {
                          final pb = ref.read(pocketbaseProvider);
                          final record = pb?.authStore.record;
                          if (pb != null && record != null) {
                            final files = <http.MultipartFile>[];
                            if (photoPath != null) {
                              final file = File(photoPath);
                              if (await file.exists()) {
                                files.add(http.MultipartFile.fromBytes(
                                  'photo',
                                  await file.readAsBytes(),
                                  filename: photoPath.split(Platform.pathSeparator).last,
                                ));
                              }
                            }
                            await pb.collection('users').update(
                              record.id,
                              body: {'name': name},
                              files: files,
                            );
                          }
                        } catch (_) {
                          // Игнор: фоллбэк на локальный mock-стейт.
                        }
                        if (!context.mounted) return;
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
