// Money and date helpers. Money is always whole cents; weeks start on Tuesday.

String formatCents(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final part = abs % 100;
  final wholeStr = whole.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
  final text = part == 0 ? '\$$wholeStr' : '\$$wholeStr.${part.toString().padLeft(2, '0')}';
  return negative ? '-$text' : text;
}

/// Parses "5", "5.4", "$12.50", "1,200" into cents. Returns null if not a positive amount.
int? parseCents(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\$,\s]'), '');
  final value = double.tryParse(cleaned);
  if (value == null || value <= 0) return null;
  return (value * 100).round();
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day arithmetic. Unlike adding a Duration, this stays on midnight
/// when daylight saving starts or ends.
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// The Tuesday (payday) that starts the budget week containing [d].
DateTime weekStartOf(DateTime d) {
  final offset = (d.weekday - DateTime.tuesday + 7) % 7;
  return addDays(d, -offset);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today", "Yesterday", or "Sat 27 Sep".
String friendlyDate(DateTime d) {
  final today = dateOnly(DateTime.now());
  final day = dateOnly(d);
  if (day == today) return 'Today';
  if (day == addDays(today, -1)) return 'Yesterday';
  return '${_weekdayShort[day.weekday - 1]} ${day.day} ${_monthShort[day.month - 1]}';
}

String shortRange(DateTime start, DateTime end) =>
    '${start.day} ${_monthShort[start.month - 1]} – ${end.day} ${_monthShort[end.month - 1]}';

/// Australian financial year start (1 July) for the year containing [d].
DateTime financialYearStart(DateTime d) =>
    d.month >= 7 ? DateTime(d.year, 7, 1) : DateTime(d.year - 1, 7, 1);
