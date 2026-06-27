import '../database/app_database.dart';
import '../models/med_dose.dart';

/// مستودع سجلّ جرعات الدواء (وضع العلاج).
class MedRepository {
  final AppDatabase _appDb;
  MedRepository(this._appDb);

  Future<List<MedDose>> getAll() async {
    final db = await _appDb.database;
    final rows = await db.query('med_doses', orderBy: 'at DESC');
    return rows.map(MedDose.fromMap).toList();
  }

  Future<int> insert(MedDose d) async {
    final db = await _appDb.database;
    return db.insert('med_doses', d.toMap());
  }

  Future<void> delete(int id) async {
    final db = await _appDb.database;
    await db.delete('med_doses', where: 'id = ?', whereArgs: [id]);
  }

  /// أسماء الأدوية المسجّلة سابقًا (لاقتراحها عند الإضافة).
  Future<List<String>> distinctNames() async {
    final db = await _appDb.database;
    final rows = await db.rawQuery(
        'SELECT DISTINCT name FROM med_doses ORDER BY at DESC LIMIT 20');
    return rows.map((r) => (r['name'] as String?) ?? '').toList();
  }
}
