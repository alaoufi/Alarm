import '../database/app_database.dart';
import '../models/reminder_log_entry.dart';

/// مستودع «سجلّ التنبيهات المنفّذة» (كل تنبيه فات وقته — لكل الأنواع).
class ReminderLogRepository {
  final AppDatabase _appDb;
  ReminderLogRepository(this._appDb);

  Future<List<ReminderLogEntry>> getAll() async {
    final db = await _appDb.database;
    final rows = await db.query('reminder_log', orderBy: 'at DESC');
    return rows.map(ReminderLogEntry.fromMap).toList();
  }

  Future<int> insert(ReminderLogEntry e) async {
    final db = await _appDb.database;
    return db.insert('reminder_log', e.toMap());
  }

  Future<void> delete(int id) async {
    final db = await _appDb.database;
    await db.delete('reminder_log', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await _appDb.database;
    await db.delete('reminder_log');
  }
}
