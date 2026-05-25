import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:simba/core/utils/backend_error.dart';
import 'package:simba/data/remote/order_responses_repository.dart';

ClientException _err({
  int statusCode = 400,
  Map<String, dynamic> response = const {},
}) {
  return ClientException(
    statusCode: statusCode,
    response: response,
    url: Uri.parse('https://example.com/api'),
  );
}

void main() {
  group('humanizeBackendError — доменные исключения', () {
    test('OrderResponseGoneException → «Этот отклик уже недоступен»', () {
      final e = OrderResponseGoneException('response_gone');
      expect(humanizeBackendError(e), 'Этот отклик уже недоступен');
    });
  });

  group('humanizeBackendError — машинные коды бэка', () {
    test('order_already_accepted', () {
      final e = _err(response: {'message': 'order_already_accepted'});
      expect(humanizeBackendError(e), 'Заказ уже принят другим исполнителем');
    });

    test('city_mismatch', () {
      final e = _err(response: {'message': 'city_mismatch'});
      expect(humanizeBackendError(e), 'Заказ из другого города');
    });

    test('phone_unavailable', () {
      final e = _err(response: {'message': 'phone_unavailable'});
      expect(humanizeBackendError(e), 'Этот номер недоступен для регистрации');
    });

    test('too_many_attempts', () {
      final e = _err(response: {'message': 'too_many_attempts'});
      expect(humanizeBackendError(e),
          'Слишком много попыток. Запросите код заново');
    });

    test('session_expired', () {
      final e = _err(response: {'message': 'session_expired'});
      expect(humanizeBackendError(e),
          'Время ввода кода истекло. Запросите новый код');
    });
  });

  group('humanizeBackendError — стандартные сообщения PB', () {
    test('failed to update record → «Не удалось сохранить изменения»', () {
      final e = _err(response: {'message': 'failed to update record'});
      expect(humanizeBackendError(e), 'Не удалось сохранить изменения');
    });

    test('invalid mime type → «Формат файла не поддерживается»', () {
      final e = _err(response: {'message': 'invalid mime type'});
      expect(humanizeBackendError(e), 'Формат файла не поддерживается');
    });

    test('exceeds the maximum allowed file size → «Файл слишком большой»', () {
      final e = _err(response: {
        'message': 'exceeds the maximum allowed file size',
      });
      expect(humanizeBackendError(e), 'Файл слишком большой');
    });

    test('forbidden → «Действие недоступно»', () {
      final e = _err(response: {'message': 'You are not allowed'});
      expect(humanizeBackendError(e), 'Действие недоступно');
    });
  });

  group('humanizeBackendError — HTTP-коды без message', () {
    test('statusCode 0 → нет соединения', () {
      final e = _err(statusCode: 0);
      expect(humanizeBackendError(e), 'Нет соединения. Проверьте интернет');
    });

    test('500+ → сервер недоступен', () {
      final e = _err(statusCode: 503);
      expect(humanizeBackendError(e), 'Сервер недоступен. Попробуйте позже');
    });

    test('403 → действие недоступно', () {
      final e = _err(statusCode: 403);
      expect(humanizeBackendError(e), 'Действие недоступно');
    });

    test('401 → сессия истекла', () {
      final e = _err(statusCode: 401);
      expect(humanizeBackendError(e), 'Сессия истекла, войдите заново');
    });
  });

  group('humanizeBackendError — сетевые исключения', () {
    test('TimeoutException → «Сервер не отвечает»', () {
      final e = TimeoutException('timed out');
      expect(humanizeBackendError(e), 'Сервер не отвечает. Попробуйте позже');
    });
  });

  group('humanizeBackendError — fallback', () {
    test('неизвестная ошибка → общее «Ошибка. Попробуйте позже»', () {
      final e = Exception('something weird');
      expect(humanizeBackendError(e), 'Ошибка. Попробуйте позже');
    });

    test('кастомное сообщение на русском возвращается как есть', () {
      // Бэк может слать собственные текстовые сообщения — они должны
      // долетать до юзера без потерь, иначе теряется конкретика лимитов.
      final e = _err(response: {
        'message': 'Лимит активных откликов: 10 исчерпан',
      });
      expect(humanizeBackendError(e),
          'Лимит активных откликов: 10 исчерпан');
    });
  });
}
