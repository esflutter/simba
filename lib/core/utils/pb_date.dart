import 'package:flutter/foundation.dart';

/// Парсит дату/время из PocketBase в `DateTime` локальной таймзоны.
///
/// PB отдаёт даты в ISO8601 в UTC. На клиенте дальше эти даты идут в UI
/// и в `DateFormat('dd.MM.yyyy HH:mm')`, который ожидает время в часовой
/// поясе устройства. Без `toLocal()` юзер видит «вчера 22:00» вместо
/// «сегодня 01:00» — баг проявляется только ночью, поэтому легко упустить.
///
/// Возвращает `null` для пустой/невалидной строки. Невалидную дату пишет
/// в `debugPrint`, чтобы в логах было видно расхождение версий бэка/клиента.
DateTime? parsePbDate(String? s) {
  if (s == null || s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) {
    // Только в debug: в release не пишем в системный лог (единообразно с
    // остальным кодом — все debugPrint обёрнуты в kDebugMode).
    if (kDebugMode) {
      debugPrint('[parsePbDate] failed to parse "$s"');
    }
    return null;
  }
  return parsed.isUtc ? parsed.toLocal() : parsed;
}
