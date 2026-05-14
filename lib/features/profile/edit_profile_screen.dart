import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/image_compressor.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/mock/app_state.dart';
import '../../data/remote/pocketbase_client.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _name;
  String? _photoPath;
  bool _hasTools = false;
  bool _hasTransport = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final u = ref.read(appControllerProvider).user!;
    _name = TextEditingController(text: u.name);
    _photoPath = u.photoPath;
    _hasTools = u.hasTools;
    _hasTransport = u.hasTransport;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Максимальный размер аватара (МБ). 1024×1024 источника + JPEG-85 обычно
  /// дают <1 МБ; 4 МБ — потолок для пограничных PNG/HEIC случаев.
  static const double _kMaxPhotoMb = 4.0;

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final f = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (f == null) return;
      // image_picker уже жал; для пограничных PNG/HEIC дожимаем нативно.
      final source = await ensurePhotoUnderLimit(f.path, _kMaxPhotoMb);
      if (!mounted) return;
      if (source == null) {
        AppToast.show(context, 'Не удалось обработать фото. Попробуйте другое.');
        return;
      }
      // Копируем в documents directory — image_picker возвращает путь во
      // временную папку, которая может быть очищена OS, и Image.file
      // потом крэшится на cold-start. См. profile_setup_screen для
      // подробностей.
      final docs = await getApplicationDocumentsDirectory();
      final ext = source.path.contains('.') ? source.path.split('.').last : 'jpg';
      final dst = File(
        '${docs.path}${Platform.pathSeparator}profile_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await source.copy(dst.path);
      if (!mounted) return;
      setState(() => _photoPath = dst.path);
    } catch (_) {}
  }

  Future<void> _onAvatarTap() async {
    if (_photoPath == null) {
      await _pickFromGallery();
      return;
    }
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AvatarSheet(),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AvatarAction.change:
        await _pickFromGallery();
      case _AvatarAction.remove:
        setState(() => _photoPath = null);
    }
  }

  bool get _canSave {
    final user = ref.read(appControllerProvider).user;
    if (user == null) return false;
    final nameChanged = _name.text.trim() != user.name && _name.text.trim().isNotEmpty;
    final photoChanged = _photoPath != user.photoPath;
    final toolsChanged = _hasTools != user.hasTools;
    final transportChanged = _hasTransport != user.hasTransport;
    return nameChanged || photoChanged || toolsChanged || transportChanged;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      // Если бэкенд подключён и юзер залогинен — пушим изменения в PB.
      // Если фото — локальный путь (не URL), грузим как multipart-файл.
      // На моках просто обновляем appController (как было раньше).
      final pb = ref.read(pocketbaseProvider);
      if (pb != null && pb.authStore.isValid) {
        final body = <String, dynamic>{
          'name': _name.text.trim(),
          'has_tools': _hasTools,
          'has_transport': _hasTransport,
        };
        final files = <http.MultipartFile>[];
        final photo = _photoPath;
        if (photo != null && !photo.startsWith('http')) {
          // Локальный файл из image_picker — отправляем байты как
          // multipart. PocketBase поле `users.photo` уже сконфигурено
          // как file (см. миграция 1700000000_init_users).
          final bytes = await File(photo).readAsBytes();
          files.add(http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: 'avatar.jpg',
          ));
        }
        // upload фото может занимать дольше обычного update — даём 30с,
        // как в orders.create. Без таймаута PB SDK мог зависать.
        await pb
            .collection('users')
            .update(
              pb.authStore.record!.id,
              body: body,
              files: files,
            )
            .timeout(const Duration(seconds: 30));
      }
      ref.read(appControllerProvider.notifier).completeProfile(
            name: _name.text,
            photoPath: _photoPath,
            hasTools: _hasTools,
            hasTransport: _hasTransport,
          );
      if (!mounted) return;
      context.pop();
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Не удалось сохранить');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
                  // Avatar 100×100 + камера-бейдж всегда поверх в правом-нижнем
                  // углу (и для фото, и для дефолтной user-иконки).
                  Center(
                    child: GestureDetector(
                      onTap: _onAvatarTap,
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
                                  ? (_photoPath!.startsWith('http')
                                      ? Image.network(
                                          _photoPath!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              Image.asset(
                                            'assets/images/avatar_default.webp',
                                            fit: BoxFit.contain,
                                          ),
                                        )
                                      : Image.file(
                                          File(_photoPath!),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              Image.asset(
                                            'assets/images/avatar_default.webp',
                                            fit: BoxFit.contain,
                                          ),
                                        ))
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
                  SizedBox(height: 16.h),
                  AppTextField(
                    label: 'Имя / Никнейм',
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    maxLength: 50,
                    textCapitalization: TextCapitalization.words,
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
              child: _SaveButton(
                enabled: _canSave && !_isSaving,
                isLoading: _isSaving,
                onTap: _save,
              ),
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

enum _AvatarAction { change, remove }

class _AvatarSheet extends StatelessWidget {
  const _AvatarSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(15.r)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 8.h),
            _AvatarSheetItem(
              icon: Icons.photo_camera_rounded,
              label: 'Сменить фото',
              onTap: () => Navigator.of(context).pop(_AvatarAction.change),
            ),
            Container(
              height: 1,
              margin: EdgeInsets.symmetric(horizontal: 16.w),
              color: AppColors.divider,
            ),
            _AvatarSheetItem(
              icon: Icons.delete_outline_rounded,
              label: 'Удалить фото',
              destructive: true,
              onTap: () => Navigator.of(context).pop(_AvatarAction.remove),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }
}

class _AvatarSheetItem extends StatelessWidget {
  const _AvatarSheetItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : AppColors.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24.r),
              SizedBox(width: 16.w),
              Text(
                label,
                style: TextStyle(
                  color: destructive ? AppColors.error : Colors.black,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.50,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.enabled,
    required this.onTap,
    this.isLoading = false,
  });
  final bool enabled;
  final VoidCallback onTap;
  final bool isLoading;

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
            child: isLoading
                ? SizedBox(
                    width: 22.r,
                    height: 22.r,
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    'Сохранить',
                    style: TextStyle(
                      color: enabled ? Colors.white : const Color(0x4C3C3C43),
                      fontSize: 17.sp,
                      fontWeight:
                          enabled ? FontWeight.w600 : FontWeight.w400,
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
