import 'package:flutter/services.dart';

/// "(12) 99999-8888" enquanto digita. Só dígitos entram, no máximo 11; com
/// 10 dígitos (fixo) o hífen fica depois do 4º, com 11 depois do 5º.
/// ponytail: sem lib de máscara; é um campo só.
class PhoneMaskFormatter extends TextInputFormatter {
  static String mask(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length > 11) d = d.substring(0, 11);
    final hyphenAfter = d.length > 10 ? 7 : 6; // índice do dígito, contando o DDD
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 0) b.write('(');
      if (i == 2) b.write(') ');
      if (i == hyphenAfter) b.write('-');
      b.write(d[i]);
    }
    return b.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = mask(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
