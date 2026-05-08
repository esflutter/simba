import 'package:flutter/services.dart';

class RuPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('8')) d = '7${d.substring(1)}';
    if (!d.startsWith('7')) d = '7$d';
    if (d.length > 11) d = d.substring(0, 11);
    // Если пользователь удалил символ, но число цифр не изменилось — он удалил пунктуацию,
    // нужно убрать ещё одну цифру чтобы backspace работал ожидаемо
    final oldDigits = oldValue.text.replaceAll(RegExp(r'\D'), '');
    if (newValue.text.length < oldValue.text.length && d.length == oldDigits.length && d.length > 1) {
      d = d.substring(0, d.length - 1);
    }
    final buf = StringBuffer();
    buf.write('+7');
    if (d.length > 1) buf.write(' (${d.substring(1, d.length.clamp(1, 4))}');
    if (d.length >= 4) buf.write(')');
    if (d.length >= 5) buf.write(' ${d.substring(4, d.length.clamp(4, 7))}');
    if (d.length >= 8) buf.write('-${d.substring(7, d.length.clamp(7, 9))}');
    if (d.length >= 10) buf.write('-${d.substring(9, d.length.clamp(9, 11))}');
    final t = buf.toString();
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}
