import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../util/format.dart';

/// Savings goals: how much is in each jar, how far to go, and what it takes
/// each week to get there on time.
class JarsScreen extends StatefulWidget {
  const JarsScreen({super.key});

  @override
  State<JarsScreen> createState() => _JarsScreenState();
}

class _JarsScreenState extends State<JarsScreen> {
  late Future<List<Jar>> _future = Repo.loadJars();

  Future<void> _reload() async {
    final next = Repo.loadJars();
    setState(() => _future = next);
    await next;
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      if (!mounted) return;
      if (done != null) _toast(done);
      await _reload();
    } catch (_) {
      if (mounted) _toast('Couldn\'t save — check your connection');
    }
  }

  // ------------------------------------------------------------ actions

  Future<void> _addMoney(Jar jar) async {
    final cents = await _askAmount(title: 'Add to ${jar.name}');
    if (cents == null) return;
    await _run(() => Repo.addToJar(jar.id, cents, DateTime.now()),
        done: 'Added ${formatCents(cents)} to ${jar.name}');
  }

  Future<void> _editJar(Jar? jar) async {
    final result = await showDialog<_JarForm>(
      context: context,
      builder: (_) => _JarDialog(jar: jar),
    );
    if (result == null) return;
    if (jar == null) {
      await _run(
          () => Repo.addJar(
              name: result.name, targetCents: result.targetCents, targetDate: result.targetDate),
          done: 'Created ${result.name}');
    } else {
      await _run(() => Repo.updateJar(jar.id,
          name: result.name, targetCents: result.targetCents, targetDate: result.targetDate));
    }
  }

  Future<void> _archive(Jar jar) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close ${jar.name}?'),
        content: const Text(
            'It disappears from your jars. Nothing is deleted, so its history is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Close jar')),
        ],
      ),
    );
    if (ok == true) await _run(() => Repo.archiveJar(jar.id), done: 'Closed ${jar.name}');
  }

  Future<void> _history(Jar jar) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('${jar.name} · ${formatCents(jar.savedCents)}',
                    style: theme.textTheme.titleLarge),
              ),
              if (jar.contributions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nothing added yet.', textAlign: TextAlign.center),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    for (final c in jar.contributions)
                      ListTile(
                        title: Text(formatCents(c.amountCents)),
                        subtitle: Text(friendlyDate(c.on)),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            Navigator.of(sheetContext).pop();
                            await _run(() => Repo.deleteJarContribution(c.id),
                                done: 'Removed ${formatCents(c.amountCents)}');
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<int?> _askAmount({required String title}) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Add')),
        ],
      ),
    );
    controller.dispose();
    if (text == null) return null;
    final cents = parseCents(text);
    if (cents == null && mounted) _toast('Enter an amount above \$0');
    return cents;
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Savings jars')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editJar(null),
        icon: const Icon(Icons.add),
        label: const Text('New jar'),
      ),
      body: FutureBuilder<List<Jar>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Couldn\'t load your jars.'),
                const SizedBox(height: 16),
                FilledButton(onPressed: _reload, child: const Text('Try again')),
              ]),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final jars = snap.data!;
          final total = jars.fold<int>(0, (s, j) => s + j.savedCents);
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text('${formatCents(total)} saved across ${jars.length} '
                      '${jars.length == 1 ? 'jar' : 'jars'}'),
                ),
                if (jars.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No jars yet. Tap New jar to start one.',
                        textAlign: TextAlign.center),
                  ),
                for (final j in jars) _jarCard(j),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _jarCard(Jar jar) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final target = jar.targetCents;
    final reached = target != null && jar.savedCents >= target;

    String? pace;
    if (target != null && jar.targetDate != null && !reached) {
      final daysLeft = dateOnly(jar.targetDate!).difference(dateOnly(DateTime.now())).inDays;
      final remaining = target - jar.savedCents;
      if (daysLeft <= 0) {
        pace = 'Target date passed · ${formatCents(remaining)} to go';
      } else {
        final weeks = (daysLeft / 7).ceil();
        pace = '${formatCents((remaining / weeks).ceil())}/week to reach it by '
            '${friendlyDate(jar.targetDate!)}';
      }
    }

    return Card(
      elevation: 0,
      color: reached ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _history(jar),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(jar.name, style: theme.textTheme.titleMedium)),
                  PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? _editJar(jar) : _archive(jar),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit name or target')),
                      PopupMenuItem(value: 'close', child: Text('Close jar')),
                    ],
                  ),
                ],
              ),
              Text(formatCents(jar.savedCents),
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (target != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(minHeight: 8, value: jar.progress),
                      ),
                      const SizedBox(height: 6),
                      Text(reached
                          ? 'Target of ${formatCents(target)} reached'
                          : '${formatCents(target - jar.savedCents)} to go of ${formatCents(target)}'),
                    ] else
                      Text('No target set',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    if (pace != null)
                      Text(pace,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _addMoney(jar),
                      icon: const Icon(Icons.add),
                      label: const Text('Add money'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JarForm {
  final String name;
  final int? targetCents;
  final DateTime? targetDate;
  _JarForm(this.name, this.targetCents, this.targetDate);
}

class _JarDialog extends StatefulWidget {
  final Jar? jar;
  const _JarDialog({this.jar});

  @override
  State<_JarDialog> createState() => _JarDialogState();
}

class _JarDialogState extends State<_JarDialog> {
  late final _name = TextEditingController(text: widget.jar?.name ?? '');
  late final _target = TextEditingController(
      text: widget.jar?.targetCents == null
          ? ''
          : (widget.jar!.targetCents! / 100).toStringAsFixed(2));
  late DateTime? _date = widget.jar?.targetDate;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Give the jar a name');
    final targetText = _target.text.trim();
    final target = targetText.isEmpty ? null : parseCents(targetText);
    if (targetText.isNotEmpty && target == null) {
      return setState(() => _error = 'That target doesn\'t look right');
    }
    Navigator.of(context).pop(_JarForm(name, target, _date));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? addDays(now, 90),
      firstDate: dateOnly(now),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.jar == null ? 'New jar' : 'Edit jar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.jar == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Vacation'),
          ),
          TextField(
            controller: _target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration:
                const InputDecoration(labelText: 'Target (optional)', prefixText: '\$ '),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(_date == null ? 'No target date' : 'By ${friendlyDate(_date!)} ${_date!.year}'),
              ),
              if (_date != null)
                IconButton(
                    tooltip: 'Clear date',
                    onPressed: () => setState(() => _date = null),
                    icon: const Icon(Icons.close)),
              TextButton(onPressed: _pickDate, child: Text(_date == null ? 'Set date' : 'Change')),
            ],
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
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
