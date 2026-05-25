import 'package:flutter_test/flutter_test.dart';
import 'package:simba/core/utils/plural_ru.dart';

void main() {
  group('pluralRu — базовое правило', () {
    test('форма "one" для 1, 21, 31, 101', () {
      expect(pluralRu(1, 'a', 'b', 'c'), 'a');
      expect(pluralRu(21, 'a', 'b', 'c'), 'a');
      expect(pluralRu(31, 'a', 'b', 'c'), 'a');
      expect(pluralRu(101, 'a', 'b', 'c'), 'a');
    });

    test('форма "few" для 2-4, 22-24, 102-104', () {
      for (final n in [2, 3, 4, 22, 23, 24, 102, 103, 104]) {
        expect(pluralRu(n, 'a', 'b', 'c'), 'b', reason: 'n=$n');
      }
    });

    test('форма "many" для 0, 5-20, 25-30, 100', () {
      for (final n in [0, 5, 6, 7, 10, 15, 20, 25, 26, 30, 100]) {
        expect(pluralRu(n, 'a', 'b', 'c'), 'c', reason: 'n=$n');
      }
    });

    test('исключение 11-14 — всегда "many"', () {
      for (final n in [11, 12, 13, 14, 111, 112, 113, 114]) {
        expect(pluralRu(n, 'a', 'b', 'c'), 'c', reason: 'n=$n');
      }
    });
  });

  group('Готовые формы', () {
    test('секунды: 1 секунду, 2 секунды, 5 секунд, 11 секунд', () {
      expect(pluralSec(1), 'секунду');
      expect(pluralSec(2), 'секунды');
      expect(pluralSec(5), 'секунд');
      expect(pluralSec(11), 'секунд');
    });

    test('минуты: 1 минуту, 22 минуты, 25 минут', () {
      expect(pluralMin(1), 'минуту');
      expect(pluralMin(22), 'минуты');
      expect(pluralMin(25), 'минут');
    });

    test('отзывы: 1 отзыв, 2 отзыва, 12 отзывов', () {
      expect(pluralReviews(1), 'отзыв');
      expect(pluralReviews(2), 'отзыва');
      expect(pluralReviews(12), 'отзывов');
    });

    test('рубли: 1 рубль, 4 рубля, 5 рублей', () {
      expect(pluralRubles(1), 'рубль');
      expect(pluralRubles(4), 'рубля');
      expect(pluralRubles(5), 'рублей');
    });
  });

  group('formatRetryAfter', () {
    test('меньше минуты — в секундах', () {
      expect(formatRetryAfter(1), '1 секунду');
      expect(formatRetryAfter(5), '5 секунд');
      expect(formatRetryAfter(59), '59 секунд');
    });

    test('ровно минута и больше — в минутах', () {
      expect(formatRetryAfter(60), '1 минуту');
      expect(formatRetryAfter(120), '2 минуты');
      expect(formatRetryAfter(300), '5 минут');
    });

    test('null превращается в 1 минуту (дефолт сервера 60 секунд)', () {
      expect(formatRetryAfter(null), '1 минуту');
    });
  });
}
