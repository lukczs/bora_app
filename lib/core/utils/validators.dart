String onlyDigits(String v) => v.replaceAll(RegExp(r'\D'), '');

/// Valida CPF pelos dígitos verificadores.
bool isValidCpf(String input) {
  final cpf = onlyDigits(input);
  if (cpf.length != 11 || RegExp(r'^(\d)\1{10}$').hasMatch(cpf)) return false;

  int digit(int length) {
    var sum = 0;
    for (var i = 0; i < length; i++) {
      sum += int.parse(cpf[i]) * (length + 1 - i);
    }
    final r = (sum * 10) % 11;
    return r == 10 ? 0 : r;
  }

  return digit(9) == int.parse(cpf[9]) && digit(10) == int.parse(cpf[10]);
}

/// Celular brasileiro: DDD + 9 dígitos começando em 9.
bool isValidBrMobile(String input) {
  final d = onlyDigits(input);
  return d.length == 11 && d[2] == '9';
}

/// (61) 99999-9999 -> +5561999999999
String toE164Br(String input) => '+55${onlyDigits(input)}';

DateTime? parseBrDate(String input) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(input);
  if (m == null) return null;
  final d = int.parse(m[1]!), mo = int.parse(m[2]!), y = int.parse(m[3]!);
  final date = DateTime(y, mo, d);
  if (date.day != d || date.month != mo) return null;
  return date;
}

bool isAdult(DateTime birth) {
  final eighteen = DateTime(birth.year + 18, birth.month, birth.day);
  return !eighteen.isAfter(DateTime.now());
}
