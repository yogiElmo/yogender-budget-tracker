import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repo.dart';
import '../util/app_version.dart';
import '../util/format.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onSignOut;
  const SettingsScreen({super.key, required this.onSignOut});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

const _accountTypes = {
  'bank': 'Bank',
  'investment': 'Investment',
  'wallet': 'Wallet',
  'super': 'Super',
  'other': 'Other',
};

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<SettingsData> _future = Repo.loadSettings();

  Future<void> _reload() async {
    final next = Repo.loadSettings();
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

  // ------------------------------------------------------------ budget

  Future<void> _editBudget(SettingsData d) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _BudgetEditor(data: d), fullscreenDialog: true),
    );
    if (saved == true && mounted) {
      _toast('Budget updated from this week');
      _reload();
    }
  }

  // ------------------------------------------------------------ categories

  Future<void> _categoryActions(Category c, bool archived) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(c.name, style: Theme.of(context).textTheme.titleMedium)),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.of(context).pop('rename'),
          ),
          ListTile(
            leading: Icon(archived ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            title: Text(archived ? 'Show again' : 'Hide'),
            subtitle: archived
                ? null
                : const Text('Removes it from Add expense. Past expenses keep it.'),
            onTap: () => Navigator.of(context).pop(archived ? 'show' : 'hide'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        final name = await _askText(title: 'Rename category', initial: c.name);
        if (name != null) await _run(() => Repo.renameCategory(c.id, name));
      case 'hide':
        await _run(() => Repo.setCategoryArchived(c.id, true), done: 'Hid ${c.name}');
      case 'show':
        await _run(() => Repo.setCategoryArchived(c.id, false), done: '${c.name} is back');
    }
  }

  // ------------------------------------------------------------ accounts

  Future<void> _editAccount(Account? a) async {
    final result = await showDialog<(String, String, String)>(
      context: context,
      builder: (_) => _AccountDialog(account: a),
    );
    if (result == null) return;
    final (name, type, purpose) = result;
    await _run(() => Repo.saveAccount(id: a?.id, name: name, type: type, purpose: purpose),
        done: a == null ? 'Added $name' : null);
  }

  // ------------------------------------------------------------ income

  Future<void> _editIncome(IncomeSource? src) async {
    final result = await showDialog<(String, double, bool)>(
      context: context,
      builder: (_) => _IncomeDialog(source: src),
    );
    if (result == null) return;
    final (name, rate, side) = result;
    await _run(() => Repo.saveIncomeSource(id: src?.id, name: name, taxRate: rate, isSide: side),
        done: src == null ? 'Added $name' : null);
  }

  Future<void> _deleteIncome(IncomeSource src) async {
    final ok = await _confirm('Remove ${src.name}?', 'Income already recorded from it is kept.');
    if (ok) await _run(() => Repo.deleteIncomeSource(src.id), done: 'Removed ${src.name}');
  }

  // ------------------------------------------------------------ helpers

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
          ],
        ),
      ) ??
      false;

  Future<String?> _askText({required String title, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.of(context).pop(v),
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
    final t = text?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: FutureBuilder<SettingsData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Couldn\'t load settings.'),
                const SizedBox(height: 16),
                FilledButton(onPressed: _reload, child: const Text('Try again')),
              ]),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return RefreshIndicator(onRefresh: _reload, child: _body(snap.data!));
        },
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Widget _body(SettingsData d) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final email = Supabase.instance.client.auth.currentUser?.email;
    final splitText = [
      for (final g in d.groups) '${g.name} ${(d.percentByGroup[g.id] ?? 0).toStringAsFixed(0)}%',
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _header('Weekly budget'),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text('${formatCents(d.weeklyCents)} a week'),
          subtitle: Text(splitText),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editBudget(d),
        ),

        _header('Categories'),
        for (final g in d.groups)
          ExpansionTile(
            leading: const Icon(Icons.label_outline),
            title: Text(g.name),
            subtitle: Text(
                '${d.categories.where((c) => c.$1.groupId == g.id && !c.$2).length} categories'),
            children: [
              for (final (c, archived) in d.categories.where((c) => c.$1.groupId == g.id))
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 72, right: 16),
                  title: Text(c.name,
                      style: archived ? TextStyle(color: scheme.onSurfaceVariant) : null),
                  subtitle: archived ? const Text('Hidden') : null,
                  trailing: const Icon(Icons.more_horiz),
                  onTap: () => _categoryActions(c, archived),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                child: Text('Add new ones with + New on the Add expense screen.',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ],
          ),

        _header('Accounts'),
        for (final (a, active) in d.accounts)
          ListTile(
            leading: Icon(switch (a.type) {
              'investment' => Icons.trending_up,
              'wallet' => Icons.wallet_outlined,
              'super' => Icons.elderly_outlined,
              _ => Icons.account_balance_outlined,
            }),
            title: Text(a.name,
                style: active ? null : TextStyle(color: scheme.onSurfaceVariant)),
            subtitle: Text([
              _accountTypes[a.type] ?? a.type,
              if (a.purpose != null) a.purpose!,
              if (!active) 'Not in payday transfers',
            ].join(' · ')),
            trailing: Switch(
              value: active,
              onChanged: (v) => _run(() => Repo.setAccountActive(a.id, v)),
            ),
            onTap: () => _editAccount(a),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _editAccount(null),
              icon: const Icon(Icons.add),
              label: const Text('Add account'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Switched-off accounts are left out of payday transfers.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),

        _header('Income sources & tax'),
        if (d.incomeSources.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
                'Add where your money comes from and how much tax to set aside from each.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        for (final src in d.incomeSources)
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(src.name),
            subtitle: Text([
              'Set aside ${_pct(src.taxRatePercent)} for tax',
              if (src.isSideIncome) 'Side income',
            ].join(' · ')),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteIncome(src),
            ),
            onTap: () => _editIncome(src),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _editIncome(null),
              icon: const Icon(Icons.add),
              label: const Text('Add income source'),
            ),
          ),
        ),

        _header('Account'),
        if (email != null)
          ListTile(leading: const Icon(Icons.person_outline), title: Text(email)),
        ListTile(
          leading: Icon(Icons.logout, color: scheme.error),
          title: Text('Sign out', style: TextStyle(color: scheme.error)),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Sign out?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Sign out')),
                ],
              ),
            );
            if (ok == true && mounted) {
              Navigator.of(context).popUntil((r) => r.isFirst);
              widget.onSignOut();
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Version $appVersion',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

String _pct(double v) => v == v.roundToDouble() ? '${v.toStringAsFixed(0)}%' : '${v.toStringAsFixed(1)}%';

// ============================================================== budget editor

class _BudgetEditor extends StatefulWidget {
  final SettingsData data;
  const _BudgetEditor({required this.data});

  @override
  State<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<_BudgetEditor> {
  late final _amount = TextEditingController(
      text: widget.data.weeklyCents == 0 ? '' : (widget.data.weeklyCents / 100).toStringAsFixed(0));
  late final Map<String, TextEditingController> _pcts = {
    for (final g in widget.data.groups)
      g.id: TextEditingController(
          text: (widget.data.percentByGroup[g.id] ?? 0).toStringAsFixed(0)),
  };
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    for (final c in _pcts.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _pct(String id) => double.tryParse(_pcts[id]!.text.trim()) ?? 0;

  Future<void> _save() async {
    final cents = parseCents(_amount.text);
    if (cents == null) return;
    setState(() => _saving = true);
    try {
      await Repo.saveBudget(cents, {for (final g in widget.data.groups) g.id: _pct(g.id)});
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t save — check your connection')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cents = parseCents(_amount.text) ?? 0;
    final total = widget.data.groups.fold<double>(0, (s, g) => s + _pct(g.id));
    final balanced = (total - 100).abs() < 0.01;
    final canSave = !_saving && cents > 0 && balanced;

    return Scaffold(
      appBar: AppBar(title: const Text('Weekly budget')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: theme.textTheme.headlineMedium,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Each week',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('Split', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final g in widget.data.groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(child: Text(g.name, style: theme.textTheme.bodyLarge)),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _pcts[g.id],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      textAlign: TextAlign.end,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          suffixText: '%', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(formatCents((cents * _pct(g.id) / 100).round()),
                        textAlign: TextAlign.end, style: theme.textTheme.bodyLarge),
                  ),
                ],
              ),
            ),
          const Divider(),
          Row(
            children: [
              Text('Total', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text('${total.toStringAsFixed(total == total.roundToDouble() ? 0 : 1)}%',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: balanced ? scheme.primary : scheme.error)),
            ],
          ),
          if (!balanced)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  total < 100
                      ? '${(100 - total).toStringAsFixed(0)}% still to assign'
                      : '${(total - 100).toStringAsFixed(0)}% too much',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
            ),
          const SizedBox(height: 24),
          Text(
            'Changes apply from this week (starting ${friendlyDate(weekStartOf(DateTime.now()))}). '
            'Earlier weeks keep the budget they had.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: canSave ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================== dialogs

class _AccountDialog extends StatefulWidget {
  final Account? account;
  const _AccountDialog({this.account});

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _purpose = TextEditingController(text: widget.account?.purpose ?? '');
  late String _type = widget.account?.type ?? 'bank';

  @override
  void dispose() {
    _name.dispose();
    _purpose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.account == null ? 'Add account' : 'Edit account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.account == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. eToro'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final e in _accountTypes.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'bank'),
            ),
            TextField(
              controller: _purpose,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Purpose (optional)', hintText: 'e.g. Rent'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.of(context).pop((_name.text.trim(), _type, _purpose.text.trim()));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _IncomeDialog extends StatefulWidget {
  final IncomeSource? source;
  const _IncomeDialog({this.source});

  @override
  State<_IncomeDialog> createState() => _IncomeDialogState();
}

class _IncomeDialogState extends State<_IncomeDialog> {
  late final _name = TextEditingController(text: widget.source?.name ?? '');
  late final _rate = TextEditingController(
      text: widget.source == null ? '' : _pct(widget.source!.taxRatePercent).replaceAll('%', ''));
  late bool _side = widget.source?.isSideIncome ?? false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final rateText = _rate.text.trim();
    final rate = rateText.isEmpty ? 0.0 : double.tryParse(rateText);
    if (name.isEmpty) return setState(() => _error = 'Give it a name');
    if (rate == null || rate < 0 || rate > 100) {
      return setState(() => _error = 'Tax rate must be between 0 and 100');
    }
    Navigator.of(context).pop((name, rate, _side));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.source == null ? 'Add income source' : 'Edit income source'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.source == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Uber driving'),
            ),
            TextField(
              controller: _rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(
                  labelText: 'Set aside for tax', suffixText: '%', hintText: '0'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Side income'),
              value: _side,
              onChanged: (v) => setState(() => _side = v),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
