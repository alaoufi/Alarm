import 'package:sqflite_sqlcipher/sqflite.dart';

import '../database/app_database.dart';
import '../models/category.dart';

class CategoryRepository {
  final AppDatabase _appDb;
  CategoryRepository(this._appDb);

  Future<Database> get _db async => _appDb.database;

  Future<List<Category>> getAll() async {
    final db = await _db;
    final rows = await db.query('categories', orderBy: 'position ASC, id ASC');
    return rows.map(Category.fromMap).toList();
  }

  Future<int> insert(Category category) async {
    final db = await _db;
    return db.insert('categories', category.toMap());
  }

  /// يُرجع تصنيفًا بالاسم، ويُنشئه إن لم يكن موجودًا (يُستخدم لـ«الوارد»).
  Future<int> ensureByName(String name,
      {required int color, required int iconCode, int position = 0}) async {
    final db = await _db;
    final rows = await db
        .query('categories', where: 'name = ?', whereArgs: [name], limit: 1);
    if (rows.isNotEmpty) return rows.first['id'] as int;
    return db.insert(
        'categories',
        Category(name: name, color: color, iconCode: iconCode, position: position)
            .toMap());
  }

  Future<void> update(Category category) async {
    final db = await _db;
    await db.update('categories', category.toMap(), where: 'id = ?', whereArgs: [category.id]);
  }

  Future<void> delete(int id) async {
    final db = await _db;
    // الملاحظات المرتبطة تصبح بلا تصنيف (ON DELETE SET NULL).
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> reorder(List<Category> ordered) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (var i = 0; i < ordered.length; i++) {
        await txn.update('categories', {'position': i},
            where: 'id = ?', whereArgs: [ordered[i].id]);
      }
    });
  }
}
