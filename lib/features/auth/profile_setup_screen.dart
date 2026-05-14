import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/image_compressor.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/app_toast.dart';
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
  bool _isSaving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Максимальный размер аватара (МБ). Аватарка показывается ~100×100 px, так
  /// что 1024×1024 на источнике хватит с запасом. 4 МБ — потолок для пограничных
  /// случаев; бэк-схема users.photo синхронизирована.
  static const double _kMaxPhotoMb = 4.0;

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final f = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (f == null) return;
      // 1) image_picker нативно сжал. 2) Если всё ещё >4 МБ — дожимаем
      // циклом через flutter_image_compress (PNG/HEIC случаи).
      final source = await ensurePhotoUnderLimit(f.path, _kMaxPhotoMb);
      if (!mounted) return;
      if (source == null) {
        AppToast.show(context, 'Не удалось обработать фото. Попробуйте другое.');
        return;
      }
      // ImagePicker возвращает путь во временную/кэшевую директорию (на
      // Android — getCacheDir/<pkg>/<file>.jpg; на iOS — tmp/). После
      // очистки кэша системой файл пропадает, и Image.file крэшится при
      // следующем cold-start. Копируем в documents directory — она
      // persistent для приложения.
      final docs = await getApplicationDocumentsDirectory();
      // source.path может быть оригиналом (.png/.heic) или сжатым (.jpg).
      // Берём расширение из реального пути, чтобы Image.file правильно
      // декодировал файл.
      final ext = source.path.contains('.') ? source.path.split('.').last : 'jpg';
      final dst = File(
        '${docs.path}${Platform.pathSeparator}profile_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await source.copy(dst.path);
      if (!mounted) return;
      setState(() => _photoPath = dst.path);
    } catch (_) {}
  }

  Future<void> _onContinue() async {
    if (_isSaving) return;
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    final photoPath = _photoPath;
    setState(() => _isSaving = true);
    try {
      final pb = ref.read(pocketbaseProvider);
      // Если бэкенд подключён — пробуем PATCH, но НЕ блокируем flow при
      // сетевой ошибке: юзер не должен запираться на экране. Локальное
      // зеркало AppController сохранится в любом случае; повторный sync
      // в будущем будет вынесен в фоновый job (TODO).
      if (pb != null && pb.authStore.isValid && pb.authStore.record != null) {
        try {
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
          // city сохраняем вместе с именем — это часть онбординга. Если в
          // state нет selectedCityId (роутер до profile должен был провести
          // через /city, но защитимся), не отправляем — бэк не примет пустой
          // relation.
          final selectedCityId =
              ref.read(appControllerProvider).selectedCityId;
          final patchBody = <String, dynamic>{
            'name': name,
            if (selectedCityId != null && selectedCityId.isNotEmpty)
              'city': selectedCityId,
          };
          await pb
              .collection('users')
              .update(
                pb.authStore.record!.id,
                body: patchBody,
                files: files,
              )
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          // Сеть/таймаут/серверная ошибка — показываем тост, но flow
          // продолжаем: имя/фото уже лежат в AppController, sync позже.
          if (mounted) {
            AppToast.show(
              context,
              'Профиль сохранён локально. Синхронизируем позже.',
            );
          }
        }
      }
      // Зеркалим имя/фото в локальный AppController — UI-консьюмеры
      // продолжают читать state.user без изменений.
      ref.read(appControllerProvider.notifier).completeProfile(
            name: name,
            photoPath: photoPath,
          );
      if (!mounted) return;
      context.go('/auth/role');
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Не удалось сохранить профиль');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _ctrl.text.trim().isNotEmpty && !_isSaving;
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
                          onTap: _isSaving ? null : _pickPhoto,
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
                                          // Файл может пропасть, если
                                          // OS очистила кэш до того, как мы
                                          // успели скопировать в documents
                                          // (или пользователь старой версии).
                                          errorBuilder: (_, _, _) =>
                                              Image.asset(
                                            'assets/images/avatar_default.webp',
                                            fit: BoxFit.contain,
                                          ),
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
                        enabled: !_isSaving,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              _ContinueButton(
                isSaving: _isSaving,
                onPressed: canContinue ? _onContinue : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.isSaving, required this.onPressed});

  final bool isSaving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!isSaving) {
      return PrimaryButton(label: 'Далее', onPressed: onPressed);
    }
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16.r),
        child: SizedBox(
          height: 50.h,
          child: Center(
            child: SizedBox(
              width: 22.r,
              height: 22.r,
              child: const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
