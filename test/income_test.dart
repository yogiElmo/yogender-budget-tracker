import 'package:budget_tracker/data/repo.dart';
import 'package:budget_tracker/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

IncomeWeek week(List<(int, int)> income, {int moved = 0}) => IncomeWeek(
      DateTime(2026, 9, 29),
      60000, // $600 budget
      const [],
      [for (final (amt, tax) in income) Income('i', 's', amt, tax, DateTime(2026, 9, 29), null)],
      moved,
      const [],
    );

void main() {
  test('residual is after-tax income above the budget', () {
    final w = week([(70000, 0), (20000, 3000)]); // $900 in, $30 tax
    expect(w.netCents, 87000);
    expect(w.residualCents, 27000); // $870 - $600
    expect(w.residualLeftCents, 27000);
  });

  test('money moved to jars reduces what is left', () {
    final w = week([(80000, 0)], moved: 15000);
    expect(w.residualCents, 20000);
    expect(w.residualLeftCents, 5000);
  });

  test('no residual when income is under budget', () {
    final w = week([(40000, 0)]);
    expect(w.residualCents, 0);
    expect(w.residualLeftCents, 0);
  });

  test('tax is only set aside from side income', () {
    final pay = IncomeSource('p', 'Main pay', 30, false); // rate ignored for regular pay
    final uber = IncomeSource('u', 'Uber', 25, true);
    expect(pay.taxFor(60000), 0);
    expect(uber.taxFor(20000), 5000);
  });

  test('pay and side income are reported separately', () {
    final w = IncomeWeek(
      DateTime(2026, 9, 29),
      60000,
      [IncomeSource('p', 'Main pay', 0, false), IncomeSource('u', 'Uber', 25, true)],
      [
        Income('1', 'p', 60000, 0, DateTime(2026, 9, 29), null),
        Income('2', 'u', 20000, 5000, DateTime(2026, 9, 30), null),
      ],
      0,
      const [],
    );
    expect(w.payCents, 60000);
    expect(w.sideCents, 20000);
    expect(w.taxCents, 5000);
    expect(w.residualCents, 15000); // $600 + $200 - $50 tax - $600 budget
  });

  test('financial year starts on 1 July', () {
    expect(financialYearStart(DateTime(2026, 10, 1)), DateTime(2026, 7, 1));
    expect(financialYearStart(DateTime(2027, 3, 15)), DateTime(2026, 7, 1));
    expect(financialYearStart(DateTime(2026, 7, 1)), DateTime(2026, 7, 1));
  });
}
