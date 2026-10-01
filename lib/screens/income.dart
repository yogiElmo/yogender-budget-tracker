import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../util/format.dart';

/// This week's income: what came in, what's set aside for tax, and any money
/// above the weekly budget that can go into a savings jar.
class IncomeScreen extends StatefulWidget {
  const IncomeScreen({super.key});

  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  late Future<IncomeWeek> _future = Repo.loadIncomeWeek(DateTime.now());

  Future<void> _reload() async {
    final next = Repo.loadIncomeWeek(DateTime.now());
    setState(() => _future = next);
    await next;
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _add(IncomeWeek w) async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddIncomeSheet(sources: w.sources),
    );
    if (saved != null && mounted) {
      _toast(saved);
      _reload();
    }
  }

  Future<void> _delete(Income i, String sourceName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this income?'),
        content: Text('${formatCents(i.amountCents)} · $sourceName · ${friendlyDate(i.receivedOn)}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.deleteIncome(i.id);
      if (mounted) _reload();
    } catch (_) {
      if (mounted) _toast('Couldn\'t delete — try again');
    }
  }

  Future<void> _moveToJar(IncomeWeek w) async {
    if (w.jars.isEmpty) return _toast('Create a savings jar first');
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) => _MoveDialog(jars: w.jars, maxCents: w.residualLeftCents),
    );
    if (result == null) return;
    final (jarId, cents) = result;
    final jarName = w.jars.firstWhere((j) => j.$1 == jarId).$2;
    try {
      await Repo.moveResidualToJar(jarId, cents, w.weekStart);
      if (!mounted) return;
      _toast('Moved ${formatCents(cents)} to $jarName');
      _reload();
    } catch (_) {
      if (mounted) _toast('Couldn\'t save — check your connection');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<IncomeWeek>(
      future: _future,
      builder: (context, snap) {
        final w = snap.data;
        return Scaffold(
          appBar: AppBar(title: const Text('Income')),
          floatingActionButton: w == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _add(w),
                  icon: const Icon(Icons.add),
                  label: const Text('Log income'),
                ),
          body: snap.hasError
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Couldn\'t load your income.'),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _reload, child: const Text('Try again')),
                  ]),
                )
              : w == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(onRefresh: _reload, child: _body(w)),
        );
      },
    );
  }

  Widget _row(String label, String value, {TextStyle? style}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Text(label, style: style), const Spacer(), Text(value, style: style)]),
      );

  Widget _body(IncomeWeek w) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sourceName = {for (final s in w.sources) s.id: s.name};
    final bold = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);

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
                Text('Week of ${friendlyDate(w.weekStart)}', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                _row('Income', formatCents(w.grossCents)),
                _row('Set aside for tax', '− ${formatCents(w.taxCents)}'),
                const Divider(),
                _row('After tax', formatCents(w.netCents), style: bold),
                _row('Weekly budget', formatCents(w.weeklyBudgetCents)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Money above the budget
        Card(
          elevation: 0,
          color: w.residualLeftCents > 0 ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Above budget', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(formatCents(w.residualLeftCents),
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  w.residualCents == 0
                      ? w.netCents == 0
                          ? 'Log your pay to see what\'s left over after the budget.'
                          : '${formatCents(w.weeklyBudgetCents - w.netCents)} more income this week '
                              'and anything extra shows here.'
                      : w.movedToJarsCents > 0
                          ? '${formatCents(w.movedToJarsCents)} of ${formatCents(w.residualCents)} '
                              'already moved to jars'
                          : 'Earned above your ${formatCents(w.weeklyBudgetCents)} budget',
                  style: theme.textTheme.bodyMedium,
                ),
                if (w.residualLeftCents > 0) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _moveToJar(w),
                    icon: const Icon(Icons.savings_outlined),
                    label: const Text('Move to a jar'),
                  ),
                ],
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
          child: Text('This week', style: theme.textTheme.titleMedium),
        ),
        if (w.income.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No income logged this week.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        for (final i in w.income)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 4),
            title: Text(sourceName[i.sourceId] ?? 'Income'),
            subtitle: Text([
              friendlyDate(i.receivedOn),
              if (i.taxCents > 0) '${formatCents(i.taxCents)} for tax',
              if (i.note != null) i.note!,
            ].join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(formatCents(i.amountCents), style: theme.textTheme.titleMedium),
              IconButton(
                tooltip: 'Delete',
                icon: Icon(Icons.delete_outline, color: scheme.onSurfaceVariant),
                onPressed: () => _delete(i, sourceName[i.sourceId] ?? 'Income'),
              ),
            ]),
          ),
      ],
    );
  }
}

