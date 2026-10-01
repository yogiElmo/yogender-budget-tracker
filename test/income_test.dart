import 'package:budget_tracker/data/repo.dart';
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
}
