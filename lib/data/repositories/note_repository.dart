import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/checklist_item.dart';
import '../models/enums.dart';
import '../models/note.dart';

/// كل عمليات قراءة/كتابة الملاحظات وقوائم المهام والوسوم.
class NoteRepository {
  final AppDatabase _appDb;
  NoteRepository(this._appDb);

  Future<Database> get _db async => _appDb.database;

  // ---------------------------------------------------------------------------
  // قراءة الملاحظات
  // ---------------------------------------------------------------------------

  /// الملاحظات النشطة (غير محذوفة وغير مؤرشفة وغير مقفلة) مع فلترة اختيارية.
  ///
  /// الملاحظات المقفلة (السرية وكلمات المرور) تُستبعد من القائمة الرئيسية
  /// وتظهر فقط في القسم السري المحمي. [onlyFavorites] لقسم المفضلة.
  Future<List<Note>> getNotes({
    int? categoryId,
    String? tag,
    String? search,
    bool onlyFavorites = false,
    NoteSort sort = NoteSort.updatedDesc,
    // فلاتر البحث المتقدّم (افتراضيًّا معطّلة فلا تؤثّر على النداءات الحالية).
    NoteType? type,
    bool onlyPinned = false,
    bool onlyLocked = false,
    bool hasImage = false,
    bool hasAudio = false,
    bool hasPdf = false,
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _db;

    final where = <String>[
      'n.is_deleted = 0',
      'n.is_archived = 0',
      // الملاحظات المقفلة تبقى ظاهرة في مكانها (بمحتوى مُخفى) وتُفتح برقم سري.
    ];
    final args = <dynamic>[];

    if (onlyFavorites) where.add('n.is_favorite = 1');
    if (onlyPinned) where.add('n.is_pinned = 1');
    if (onlyLocked) where.add('n.is_locked = 1');
    if (hasImage) where.add('n.image_path IS NOT NULL');
    if (hasAudio) where.add('n.audio_path IS NOT NULL');
    if (hasPdf) where.add('n.pdf_path IS NOT NULL');
    if (type != null) {
      where.add('n.type = ?');
      args.add(type.dbValue);
    }
    if (from != null) {
      where.add('n.updated_at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('n.updated_at <= ?');
      args.add(to.millisecondsSinceEpoch);
    }
    if (categoryId != null) {
      where.add('n.category_id = ?');
      args.add(categoryId);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(n.title LIKE ? OR n.content LIKE ?)');
      final like = '%${search.trim()}%';
      args.add(like);
      args.add(like);
    }

    String sql = 'SELECT n.* FROM notes n';
    if (tag != null && tag.isNotEmpty) {
      sql += '''
        JOIN note_tags nt ON nt.note_id = n.id
        JOIN tags t ON t.id = nt.tag_id AND t.name = ?
      ''';
      args.insert(0, tag);
    }
    sql += ' WHERE ${where.join(' AND ')}';
    final order = switch (sort) {
      NoteSort.updatedDesc => 'n.updated_at DESC',
      NoteSort.createdDesc => 'n.created_at DESC',
      NoteSort.createdAsc => 'n.created_at ASC',
      NoteSort.titleAsc => 'n.title COLLATE NOCASE ASC',
    };
    sql += ' ORDER BY n.is_pinned DESC, $order';

    final rows = await db.rawQuery(sql, args);
    return _attachTags(db, rows);
  }

  Future<List<Note>> getArchived() async {
    final db = await _db;
    final rows = await db.query(
      'notes',
      where: 'is_archived = 1 AND is_deleted = 0',
      orderBy: 'updated_at DESC',
    );
    return _attachTags(db, rows);
  }

  Future<List<Note>> getTrash() async {
    final db = await _db;
    final rows = await db.query(
      'notes',
      where: 'is_deleted = 1',
      orderBy: 'deleted_at DESC',
    );
    return _attachTags(db, rows);
  }

  /// كل الملاحظات (لأغراض الاستيراد/منع التكرار).
  Future<List<Note>> getEverything() async {
    final db = await _db;
    final rows = await db.query('notes');
    return _attachTags(db, rows);
  }

  /// الملاحظات السرية المقفلة (للقسم المحمي).
  Future<List<Note>> getLocked() async {    final db = await _db;
    final rows = await db.query(
      'notes',
      where: 'is_locked = 1 AND is_deleted = 0 AND is_archived = 0',
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return _attachTags(db, rows);
  }

  Future<Note?> getNote(int id) async {
    final db = await _db;
    final rows = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final notes = await _attachTags(db, rows);
    return notes.first;
  }

  /// الملاحظات التي تشير إلى عنوان معيّن عبر رابط داخلي [[العنوان]].
  Future<List<Note>> findBacklinks(String title) async {
    final t = title.trim();
    if (t.isEmpty) return [];
    final db = await _db;
    final rows = await db.query('notes',
        where: 'is_deleted = 0 AND content LIKE ?', whereArgs: ['%[[$t]]%']);
    return _attachTags(db, rows);
  }

  /// يبحث عن ملاحظة نشطة بعنوان مطابق (يُستخدم لملاحظة اليوم).
  Future<Note?> findByTitle(String title) async {
    final db = await _db;
    final rows = await db.query('notes',
        where: 'title = ? AND is_deleted = 0 AND is_archived = 0',
        whereArgs: [title],
        orderBy: 'updated_at DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return (await _attachTags(db, rows)).first;
  }

  Future<List<Note>> _attachTags(Database db, List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return [];
    // استعلام واحد لكل الوسوم (بدل استعلام لكل ملاحظة) — أسرع بكثير في القوائم الكبيرة.
    final ids = rows.map((r) => r['id'] as int).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final tagRows = await db.rawQuery(
      'SELECT nt.note_id AS nid, t.name AS name FROM note_tags nt '
      'JOIN tags t ON t.id = nt.tag_id WHERE nt.note_id IN ($placeholders) '
      'ORDER BY t.name',
      ids,
    );
    final byNote = <int, List<String>>{};
    for (final tr in tagRows) {
      (byNote[tr['nid'] as int] ??= []).add(tr['name'] as String);
    }
    return rows
        .map((row) =>
            Note.fromMap(row, tags: byNote[row['id'] as int] ?? const []))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // كتابة الملاحظات
  // ---------------------------------------------------------------------------

  Future<int> insertNote(Note note) async {
    final db = await _db;
    // الإدراج ينشئ صفًّا جديدًا دائمًا؛ نُسقِط المعرّف لتفادي تعارض
    // UNIQUE عند تكرار/استيراد ملاحظة تحمل معرّفًا موجودًا.
    final map = note.toMap()..remove('id');
    final id = await db.insert('notes', map);
    await _saveTags(db, id, note.tags);
    return id;
  }

  Future<void> updateNote(Note note) async {
    final db = await _db;
    final updated = note.copyWith(updatedAt: DateTime.now());
    await db.update('notes', updated.toMap(), where: 'id = ?', whereArgs: [note.id]);
    await _saveTags(db, note.id!, note.tags);
  }

  /// حفظ ملاحظة جديدة أو تحديث الموجودة. يُعيد المعرّف.
  Future<int> upsertNote(Note note) async {
    if (note.id == null) {
      return insertNote(note);
    }
    await updateNote(note);
    return note.id!;
  }

  /// يطبّق نمط الصفحة نفسه (لون + نمط + تدرّج + تسطير + **تباعد الأسطر**) على
  /// **كل الملاحظات** غير المحذوفة دفعةً واحدة. يعيد عدد الملاحظات المُحدَّثة. لا
  /// يغيّر updated_at كي لا يُعيد ترتيب القائمة (تغيير شكليّ).
  Future<int> applyBackgroundToAll({
    int? color,
    required int bgStyle,
    String? gradient,
    bool? ruleOnLine,
    double? ruleThickness,
    double? ruleOpacity,
    double? ruleLineHeight,
  }) async {
    final db = await _db;
    return db.update(
      'notes',
      {
        'color': color,
        'bg_style': bgStyle,
        'gradient': gradient,
        'rule_on_line': ruleOnLine == null ? null : (ruleOnLine ? 1 : 0),
        'rule_thickness': ruleThickness,
        'rule_opacity': ruleOpacity,
        'rule_line_height': ruleLineHeight,
      },
      where: 'is_deleted = 0',
    );
  }

  Future<void> togglePin(Note note) async {
    final db = await _db;
    await db.update(
      'notes',
      {'is_pinned': note.isPinned ? 0 : 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  /// تثبيت/إلغاء تثبيت بالمعرّف (للعمليات الجماعية).
  Future<void> setPinned(int id, bool pinned) async {
    final db = await _db;
    await db.update(
      'notes',
      {'is_pinned': pinned ? 1 : 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// نقل ملاحظة إلى تصنيف (أو إزالته) بالمعرّف (للعمليات الجماعية).
  Future<void> setCategory(int id, int? categoryId) async {
    final db = await _db;
    await db.update(
      'notes',
      {'category_id': categoryId, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleFavorite(Note note) async {
    final db = await _db;
    await db.update(
      'notes',
      {'is_favorite': note.isFavorite ? 0 : 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> setArchived(int id, bool archived) async {
    final db = await _db;
    await db.update(
      'notes',
      {'is_archived': archived ? 1 : 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setColor(int id, int? color) async {
    final db = await _db;
    await db.update(
        'notes',
        {'color': color, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id]);
  }

  Future<void> setLocked(int id, bool locked) async {
    final db = await _db;
    await db.update(
        'notes',
        {
          'is_locked': locked ? 1 : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // سلة المحذوفات
  // ---------------------------------------------------------------------------

  Future<void> moveToTrash(int id) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    // نُحدّث updated_at أيضًا كي ينتشر الحذف عبر المزامنة (آخر تعديل يفوز).
    await db.update(
      'notes',
      {'is_deleted': 1, 'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> restoreFromTrash(int id) async {
    final db = await _db;
    await db.update(
      'notes',
      {'is_deleted': 0, 'deleted_at': null, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePermanently(int id) async {
    final db = await _db;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> emptyTrash() async {
    final db = await _db;
    await db.delete('notes', where: 'is_deleted = 1');
  }

  /// حذف كل الملاحظات نهائيًا (يُستخدم في «حذف الحالي وإعادة الاستيراد»).
  /// الوسوم وعناصر القوائم والتذكيرات تُحذف تلقائيًا (ON DELETE CASCADE).
  Future<int> deleteAllNotes() async {
    final db = await _db;
    return db.delete('notes');
  }

  /// حذف عناصر السلة الأقدم من [days] يومًا (تنظيف تلقائي).
  Future<void> purgeOldTrash({int days = 30}) async {
    final db = await _db;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    await db.delete('notes', where: 'is_deleted = 1 AND deleted_at < ?', whereArgs: [cutoff]);
  }

  /// نسخ ملاحظة (مع عناصر القائمة والوسوم).
  Future<int> duplicate(int id) async {
    final db = await _db;
    final note = await getNote(id);
    if (note == null) return -1;
    final now = DateTime.now();
    final copy = note.copyWith(
      id: null,
      uuid: const Uuid().v4(), // نسخة مستقلّة ⇒ معرّف مزامنة جديد.
      title: note.title.isEmpty ? note.title : '${note.title} (نسخة)',
      isPinned: false,
      createdAt: now,
      updatedAt: now,
    );
    final newId = await insertNote(copy);
    final items = await getChecklist(id);
    for (final item in items) {
      await db.insert('checklist_items', item.copyWith(id: null, noteId: newId).toMap());
    }
    return newId;
  }

  // ---------------------------------------------------------------------------
  // قوائم المهام (Checklist)
  // ---------------------------------------------------------------------------

  Future<List<ChecklistItem>> getChecklist(int noteId) async {
    final db = await _db;
    final rows = await db.query(
      'checklist_items',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'position ASC, id ASC',
    );
    return rows.map(ChecklistItem.fromMap).toList();
  }

  Future<void> saveChecklist(int noteId, List<ChecklistItem> items) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('checklist_items', where: 'note_id = ?', whereArgs: [noteId]);
      for (var i = 0; i < items.length; i++) {
        final item = items[i].copyWith(noteId: noteId, position: i, id: null);
        await txn.insert('checklist_items', item.toMap());
      }
    });
  }

  // ---------------------------------------------------------------------------
  // الوسوم (Tags)
  // ---------------------------------------------------------------------------

  /// عدد الملاحظات الظاهرة (غير محذوفة/مؤرشفة) لكل تصنيف + الإجماليّ — لشارات
  /// شرائح التصنيفات في الرئيسية.
  Future<({Map<int, int> byCategory, int total})> homeCounts() async {
    final db = await _db;
    final rows = await db.rawQuery(
        'SELECT category_id, COUNT(*) AS c FROM notes '
        'WHERE is_deleted = 0 AND is_archived = 0 GROUP BY category_id');
    final map = <int, int>{};
    var total = 0;
    for (final r in rows) {
      final cnt = (r['c'] as int?) ?? 0;
      total += cnt;
      final cid = r['category_id'] as int?;
      if (cid != null) map[cid] = cnt;
    }
    return (byCategory: map, total: total);
  }

  /// معرّفات الملاحظات التي لها تنبيه نشِط (لإظهار مؤشّر على البطاقة).
  Future<Set<int>> noteIdsWithReminders() async {
    final db = await _db;
    final rows = await db.rawQuery(
        'SELECT DISTINCT note_id FROM reminders '
        'WHERE note_id IS NOT NULL AND is_active = 1');
    return rows.map((r) => r['note_id'] as int).toSet();
  }

  Future<List<String>> getAllTags() async {
    final db = await _db;
    final rows = await db.query('tags', orderBy: 'name ASC');
    return rows.map((e) => e['name'] as String).toList();
  }

  /// كل الوسوم مع ألوانها المختارة (0 = اشتقاق تلقائيّ من الاسم).
  Future<List<({String name, int color})>> getAllTagsWithColors() async {
    final db = await _db;
    final rows = await db.query('tags', orderBy: 'name ASC');
    return rows
        .map((e) => (
              name: e['name'] as String,
              color: (e['color'] as int?) ?? 0,
            ))
        .toList();
  }

  /// يضبط لون وسم (بالاسم). 0 يعيده إلى اللون التلقائيّ.
  Future<void> setTagColor(String name, int color) async {
    final db = await _db;
    await db.update('tags', {'color': color},
        where: 'name = ?', whereArgs: [name]);
  }

  Future<void> _saveTags(Database db, int noteId, List<String> tags) async {
    await db.delete('note_tags', where: 'note_id = ?', whereArgs: [noteId]);
    for (final raw in tags) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      int tagId;
      final existing = await db.query('tags', where: 'name = ?', whereArgs: [name]);
      if (existing.isNotEmpty) {
        tagId = existing.first['id'] as int;
      } else {
        tagId = await db.insert('tags', {'name': name});
      }
      await db.insert(
        'note_tags',
        {'note_id': noteId, 'tag_id': tagId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    // إزالة الوسوم التي لم تعد مستخدمة.
    await db.rawDelete(
      'DELETE FROM tags WHERE id NOT IN (SELECT DISTINCT tag_id FROM note_tags)',
    );
  }

  // ---------------------------------------------------------------------------
  // إحصائيات / تقويم
  // ---------------------------------------------------------------------------

  Future<int> countByCategory(int categoryId) async {
    final db = await _db;
    final r = await db.rawQuery(
      'SELECT COUNT(*) c FROM notes WHERE category_id = ? AND is_deleted = 0 AND is_archived = 0',
      [categoryId],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }
}
