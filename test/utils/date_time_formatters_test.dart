import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simba/core/utils/date_time_formatters.dart';

TextEditingValue _applyDate(String typed, {String previous = ''}) {
  final fmt = DateMaskFormatter();
  return fmt.formatEditUpdate(
    TextEditingValue(text: previous),
    TextEditingValue(
      text: typed,
      selection: TextSelection.collapsed(offset: typed.length),
    ),
  );
}

TextEditingValue _applyTime(String typed, {String previous = ''}) {
  final fmt = TimeMaskFormatter();
  return fmt.formatEditUpdate(
    TextEditingValue(text: previous),
    TextEditingValue(
      text: typed,
      selection: TextSelection.collapsed(offset: typed.length),
    ),
  );
}

TextEditingValue _applyRub(String typed, {String previous = ''}) {
  final fmt = RubFormatter();
  return fmt.formatEditUpdate(
    TextEditingValue(text: previous),
    TextEditingValue(
      text: typed,
      selection: TextSelection.collapsed(offset: typed.length),
    ),
  );
}

void main() {
  group('DateMaskFormatter', () {
    test('две цифры → день', () {
      final res = _applyDate('15');
      expect(res.text, '15');
    });

    test('четыре цифры → день.месяц', () {
      final res = _applyDate('1503');
      expect(res.text, '15.03');
    });

    test('восемь цифр → день.месяц.год', () {
      final year = DateTime.now().year;
      final res = _applyDate('1503$year');
      expect(res.text, '15.03.$year');
    });

    test('день клампится к 31', () {
      final res = _applyDate('99');
      expect(res.text, '31');
    });

    test('месяц клампится к 12', () {
      final res = _applyDate('1599');
      expect(res.text, '15.12');
    });

    test('31 февраля → 28/29 февраля в зависимости от года', () {
      final res = _applyDate('3102${DateTime.now().year}');
      // Февраль текущего года — либо 28 либо 29.
      expect(['28.02.${DateTime.now().year}', '29.02.${DateTime.now().year}']
          .contains(res.text), isTrue);
    });

    test('31 апреля → 30 апреля', () {
      final year = DateTime.now().year;
      final res = _applyDate('3104$year');
      expect(res.text, '30.04.$year');
    });

    test('год клампится к [текущий, текущий+1]', () {
      // 9999 → клампится к year + 1. Подаём 8 цифр (день+месяц+год).
      // Месяц делаем '03' чтобы не было конфликта 99→12.
      final res = _applyDate('15039999');
      expect(res.text.endsWith('.${DateTime.now().year + 1}'), isTrue,
          reason: 'actual: ${res.text}');
    });
  });

  group('TimeMaskFormatter', () {
    test('две цифры → часы', () {
      final res = _applyTime('14');
      expect(res.text, '14');
    });

    test('четыре цифры → часы:минуты', () {
      final res = _applyTime('1445');
      expect(res.text, '14:45');
    });

    test('часы клампятся к 23', () {
      final res = _applyTime('99');
      expect(res.text, '23');
    });

    test('минуты клампятся к 59', () {
      final res = _applyTime('1499');
      expect(res.text, '14:59');
    });
  });

  group('parseRuDate', () {
    test('валидная дата', () {
      final dt = parseRuDate('15.03.2026');
      expect(dt, DateTime(2026, 3, 15));
    });

    test('невалидный формат → null', () {
      expect(parseRuDate('15-03-2026'), isNull);
      expect(parseRuDate('15.3.2026'), isNull);
      expect(parseRuDate(''), isNull);
    });

    test('31 февраля → null (несуществующая дата)', () {
      expect(parseRuDate('31.02.2026'), isNull);
    });
  });

  group('parseRuTime', () {
    test('валидное время', () {
      expect(parseRuTime('14:30'), (hour: 14, minute: 30));
    });

    test('невалидный формат → null', () {
      expect(parseRuTime('14-30'), isNull);
      expect(parseRuTime('4:30'), isNull);
      expect(parseRuTime(''), isNull);
    });

    test('часы > 23 → null', () {
      expect(parseRuTime('24:00'), isNull);
    });

    test('минуты > 59 → null', () {
      expect(parseRuTime('14:60'), isNull);
    });
  });

  group('formatRub', () {
    test('0 → пустая строка', () {
      expect(formatRub(0), '');
    });

    test('1 → 1 ₽', () {
      expect(formatRub(1), '1 ₽');
    });

    test('1500 → 1 500 ₽', () {
      expect(formatRub(1500), '1 500 ₽');
    });

    test('1234567 → 1 234 567 ₽', () {
      expect(formatRub(1234567), '1 234 567 ₽');
    });
  });

  group('formatRating', () {
    test('целое — с запятой', () {
      expect(formatRating(4.0), '4,0');
    });

    test('с десятичной частью', () {
      expect(formatRating(4.5), '4,5');
    });

    test('округление', () {
      expect(formatRating(4.56), '4,6');
    });
  });

  group('RubFormatter', () {
    test('первая цифра → "1 ₽"', () {
      final res = _applyRub('1');
      expect(res.text, '1 ₽');
    });

    test('пустой ввод → пустая строка', () {
      final res = _applyRub('');
      expect(res.text, '');
    });

    test('1500 → "1 500 ₽"', () {
      final res = _applyRub('1500');
      expect(res.text, '1 500 ₽');
    });

    test('ведущие нули съедаются', () {
      final res = _applyRub('00123');
      expect(res.text, '123 ₽');
    });

    test('лимит — kPriceMax', () {
      final res = _applyRub('999999999999');
      expect(res.text.endsWith(' ₽'), isTrue);
      final digits = res.text.replaceAll(RegExp(r'\D'), '');
      expect(int.parse(digits), lessThanOrEqualTo(kPriceMax));
    });
  });
}
