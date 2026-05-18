import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Запуск чата в WhatsApp / Telegram / MAX по номеру телефона.
///
/// Стратегия: сначала пробуем нативный deeplink (`whatsapp://`, `tg://`,
/// `max://`) — он откроет именно установленный мессенджер и сразу в чате
/// с контактом. Если deeplink недоступен (приложение не установлено или
/// схема не задекларирована в манифесте) — fallback на web-ссылку, она
/// откроется в браузере и предложит установить приложение.
///
/// Возвращает `true`, если хотя бы один URL удалось открыть.
/// Вызывающий должен показать тост при `false` — здесь логику UI не держим.
class MessengerLauncher {
  const MessengerLauncher._();

  /// Очистка номера: только цифры. WhatsApp/Telegram ожидают E.164 без `+`,
  /// без скобок и пробелов; иначе deeplink молча упадёт в «номер не найден».
  static String _digits(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  /// Открыть WhatsApp. Сначала нативный deeplink, потом wa.me.
  /// Возвращает `false`, если телефон пуст или ни один URL не открылся.
  static Future<bool> openWhatsApp(String phone) async {
    final d = _digits(phone);
    if (d.isEmpty) return false;
    return _tryAll(<String>[
      'whatsapp://send?phone=$d',
      'https://wa.me/$d',
    ]);
  }

  /// Открыть Telegram. Приоритет — `username`, если он передан:
  /// `tg://resolve?domain=<u>` работает безусловно при установленном
  /// клиенте. Поиск по номеру телефона (`tg://resolve?phone=...`) работает
  /// только если у получателя номер открыт для поиска — поэтому это
  /// fallback‑случай, не основной.
  static Future<bool> openTelegram({String? phone, String? username}) async {
    final u = (username ?? '').trim();
    final cleanUser = u.startsWith('@') ? u.substring(1) : u;
    if (cleanUser.isNotEmpty) {
      return _tryAll(<String>[
        'tg://resolve?domain=$cleanUser',
        'https://t.me/$cleanUser',
      ]);
    }
    final d = _digits(phone ?? '');
    if (d.isEmpty) return false;
    return _tryAll(<String>[
      'tg://resolve?phone=$d',
      'https://t.me/+$d',
    ]);
  }

  /// Открыть MAX (мессенджер). Публично документированной deeplink‑схемы
  /// у MAX на момент написания нет, поэтому это best‑effort: пробуем
  /// несколько кандидатов и веб-страницу как последний рубеж.
  static Future<bool> openMax({String? phone, String? userId}) async {
    final candidates = <String>[];
    final id = (userId ?? '').trim();
    if (id.isNotEmpty) {
      candidates.addAll(<String>[
        'max://user/$id',
        'https://max.ru/$id',
      ]);
    }
    final d = _digits(phone ?? '');
    if (d.isNotEmpty) {
      candidates.addAll(<String>[
        'max://chat?phone=$d',
        'https://max.ru/+$d',
      ]);
    }
    if (candidates.isEmpty) return false;
    return _tryAll(candidates);
  }

  /// Перебор кандидатов: первый успешный запуск — выходим.
  /// `canLaunchUrl` важен для пользовательских схем (whatsapp/tg/max) —
  /// они декларированы в AndroidManifest и Info.plist. Для https‑fallback
  /// `canLaunchUrl` обычно `true` всегда (есть браузер), это и нужно.
  static Future<bool> _tryAll(List<String> urls) async {
    for (final url in urls) {
      try {
        final uri = Uri.parse(url);
        final can = await canLaunchUrl(uri);
        if (!can) continue;
        final ok =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      } catch (e) {
        debugPrint('[MessengerLauncher] $url failed: $e');
      }
    }
    return false;
  }
}
