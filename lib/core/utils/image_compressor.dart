import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Гарантирует, что фото будет <= [maxMb] мегабайт.
///
/// `image_picker` с `maxWidth+imageQuality` обычно справляется сам, но в
/// 1% случаев (большие PNG/HEIC, RAW из странных галерей) возвращает файл
/// больше лимита. Тогда дожимаем нативно через `flutter_image_compress`,
/// циклом снижая качество JPEG: 70 → 50 → 30 → 15. После такой цепочки
/// 14-МБ исходник гарантированно влезает в 1-2 МБ.
///
/// Возвращает:
/// - исходный [File], если он уже укладывается;
/// - сжатый [File] во временной директории, если потребовалось пережатие;
/// - `null`, если даже на quality=15 фото не влезло (теоретически невозможно
///   при разумных входных данных, но если файл повреждён или это видео —
///   получим null и покажем юзеру понятный тост).
/// Сжимает аватар до маленького JPEG в кружок. На сервере users.photo —
/// это профильная аватарка, которая никогда не открывается в полный
/// размер: только круг ~100×100 на экране профиля. Хранить и тащить
/// её в 1-4 МБ бессмысленно — после сжатия типичная аватарка получается
/// 50–200 КБ и визуально неотличима в кружке.
///
/// Всегда перекодирует через flutter_image_compress, независимо от
/// размера исходника. Это покрывает и HEIC/HEIF с iPhone (бэк их не
/// принимает), и крупные исходники 12+ МБ.
Future<File?> compressAvatar(String srcPath) async {
  final src = File(srcPath);
  if (!await src.exists()) return null;
  final tmpDir = await getTemporaryDirectory();
  final ts = DateTime.now().millisecondsSinceEpoch;
  final dst = '${tmpDir.path}${Platform.pathSeparator}simba_avatar_$ts.jpg';
  final out = await FlutterImageCompress.compressAndGetFile(
    srcPath,
    dst,
    // 512×512 — достаточно для retina-дисплеев при максимальном размере
    // кружка ~120×120 (3×). Quality 82 даёт стабильно красивое лицо
    // без видимых JPEG-артефактов.
    minWidth: 512,
    minHeight: 512,
    quality: 82,
    format: CompressFormat.jpeg,
  );
  if (out == null) return null;
  return File(out.path);
}

Future<File?> ensurePhotoUnderLimit(String srcPath, double maxMb) async {
  final src = File(srcPath);
  if (!await src.exists()) return null;
  final srcMb = (await src.length()) / 1024 / 1024;
  // HEIC / HEIF (формат фото из iOS-галереи) на сервере не принимается —
  // users.photo / orders.photos валидируют по mime, а наш клиент шлёт
  // application/jpeg|png|webp в зависимости от расширения. Поэтому даже
  // если HEIC-файл вписался в лимит по размеру, его надо принудительно
  // перекодировать в JPEG. Без этого iPhone-юзер получал «invalid mime
  // type» от бэка и не понимал, почему фото не загружается.
  final ext = srcPath.toLowerCase().split('.').last;
  final isHeic = ext == 'heic' || ext == 'heif';
  if (srcMb <= maxMb && !isHeic) return src;

  final tmpDir = await getTemporaryDirectory();
  final ts = DateTime.now().millisecondsSinceEpoch;
  // Каждая итерация пишет в свой target, иначе compressAndGetFile может
  // вернуть тот же путь и FS-кеш будет читать старый размер.
  final intermediates = <String>[];
  Future<void> cleanupOthers(String? keep) async {
    for (final p in intermediates) {
      if (p == keep) continue;
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {/* не критично */}
    }
  }

  for (var i = 0; i < 4; i++) {
    final quality = const [70, 50, 30, 15][i];
    final dst = '${tmpDir.path}${Platform.pathSeparator}simba_compress_${ts}_$quality.jpg';
    intermediates.add(dst);
    final out = await FlutterImageCompress.compressAndGetFile(
      srcPath,
      dst,
      quality: quality,
      // Если исходник уже маленький — minWidth/Height не увеличат, только
      // ограничат снизу. 1920 — достаточно для marketplace-фото.
      minWidth: 1920,
      minHeight: 1920,
      format: CompressFormat.jpeg,
    );
    if (out == null) continue;
    final outFile = File(out.path);
    final outMb = (await outFile.length()) / 1024 / 1024;
    if (outMb <= maxMb) {
      // Чистим промежуточные пережатия с большей quality, оставляем
      // только тот файл, который вернули. Без этого после выбора 5 фото
      // в tmp могло остаться до 20 файлов-черновиков — ОС их подчистит,
      // но локально диск зря тратится.
      await cleanupOthers(out.path);
      return outFile;
    }
  }
  // Все итерации не уложились — на всякий случай чистим, чтобы не
  // оставить мусор от неудачной обработки.
  await cleanupOthers(null);
  return null;
}
