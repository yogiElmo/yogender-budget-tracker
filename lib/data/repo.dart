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

class WeekData {
  final DateTime weekStart;
  final int weeklyCents;
  final List<Group> groups;
  final List<Category> categories;
  final List<Expense> expenses;
  WeekData(this.weekStart, this.weeklyCents, this.groups, this.categories, this.expenses);

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
    );
  }

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
}
