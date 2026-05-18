import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:http_parser/http_parser.dart' show MediaType;

import '../../core/theme/app_colors.dart';
import '../../core/utils/backend_error.dart';
import '../../core/utils/image_compressor.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_network_image.dart';
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
    final u = ref.read(appControllerProvider).user;
    // u может быть null, если роутер пропустил без auth (теоретический
    // edge case — guard в роутере отправляет на /auth/phone, но мы не
    // полагаемся на это и инициализируем поля пустыми).
    _name = TextEditingController(text: u?.name ?? '');
    _photoPath = u?.photoPath;
    _hasTools = u?.hasTools ?? false;
    _hasTransport = u?.hasTransport ?? false;
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
    } catch (e) {
      // Не глушим исключение молча — раньше пользователь не понимал,
      // почему «Выбрать фото» ничего не открывает. Показываем тост.
      debugPrint('[edit_profile] pickPhoto failed: $e');
      if (!mounted) return;
      AppToast.show(context, 'Не удалось добавить фото');
    }
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
      // authStore.record может оказаться null даже при isValid (после refresh
      // без user-data или гонки logout). Без явной проверки `record!.id`
      // ниже даст TypeError; лучше тихо пропустить sync — локальный
      // AppController всё равно обновится через completeProfile.
      final me = pb?.authStore.record;
      if (pb != null && pb.authStore.isValid && me != null) {
        final photo = _photoPath;
        final hasNewPhoto = photo != null && !photo.startsWith('http');
        // Если в исходном профиле было фото (URL с сервера), а сейчас
        // _photoPath == null — пользователь нажал «Удалить фото». Надо
        // явно сказать серверу очистить файл-поле, иначе PATCH без
        // упоминания photo оставляет старое значение, и после рестарта
        // приложения старая аватарка возвращается из PB.
        final serverPhotoUrl =
            ref.read(appControllerProvider).user?.photoPath ?? '';
        final hadServerPhoto = serverPhotoUrl.startsWith('http');
        final photoCleared = !hasNewPhoto && photo == null && hadServerPhoto;
        // PB Dart SDK при передаче files: [...] (даже пустого) собирает
        // multipart/form-data и сериализует bool как "true"/"false" — PB
        // потом отказывается записать строку в BOOLEAN-поле. Поэтому в
        // отсутствии нового фото шлём чистый JSON, а multipart используем
        // только когда реально аплоадим аватар (там bool кодируем как 1/0).
        if (hasNewPhoto) {
          // Грузим через bytes-буфер, не stream. Поток `openRead()` в
          // паре с PB SDK 0.22 даёт PATCH-ошибку «не удалось сохранить»:
          // SDK при ретраях или внутреннем re-finalize пытается прочесть
          // stream повторно, а он уже исчерпан. Для аватара (лимит 4 МБ)
          // буфер безопаснее: тяжёлые случаи (фото заказов) обходим в
          // orders_repository, там есть `_withAuthRetry`-ловушка.
          final bytes = await File(photo).readAsBytes();
          // Корректный content-type важен: PB users.photo разрешает
          // jpeg/png/webp (см. миграцию 002 + 011). По умолчанию
          // MultipartFile.fromBytes ставит application/octet-stream —
          // PB по нему не угадает картинку и вернёт «invalid mime type».
          // Тип определяем по расширению файла (после ensurePhotoUnderLimit
          // оно соответствует реальному формату — image_compressor
          // конвертирует в jpeg при пересжатии).
          final ext = photo.toLowerCase().split('.').last;
          final mime = switch (ext) {
            'png' => MediaType('image', 'png'),
            'webp' => MediaType('image', 'webp'),
            _ => MediaType('image', 'jpeg'),
          };
          final fname = 'avatar.${ext == 'jpg' ? 'jpg' : ext}';
          await pb
              .collection('users')
              .update(
                me.id,
                body: {
                  'name': _name.text.trim(),
                  // В multipart булевы поля пишем как "1"/"0" — иначе SDK
                  // отправит "true"/"false" и PB бракует тип.
                  'has_tools': _hasTools ? '1' : '0',
                  'has_transport': _hasTransport ? '1' : '0',
                },
                files: [
                  http.MultipartFile.fromBytes(
                    'photo',
                    bytes,
                    filename: fname,
                    contentType: mime,
                  ),
                ],
              )
              .timeout(const Duration(seconds: 30));
        } else {
          // PB-документация: чтобы очистить single-file-поле, шлём
          // его значение как пустую строку (поведение проверено на
          // версии 0.22 SDK). null в JSON-теле обрабатывается так же,
          // но пустая строка надёжнее — некоторые серверы PB строго
          // проверяют тип.
          final body = <String, dynamic>{
            'name': _name.text.trim(),
            'has_tools': _hasTools,
            'has_transport': _hasTransport,
            if (photoCleared) 'photo': '',
          };
          await pb
              .collection('users')
              .update(me.id, body: body)
              .timeout(const Duration(seconds: 30));
        }
      }
      ref.read(appControllerProvider.notifier).completeProfile(
            name: _name.text,
            photoPath: _photoPath,
            hasTools: _hasTools,
            hasTransport: _hasTransport,
          );
      if (!mounted) return;
      context.pop();
    } catch (e, st) {
      // Логируем + показываем юзеру конкретную причину через
      // humanizeBackendError: лимиты, 401 (сессия истекла), 5xx,
      // mime/размер фото — всё переводится в дружелюбный русский текст.
      // До этого был просто «Не удалось сохранить» без подсказки.
      debugPrint('[edit_profile] save failed: $e\n$st');
      if (!mounted) return;
      AppToast.show(context, humanizeBackendError(e));
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
                          color: AppColors.textPrimary,
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
                                      // AppNetworkImage даёт disk+memory
                                      // cache и memCacheWidth под фактический
                                      // размер виджета — без этого аватар PB
                                      // 1024×1024 декодился под 100r-кружок
                                      // целиком. Размер передаём явно: cap
                                      // считается из `width × dpr`.
                                      ? AppNetworkImage(
                                          url: _photoPath!,
                                          width: 100.r,
                                          height: 100.r,
                                          fallback: Image.asset(
                                            'assets/images/avatar_default.webp',
                                            fit: BoxFit.contain,
                                          ),
                                        )
                                      : Image.file(
                                          File(_photoPath!),
                                          fit: BoxFit.cover,
                                          // 100r-аватар на 3×-устройстве =
                                          // 300px. Декодим именно столько,
                                          // а не весь 1024×1024 оригинал.
                                          cacheWidth: 300,
                                          cacheHeight: 300,
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
                      color: AppColors.textPrimary,
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
              color: AppColors.surface,
              shadows: const [Shadow(color: AppColors.surface, blurRadius: 2)],
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
        color: AppColors.surface,
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
                  color: destructive ? AppColors.error : AppColors.textPrimary,
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
                      color: AppColors.surface,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    'Сохранить',
                    style: TextStyle(
                      color: enabled ? AppColors.surface : const Color(0x4C3C3C43),
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
