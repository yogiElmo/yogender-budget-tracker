import 'package:budget_tracker/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseCents', () {
    expect(parseCents('5'), 500);
    expect(parseCents('5.4'), 540);
    expect(parseCents('\$12.50'), 1250);
    expect(parseCents('1,200'), 120000);
    expect(parseCents('0.1'), 10);
    expect(parseCents('0'), isNull);
    expect(parseCents(''), isNull);
    expect(parseCents('abc'), isNull);
  });

  test('formatCents', () {
    expect(formatCents(500), '\$5');
    expect(formatCents(540), '\$5.40');
    expect(formatCents(120000), '\$1,200');
    expect(formatCents(-2550), '-\$25.50');
  });

  test('week starts on Tuesday', () {
    // 2026-10-01 is a Thursday -> week starts Tue 2026-09-29
    expect(weekStartOf(DateTime(2026, 10, 1, 15)), DateTime(2026, 9, 29));
    expect(weekStartOf(DateTime(2026, 9, 29)), DateTime(2026, 9, 29)); // Tuesday itself
    expect(weekStartOf(DateTime(2026, 10, 5)), DateTime(2026, 9, 29)); // Monday
    expect(weekStartOf(DateTime(2026, 10, 6)), DateTime(2026, 10, 6)); // next Tuesday
  });

  test('day maths stays on midnight across daylight saving', () {
    // Sydney clocks go forward on Sun 4 Oct 2026
    expect(addDays(DateTime(2026, 9, 29), 6), DateTime(2026, 10, 5));
    expect(addDays(DateTime(2026, 10, 5), -1), DateTime(2026, 10, 4));
  });
}
