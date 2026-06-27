import 'package:sqflite_sqlcipher/sqflite.dart';

import '../database/app_database.dart';
import '../models/info_entry.dart';

/// عمليات قاعدة المعلومات العامة (قراءة/كتابة/بحث).
class InfoRepository {
  InfoRepository([AppDatabase? db]) : _appDb = db ?? AppDatabase.instance;
  final AppDatabase _appDb;

  Future<Database> get _db async => _appDb.database;

  /// كل العناصر (الأحدث أولًا).
  Future<List<InfoEntry>> getAll() async {
    final db = await _db;
    final rows = await db.query('info_entries', orderBy: 'created_at DESC');
    return rows.map(InfoEntry.fromMap).toList();
  }

  /// بحث في كل الحقول النصّية.
  Future<List<InfoEntry>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return getAll();
    final db = await _db;
    final like = '%$q%';
    final rows = await db.query(
      'info_entries',
      where: '''main_specialty LIKE ? OR sub_specialty LIKE ? OR topic LIKE ?
        OR brief LIKE ? OR detail LIKE ? OR notes LIKE ? OR source LIKE ?''',
      whereArgs: List.filled(7, like),
      orderBy: 'created_at DESC',
    );
    return rows.map(InfoEntry.fromMap).toList();
  }

  /// تصفية حسب التخصص الرئيسي و/أو الفرعي (مطابقة تامة).
  Future<List<InfoEntry>> filter({String? main, String? sub}) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object>[];
    if (main != null) {
      where.add('main_specialty = ?');
      args.add(main);
    }
    if (sub != null) {
      where.add('sub_specialty = ?');
      args.add(sub);
    }
    final rows = await db.query(
      'info_entries',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(InfoEntry.fromMap).toList();
  }

  /// قائمة التخصصات الرئيسية الفريدة (للاقتراح والتصفية).
  Future<List<String>> mainSpecialties() async {
    final db = await _db;
    final rows = await db.rawQuery(
        "SELECT DISTINCT main_specialty FROM info_entries WHERE main_specialty <> '' ORDER BY main_specialty");
    return rows.map((r) => r['main_specialty'] as String).toList();
  }

  Future<int> insert(InfoEntry e) async {
    final db = await _db;
    final map = e.toMap()..remove('id');
    return db.insert('info_entries', map);
  }

  Future<void> update(InfoEntry e) async {
    final db = await _db;
    await db.update('info_entries', e.toMap(),
        where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('info_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _db;
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM info_entries')) ??
        0;
  }
}
