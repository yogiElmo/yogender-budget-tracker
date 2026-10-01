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

class JarContribution {
  final String id;
  final int amountCents;
  final DateTime on;
  JarContribution(this.id, this.amountCents, this.on);
}

class Jar {
  final String id;
  final String name;
  final int? targetCents;
  final DateTime? targetDate;
  final List<JarContribution> contributions; // newest first
  Jar(this.id, this.name, this.targetCents, this.targetDate, this.contributions);

  int get savedCents => contributions.fold(0, (s, c) => s + c.amountCents);
  double? get progress =>
      targetCents == null || targetCents == 0 ? null : (savedCents / targetCents!).clamp(0, 1);
}

class IncomeSource {
  final String id;
  final String name;
  final double taxRatePercent;
  final bool isSideIncome;
  IncomeSource(this.id, this.name, this.taxRatePercent, this.isSideIncome);
}

class Income {
  final String id;
  final String sourceId;
  final int amountCents;
  final int taxCents;
  final DateTime receivedOn;
  final String? note;
  Income(this.id, this.sourceId, this.amountCents, this.taxCents, this.receivedOn, this.note);
  int get netCents => amountCents - taxCents;
}

class IncomeWeek {
  final DateTime weekStart;
  final int weeklyBudgetCents;
  final List<IncomeSource> sources;
  final List<Income> income;
  final int movedToJarsCents; // residual already put into jars this week
  final List<(String, String)> jars; // (id, name)
  IncomeWeek(this.weekStart, this.weeklyBudgetCents, this.sources, this.income,
      this.movedToJarsCents, this.jars);

  int get grossCents => income.fold(0, (s, i) => s + i.amountCents);
  int get taxCents => income.fold(0, (s, i) => s + i.taxCents);
  int get netCents => grossCents - taxCents;
  int get residualCents => (netCents - weeklyBudgetCents).clamp(0, 1 << 31);
  int get residualLeftCents => (residualCents - movedToJarsCents).clamp(0, 1 << 31);
}

class SettingsData {
  final int weeklyCents;
  final Map<String, double> percentByGroup;
  final DateTime? budgetFrom;
  final List<Group> groups;
  final List<(Category, bool)> categories; // (category, archived)
  final List<(Account, bool)> accounts; // (account, active)
  final List<IncomeSource> incomeSources;
  SettingsData(this.weeklyCents, this.percentByGroup, this.budgetFrom, this.groups, this.categories,
      this.accounts, this.incomeSources);
}

