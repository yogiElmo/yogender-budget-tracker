import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../util/format.dart';

/// Where the money actually went, compared with the plan.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _weeks = 4;
  late Future<InsightsInput> _future = Repo.loadInsights(_weeks);

  Future<void> _reload() async {
    final next = Repo.loadInsights(_weeks);
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 4, label: Text('4 weeks')),
                ButtonSegment(value: 8, label: Text('8 weeks')),
                ButtonSegment(value: 12, label: Text('12 weeks')),
              ],
              selected: {_weeks},
              onSelectionChanged: (s) {
                _weeks = s.first;
                _reload();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<InsightsInput>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Couldn\'t load insights.'),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _reload, child: const Text('Try again')),
                    ]),
                  );
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                return RefreshIndicator(
                  onRefresh: _reload,
                  child: _body(Insights.from(snap.data!)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, {String? subtitle}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null)
            Text(subtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _body(Insights i) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (i.totalSpentCents == 0) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No expenses in the last $_weeks weeks yet. Log a few and your patterns will show up here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ]);
    }

    final cats = i.categories.take(8).toList();
    final topCat = cats.isEmpty ? 1 : cats.first.spentCents;
    final done = i.completeWeeks;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        // Headline numbers
        Row(children: [
          _Stat(
            label: 'Avg per week',
            value: done == 0 ? '—' : formatCents(i.averagePerWeekCents),
            note: done == 0 ? 'after first full week' : 'over $done full ${done == 1 ? 'week' : 'weeks'}',
          ),
          const SizedBox(width: 8),
          _Stat(label: 'Avg per day', value: formatCents(i.averagePerDayCents)),
          const SizedBox(width: 8),
          _Stat(
            label: 'Over budget',
            value: done == 0 ? '—' : '${i.weeksOver} of $done',
            note: 'weeks',
            warn: i.weeksOver > 0,
          ),
        ]),

        // Weekly trend
        _section('Spending each week',
            subtitle: 'Bars are what you spent; the line is that week\'s budget.'),
        _WeekChart(weeks: i.weeks),

        // Plan vs actual
        _section('Plan vs actual',
            subtitle: 'Planned is your split of each week\'s budget over these $_weeks weeks.'),
        for (final g in i.groups) _PlanRow(total: g),

        // Top categories
        _section('Top categories',
            subtitle: '${formatCents(i.totalSpentCents)} spent in total'),
        for (final c in cats)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: c.category.name, style: theme.textTheme.bodyLarge),
                      TextSpan(
                          text: '  ${c.groupName} · ${c.count}×',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ])),
                  ),
                  Text(formatCents(c.spentCents), style: theme.textTheme.titleSmall),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(c.spentCents * 100 / i.totalSpentCents).round()}%',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: c.spentCents / topCat,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),

        if (i.biggest != null) ...[
          _section('Biggest single expense'),
          Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest,
            child: ListTile(
              title: Text(i.categories
                      .where((c) => c.category.id == i.biggest!.categoryId)
                      .firstOrNull
                      ?.category
                      .name ??
                  'Expense'),
              subtitle: Text([
                friendlyDate(i.biggest!.spentOn),
                if (i.biggest!.note != null) i.biggest!.note!,
              ].join(' · ')),
              trailing:
                  Text(formatCents(i.biggest!.amountCents), style: theme.textTheme.titleMedium),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String? note;
  final bool warn;
  const _Stat({required this.label, required this.value, this.note, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: warn ? scheme.errorContainer : scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (note != null)
                Text(note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  final List<WeekTotal> weeks;
  const _WeekChart({required this.weeks});

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = weeks.fold<int>(1, (m, w) => [m, w.spentCents, w.budgetCents].reduce((a, b) => a > b ? a : b));
    const chartHeight = 150.0;
    final showAmounts = weeks.length <= 8;
    final labelEvery = weeks.length <= 8 ? 1 : 2;

    return SizedBox(
      height: chartHeight + (showAmounts ? 56 : 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var idx = 0; idx < weeks.length; idx++)
            Expanded(
              child: Builder(builder: (context) {
                final w = weeks[idx];
                final barH = chartHeight * w.spentCents / top;
                final budgetY = chartHeight * w.budgetCents / top;
                final color = w.over ? scheme.error : scheme.primary;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (showAmounts)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            w.spentCents == 0 ? '' : '\$${(w.spentCents / 100).round()}',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: chartHeight,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Container(
                              height: barH < 2 && w.spentCents > 0 ? 2 : barH,
                              decoration: BoxDecoration(
                                color: w.inProgress ? color.withValues(alpha: 0.45) : color,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                            if (w.budgetCents > 0)
                              Positioned(
                                bottom: budgetY - 1,
                                left: -3,
                                right: -3,
                                child: Container(height: 2, color: scheme.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 30,
                        child: idx % labelEvery == (weeks.length - 1) % labelEvery
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  w.inProgress
                                      ? 'Now'
                                      : '${w.weekStart.day}\n${_months[w.weekStart.month - 1]}',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  final GroupTotal total;
  const _PlanRow({required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final planned = total.plannedCents;
    final spent = total.spentCents;
    final over = planned > 0 && spent > planned;
    final pct = planned == 0 ? null : (spent * 100 / planned).round();
    final isSavings = total.group.name.toLowerCase().contains('saving');

    String note;
    if (planned == 0) {
      note = 'No share of the budget planned';
    } else if (isSavings) {
      note = spent >= planned
          ? 'On target — ${formatCents(spent)} put towards savings'
          : '${formatCents(planned - spent)} short of the savings plan';
    } else {
      note = over
          ? '${formatCents(spent - planned)} over plan'
          : '${formatCents(planned - spent)} under plan';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(total.group.name, style: theme.textTheme.titleSmall),
            const Spacer(),
            Text('${formatCents(spent)} of ${formatCents(planned)}',
                style: theme.textTheme.bodyMedium),
            if (pct != null)
              SizedBox(
                width: 48,
                child: Text('$pct%',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: over && !isSavings ? scheme.error : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: planned == 0 ? 0 : (spent / planned).clamp(0, 1),
              backgroundColor: scheme.surfaceContainerHighest,
              color: over && !isSavings ? scheme.error : scheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(note,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: over && !isSavings ? scheme.error : scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
