import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
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

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      // image_picker — первый проход чтобы не держать оригинал в памяти
      // (HEIC/RAW из галереи легко 12+ МБ). Финальное сжатие до 512×512
      // JPEG делает compressAvatar.
      final f = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (f == null) return;
      final source = await compressAvatar(f.path);
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
      //
      // Расширение принудительно `.jpg` — compressAvatar всегда отдаёт
      // JPEG; брать ext от исходного пути небезопасно (HEIC с iPhone
      // мог бы случайно унаследоваться, и Image.file его не покажет).
      final docs = await getApplicationDocumentsDirectory();
      final dst = File(
        '${docs.path}${Platform.pathSeparator}profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await source.copy(dst.path);
      // compressAvatar вернул временный JPEG во временной папке — после
      // копии в documents он больше не нужен. Удаляем, чтобы при каждой
      // смене аватарки не копился файл-сирота во временном каталоге.
      try {
        if (await source.exists()) await source.delete();
      } catch (_) {/* не критично */}
      // Удаляем предыдущую локальную аватарку, если она была — иначе
      // повторный пик до сабмита плодит файлы в documents.
      final prev = _photoPath;
      if (prev != null &&
          !prev.startsWith('http') &&
          prev != dst.path &&
          prev.startsWith(docs.path)) {
        try {
          final f = File(prev);
          if (await f.exists()) await f.delete();
        } catch (_) {/* не критично */}
      }
      if (!mounted) return;
      setState(() => _photoPath = dst.path);
    } catch (e) {
      // Любая ошибка: permission denied на iOS, OOM на больших RAW,
      // повреждённый файл. Раньше глотали молча — юзер не понимал, почему
      // ничего не происходит. Показываем тост + лог для диагностики.
      // $e не пишем в release — путь к файлу/системное сообщение могут
      // утечь в logcat.
      if (kDebugMode) {
        debugPrint('[profile_setup] pickPhoto failed: $e');
      }
      if (!mounted) return;
      AppToast.show(context, 'Не удалось добавить фото');
    }
  }

  Future<void> _onContinue() async {
    if (_isSaving) return;
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    final photoPath = _photoPath;
    // По умолчанию зеркалим локальное значение; после успешной загрузки
    // заменим на серверную ссылку (см. ниже).
    String? mirroredPhoto = photoPath;
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
              // Грузим через bytes-буфер, не stream: PB SDK 0.22 с
              // потоком даёт ошибку сохранения (stream consumed при
              // ре-финализации запроса). Для аватара 4 МБ буфер
              // безопасен по памяти; тяжёлые случаи (несколько фото
              // заказа) обрабатываются в orders_repository, где есть
              // полноценный _withAuthRetry-обработчик.
              final bytes = await file.readAsBytes();
              // Явный content-type обязателен. По умолчанию http_parser
              // ставит application/octet-stream, PB не угадывает по
              // содержимому и возвращает «invalid mime type». В
              // edit_profile_screen это уже починено, здесь забыли.
              // Расширение принудительно .jpg в `compressAvatar`, тип
              // ставим image/jpeg.
              files.add(http.MultipartFile.fromBytes(
                'photo',
                bytes,
                filename: 'avatar.jpg',
                contentType: MediaType('image', 'jpeg'),
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
          // withAuthRetry — на случай, если токен истёк ровно между
          // verify и переходом на этот экран (юзер промедлил пару минут
          // на ввод имени).
          final updated = await pb.withAuthRetry(
            () => pb
                .collection('users')
                .update(
                  pb.authStore.record!.id,
                  body: patchBody,
                  files: files,
                )
                .timeout(const Duration(seconds: 10)),
          );
          // В локальный стейт кладём СЕРВЕРНУЮ ссылку на фото, а не путь к
          // локальному файлу: иначе если ОС удалит файл, аватарка нового
          // пользователя показывалась бы дефолтной до первого обновления
          // сессии. Локальную копию после успешной загрузки удаляем — она
          // больше не нужна.
          final uploadedName = updated.getStringValue('photo');
          if (uploadedName.isNotEmpty) {
            mirroredPhoto = pb.files.getUrl(updated, uploadedName).toString();
            if (photoPath != null) {
              try {
                final local = File(photoPath);
                if (await local.exists()) await local.delete();
              } catch (_) {/* не критично */}
            }
          }
        } catch (_) {
          // Сеть/таймаут/серверная ошибка — НЕ переходим дальше, иначе
          // имя сохранится только локально, на бэке останется пустым,
          // и следующий silent refresh снова отправит юзера сюда —
          // получится петля «заполнил → главный → перезапуск → опять
          // профиль». Просим попробовать снова.
          if (!mounted) return;
          AppToast.show(
            context,
            'Не удалось сохранить профиль. Проверьте интернет и попробуйте снова.',
          );
          setState(() => _isSaving = false);
          return;
        }
      }
      // Зеркалим имя/фото в локальный AppController — UI-консьюмеры
      // продолжают читать state.user без изменений.
      ref.read(appControllerProvider.notifier).completeProfile(
            name: name,
            photoPath: mirroredPhoto,
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
                                          // cacheWidth — декодим в ~300px
                                          // (3×100r), не в полные 1024×1024
                                          // оригинала. Без этого один аватар
                                          // в RAM ≈ 4МБ растрового bitmap.
                                          cacheWidth: 300,
                                          cacheHeight: 300,
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
                color: AppColors.surface,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