class WeekData {
  final DateTime weekStart;
  final int weeklyCents;
  final List<Group> groups;
  final List<Category> categories;
  final List<Expense> expenses;
  final int transfersToDo; // payday transfers with an amount set this week
  final int transfersDone;
  final int jarCount;
  final int jarsSavedCents;
  final int incomeCents;
  final int incomeTaxCents;
  final int residualLeftCents;
  WeekData(this.weekStart, this.weeklyCents, this.groups, this.categories, this.expenses,
      {this.transfersToDo = 0,
      this.transfersDone = 0,
      this.jarCount = 0,
      this.jarsSavedCents = 0,
      this.incomeCents = 0,
      this.incomeTaxCents = 0,
      this.residualLeftCents = 0});

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
      _db
          .from('jar')
          .select('id, jar_contribution(amount_cents, deleted_at)')
          .isFilter('deleted_at', null)
          .eq('archived', false),
      _db
          .from('income')
          .select('amount_cents, tax_set_aside_cents')
          .isFilter('deleted_at', null)
          .gte('received_on', isoDate(ws))
          .lte('received_on', isoDate(we)),
      _db
          .from('weekly_residual')
          .select('residual_left_cents')
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
      jarCount: results[5].length,
      jarsSavedCents: [
        for (final j in results[5])
          for (final c in (j['jar_contribution'] as List? ?? const []))
            if (c['deleted_at'] == null) c['amount_cents'] as int,
      ].fold(0, (a, b) => a + b),
      incomeCents: results[6].fold(0, (s, r) => s + (r['amount_cents'] as int)),
      incomeTaxCents: results[6].fold(0, (s, r) => s + (r['tax_set_aside_cents'] as int)),
      residualLeftCents: results[7].isEmpty
          ? 0
          : ((results[7].first['residual_left_cents'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
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

  // ---------------------------------------------------------------- jars

  static Future<List<Jar>> loadJars() async {
    final rows = await _db
        .from('jar')
        .select('id, name, target_cents, target_date, '
            'jar_contribution(id, amount_cents, contributed_on, created_at, deleted_at)')
        .isFilter('deleted_at', null)
        .eq('archived', false)
        .order('created_at')
        .order('name');
    return [
      for (final r in rows)
        Jar(
          r['id'] as String,
          r['name'] as String,
          r['target_cents'] as int?,
          r['target_date'] == null ? null : DateTime.parse(r['target_date'] as String),
          ([
            for (final c in (r['jar_contribution'] as List? ?? const []))
              if (c['deleted_at'] == null) c as Map<String, dynamic>,
          ]..sort((a, b) {
                  final byDay = (b['contributed_on'] as String).compareTo(a['contributed_on'] as String);
                  return byDay != 0
                      ? byDay
                      : (b['created_at'] as String).compareTo(a['created_at'] as String);
                }))
              .map((c) => JarContribution(c['id'] as String, c['amount_cents'] as int,
                  DateTime.parse(c['contributed_on'] as String)))
              .toList(),
        ),
    ];
  }

  static Future<void> addJar({required String name, int? targetCents, DateTime? targetDate}) =>
      _db.from('jar').insert({
        'name': name.trim(),
        'target_cents': targetCents,
        'target_date': targetDate == null ? null : isoDate(targetDate),
      });

  static Future<void> updateJar(String id,
          {required String name, int? targetCents, DateTime? targetDate}) =>
      _db.from('jar').update({
        'name': name.trim(),
        'target_cents': targetCents,
        'target_date': targetDate == null ? null : isoDate(targetDate),
      }).eq('id', id);

  /// Hides a finished or abandoned jar; its history is kept.
  static Future<void> archiveJar(String id) =>
      _db.from('jar').update({'archived': true}).eq('id', id);

  static Future<void> addToJar(String jarId, int cents, DateTime on) =>
      _db.from('jar_contribution').insert({
        'jar_id': jarId,
        'amount_cents': cents,
        'source': 'other',
        'contributed_on': isoDate(on),
      });

  static Future<void> deleteJarContribution(String id) => _db
      .from('jar_contribution')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);

  // ---------------------------------------------------------------- history

  /// Groups and every category, archived ones included, so old entries still have names.
  static Future<(List<Group>, List<Category>)> loadCatalog() async {
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _db
          .from('category_group')
          .select('id, name, sort_order')
          .isFilter('deleted_at', null)
          .order('sort_order'),
      _db.from('category').select('id, name, group_id').isFilter('deleted_at', null).order('name'),
    ]);
    return (
      [
        for (final g in results[0])
          Group(g['id'] as String, g['name'] as String, g['sort_order'] as int, 0),
      ],
      [
        for (final c in results[1])
          Category(c['id'] as String, c['name'] as String, c['group_id'] as String),
      ],
    );
  }

  static Future<List<Expense>> loadExpenses(DateTime from, DateTime to) async {
    final rows = await _db
        .from('expense')
        .select('id, amount_cents, category_id, spent_on, note')
        .isFilter('deleted_at', null)
        .gte('spent_on', isoDate(from))
        .lte('spent_on', isoDate(to))
        .order('spent_on', ascending: false)
        .order('created_at', ascending: false)
        .limit(2000);
    return [for (final r in rows) Expense.fromRow(r)];
  }

  // ---------------------------------------------------------------- settings

