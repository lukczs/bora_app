String formatCents(int cents) {
  final reais = cents ~/ 100;
  final c = (cents % 100).toString().padLeft(2, '0');
  return 'R\$ $reais,$c';
}

String formatKm(int meters) => '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

String _two(int n) => n.toString().padLeft(2, '0');

const _weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

String weekdayShort(int weekday) => _weekdays[weekday - 1];

String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// "Hoje, 18:00" / "Amanhã, 07:30" / "ter, 22/09 às 18:00"
String formatWhen(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Hoje, ${formatTime(d)}';
  if (diff == 1) return 'Amanhã, ${formatTime(d)}';
  return '${weekdayShort(d.weekday)}, ${_two(d.day)}/${_two(d.month)} às ${formatTime(d)}';
}

String formatRecurring(List<int> weekdays) {
  if (weekdays.isEmpty) return '';
  final sorted = [...weekdays]..sort();
  return 'Repete: ${sorted.map(weekdayShort).join(', ')}';
}
