import 'package:pocketbase/pocketbase.dart';

import '../../data/remote/order_responses_repository.dart';

/// Превращает любое исключение от бэка/репозитория в человекочитаемое
/// сообщение для тоста. Раньше во всех `catch (_)` UI показывал
/// «Ошибка. Попробуйте позже», и юзер не понимал, что произошло
/// (особенно при лимитах: «10 активных откликов исчерпан», «30 заказов
/// в сутки» и т.п.).
String humanizeBackendError(Object e) {
  // Доменные исключения с собственным сообщением.
  if (e is OrderResponseGoneException) {
    return 'Этот отклик уже недоступен';
  }

  if (e is ClientException) {
    final data = e.response;
    // PB обычно кладёт текст в `message`, иногда в `error`.
    final msg = (data['message'] as String?) ??
        (data['error'] as String?) ??
        '';
    if (msg.isNotEmpty) {
      return _mapBackendMessage(msg);
    }
    if (e.statusCode == 0) return 'Нет соединения. Проверьте интернет';
    if (e.statusCode >= 500) return 'Сервер недоступен. Попробуйте позже';
    if (e.statusCode == 403) return 'Действие недоступно';
    if (e.statusCode == 401) return 'Сессия истекла, войдите заново';
  }

  // Таймаут, сетевые ошибки.
  final s = e.toString();
  if (s.contains('TimeoutException')) {
    return 'Сервер не отвечает. Попробуйте позже';
  }
  if (s.contains('SocketException') || s.contains('Failed host lookup')) {
    return 'Нет соединения. Проверьте интернет';
  }

  return 'Ошибка. Попробуйте позже';
}

/// Маппинг известных сообщений бэка → дружелюбный русский текст.
/// Если бэк уже шлёт по-русски (наши кастомные ручки) — возвращаем как есть.
String _mapBackendMessage(String msg) {
  // Технические машинные коды (на латинице) — переводим вручную.
  switch (msg) {
    case 'order_not_open':
    case 'order_already_accepted':
      return 'Заказ уже принят другим исполнителем';
    case 'city_mismatch':
    case 'city_mismatch_create':
      return 'Заказ из другого города';
    case 'city_required':
      return 'Сначала выберите город в профиле';
    case 'phone_unavailable':
      return 'Этот номер недоступен для регистрации';
    case 'too_many_attempts':
      return 'Слишком много попыток. Запросите код заново';
    case 'session_expired':
      return 'Время ввода кода истекло. Запросите новый код';
    case 'unauthorized':
      return 'Сессия истекла, войдите заново';
    case 'rate_limit_hour':
    case 'rate_limit_day':
      return 'Слишком частые запросы. Попробуйте позже';
  }
  // Уже на русском — возвращаем как есть. На бэке кастомные ошибки FSM/лимитов
  // (например «Лимит активных откликов: 10 исчерпан») рисуются по-русски.
  return msg;
}
