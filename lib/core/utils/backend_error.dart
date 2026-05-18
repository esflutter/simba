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
  // Стандартные английские сообщения PocketBase — переводим.
  // PB шлёт их как `data.message` в строго определённой форме, тех же
  // строк ждут и пользовательские сценарии в админке.
  final lower = msg.toLowerCase();
  if (lower.startsWith('failed to update record') ||
      lower.startsWith('failed to update the record')) {
    return 'Не удалось сохранить изменения';
  }
  if (lower.startsWith('failed to create record')) {
    return 'Не удалось создать запись';
  }
  if (lower.startsWith('failed to delete record')) {
    return 'Не удалось удалить запись';
  }
  if (lower.contains('failed to upload') || lower.contains('upload all files')) {
    return 'Не удалось загрузить файл';
  }
  if (lower.contains('invalid mime type') ||
      lower.contains('the submitted file is invalid') ||
      lower.contains('unsupported file type')) {
    return 'Формат файла не поддерживается';
  }
  if (lower.contains('exceeds the maximum allowed file size') ||
      lower.contains('file size is too large') ||
      lower.contains('size limit')) {
    return 'Файл слишком большой';
  }
  if (lower.contains('the request requires valid record authorization') ||
      lower.contains('admin authorization required') ||
      lower.contains('not authenticated') ||
      lower == 'missing or invalid auth') {
    return 'Сессия истекла, войдите заново';
  }
  if (lower.contains("you are not allowed") ||
      lower.contains('forbidden') ||
      lower.contains('action is forbidden')) {
    return 'Действие недоступно';
  }
  // Уже на русском (наши кастомные FSM/лимиты «Лимит активных откликов:
  // 10 исчерпан» и т.п.) — возвращаем как есть. Английский без перевода
  // тоже возвращаем, но это исключительный кейс — лучше неаккуратный
  // текст, чем глухой «Ошибка».
  return msg;
}
