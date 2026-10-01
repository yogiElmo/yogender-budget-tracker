import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../util/format.dart';

/// Every expense over a chosen period, searchable by category or note,
/// filterable by Needs / Wants / Savings, grouped by day.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

enum _Range { thisWeek, lastWeek, thisMonth, lastMonth, last3Months, custom }

const _rangeLabels = {
  _Range.thisWeek: 'This week',
  _Range.lastWeek: 'Last week',
  _Range.thisMonth: 'This month',
  _Range.lastMonth: 'Last month',
  _Range.last3Months: 'Last 3 months',
  _Range.custom: 'Pick dates',
};

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();
  _Range _range = _Range.thisMonth;
  DateTimeRange? _custom;
  String? _groupId; // null = all
  late Future<(List<Group>, List<Category>)> _catalog = Repo.loadCatalog();
  late Future<List<Expense>> _expenses = _load();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  (DateTime, DateTime) get _bounds {
    final today = dateOnly(DateTime.now());
    final ws = weekStartOf(today);
    return switch (_range) {
      _Range.thisWeek => (ws, addDays(ws, 6)),
      _Range.lastWeek => (addDays(ws, -7), addDays(ws, -1)),
      _Range.thisMonth => (DateTime(today.year, today.month, 1), DateTime(today.year, today.month + 1, 0)),
      _Range.lastMonth => (DateTime(today.year, today.month - 1, 1), DateTime(today.year, today.month, 0)),
      _Range.last3Months => (DateTime(today.year, today.month - 2, 1), today),
      _Range.custom => (_custom!.start, _custom!.end),
    };
  }

  Future<List<Expense>> _load() {
    final (from, to) = _bounds;
    return Repo.loadExpenses(from, to);
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _expenses = next;
      _catalog = Repo.loadCatalog();
    });
    await next;
  }

  Future<void> _pickRange(_Range r) async {
    if (r == _Range.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange: _custom,
      );
      if (picked == null) return;
      _custom = DateTimeRange(start: dateOnly(picked.start), end: dateOnly(picked.end));
    }
    setState(() => _range = r);
    _reload();
  }

  Future<void> _confirmDelete(Expense e, String categoryName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text('${formatCents(e.amountCents)} · $categoryName · ${friendlyDate(e.spentOn)}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Repo.deleteExpense(e.id);
      messenger.showSnackBar(SnackBar(
        content: Text('Deleted ${formatCents(e.amountCents)}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await Repo.restoreExpense(e.id);
            _reload();
          },
        ),
      ));
      _reload();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t delete — try again')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: FutureBuilder<(List<Group>, List<Category>)>(
        future: _catalog,
        builder: (context, catSnap) {
          final groups = catSnap.data?.$1 ?? const <Group>[];
          final cats = {for (final c in catSnap.data?.$2 ?? const <Category>[]) c.id: c};
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search category or note',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.close), onPressed: _search.clear),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final r in _Range.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(r == _Range.custom && _custom != null && _range == r
                              ? '${friendlyDate(_custom!.start)} – ${friendlyDate(_custom!.end)}'
                              : _rangeLabels[r]!),
                          selected: _range == r,
                          onSelected: (_) => _pickRange(r),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: _groupId == null,
                        onSelected: (_) => setState(() => _groupId = null),
                      ),
                    ),
                    for (final g in groups)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(g.name),
                          selected: _groupId == g.id,
                          onSelected: (_) => setState(() => _groupId = _groupId == g.id ? null : g.id),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Expense>>(
                  future: _expenses,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Couldn\'t load your history.'),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _reload, child: const Text('Try again')),
                        ]),
                      );
                    }
                    if (!snap.hasData || !catSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return RefreshIndicator(
                      onRefresh: _reload,
                      child: _results(snap.data!, cats, theme),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _results(List<Expense> all, Map<String, Category> cats, ThemeData theme) {
    final scheme = theme.colorScheme;
    final q = _search.text.trim().toLowerCase();
    final shown = all.where((e) {
      final cat = cats[e.categoryId];
      if (_groupId != null && cat?.groupId != _groupId) return false;
      if (q.isEmpty) return true;
      return (cat?.name.toLowerCase().contains(q) ?? false) ||
          (e.note?.toLowerCase().contains(q) ?? false);
    }).toList();
    final total = shown.fold<int>(0, (s, e) => s + e.amountCents);

    // Group by day, newest first (already sorted by the query).
    final days = <DateTime, List<Expense>>{};
    for (final e in shown) {
      days.putIfAbsent(dateOnly(e.spentOn), () => []).add(e);
    }

    final (from, to) = _bounds;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shortRange(from, to), style: theme.textTheme.labelLarge),
                      Text('${shown.length} ${shown.length == 1 ? 'expense' : 'expenses'}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(formatCents(total),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(q.isEmpty ? 'Nothing logged in this period.' : 'No matches for "$q".',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        for (final entry in days.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Row(
              children: [
                Text(
                    '${friendlyDate(entry.key)}${entry.key.year != DateTime.now().year ? ' ${entry.key.year}' : ''}',
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(formatCents(entry.value.fold(0, (s, e) => s + e.amountCents)),
                    style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          for (final e in entry.value)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 4),
              title: Text(cats[e.categoryId]?.name ?? 'Unknown',
                  style: theme.textTheme.bodyLarge),
              subtitle: e.note == null ? null : Text(e.note!),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatCents(e.amountCents), style: theme.textTheme.titleMedium),
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(Icons.delete_outline, color: scheme.onSurfaceVariant),
                    onPressed: () => _confirmDelete(e, cats[e.categoryId]?.name ?? 'Unknown'),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
