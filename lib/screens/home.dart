import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../util/format.dart';
import 'add_expense.dart';
import 'payday.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onSignOut;
  const HomeScreen({super.key, required this.onSignOut});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<WeekData> _future = _firstLoad();
  final _hidden = <String>{}; // swiped away, waiting on the server

  Future<WeekData> _firstLoad() async {
    await Repo.seed();
    return Repo.loadWeek(DateTime.now());
  }

  Future<void> _reload() async {
    final next = Repo.loadWeek(DateTime.now());
    setState(() => _future = next);
    await next;
  }

  Future<void> _openAdd(WeekData data) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AddExpenseScreen(groups: data.groups, categories: data.categories),
      ),
    );
    if (!mounted) return;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    _reload(); // also picks up any new categories, even if nothing was saved
  }

  Future<void> _openPayday() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaydayScreen()));
    if (mounted) _reload();
  }

  Future<void> _confirmDelete(Expense e, String categoryName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text('${formatCents(e.amountCents)} · $categoryName · ${friendlyDate(e.spentOn)}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) _delete(e);
  }

  Future<void> _delete(Expense e) async {
    setState(() => _hidden.add(e.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Repo.deleteExpense(e.id);
      messenger.showSnackBar(SnackBar(
        content: Text('Deleted ${formatCents(e.amountCents)}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await Repo.restoreExpense(e.id);
            _hidden.remove(e.id);
            _reload();
          },
        ),
      ));
      await _reload();
      _hidden.remove(e.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hidden.remove(e.id));
      messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t delete — try again')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeekData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(data == null ? 'This week' : shortRange(data.weekStart, data.weekEnd)),
            actions: [
              IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout),
                onPressed: widget.onSignOut,
              ),
            ],
          ),
          floatingActionButton: data == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _openAdd(data),
                  icon: const Icon(Icons.add),
                  label: const Text('Add expense'),
                ),
          body: switch (snap) {
            _ when snap.hasError => _ErrorView(error: snap.error!, onRetry: _reload),
            _ when data == null => const Center(child: CircularProgressIndicator()),
            _ => RefreshIndicator(
                onRefresh: _reload,
                child: _Dashboard(
                  data: data,
                  expenses: data.expenses.where((e) => !_hidden.contains(e.id)).toList(),
                  onDelete: _delete,
                  onDeleteTap: (e) => _confirmDelete(
                      e, data.categoryById[e.categoryId]?.name ?? 'Unknown'),
                  onAdd: () => _openAdd(data),
                  onPayday: _openPayday,
                ),
              ),
          },
        );
      },
    );
  }
}

class _Dashboard extends StatelessWidget {
  final WeekData data;
  final List<Expense> expenses;
  final void Function(Expense) onDelete; // swipe: instant, with Undo
  final void Function(Expense) onDeleteTap; // bin button: asks first
  final VoidCallback onAdd;
  final VoidCallback onPayday;
  const _Dashboard(
      {required this.data,
      required this.expenses,
      required this.onDelete,
      required this.onDeleteTap,
      required this.onAdd,
      required this.onPayday});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cats = data.categoryById;
    final today = dateOnly(DateTime.now());

