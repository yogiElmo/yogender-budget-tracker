// Pure calculations behind the insights screen, kept free of Flutter and
// Supabase so they can be tested directly.

import '../util/format.dart';
import 'repo.dart';

class BudgetVersion {
  final DateTime effectiveFrom;
  final int weeklyCents;
  final Map<String, double> percentByGroup;
  BudgetVersion(this.effectiveFrom, this.weeklyCents, this.percentByGroup);
}

class InsightsInput {
  final List<DateTime> weekStarts; // oldest first; last one is this week
  final List<BudgetVersion> budgets; // oldest first
  final List<Group> groups;
  final List<Category> categories;
  final List<Expense> expenses;
  InsightsInput(this.weekStarts, this.budgets, this.groups, this.categories, this.expenses);
}

class WeekTotal {
  final DateTime weekStart;
  final int spentCents;
  final int budgetCents;
  final bool inProgress;
  WeekTotal(this.weekStart, this.spentCents, this.budgetCents, this.inProgress);
  bool get over => budgetCents > 0 && spentCents > budgetCents;
}

class GroupTotal {
  final Group group;
  final int plannedCents;
  final int spentCents;
  GroupTotal(this.group, this.plannedCents, this.spentCents);
}

class CategoryTotal {
  final Category category;
  final String groupName;
  final int spentCents;
  final int count;
  CategoryTotal(this.category, this.groupName, this.spentCents, this.count);
}

class Insights {
  final List<WeekTotal> weeks;
  final List<GroupTotal> groups;
  final List<CategoryTotal> categories; // biggest first
  final int totalSpentCents;
  final int totalBudgetCents;
  final Expense? biggest;
  final int daysCounted;

  Insights._(this.weeks, this.groups, this.categories, this.totalSpentCents, this.totalBudgetCents,
      this.biggest, this.daysCounted);

  int get completeWeeks => weeks.where((w) => !w.inProgress).length;
  int get averagePerWeekCents {
    final done = weeks.where((w) => !w.inProgress).toList();
    if (done.isEmpty) return 0;
    return (done.fold(0, (s, w) => s + w.spentCents) / done.length).round();
  }

  int get averagePerDayCents => daysCounted == 0 ? 0 : (totalSpentCents / daysCounted).round();
  int get weeksOver => weeks.where((w) => !w.inProgress && w.over).length;

  /// The budget in force for a week: the newest version starting on or before it,
  /// or the oldest one if the week predates them all.
  static BudgetVersion? budgetFor(List<BudgetVersion> budgets, DateTime weekStart) {
    if (budgets.isEmpty) return null;
    BudgetVersion? found;
    for (final b in budgets) {
      if (!b.effectiveFrom.isAfter(weekStart)) found = b;
    }
    return found ?? budgets.first;
  }

  factory Insights.from(InsightsInput input, {DateTime? today}) {
    final now = dateOnly(today ?? DateTime.now());
    final cats = {for (final c in input.categories) c.id: c};
    final groupNames = {for (final g in input.groups) g.id: g.name};

    final weekOf = <DateTime, int>{};
    for (final e in input.expenses) {
      final ws = weekStartOf(e.spentOn);
      weekOf[ws] = (weekOf[ws] ?? 0) + e.amountCents;
    }

    final weeks = <WeekTotal>[];
    final planned = <String, int>{};
    var totalBudget = 0;
    for (final ws in input.weekStarts) {
      final b = budgetFor(input.budgets, ws);
      final budget = b?.weeklyCents ?? 0;
      totalBudget += budget;
      for (final g in input.groups) {
        planned[g.id] = (planned[g.id] ?? 0) + (budget * (b?.percentByGroup[g.id] ?? 0) / 100).round();
      }
      weeks.add(WeekTotal(ws, weekOf[ws] ?? 0, budget, !addDays(ws, 6).isBefore(now)));
    }

    final spentByGroup = <String, int>{};
    final byCat = <String, (int, int)>{};
    Expense? biggest;
    for (final e in input.expenses) {
      final g = cats[e.categoryId]?.groupId;
      if (g != null) spentByGroup[g] = (spentByGroup[g] ?? 0) + e.amountCents;
      final (sum, n) = byCat[e.categoryId] ?? (0, 0);
      byCat[e.categoryId] = (sum + e.amountCents, n + 1);
      if (biggest == null || e.amountCents > biggest.amountCents) biggest = e;
    }

    final categories = [
      for (final entry in byCat.entries)
        if (cats[entry.key] != null)
          CategoryTotal(cats[entry.key]!, groupNames[cats[entry.key]!.groupId] ?? '',
              entry.value.$1, entry.value.$2),
    ]..sort((a, b) => b.spentCents.compareTo(a.spentCents));

    // Count days from the first logged expense, so weeks before you started
    // using the app don't drag the daily average down.
    DateTime? first;
    for (final e in input.expenses) {
      final d = dateOnly(e.spentOn);
      if (first == null || d.isBefore(first)) first = d;
    }
    final days = first == null || now.isBefore(first) ? 0 : now.difference(first).inDays + 1;

    return Insights._(
      weeks,
      [
        for (final g in [...input.groups]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
          GroupTotal(g, planned[g.id] ?? 0, spentByGroup[g.id] ?? 0),
      ],
      categories,
      input.expenses.fold(0, (s, e) => s + e.amountCents),
      totalBudget,
      biggest,
      days,
    );
  }
}
