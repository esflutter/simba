import 'package:flutter/services.dart';

/// Маска даты ДД.ММ.ГГГГ.
///
/// Каждый сегмент клампится независимо к своему диапазону:
/// день 1..31, месяц 1..12, год в [сегодня.year; сегодня.year+1].
/// Единственная межсегментная связь — день не может превышать длину
/// введённого месяца (31.04 → 30.04, 31.02 → 28/29.02).
class DateMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var raw = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (raw.length > 8) raw = raw.substring(0, 8);

    // Backspace по пунктуации: цифры не изменились — стираем последнюю.
    final oldDigits = oldValue.text.replaceAll(RegExp(r'\D'), '');
    if (newValue.text.length < oldValue.text.length &&
        raw.length == oldDigits.length &&
        raw.isNotEmpty) {
      raw = raw.substring(0, raw.length - 1);
    }

    final now = DateTime.now();

    String day = raw.length >= 2 ? raw.substring(0, 2) : '';
    String month = raw.length >= 4 ? raw.substring(2, 4) : '';
    String year = raw.length == 8 ? raw.substring(4, 8) : '';

    if (day.isNotEmpty) {
      day = int.parse(day).clamp(1, 31).toInt().toString().padLeft(2, '0');
    }
    if (month.isNotEmpty) {
      final mn = int.parse(month).clamp(1, 12).toInt();
      month = mn.toString().padLeft(2, '0');
      // День не должен превышать длину месяца. Если год ещё не введён —
      // используем сегодняшний для расчёта (важно для февраля).
      final yn = year.isNotEmpty
          ? int.parse(year).clamp(now.year, now.year + 1).toInt()
          : now.year;
      final lastDay = DateTime(yn, mn + 1, 0).day;
      final dn = int.parse(day);
      if (dn > lastDay) {
        day = lastDay.toString().padLeft(2, '0');
      }
    }
    if (year.isNotEmpty) {
      final yn = int.parse(year).clamp(now.year, now.year + 1).toInt();
      year = yn.toString().padLeft(4, '0');
      // Финальная подстраховка: день после уточнения года (29 февраля).
      final mn = int.parse(month);
      final lastDay = DateTime(yn, mn + 1, 0).day;
      final dn = int.parse(day);
      if (dn > lastDay) {
        day = lastDay.toString().padLeft(2, '0');
      }
    }

    final buf = StringBuffer();
    if (raw.length <= 2) {
      buf.write(raw.length >= 2 ? day : raw);
    } else if (raw.length <= 4) {
      buf.write(day);
      buf.write('.');
      buf.write(raw.length >= 4 ? month : raw.substring(2));
    } else {
      buf.write(day);
      buf.write('.');
      buf.write(month);
      buf.write('.');
      buf.write(raw.length == 8 ? year : raw.substring(4));
    }

    final t = buf.toString();
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

/// Маска времени ЧЧ:ММ. Часы клампятся к [0; 23], минуты — к [0; 59].
class TimeMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var raw = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (raw.length > 4) raw = raw.substring(0, 4);

    final oldDigits = oldValue.text.replaceAll(RegExp(r'\D'), '');
    if (newValue.text.length < oldValue.text.length &&
        raw.length == oldDigits.length &&
        raw.isNotEmpty) {
      raw = raw.substring(0, raw.length - 1);
    }

    String hour = raw.length >= 2 ? raw.substring(0, 2) : '';
    String minute = raw.length == 4 ? raw.substring(2, 4) : '';

    if (hour.isNotEmpty) {
      hour = int.parse(hour).clamp(0, 23).toInt().toString().padLeft(2, '0');
    }
    if (minute.isNotEmpty) {
      minute = int.parse(minute).clamp(0, 59).toInt().toString().padLeft(2, '0');
    }

    final buf = StringBuffer();
    if (raw.length <= 2) {
      buf.write(raw.length >= 2 ? hour : raw);
    } else {
      buf.write(hour);
      buf.write(':');
      buf.write(raw.length == 4 ? minute : raw.substring(2));
    }

    final t = buf.toString();
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

/// Парсит ДД.ММ.ГГГГ → DateTime. Полагается, что формат уже проклампован
/// маской; здесь просто вытащить числа и собрать DateTime.
DateTime? parseRuDate(String s) {
  if (s.length != 10) return null;
  final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(s);
  if (m == null) return null;
  final day = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final year = int.parse(m.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final dt = DateTime(year, month, day);
  if (dt.month != month || dt.day != day) return null;
  return dt;
}

/// Минимальная и максимальная сумма заказа (₽). На бэке зеркалятся в схеме
/// `orders.price_rub` (min/max) — если меняешь здесь, проверь миграцию 019.
const kPriceMin = 100;
const kPriceMax = 99999999;

String _withThousands(String digits) {
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Форматирует целую сумму в строку «1 500 ₽» (или пусто при `n == 0`).
String formatRub(int n) {
  if (n <= 0) return '';
  return '${_withThousands(n.toString())} ₽';
}

/// Форматирует рейтинг — одна цифра после запятой, разделитель русский («4,5»).
/// Используется на всех экранах с рейтингом, чтобы один и тот же рейтинг
/// не показывался то с точкой, то с запятой в зависимости от экрана.
String formatRating(double r) {
  return r.toStringAsFixed(1).replaceAll('.', ',');
}

/// Маска цены: «1 500 ₽». Знак ₽ автоматически появляется при первой цифре
/// и пропадает, когда поле пустое. Курсор всегда стоит перед « ₽».
/// Сумма ограничена сверху [kPriceMax]; ведущие нули съедаются;
/// между разрядами тысяч ставится пробел.
class RubFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      digits = digits.replaceFirst(RegExp(r'^0+'), '');
    }
    if (digits.isEmpty) {
      return const TextEditingValue();
    }
    final n = int.tryParse(digits) ?? 0;
    if (n > kPriceMax) digits = kPriceMax.toString();
    final withSep = _withThousands(digits);
    final t = '$withSep ₽';
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: withSep.length),
    );
  }
}

/// Парсит ЧЧ:ММ → (h, m).
({int hour, int minute})? parseRuTime(String s) {
  if (s.length != 5) return null;
  final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final hh = int.parse(m.group(1)!);
  final mm = int.parse(m.group(2)!);
  if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return null;
  return (hour: hh, minute: mm);
}
