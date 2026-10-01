import 'package:budget_tracker/data/repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final needs = Group('n', 'Needs', 1, 0);
  final wants = Group('w', 'Wants', 2, 0);
  final rent = Category('rent', 'Rent', 'n');
  final coffee = Category('coffee', 'Coffee', 'w');

  Expense e(String cat, int cents, DateTime on) => Expense('$cat$cents$on', cents, cat, on, null);

  test('weekly totals, plan vs actual and top categories', () {
    final input = InsightsInput(
      [DateTime(2026, 9, 22), DateTime(2026, 9, 29)], // two Tuesdays
      [
        BudgetVersion(DateTime(2026, 9, 1), 60000, {'n': 50, 'w': 20}),
        BudgetVersion(DateTime(2026, 9, 29), 70000, {'n': 50, 'w': 20}), // raised this week
      ],
      [needs, wants],
      [rent, coffee],
      [
        e('rent', 30000, DateTime(2026, 9, 22)),
        e('coffee', 4000, DateTime(2026, 9, 25)),
        e('coffee', 50000, DateTime(2026, 9, 28)), // pushes last week over
        e('rent', 30000, DateTime(2026, 9, 29)),
      ],
    );
    final i = Insights.from(input, today: DateTime(2026, 10, 1));

    expect(i.weeks.map((w) => w.spentCents), [84000, 30000]);
    expect(i.weeks.map((w) => w.budgetCents), [60000, 70000]); // each week uses its own budget
    expect(i.weeks.first.over, isTrue);
    expect(i.weeks.last.inProgress, isTrue);
    expect(i.weeksOver, 1);
    expect(i.averagePerWeekCents, 84000); // only finished weeks count

    expect(i.groups.first.plannedCents, 30000 + 35000); // 50% of 600 + 50% of 700
    expect(i.groups.first.spentCents, 60000);
    expect(i.groups.last.spentCents, 54000);

    expect(i.categories.map((c) => c.category.name), ['Rent', 'Coffee']); // biggest first
    expect(i.categories.first.count, 2);
    expect(i.biggest!.amountCents, 50000);
    expect(i.daysCounted, 10); // 22 Sep to 1 Oct
  });

  test('a week before any budget uses the oldest budget', () {
    final b = [BudgetVersion(DateTime(2026, 9, 29), 60000, const {})];
    expect(Insights.budgetFor(b, DateTime(2026, 9, 1))!.weeklyCents, 60000);
  });
}
