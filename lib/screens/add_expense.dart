import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../util/format.dart';

/// Amount first, category second, done. Recent entries log in one tap.
/// Pops with a short confirmation message when something was saved.
class AddExpenseScreen extends StatefulWidget {
  final List<Group> groups;
  final List<Category> categories;
  const AddExpenseScreen({super.key, required this.groups, required this.categories});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

enum _Day { today, yesterday, other }

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _categoryId;
  _Day _day = _Day.today;
  DateTime _otherDate = dateOnly(DateTime.now());
  bool _saving = false;
  late final Future<List<QuickEntry>> _quick = Repo.quickEntries();
  late final List<Category> _categories = [...widget.categories];

  Map<String, Category> get _catById => {for (final c in _categories) c.id: c};

  DateTime get _date => switch (_day) {
        _Day.today => dateOnly(DateTime.now()),
        _Day.yesterday => addDays(DateTime.now(), -1),
        _Day.other => _otherDate,
      };

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save({int? cents, String? categoryId, String? note, DateTime? date}) async {
    final amount = cents ?? parseCents(_amount.text);
    final cat = categoryId ?? _categoryId;
    if (amount == null) return _toast('Enter an amount');
    if (cat == null) return _toast('Pick a category');

    setState(() => _saving = true);
    try {
      await Repo.addExpense(
        amountCents: amount,
        categoryId: cat,
        spentOn: date ?? _date,
        note: note ?? _note.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop('Logged ${formatCents(amount)} · ${_catById[cat]?.name ?? ''}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Couldn\'t save — check your connection and try again');
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _newCategory(Group group) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('New ${group.name} category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Haircut'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Add')),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;

    // Already exists in this group? Just select it.
    final existing = _categories.where(
        (c) => c.groupId == group.id && c.name.toLowerCase() == trimmed.toLowerCase());
    if (existing.isNotEmpty) {
      setState(() => _categoryId = existing.first.id);
      return;
    }
    try {
      final created = await Repo.addCategory(name: trimmed, groupId: group.id);
      if (!mounted) return;
      setState(() {
        _categories.add(created);
        _categoryId = created.id;
      });
    } catch (_) {
      _toast('Couldn\'t add the category — try again');
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _otherDate,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _otherDate = dateOnly(picked);
        _day = _Day.other;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = [...widget.groups]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Scaffold(
      appBar: AppBar(title: const Text('Add expense')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  // 1. Amount — focused straight away
                  TextField(
                    controller: _amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    textInputAction: TextInputAction.done,
                    style: theme.textTheme.displaySmall,
                    decoration: InputDecoration(
                      // An icon-slot prefix stays visible even before the field is tapped.
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('\$',
                            style: theme.textTheme.displaySmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      hintText: '0.00',
                      border: InputBorder.none,
                    ),
                  ),

                  // One-tap repeats
                  FutureBuilder<List<QuickEntry>>(
                    future: _quick,
                    builder: (context, snap) {
                      final items = (snap.data ?? const <QuickEntry>[])
                          .where((q) => _catById.containsKey(q.categoryId))
                          .toList();
                      if (items.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tap to log again', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final q in items)
                                  ActionChip(
                                    avatar: const Icon(Icons.bolt, size: 18),
                                    label: Text(
                                        '${q.note ?? _catById[q.categoryId]!.name} ${formatCents(q.amountCents)}'),
                                    onPressed: _saving
                                        ? null
                                        : () => _save(
                                              cents: q.amountCents,
                                              categoryId: q.categoryId,
                                              note: q.note ?? '',
                                              date: dateOnly(DateTime.now()),
                                            ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // 2. Category
                  for (final g in groups) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Text(g.name, style: theme.textTheme.titleSmall),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in _categories.where((c) => c.groupId == g.id))
                          ChoiceChip(
                            label: Text(c.name),
                            selected: _categoryId == c.id,
                            onSelected: (_) => setState(() => _categoryId = c.id),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: const Text('New'),
                          onPressed: _saving ? null : () => _newCategory(g),
                        ),
                      ],
                    ),
                  ],

                  // When
                  Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 8),
                    child: Text('When', style: theme.textTheme.titleSmall),
                  ),
                  SegmentedButton<_Day>(
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(value: _Day.today, label: Text('Today')),
                      const ButtonSegment(value: _Day.yesterday, label: Text('Yesterday')),
                      ButtonSegment(
                        value: _Day.other,
                        label: Text(_day == _Day.other ? friendlyDate(_otherDate) : 'Pick date'),
                      ),
                    ],
                    selected: {_day},
                    onSelectionChanged: (s) {
                      if (s.first == _Day.other) {
                        _pickDate();
                      } else {
                        setState(() => _day = s.first);
                      }
                    },
                  ),

                  // Optional note
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: TextField(
                      controller: _note,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(),
                  child: _saving
                      ? const SizedBox(
                          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
