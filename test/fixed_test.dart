import 'package:budget_tracker/data/repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FixedExpense f(int cents, String freq) => FixedExpense('', '', cents, '', freq, DateTime(2026), true);

  test('fixed costs convert to a weekly average', () {
    expect(f(30000, 'weekly').weeklyCents, 30000);
    expect(f(6000, 'fortnightly').weeklyCents, 3000);
    expect(f(5200, 'monthly').weeklyCents, 1200); // $52/month = $12/week
  });

  test('expenses created by a fixed expense are marked', () {
    final row = {
      'id': 'e',
      'amount_cents': 30000,
      'category_id': 'c',
      'spent_on': '2026-09-29',
      'note': 'Rent',
    };
    expect(Expense.fromRow({...row, 'recurring_id': 'r'}).isFixed, isTrue);
    expect(Expense.fromRow(row).isFixed, isFalse); // also fine before the column exists
  });
}
