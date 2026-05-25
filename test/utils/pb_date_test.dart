import 'package:flutter_test/flutter_test.dart';
import 'package:simba/core/utils/pb_date.dart';

void main() {
  group('parsePbDate — валидные ISO-форматы', () {
    test('ISO с Z (UTC)', () {
      final dt = parsePbDate('2026-05-23T18:30:00Z');
      expect(dt, isNotNull);
      // Возвращается в локальной таймзоне; проверяем сам момент,
      // а не вывод (на CI таймзона может отличаться от dev-машины).
      expect(dt!.toUtc(), DateTime.utc(2026, 5, 23, 18, 30, 0));
    });

    test('ISO с миллисекундами', () {
      final dt = parsePbDate('2026-05-23T18:30:00.123Z');
      expect(dt, isNotNull);
      expect(dt!.toUtc(), DateTime.utc(2026, 5, 23, 18, 30, 0, 123));
    });

    test('ISO с пробелом вместо T (PocketBase-формат)', () {
      // PB в части responses отдаёт даты с пробелом, не Т.
      // DateTime.tryParse это нормально принимает.
      final dt = parsePbDate('2026-05-23 18:30:00.000Z');
      expect(dt, isNotNull);
      expect(dt!.toUtc(), DateTime.utc(2026, 5, 23, 18, 30));
    });
  });

  group('parsePbDate — пустые и невалидные', () {
    test('null → null', () {
      expect(parsePbDate(null), isNull);
    });

    test('пустая строка → null', () {
      expect(parsePbDate(''), isNull);
    });

    test('мусор → null', () {
      expect(parsePbDate('not a date'), isNull);
    });

    test('zero-DateTime от PocketBase → парсится, но дата 0001 г.', () {
      // Это та самая «zero-stamp» которая в JS truthy — на клиенте
      // полагаемся на сравнение с конкретными значениями, а не на
      // truthy-чек. Сама строка валидная.
      final dt = parsePbDate('0001-01-01 00:00:00.000Z');
      expect(dt, isNotNull);
      expect(dt!.toUtc().year, 1);
    });
  });
}
