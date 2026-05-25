import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simba/core/utils/ru_phone_formatter.dart';

TextEditingValue _apply(String typed, {String previous = ''}) {
  final fmt = RuPhoneFormatter();
  return fmt.formatEditUpdate(
    TextEditingValue(text: previous),
    TextEditingValue(
      text: typed,
      selection: TextSelection.collapsed(offset: typed.length),
    ),
  );
}

void main() {
  group('RuPhoneFormatter — базовое форматирование', () {
    test('пустой ввод → "+7" (форматтер всегда держит префикс)', () {
      final res = _apply('');
      expect(res.text, '+7');
    });

    test('одна цифра вне +7 → префикс и первая цифра кода', () {
      // Юзер ввёл «9» — форматтер нормализует в «79» (видит, что нет
      // ведущего 7), и сразу открывает скобку для кода города.
      final res = _apply('9');
      expect(res.text, '+7 (9');
    });

    test('+7 + 3 цифры → "+7 (999"', () {
      final res = _apply('+7999');
      expect(res.text, '+7 (999)');
    });

    test('+7 + 7 цифр → "+7 (999) 123-4"', () {
      // d.length = 8 (включая лидирующий 7). substring(4,7)='123',
      // substring(7,8)='4'. Тире вставляется уже на 4-й цифре после
      // скобок — формат «xxx-xx-xx».
      final res = _apply('+79991234');
      expect(res.text, '+7 (999) 123-4');
    });

    test('+7 + 9 цифр → "+7 (999) 123-45-6"', () {
      final res = _apply('+7999123456');
      expect(res.text, '+7 (999) 123-45-6');
    });

    test('+7 + 10 цифр → полный номер "+7 (999) 123-45-67"', () {
      final res = _apply('+79991234567');
      expect(res.text, '+7 (999) 123-45-67');
    });
  });

  group('RuPhoneFormatter — нормализация префиксов', () {
    test('начинается на 8 → нормализуется в 7', () {
      final res = _apply('89991234567');
      expect(res.text, '+7 (999) 123-45-67');
    });

    test('без +7 (только цифры номера) → префикс добавляется', () {
      final res = _apply('9991234567');
      expect(res.text, '+7 (999) 123-45-67');
    });

    test('лишние цифры за 11 — отбрасываются', () {
      final res = _apply('+799912345678901234');
      expect(res.text, '+7 (999) 123-45-67');
    });
  });

  group('RuPhoneFormatter — backspace через пунктуацию', () {
    test('юзер стёр символ-разделитель — снимается последняя цифра', () {
      // Был '+7 (999) 123', юзер тапнул на курсор между скобкой и пробелом
      // и стёр пробел/скобку. Текст укоротился на 1 символ, но количество
      // цифр осталось прежним. Форматтер обязан догнать «реальную» правку
      // и убрать ещё одну цифру — иначе backspace «прыгал бы» через
      // разделитель, выглядит как сломанный.
      final fmt = RuPhoneFormatter();
      const oldValue = TextEditingValue(text: '+7 (999) 123');
      // На 1 короче, но цифр столько же.
      const newValue = TextEditingValue(text: '+7 (999 123');
      final res = fmt.formatEditUpdate(oldValue, newValue);
      // Ожидаем 6 цифр после +7 → "+7 (999) 12".
      expect(res.text, '+7 (999) 12');
    });
  });

  group('RuPhoneFormatter — позиция курсора', () {
    test('курсор всегда в конце форматированной строки', () {
      final res = _apply('+79991234567');
      expect(res.selection.baseOffset, res.text.length);
      expect(res.selection.extentOffset, res.text.length);
    });
  });
}
