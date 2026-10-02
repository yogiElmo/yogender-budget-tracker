import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repo.dart';
import '../util/format.dart';

const _freqLabels = {'weekly': 'Weekly', 'fortnightly': 'Fortnightly', 'monthly': 'Monthly'};

/// Rent, bills and other regular costs. Each one logs itself as an expense on
/// its due date, so the week's budget already accounts for it.
class FixedExpensesScreen extends StatefulWidget {
  const FixedExpensesScreen({super.key});

  @override
  State<FixedExpensesScreen> createState() => _FixedExpensesScreenState();
}

class _FixedExpensesScreenState extends State<FixedExpensesScreen> {
  late Future<FixedData> _future = Repo.loadFixed();

  Future<void> _reload() async {
    final next = Repo.loadFixed();
    setState(() => _future = next);
    await next;
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _edit(FixedData d, FixedExpense? item) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FixedSheet(data: d, item: item),
    );
    if (saved != true || !mounted) return;
    final posted = await Repo.postDueFixed();
    if (!mounted) return;
    _toast(posted > 0
        ? 'Saved — logged $posted ${posted == 1 ? 'expense' : 'expenses'} that were already due'
        : 'Saved');
    _reload();
  }

  Future<void> _delete(FixedExpense f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${f.name}?'),
        content: const Text('It stops logging. Anything it already logged stays in your history.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.deleteFixed(f.id);
      if (mounted) _reload();
    } catch (_) {
      if (mounted) _toast('Couldn\'t remove — check your connection');
    }
  }

  Future<void> _toggle(FixedExpense f, bool active) async {
    try {
      await Repo.setFixedActive(f.id, active);
      if (active) await Repo.postDueFixed();
      if (mounted) _reload();
    } catch (_) {
      if (mounted) _toast('Couldn\'t save — check your connection');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FixedData>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        return Scaffold(
          appBar: AppBar(title: const Text('Fixed expenses')),
          floatingActionButton: d == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _edit(d, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add fixed expense'),
                ),
          body: snap.hasError
              ? _setupNeeded(snap.error!)
              : d == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(onRefresh: _reload, child: _body(d)),
        );
      },
    );
  }

  Widget _setupNeeded(Object error) {
    final missing = error is PostgrestException &&
        (error.code == 'PGRST205' || error.code == '42P01' || error.message.contains('recurring_expense'));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(missing
              ? 'Fixed expenses need a one-time database step. Run the fixed-expenses SQL in Supabase, then come back.'
              : 'Couldn\'t load fixed expenses.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _reload, child: const Text('Try again')),
        ]),
      ),
    );
  }

  Widget _body(FixedData d) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cats = {for (final c in d.categories) c.id: c};
    final groupName = {for (final g in d.groups) g.id: g.name};
    final active = d.items.where((f) => f.active).toList();
    final weekly = active.fold<int>(0, (s, f) => s + f.weeklyCents);

    // Weekly cost per group, for the summary.
    final byGroup = <String, int>{};
    for (final f in active) {
      final g = cats[f.categoryId]?.groupId;
      if (g != null) byGroup[g] = (byGroup[g] ?? 0) + f.weeklyCents;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Card(
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fixed costs each week', style: theme.textTheme.labelLarge),
                Text(formatCents(weekly),
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (byGroup.isNotEmpty)
                  Text(
                    [
                      for (final g in d.groups)
                        if ((byGroup[g.id] ?? 0) > 0) '${g.name} ${formatCents(byGroup[g.id]!)}',
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium,
                  ),
                const SizedBox(height: 8),
                Text(
                  'Each one logs itself as an expense on its due date, so "Left this week" '
                  'already counts it. Fortnightly and monthly costs are shown as a weekly average.',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (d.items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Add rent, bills, subscriptions or regular savings.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        for (final f in d.items)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(top: 8),
            color: scheme.surfaceContainerLow,
            child: ListTile(
              onTap: () => _edit(d, f),
              leading: Switch(value: f.active, onChanged: (v) => _toggle(f, v)),
              title: Text(f.name,
                  style: f.active ? null : TextStyle(color: scheme.onSurfaceVariant)),
              subtitle: Text([
                '${_freqLabels[f.frequency]} · ${cats[f.categoryId]?.name ?? '—'}'
                    '${cats[f.categoryId] == null ? '' : ' (${groupName[cats[f.categoryId]!.groupId] ?? ''})'}',
                f.active ? 'Next: ${friendlyDate(f.nextDue)}' : 'Paused',
              ].join('\n')),
              isThreeLine: true,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(formatCents(f.amountCents), style: theme.textTheme.titleMedium),
                IconButton(
                  tooltip: 'Remove',
                  icon: Icon(Icons.delete_outline, color: scheme.onSurfaceVariant),
                  onPressed: () => _delete(f),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}

class _FixedSheet extends StatefulWidget {
  final FixedData data;
  final FixedExpense? item;
  const _FixedSheet({required this.data, this.item});

  @override
  State<_FixedSheet> createState() => _FixedSheetState();
}

class _FixedSheetState extends State<_FixedSheet> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _amount = TextEditingController(
      text: widget.item == null ? '' : (widget.item!.amountCents / 100).toStringAsFixed(2));
  late String? _categoryId = widget.item?.categoryId;
  late String _freq = widget.item?.frequency ?? 'weekly';
  // New ones start on this week's payday so this week's budget includes them.
  late DateTime _date = widget.item?.nextDue ?? weekStartOf(DateTime.now());
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final cents = parseCents(_amount.text);
    if (name.isEmpty) return setState(() => _error = 'Give it a name, e.g. Rent');
    if (cents == null) return setState(() => _error = 'Enter an amount');
    if (_categoryId == null) return setState(() => _error = 'Pick a category');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Repo.saveFixed(
        id: widget.item?.id,
        name: name,
        amountCents: cents,
        categoryId: _categoryId!,
        frequency: _freq,
        nextDue: _date,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Couldn\'t save — check your connection';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = dateOnly(DateTime.now());
    final backdated = !_date.isAfter(today);
    final groups = [...widget.data.groups]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.item == null ? 'Add fixed expense' : 'Edit fixed expense',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.item == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Rent, Phone bill'),
            ),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '\$ '),
            ),
            const SizedBox(height: 16),
            Text('How often', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final e in _freqLabels.entries) ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: {_freq},
              onSelectionChanged: (s) => setState(() => _freq = s.first),
            ),
            for (final g in groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(g.name, style: theme.textTheme.titleSmall),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in widget.data.categories.where((c) => c.groupId == g.id))
                  ChoiceChip(
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
              ]),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Text(
                  widget.item == null ? 'First one: ${friendlyDate(_date)}' : 'Next one: ${friendlyDate(_date)}',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              TextButton(onPressed: _pickDate, child: const Text('Change')),
            ]),
            if (backdated)
              Text(
                'This date has passed, so it logs straight away when you save. '
                'If you already logged it by hand this week, delete one of them.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
