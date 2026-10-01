// All reads and writes to Supabase live here, so the screens stay simple
// and the offline layer can slot in behind this later.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../util/format.dart';

SupabaseClient get _db => Supabase.instance.client;

class Group {
  final String id;
  final String name;
  final int sortOrder;
  final double percent; // share of the weekly budget this week
  Group(this.id, this.name, this.sortOrder, this.percent);
}

class Category {
  final String id;
  final String name;
  final String groupId;
  Category(this.id, this.name, this.groupId);
}

class Expense {
  final String id;
  final int amountCents;
  final String categoryId;
  final DateTime spentOn;
  final String? note;
  Expense(this.id, this.amountCents, this.categoryId, this.spentOn, this.note);

  factory Expense.fromRow(Map<String, dynamic> r) => Expense(
        r['id'] as String,
        r['amount_cents'] as int,
        r['category_id'] as String,
        DateTime.parse(r['spent_on'] as String),
        (r['note'] as String?)?.trim().isEmpty ?? true ? null : r['note'] as String,
      );
}

/// A repeat of something logged before, for one-tap logging.
class QuickEntry {
  final int amountCents;
  final String categoryId;
  final String? note;
  QuickEntry(this.amountCents, this.categoryId, this.note);
}

class Account {
  final String id;
  final String name;
  final String type;
  final String? purpose;
  Account(this.id, this.name, this.type, this.purpose);
}

class TransferLine {
  final String id;
  final Account account;
  int plannedCents;
  bool done;
  TransferLine(this.id, this.account, this.plannedCents, this.done);
}

class Payday {
  final String allocationId;
  final DateTime weekStart;
  final int weeklyCents;
  final List<TransferLine> lines;
  Payday(this.allocationId, this.weekStart, this.weeklyCents, this.lines);
}

class WeekData {
  final DateTime weekStart;
  final int weeklyCents;
  final List<Group> groups;
  final List<Category> categories;
  final List<Expense> expenses;
  final int transfersToDo; // payday transfers with an amount set this week
  final int transfersDone;
  WeekData(this.weekStart, this.weeklyCents, this.groups, this.categories, this.expenses,
      {this.transfersToDo = 0, this.transfersDone = 0});

  DateTime get weekEnd => addDays(weekStart, 6);
  Map<String, Category> get categoryById => {for (final c in categories) c.id: c};
}

class Repo {
  /// Creates the default budget, categories, accounts and jars on first sign-in.
  static Future<void> seed() => _db.rpc('seed_defaults');

  static Future<WeekData> loadWeek(DateTime anyDay) async {
    final ws = weekStartOf(anyDay);
    final we = addDays(ws, 6);

    final results = await Future.wait<List<Map<String, dynamic>>>([
      _db
          .from('category_group')
          .select('id, name, sort_order')
          .isFilter('deleted_at', null)
          .order('sort_order'),
      _db
          .from('category')
          .select('id, name, group_id')
          .isFilter('deleted_at', null)
          .eq('archived', false)
          .order('name'),
      _db
          .from('budget_config')
          .select('weekly_amount_cents, budget_split(group_id, percent, deleted_at)')
          .isFilter('deleted_at', null)
          .lte('effective_from', isoDate(ws))
          .order('effective_from', ascending: false)
          .limit(1),
      _db
          .from('expense')
          .select('id, amount_cents, category_id, spent_on, note')
          .isFilter('deleted_at', null)
          .gte('spent_on', isoDate(ws))
          .lte('spent_on', isoDate(we))
          .order('spent_on', ascending: false)
          .order('created_at', ascending: false),
      _db
          .from('allocation')
          .select('allocation_line(planned_cents, done, deleted_at)')
          .isFilter('deleted_at', null)
          .eq('week_start', isoDate(ws)),
    ]);

    var configRows = results[2];
    if (configRows.isEmpty) {
      // Budget was set up later in the week than this week's Tuesday: use the newest one.
      configRows = await _db
          .from('budget_config')
          .select('weekly_amount_cents, budget_split(group_id, percent, deleted_at)')
          .isFilter('deleted_at', null)
          .order('effective_from', ascending: false)
          .limit(1);
    }
    final config = configRows.isEmpty ? null : configRows.first;
    final percentByGroup = <String, double>{
      for (final s in (config?['budget_split'] as List? ?? const []))
        if (s['deleted_at'] == null) s['group_id'] as String: (s['percent'] as num).toDouble(),
    };

    return WeekData(
      ws,
      config?['weekly_amount_cents'] as int? ?? 0,
      [
        for (final g in results[0])
          Group(g['id'] as String, g['name'] as String, g['sort_order'] as int,
              percentByGroup[g['id']] ?? 0),
      ],
      [
        for (final c in results[1])
          Category(c['id'] as String, c['name'] as String, c['group_id'] as String),
      ],
      [for (final e in results[3]) Expense.fromRow(e)],
      transfersToDo: _activeLines(results[4]).length,
      transfersDone: _activeLines(results[4]).where((l) => l['done'] == true).length,
    );
  }

