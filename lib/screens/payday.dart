import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../util/format.dart';

/// Tuesday payday: tick off each transfer as you make it.
/// Amounts carry over from the previous week, so most weeks it's just ticking.
class PaydayScreen extends StatefulWidget {
  const PaydayScreen({super.key});

  @override
  State<PaydayScreen> createState() => _PaydayScreenState();
}

class _PaydayScreenState extends State<PaydayScreen> {
  late Future<Payday> _future = Repo.loadPayday(DateTime.now());

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _syncStatus(Payday p) async {
    final active = p.lines.where((l) => l.plannedCents > 0);
    final allDone = active.isNotEmpty && active.every((l) => l.done);
    try {
      await Repo.setPaydayStatus(p.allocationId, allDone);
    } catch (_) {/* status is a convenience flag; lines are the source of truth */}
  }

  Future<void> _toggle(Payday p, TransferLine line, bool done) async {
    setState(() => line.done = done);
    try {
      await Repo.setTransferDone(line.id, done);
      _syncStatus(p);
    } catch (_) {
      if (!mounted) return;
      setState(() => line.done = !done);
      _toast('Couldn\'t save — check your connection');
    }
  }

  Future<void> _markAll(Payday p) async {
    final todo = p.lines.where((l) => l.plannedCents > 0 && !l.done).toList();
    setState(() {
      for (final l in todo) {
        l.done = true;
      }
    });
    try {
      await Future.wait([for (final l in todo) Repo.setTransferDone(l.id, true)]);
      _syncStatus(p);
    } catch (_) {
      if (!mounted) return;
      _toast('Some ticks didn\'t save — pull down to refresh');
    }
  }

  Future<void> _editAmount(Payday p, TransferLine line) async {
    final controller = TextEditingController(
        text: line.plannedCents == 0 ? '' : (line.plannedCents / 100).toStringAsFixed(2));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(line.account.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00'),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
            const SizedBox(height: 12),
            Text('Amount each week. Leave empty to skip this account.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    final cents = result.trim().isEmpty ? 0 : parseCents(result);
    if (cents == null && result.trim() != '0') return _toast('That amount doesn\'t look right');
    final value = cents ?? 0;
    final before = line.plannedCents;
    setState(() {
      line.plannedCents = value;
      if (value == 0) line.done = false;
    });
    try {
      await Repo.setTransferAmount(line.id, value);
      if (value == 0) await Repo.setTransferDone(line.id, false);
      _syncStatus(p);
    } catch (_) {
      if (!mounted) return;
      setState(() => line.plannedCents = before);
      _toast('Couldn\'t save — check your connection');
    }
  }

  Future<void> _reload() async {
    final next = Repo.loadPayday(DateTime.now());
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payday transfers')),
      body: FutureBuilder<Payday>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Couldn\'t load your transfers.'),
                  const SizedBox(height: 8),
                  Text('${snap.error}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _reload, child: const Text('Try again')),
                ]),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return RefreshIndicator(onRefresh: _reload, child: _body(snap.data!));
        },
      ),
    );
  }

  Widget _body(Payday p) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = p.lines.where((l) => l.plannedCents > 0).toList();
    final planned = active.fold<int>(0, (s, l) => s + l.plannedCents);
    final moved = active.where((l) => l.done).fold<int>(0, (s, l) => s + l.plannedCents);
    final doneCount = active.where((l) => l.done).length;
    final allDone = active.isNotEmpty && doneCount == active.length;
    final firstTime = active.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          elevation: 0,
          color: allDone ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Week of ${friendlyDate(p.weekStart)}', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  firstTime
                      ? 'Set your amounts'
                      : allDone
                          ? 'All done'
                          : '$doneCount of ${active.length} done',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  firstTime
                      ? 'Tap an amount to say how much goes to each account. '
                          'Next week starts with the same amounts.'
                      : 'Moved ${formatCents(moved)} of ${formatCents(planned)} · '
                          'weekly budget ${formatCents(p.weeklyCents)}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (!firstTime) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: planned == 0 ? 0 : moved / planned,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final line in p.lines) _lineTile(p, line, theme),
        if (!firstTime && !allDone)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton.icon(
              onPressed: () => _markAll(p),
              icon: const Icon(Icons.done_all),
              label: const Text('Mark all as done'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Tap an amount to change it. Changes apply to this week and carry into next week.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _lineTile(Payday p, TransferLine line, ThemeData theme) {
    final scheme = theme.colorScheme;
    final skipped = line.plannedCents == 0;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Checkbox(
        value: line.done,
        onChanged: skipped ? null : (v) => _toggle(p, line, v ?? false),
      ),
      title: Text(
        line.account.name,
        style: TextStyle(
          color: skipped ? scheme.onSurfaceVariant : null,
          decoration: line.done ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: line.account.purpose == null ? null : Text(line.account.purpose!),
      trailing: TextButton(
        onPressed: () => _editAmount(p, line),
        child: Text(
          skipped ? 'Set amount' : formatCents(line.plannedCents),
          style: skipped ? null : theme.textTheme.titleMedium?.copyWith(color: scheme.primary),
        ),
      ),
      onTap: skipped ? () => _editAmount(p, line) : () => _toggle(p, line, !line.done),
    );
  }
}
