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
Future<File?> ensurePhotoUnderLimit(String srcPath, double maxMb) async {
  final src = File(srcPath);
  if (!await src.exists()) return null;
  final srcMb = (await src.length()) / 1024 / 1024;
  if (srcMb <= maxMb) return src;

  final tmpDir = await getTemporaryDirectory();
  final ts = DateTime.now().millisecondsSinceEpoch;
  // Каждая итерация пишет в свой target, иначе compressAndGetFile может
  // вернуть тот же путь и FS-кеш будет читать старый размер.
  for (var i = 0; i < 4; i++) {
    final quality = const [70, 50, 30, 15][i];
    final dst = '${tmpDir.path}${Platform.pathSeparator}simba_compress_${ts}_$quality.jpg';
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
    if (outMb <= maxMb) return outFile;
  }
  return null;
}