// ============================================================== add income

class _AddIncomeSheet extends StatefulWidget {
  final List<IncomeSource> sources;
  const _AddIncomeSheet({required this.sources});

  @override
  State<_AddIncomeSheet> createState() => _AddIncomeSheetState();
}

class _AddIncomeSheetState extends State<_AddIncomeSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late final List<IncomeSource> _sources = [...widget.sources];
  late String? _sourceId = _sources.length == 1 ? _sources.first.id : null;
  DateTime _date = dateOnly(DateTime.now());
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  IncomeSource? get _source =>
      _sourceId == null ? null : _sources.where((s) => s.id == _sourceId).firstOrNull;

  int get _taxCents {
    final cents = parseCents(_amount.text) ?? 0;
    return (cents * (_source?.taxRatePercent ?? 0) / 100).round();
  }

  Future<void> _newSource() async {
    final name = TextEditingController();
    final rate = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New income source'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Main job'),
          ),
          TextField(
            controller: rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(
                labelText: 'Set aside for tax', suffixText: '%', hintText: '0'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Add')),
        ],
      ),
    );
    final n = name.text.trim();
    final r = double.tryParse(rate.text.trim().isEmpty ? '0' : rate.text.trim());
    name.dispose();
    rate.dispose();
    if (ok != true || n.isEmpty || !mounted) return;
    if (r == null || r < 0 || r > 100) return setState(() => _error = 'Tax rate must be 0–100%');
    try {
      final created = await Repo.addIncomeSource(name: n, taxRate: r, isSide: false);
      if (!mounted) return;
      setState(() {
        _sources.add(created);
        _sourceId = created.id;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t add the source — try again');
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(now.year - 1), lastDate: now);
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _save() async {
    final cents = parseCents(_amount.text);
    if (cents == null) return setState(() => _error = 'Enter an amount');
    if (_source == null) return setState(() => _error = 'Pick where it came from');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Repo.addIncome(
        sourceId: _source!.id,
        amountCents: cents,
        taxCents: _taxCents,
        receivedOn: _date,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop('Logged ${formatCents(cents)} from ${_source!.name}');
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
    final src = _source;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Log income', style: theme.textTheme.titleLarge),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: theme.textTheme.displaySmall,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('\$',
                      style: theme.textTheme.displaySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                hintText: '0.00',
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 8),
            Text('From', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in _sources)
                ChoiceChip(
                  label: Text(s.name),
                  selected: _sourceId == s.id,
                  onSelected: (_) => setState(() => _sourceId = s.id),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('New'),
                onPressed: _newSource,
              ),
            ]),
            if (src != null && (parseCents(_amount.text) ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  src.taxRatePercent == 0
                      ? 'No tax set aside for ${src.name}'
                      : '${formatCents(_taxCents)} set aside for tax '
                          '(${src.taxRatePercent.toStringAsFixed(src.taxRatePercent % 1 == 0 ? 0 : 1)}%)',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary),
                ),
              ),
            const SizedBox(height: 16),
            Row(children: [
              Text('Received ${friendlyDate(_date)}', style: theme.textTheme.bodyLarge),
              const Spacer(),
              TextButton(onPressed: _pickDate, child: const Text('Change')),
            ]),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
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

// ============================================================== move to jar

class _MoveDialog extends StatefulWidget {
  final List<(String, String)> jars;
  final int maxCents;
  const _MoveDialog({required this.jars, required this.maxCents});

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  late String _jarId = widget.jars.first.$1;
  late final _amount = TextEditingController(text: (widget.maxCents / 100).toStringAsFixed(2));
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Move to a jar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _jarId,
            decoration: const InputDecoration(labelText: 'Jar'),
            items: [
              for (final (id, name) in widget.jars) DropdownMenuItem(value: id, child: Text(name)),
            ],
            onChanged: (v) => setState(() => _jarId = v ?? _jarId),
          ),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '\$ ',
              helperText: 'Up to ${formatCents(widget.maxCents)}',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final cents = parseCents(_amount.text);
            if (cents == null) return setState(() => _error = 'Enter an amount');
            if (cents > widget.maxCents) {
              return setState(() => _error = 'That\'s more than is above budget');
            }
            Navigator.of(context).pop((_jarId, cents));
          },
          child: const Text('Move'),
        ),
      ],
    );
  }
}