  static List<Map<String, dynamic>> _activeLines(List<Map<String, dynamic>> allocations) => [
        for (final a in allocations)
          for (final l in (a['allocation_line'] as List? ?? const []))
            if (l['deleted_at'] == null && (l['planned_cents'] as int) > 0)
              l as Map<String, dynamic>,
      ];

  /// The most recent distinct expenses (same amount, category and note count once).
  static Future<List<QuickEntry>> quickEntries({int max = 6}) async {
    final rows = await _db
        .from('expense')
        .select('amount_cents, category_id, note')
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(60);
    final seen = <String>{};
    final out = <QuickEntry>[];
    for (final r in rows) {
      final note = (r['note'] as String?)?.trim();
      final key = '${r['amount_cents']}|${r['category_id']}|${note ?? ''}';
      if (seen.add(key)) {
        out.add(QuickEntry(r['amount_cents'] as int, r['category_id'] as String,
            note == null || note.isEmpty ? null : note));
        if (out.length == max) break;
      }
    }
    return out;
  }

  /// Adds a category under Needs, Wants or Savings and returns it.
  static Future<Category> addCategory({required String name, required String groupId}) async {
    final row = await _db
        .from('category')
        .insert({'name': name.trim(), 'group_id': groupId})
        .select('id, name, group_id')
        .single();
    return Category(row['id'] as String, row['name'] as String, row['group_id'] as String);
  }

