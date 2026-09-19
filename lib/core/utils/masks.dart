import 'package:flutter/services.dart';

/// Máscara simples: '#' = dígito. Ex.: '(##) #####-####', '###.###.###-##', '##/##/####'.
class MaskFormatter extends TextInputFormatter {
  MaskFormatter(this.mask);
  final String mask;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final out = StringBuffer();
    var di = 0;
    for (var i = 0; i < mask.length && di < digits.length; i++) {
      if (mask[i] == '#') {
        out.write(digits[di++]);
      } else {
        out.write(mask[i]);
      }
    }
    final text = out.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
