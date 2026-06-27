import 'package:sqflite_sqlcipher/sqflite.dart';

import '../database/app_database.dart';
import '../models/reminder.dart';

class ReminderRepository {
  final AppDatabase _appDb;
  ReminderRepository(this._appDb);

  Future<Database> get _db async => _appDb.database;

  Future<List<Reminder>> getAll() async {
    final db = await _db;
    final rows = await db.query('reminders', orderBy: 'time ASC');
    return rows.map(Reminder.fromMap).toList();
  }

  /// التذكيرات القادمة فقط (نشطة، أو متكررة).
  Future<List<Reminder>> getUpcoming() async {
    final db = await _db;
    final rows = await db.query('reminders',
        where: 'is_active = 1', orderBy: 'time ASC');
    return rows.map(Reminder.fromMap).toList();
  }

  Future<Reminder?> getForNote(int noteId) async {
    final db = await _db;
    final rows = await db.query('reminders', where: 'note_id = ?', whereArgs: [noteId]);
    if (rows.isEmpty) return null;
    return Reminder.fromMap(rows.first);
  }

  /// كل تذكيرات الملاحظة (قد تكون أكثر من واحد عند الأسبوعي بأيام متعددة).
  Future<List<Reminder>> getAllForNote(int noteId) async {
    final db = await _db;
    final rows = await db
        .query('reminders', where: 'note_id = ?', whereArgs: [noteId]);
    return rows.map(Reminder.fromMap).toList();
  }

  Future<int> insert(Reminder reminder) async {
    final db = await _db;
    return db.insert('reminders', reminder.toMap());
  }

  Future<void> update(Reminder reminder) async {
    final db = await _db;
    await db.update('reminders', reminder.toMap(), where: 'id = ?', whereArgs: [reminder.id]);
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('reminders', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteForNote(int noteId) async {
    final db = await _db;
    await db.delete('reminders', where: 'note_id = ?', whereArgs: [noteId]);
  }
}