  static Future<void> addExpense({
    required int amountCents,
    required String categoryId,
    required DateTime spentOn,
    String? note,
  }) =>
      _db.from('expense').insert({
        'amount_cents': amountCents,
        'category_id': categoryId,
        'spent_on': isoDate(spentOn),
        'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      });

  /// Soft delete, so the deletion syncs to other devices.
  static Future<void> deleteExpense(String id) => _db
      .from('expense')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);

  static Future<void> restoreExpense(String id) =>
      _db.from('expense').update({'deleted_at': null}).eq('id', id);

  // ---------------------------------------------------------------- payday

  /// Loads this week's payday transfers, creating them on first open.
  /// A new week copies the amounts from the most recent earlier week.
  static Future<Payday> loadPayday(DateTime anyDay) async {
    final ws = weekStartOf(anyDay);

    final accountRows = await _db
        .from('account')
        .select('id, name, type, purpose')
        .isFilter('deleted_at', null)
        .eq('active', true)
        .order('created_at')
        .order('name');
    final accounts = {
      for (final a in accountRows)
        a['id'] as String:
            Account(a['id'] as String, a['name'] as String, a['type'] as String, a['purpose'] as String?),
    };

    var alloc = await _findAllocation(ws);
    alloc ??= await _createAllocation(ws, accounts.keys.toList());

    final lines = <TransferLine>[];
    final covered = <String>{};
    for (final l in (alloc['allocation_line'] as List? ?? const [])) {
      if (l['deleted_at'] != null) continue;
      final account = accounts[l['account_id']];
      if (account == null) continue; // account was archived
      covered.add(account.id);
      lines.add(TransferLine(l['id'] as String, account, l['planned_cents'] as int, l['done'] as bool));
    }
    // Accounts added since this week was set up get a line too.
    final missing = accounts.keys.where((id) => !covered.contains(id)).toList();
    if (missing.isNotEmpty) {
      final rows = await _db
          .from('allocation_line')
          .insert([
            for (final id in missing)
              {'allocation_id': alloc['id'], 'account_id': id, 'planned_cents': 0},
          ])
          .select('id, account_id, planned_cents, done');
      for (final r in rows) {
        lines.add(TransferLine(r['id'] as String, accounts[r['account_id']]!,
            r['planned_cents'] as int, r['done'] as bool));
      }
    }
    final order = accounts.keys.toList();
    lines.sort((a, b) => order.indexOf(a.account.id).compareTo(order.indexOf(b.account.id)));

    final weekly = await _weeklyAmountFor(ws);
    return Payday(alloc['id'] as String, ws, weekly, lines);
  }

  static Future<Map<String, dynamic>?> _findAllocation(DateTime ws) => _db
      .from('allocation')
      .select('id, allocation_line(id, account_id, planned_cents, done, deleted_at)')
      .isFilter('deleted_at', null)
      .eq('week_start', isoDate(ws))
      .maybeSingle();

  static Future<Map<String, dynamic>> _createAllocation(DateTime ws, List<String> accountIds) async {
    final configId = await _configIdFor(ws);
    final prev = await _db
        .from('allocation')
        .select('allocation_line(account_id, planned_cents, deleted_at)')
        .isFilter('deleted_at', null)
        .lt('week_start', isoDate(ws))
        .order('week_start', ascending: false)
        .limit(1);
    final lastAmounts = <String, int>{
      for (final a in prev)
        for (final l in (a['allocation_line'] as List? ?? const []))
          if (l['deleted_at'] == null) l['account_id'] as String: l['planned_cents'] as int,
    };

    final String allocationId;
    try {
      final row = await _db
          .from('allocation')
          .insert({'week_start': isoDate(ws), 'config_id': configId})
          .select('id')
          .single();
      allocationId = row['id'] as String;
    } on PostgrestException catch (e) {
      // Another device created it at the same moment: use theirs.
      if (e.code == '23505') return (await _findAllocation(ws))!;
      rethrow;
    }
    if (accountIds.isNotEmpty) {
      await _db.from('allocation_line').insert([
        for (final id in accountIds)
          {'allocation_id': allocationId, 'account_id': id, 'planned_cents': lastAmounts[id] ?? 0},
      ]);
    }
    return (await _findAllocation(ws))!;
  }

  static Future<String> _configIdFor(DateTime ws) async {
    var rows = await _db
        .from('budget_config')
        .select('id')
        .isFilter('deleted_at', null)
        .lte('effective_from', isoDate(ws))
        .order('effective_from', ascending: false)
        .limit(1);
    if (rows.isEmpty) {
      rows = await _db
          .from('budget_config')
          .select('id')
          .isFilter('deleted_at', null)
          .order('effective_from', ascending: false)
          .limit(1);
    }
    return rows.first['id'] as String;
  }

  static Future<int> _weeklyAmountFor(DateTime ws) async {
    final id = await _configIdFor(ws);
    final row = await _db.from('budget_config').select('weekly_amount_cents').eq('id', id).single();
    return row['weekly_amount_cents'] as int;
  }

  static Future<void> setTransferAmount(String lineId, int cents) =>
      _db.from('allocation_line').update({'planned_cents': cents}).eq('id', lineId);

  static Future<void> setTransferDone(String lineId, bool done) => _db.from('allocation_line').update({
        'done': done,
        'done_at': done ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id', lineId);

  static Future<void> setPaydayStatus(String allocationId, bool allDone) => _db
      .from('allocation')
      .update({'status': allDone ? 'done' : 'open'}).eq('id', allocationId);
}