  static Future<SettingsData> loadSettings() async {
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _db
          .from('budget_config')
          .select('weekly_amount_cents, effective_from, budget_split(group_id, percent, deleted_at)')
          .isFilter('deleted_at', null)
          .lte('effective_from', isoDate(weekStartOf(DateTime.now())))
          .order('effective_from', ascending: false)
          .limit(1),
      _db
          .from('category_group')
          .select('id, name, sort_order')
          .isFilter('deleted_at', null)
          .order('sort_order'),
      _db
          .from('category')
          .select('id, name, group_id, archived')
          .isFilter('deleted_at', null)
          .order('name'),
      _db
          .from('account')
          .select('id, name, type, purpose, active')
          .isFilter('deleted_at', null)
          .order('created_at')
          .order('name'),
      _db
          .from('income_source')
          .select('id, name, tax_rate_percent, is_side_income')
          .isFilter('deleted_at', null)
          .order('created_at'),
    ]);
    var config = results[0].isEmpty ? null : results[0].first;
    if (config == null) {
      final newest = await _db
          .from('budget_config')
          .select('weekly_amount_cents, effective_from, budget_split(group_id, percent, deleted_at)')
          .isFilter('deleted_at', null)
          .order('effective_from', ascending: false)
          .limit(1);
      config = newest.isEmpty ? null : newest.first;
    }
    return SettingsData(
      config?['weekly_amount_cents'] as int? ?? 0,
      {
        for (final sp in (config?['budget_split'] as List? ?? const []))
          if (sp['deleted_at'] == null) sp['group_id'] as String: (sp['percent'] as num).toDouble(),
      },
      config == null ? null : DateTime.parse(config['effective_from'] as String),
      [
        for (final g in results[1])
          Group(g['id'] as String, g['name'] as String, g['sort_order'] as int, 0),
      ],
      [
        for (final c in results[2])
          (
            Category(c['id'] as String, c['name'] as String, c['group_id'] as String),
            c['archived'] as bool,
          ),
      ],
      [
        for (final a in results[3])
          (
            Account(a['id'] as String, a['name'] as String, a['type'] as String,
                a['purpose'] as String?),
            a['active'] as bool,
          ),
      ],
      [
        for (final i in results[4])
          IncomeSource(i['id'] as String, i['name'] as String,
              (i['tax_rate_percent'] as num).toDouble(), i['is_side_income'] as bool),
      ],
    );
  }

  /// Saves a new weekly amount and split, starting this week. Earlier weeks keep
  /// the numbers they had; a second change in the same week replaces the first.
  static Future<void> saveBudget(int weeklyCents, Map<String, double> percentByGroup) async {
    final ws = isoDate(weekStartOf(DateTime.now()));
    final existing = await _db
        .from('budget_config')
        .select('id')
        .isFilter('deleted_at', null)
        .eq('effective_from', ws)
        .maybeSingle();
    final String configId;
    if (existing != null) {
      configId = existing['id'] as String;
      await _db.from('budget_config').update({'weekly_amount_cents': weeklyCents}).eq('id', configId);
    } else {
      final row = await _db
          .from('budget_config')
          .insert({'weekly_amount_cents': weeklyCents, 'effective_from': ws})
          .select('id')
          .single();
      configId = row['id'] as String;
    }
    await _db.from('budget_split').upsert([
      for (final e in percentByGroup.entries)
        {'config_id': configId, 'group_id': e.key, 'percent': e.value, 'deleted_at': null},
    ], onConflict: 'config_id,group_id');
  }

  static Future<void> renameCategory(String id, String name) =>
      _db.from('category').update({'name': name.trim()}).eq('id', id);

  static Future<void> setCategoryArchived(String id, bool archived) =>
      _db.from('category').update({'archived': archived}).eq('id', id);

  static Future<void> saveAccount(
      {String? id, required String name, required String type, String? purpose}) {
    final data = {
      'name': name.trim(),
      'type': type,
      'purpose': (purpose == null || purpose.trim().isEmpty) ? null : purpose.trim(),
    };
    return id == null
        ? _db.from('account').insert(data)
        : _db.from('account').update(data).eq('id', id);
  }

  static Future<void> setAccountActive(String id, bool active) =>
      _db.from('account').update({'active': active}).eq('id', id);

  static Future<void> saveIncomeSource(
      {String? id, required String name, required double taxRate, required bool isSide}) {
    final data = {'name': name.trim(), 'tax_rate_percent': taxRate, 'is_side_income': isSide};
    return id == null
        ? _db.from('income_source').insert(data)
        : _db.from('income_source').update(data).eq('id', id);
  }

  static Future<void> deleteIncomeSource(String id) => _db
      .from('income_source')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);

  // ---------------------------------------------------------------- income

  static Future<IncomeWeek> loadIncomeWeek(DateTime anyDay) async {
    final ws = weekStartOf(anyDay);
    final we = addDays(ws, 6);
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _db
          .from('income_source')
          .select('id, name, tax_rate_percent, is_side_income')
          .isFilter('deleted_at', null)
          .order('created_at'),
      _db
          .from('income')
          .select('id, source_id, amount_cents, tax_set_aside_cents, received_on, note')
          .isFilter('deleted_at', null)
          .gte('received_on', isoDate(ws))
          .lte('received_on', isoDate(we))
          .order('received_on', ascending: false)
          .order('created_at', ascending: false),
      _db
          .from('jar_contribution')
          .select('amount_cents')
          .isFilter('deleted_at', null)
          .eq('source', 'residual')
          .gte('contributed_on', isoDate(ws))
          .lte('contributed_on', isoDate(we)),
      _db
          .from('jar')
          .select('id, name')
          .isFilter('deleted_at', null)
          .eq('archived', false)
          .order('created_at')
          .order('name'),
    ]);
    return IncomeWeek(
      ws,
      await _weeklyAmountFor(ws),
      [
        for (final i in results[0])
          IncomeSource(i['id'] as String, i['name'] as String,
              (i['tax_rate_percent'] as num).toDouble(), i['is_side_income'] as bool),
      ],
      [
        for (final r in results[1])
          Income(
            r['id'] as String,
            r['source_id'] as String,
            r['amount_cents'] as int,
            r['tax_set_aside_cents'] as int,
            DateTime.parse(r['received_on'] as String),
            (r['note'] as String?)?.trim().isEmpty ?? true ? null : r['note'] as String,
          ),
      ],
      results[2].fold(0, (s, r) => s + (r['amount_cents'] as int)),
      [for (final j in results[3]) (j['id'] as String, j['name'] as String)],
    );
  }

  /// Tax is worked out from the source's rate now and stored, so a later
  /// change to the rate doesn't rewrite past income.
  static Future<void> addIncome({
    required String sourceId,
    required int amountCents,
    required int taxCents,
    required DateTime receivedOn,
    String? note,
  }) =>
      _db.from('income').insert({
        'source_id': sourceId,
        'amount_cents': amountCents,
        'tax_set_aside_cents': taxCents,
        'received_on': isoDate(receivedOn),
        'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      });

  static Future<void> deleteIncome(String id) => _db
      .from('income')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);

  static Future<IncomeSource> addIncomeSource(
      {required String name, required double taxRate, required bool isSide}) async {
    final r = await _db
        .from('income_source')
        .insert({'name': name.trim(), 'tax_rate_percent': taxRate, 'is_side_income': isSide})
        .select('id, name, tax_rate_percent, is_side_income')
        .single();
    return IncomeSource(r['id'] as String, r['name'] as String,
        (r['tax_rate_percent'] as num).toDouble(), r['is_side_income'] as bool);
  }

  /// Moves money earned above the weekly budget into a savings jar.
  static Future<void> moveResidualToJar(String jarId, int cents, DateTime weekStart) {
    final today = dateOnly(DateTime.now());
    final weekEnd = addDays(weekStart, 6);
    // Dated inside the week it came from, so that week's residual goes down.
    final on = today.isAfter(weekEnd) ? weekEnd : today;
    return _db.from('jar_contribution').insert({
      'jar_id': jarId,
      'amount_cents': cents,
      'source': 'residual',
      'contributed_on': isoDate(on),
    });
  }
}