    final spent = expenses.fold<int>(0, (sum, e) => sum + e.amountCents);
    final left = data.weeklyCents - spent;
    final todayTotal = expenses
        .where((e) => dateOnly(e.spentOn) == today)
        .fold<int>(0, (sum, e) => sum + e.amountCents);
    final loggedDays = {for (final e in expenses) dateOnly(e.spentOn)};
    final spentByGroup = <String, int>{};
    for (final e in expenses) {
      final g = cats[e.categoryId]?.groupId;
      if (g != null) spentByGroup[g] = (spentByGroup[g] ?? 0) + e.amountCents;
    }
    final groups = [...data.groups]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final nudge = todayTotal == 0 && DateTime.now().hour >= 18;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // Left this week
        Card(
          elevation: 0,
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(left >= 0 ? 'Left this week' : 'Over budget',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: scheme.onPrimaryContainer)),
                const SizedBox(height: 4),
                Text(formatCents(left.abs()),
                    style: theme.textTheme.displaySmall?.copyWith(
                        color: left >= 0 ? scheme.onPrimaryContainer : scheme.error,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: data.weeklyCents == 0 ? 0 : (spent / data.weeklyCents).clamp(0, 1),
                    backgroundColor: scheme.onPrimaryContainer.withValues(alpha: 0.12),
                    color: left >= 0 ? scheme.primary : scheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Spent ${formatCents(spent)} of ${formatCents(data.weeklyCents)}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onPrimaryContainer)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Today + week strip
        Card(
          elevation: 0,
          color: nudge ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: nudge ? onAdd : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Today', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      Text(formatCents(todayTotal), style: theme.textTheme.titleMedium),
                    ],
                  ),
                  if (nudge) ...[
                    const SizedBox(height: 4),
                    Text('Nothing logged yet today — anything to add?',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onTertiaryContainer)),
                  ],
                  const SizedBox(height: 16),
                  _WeekStrip(weekStart: data.weekStart, logged: loggedDays),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Payday transfers
        _PaydayCard(
          toDo: data.transfersToDo,
          done: data.transfersDone,
          isPayday: DateTime.now().weekday == DateTime.tuesday,
          onTap: onPayday,
        ),
        const SizedBox(height: 12),

        // Needs / Wants / Savings
        for (final g in groups)
          _GroupRow(
            name: g.name,
            spent: spentByGroup[g.id] ?? 0,
            allocated: (data.weeklyCents * g.percent / 100).round(),
          ),

        // This week's entries
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('This week', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (expenses.isNotEmpty)
                Text('Tap the bin or swipe left to delete',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        if (expenses.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No expenses yet this week.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        for (final e in expenses)
          Dismissible(
            key: ValueKey(e.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: scheme.errorContainer,
              child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
            ),
            onDismissed: (_) => onDelete(e),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(cats[e.categoryId]?.name ?? 'Unknown'),
              subtitle: Text([friendlyDate(e.spentOn), if (e.note != null) e.note!].join(' · ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatCents(e.amountCents), style: theme.textTheme.titleMedium),
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(Icons.delete_outline, color: scheme.onSurfaceVariant),
                    onPressed: () => onDeleteTap(e),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final DateTime weekStart;
  final Set<DateTime> logged;
  const _WeekStrip({required this.weekStart, required this.logged});

  static const _letters = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = dateOnly(DateTime.now());
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (context) {
            final day = addDays(weekStart, i);
            final done = logged.contains(day);
            final isToday = day == today;
            final future = day.isAfter(today);
            return Column(
              children: [
                Text(_letters[day.weekday - 1],
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: future ? scheme.outline : scheme.onSurfaceVariant,
                        fontWeight: isToday ? FontWeight.w700 : null)),
                const SizedBox(height: 6),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? scheme.primary : Colors.transparent,
                    border: Border.all(
                      color: done
                          ? scheme.primary
                          : future
                              ? scheme.outlineVariant
                              : scheme.outline,
                      width: isToday ? 2 : 1.2,
                    ),
                  ),
                ),
              ],
            );
          }),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  final String name;
  final int spent;
  final int allocated;
  const _GroupRow({required this.name, required this.spent, required this.allocated});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final over = spent > allocated && allocated > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name, style: theme.textTheme.titleSmall),
              const Spacer(),
              Text('${formatCents(spent)} of ${formatCents(allocated)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: over ? scheme.error : scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: allocated == 0 ? 0 : (spent / allocated).clamp(0, 1),
              backgroundColor: scheme.surfaceContainerHighest,
              color: over ? scheme.error : scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Couldn\'t load your budget.', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('$error',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _PaydayCard extends StatelessWidget {
  final int toDo;
  final int done;
  final bool isPayday;
  final VoidCallback onTap;
  const _PaydayCard(
      {required this.toDo, required this.done, required this.isPayday, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final allDone = toDo > 0 && done == toDo;
    final highlight = isPayday && !allDone;
    final subtitle = toDo == 0
        ? 'Set up your weekly transfers'
        : allDone
            ? 'All done this week'
            : '$done of $toDo done${isPayday ? ' — it\'s payday' : ''}';
    return Card(
      elevation: 0,
      color: highlight ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(allDone ? Icons.check_circle : Icons.account_balance_outlined,
            color: allDone ? scheme.primary : null),
        title: const Text('Payday transfers'),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
