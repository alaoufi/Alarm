import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'db_key.dart';

/// مدير قاعدة بيانات SQLite المحلية.
///
/// كل البيانات تُخزَّن داخل الجهاز فقط — لا اتصال بأي خادم، والملف نفسه
/// مشفّر بالكامل عبر SQLCipher (AES-256) بمفتاح محفوظ في التخزين الآمن.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'mudhakkarati.db';
  static const _dbVersion = 19;

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database async {
    if (_db != null) return _db!;
    // قفل بسيط يمنع تشغيل _open (والترحيل) أكثر من مرة بالتوازي عند الإقلاع.
    _opening ??= _open();
    try {
      _db = await _opening!;
      return _db!;
    } finally {
      _opening = null;
    }
  }

  /// مسار ملف قاعدة البيانات (يُستخدم في النسخ الاحتياطي).
  Future<String> get path async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _dbName);
  }

  Future<Database> _open() async {
    final dbPath = await path;
    final key = await DbKeyManager.instance.getOrCreateKey();
    final dbFile = File(dbPath);

    // قاعدة جديدة تمامًا → تُنشأ مشفّرة مباشرة.
    if (!await dbFile.exists()) {
      await DbKeyManager.instance.markMigrated();
      return _openEncrypted(dbPath, key);
    }

    // سبق ترحيلها، أو هي مشفّرة بالفعل → افتحها مشفّرة.
    if (await DbKeyManager.instance.isMigrated() ||
        await _opensWithKey(dbPath, key)) {
      await DbKeyManager.instance.markMigrated();
      return _openEncrypted(dbPath, key);
    }

    // قاعدة نصّية قديمة → نحاول ترحيلها بأمان.
    try {
      await _migratePlainToEncrypted(dbPath, key);
      await DbKeyManager.instance.markMigrated();
      return _openEncrypted(dbPath, key);
    } catch (_) {
      // فشل الترحيل لأي سبب: لا نُعطّل التطبيق — نفتح النسخة النصّية كما هي
      // (بياناتك سليمة) ونعيد محاولة التشفير في الإقلاع التالي.
      return _openPlain(dbPath);
    }
  }

  Future<Database> _openEncrypted(String dbPath, String key) => openDatabase(
        dbPath,
        password: key,
        version: _dbVersion,
        onConfigure: _configure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

  Future<Database> _openPlain(String dbPath) => openDatabase(
        dbPath,
        version: _dbVersion,
        onConfigure: _configure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

  Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// يحوّل قاعدة بيانات نصّية إلى مشفّرة بأمان دون فقدان البيانات.
  ///
  /// يستخدم اتصالات غير مُخزّنة (singleInstance:false) واسم إرفاق فريد مع
  /// فصلٍ مضمون، ولا يستبدل الأصل إلا بعد التحقق من تطابق عدد الصفوف.
  Future<void> _migratePlainToEncrypted(String dbPath, String key) async {
    final encPath = '$dbPath.enc';
    final encFile = File(encPath);
    if (await encFile.exists()) await encFile.delete();

    // اسم إرفاق فريد لكل محاولة (تفاديًا لـ«enc already in use»).
    final alias = 'enc_${DateTime.now().millisecondsSinceEpoch}';

    final plain =
        await openDatabase(dbPath, singleInstance: false); // فتح نصّي غير مُخزّن.
    int srcNotes;
    int ver;
    try {
      ver = Sqflite.firstIntValue(
              await plain.rawQuery('PRAGMA user_version')) ??
          0;
      srcNotes = Sqflite.firstIntValue(
              await plain.rawQuery('SELECT COUNT(*) FROM notes')) ??
          0;
      await plain.rawQuery('ATTACH DATABASE ? AS $alias KEY ?', [encPath, key]);
      try {
        await plain.rawQuery("SELECT sqlcipher_export('$alias')");
        await plain.rawQuery('PRAGMA $alias.user_version = $ver');
      } finally {
        await plain.rawQuery('DETACH DATABASE $alias');
      }
    } finally {
      await plain.close();
    }

    // تحقّق: افتح المشفّرة وقارن عدد الملاحظات.
    final enc = await openDatabase(encPath, password: key, singleInstance: false);
    int dstNotes;
    try {
      dstNotes = Sqflite.firstIntValue(
              await enc.rawQuery('SELECT COUNT(*) FROM notes')) ??
          -1;
    } finally {
      await enc.close();
    }
    if (dstNotes != srcNotes) {
      if (await encFile.exists()) await encFile.delete();
      throw StateError('migration row count mismatch ($srcNotes -> $dstNotes)');
    }

    // نجح: ضع المشفّرة مكان الأصل (نحذف النصّي فعليًا لتحقيق التشفير).
    final bak = File('$dbPath.plain.bak');
    if (await bak.exists()) await bak.delete();
    await File(dbPath).rename(bak.path);
    await encFile.rename(dbPath);
    if (await bak.exists()) await bak.delete();
  }

  /// يحاول فتح القاعدة بالمفتاح؛ يعيد true إن نجح (أي أنها مشفّرة بالفعل).
  Future<bool> _opensWithKey(String dbPath, String key) async {
    try {
      final db = await openDatabase(dbPath,
          password: key, readOnly: true, singleInstance: false);
      await db.rawQuery('SELECT count(*) FROM sqlite_master');
      await db.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// إعادة فتح قاعدة البيانات (بعد استعادة نسخة احتياطية).
  Future<void> reopen() async {
    await _db?.close();
    _db = null;
    _opening = null;
    _db = await _open();
  }


  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        icon_code INTEGER NOT NULL,
        position INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'text',
        color INTEGER,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_locked INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        category_id INTEGER,
        image_path TEXT,
        audio_path TEXT,
        pdf_path TEXT,
        drawing_path TEXT,
        bg_style INTEGER NOT NULL DEFAULT 0,
        gradient TEXT,
        rule_on_line INTEGER,
        rule_thickness REAL,
        rule_opacity REAL,
        rule_line_height REAL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE checklist_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER NOT NULL,
        text TEXT NOT NULL DEFAULT '',
        is_done INTEGER NOT NULL DEFAULT 0,
        position INTEGER NOT NULL DEFAULT 0,
        is_task INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE note_tags (
        note_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (note_id, tag_id),
        FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER,
        title TEXT,
        time INTEGER NOT NULL,
        repeat TEXT NOT NULL DEFAULT 'once',
        is_active INTEGER NOT NULL DEFAULT 1,
        notification_id INTEGER NOT NULL,
        importance TEXT NOT NULL DEFAULT 'high',
        pre_alerts TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        attachment TEXT NOT NULL DEFAULT '',
        interval_days INTEGER NOT NULL DEFAULT 0,
        dose_count INTEGER NOT NULL DEFAULT 0,
        color INTEGER,
        FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
      )
    ''');

    await _createInfoTable(db);
    await _createMedTable(db);
    await _createReminderLogTable(db);

    await db.execute('CREATE INDEX idx_notes_uuid ON notes (uuid)');
    await db.execute('CREATE INDEX idx_notes_category ON notes (category_id)');
    await db.execute('CREATE INDEX idx_notes_flags ON notes (is_deleted, is_archived)');
    await db.execute('CREATE INDEX idx_checklist_note ON checklist_items (note_id)');
    await db.execute('CREATE INDEX idx_reminders_note ON reminders (note_id)');

    await _seedDefaultCategories(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE notes ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute(
          'ALTER TABLE notes ADD COLUMN bg_style INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 4) {
      await _createInfoTable(db);
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE notes ADD COLUMN gradient TEXT');
    }
    if (oldVersion < 6) {
      // تسطير لكل ملاحظة (null = استخدام الافتراضي العام من الإعدادات).
      await db.execute('ALTER TABLE notes ADD COLUMN rule_on_line INTEGER');
      await db.execute('ALTER TABLE notes ADD COLUMN rule_thickness REAL');
      await db.execute('ALTER TABLE notes ADD COLUMN rule_opacity REAL');
    }
    if (oldVersion < 7) {
      // تباعد أسطر التسطير لكل ملاحظة (null = الافتراضي العام).
      await db.execute('ALTER TABLE notes ADD COLUMN rule_line_height REAL');
    }
    if (oldVersion < 8) {
      // تنبيهات مستقلّة: note_id يصبح اختياريًّا + عمود عنوان. نعيد بناء الجدول
      // لأن SQLite لا يسمح بإزالة قيد NOT NULL. (إضافة فقط — لا تُفقد تذكيراتك.)
      await db.execute('PRAGMA foreign_keys=off');
      await db.execute('''
        CREATE TABLE reminders_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          note_id INTEGER,
          title TEXT,
          time INTEGER NOT NULL,
          repeat TEXT NOT NULL DEFAULT 'once',
          is_active INTEGER NOT NULL DEFAULT 1,
          notification_id INTEGER NOT NULL,
          FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        INSERT INTO reminders_new
          (id, note_id, time, repeat, is_active, notification_id)
        SELECT id, note_id, time, repeat, is_active, notification_id
        FROM reminders
      ''');
      await db.execute('DROP TABLE reminders');
      await db.execute('ALTER TABLE reminders_new RENAME TO reminders');
      await db.execute(
          'CREATE INDEX idx_reminders_note ON reminders (note_id)');
      await db.execute('PRAGMA foreign_keys=on');
    }
    if (oldVersion < 9) {
      // معرّف عالمي ثابت لكل ملاحظة (للمزامنة السحابية). نملأ الملاحظات الحالية
      // بمعرّفات فريدة (hex عشوائي 32 خانة) ثابتة لا تتغيّر بعدها.
      await db.execute('ALTER TABLE notes ADD COLUMN uuid TEXT');
      await db.execute(
          "UPDATE notes SET uuid = lower(hex(randomblob(16))) "
          "WHERE uuid IS NULL OR uuid = ''");
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_notes_uuid ON notes (uuid)');
    }
    if (oldVersion < 10) {
      // سطر مهمة (بمربع) أو نصّ عادي. الافتراضي مهمة (توافقًا مع القوائم القديمة).
      await db.execute(
          'ALTER TABLE checklist_items ADD COLUMN is_task INTEGER NOT NULL DEFAULT 1');
    }
    if (oldVersion < 11) {
      // مستوى أهمية التذكير (low/medium/high/critical). الافتراضي high.
      await db.execute(
          "ALTER TABLE reminders ADD COLUMN importance TEXT NOT NULL DEFAULT 'high'");
    }
    if (oldVersion < 12) {
      // تنبيهات مسبقة قبل الموعد (قائمة دقائق مفصولة بفواصل).
      await db.execute(
          "ALTER TABLE reminders ADD COLUMN pre_alerts TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 13) {
      // سجلّ جرعات الدواء.
      await _createMedTable(db);
    }
    if (oldVersion < 14) {
      // موقع التذكير (رابط خرائط) — للمواعيد.
      await db.execute(
          "ALTER TABLE reminders ADD COLUMN location TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 15) {
      // مرفق الدعوة (صورة/PDF) — للمواعيد.
      await db.execute(
          "ALTER TABLE reminders ADD COLUMN attachment TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 16) {
      // الدواء: فاصل أيام مخصّص + عدد جرعات الكورس.
      await db.execute(
          'ALTER TABLE reminders ADD COLUMN interval_days INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE reminders ADD COLUMN dose_count INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 17) {
      // سجلّ التنبيهات المنفّذة (لكل الأنواع).
      await _createReminderLogTable(db);
    }
    if (oldVersion < 18) {
      // علامات ملوّنة: لون يختاره المستخدم (0 = اشتقاق تلقائيّ من الاسم).
      await db.execute(
          'ALTER TABLE tags ADD COLUMN color INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 19) {
      // لون اختياريّ لكل تنبيه (null = اللون التلقائيّ حسب المجال الزمنيّ).
      await db.execute('ALTER TABLE reminders ADD COLUMN color INTEGER');
    }
  }

  /// جدول سجلّ التنبيهات المنفّذة (كل تنبيه فات وقته — لكل الأنواع).
  Future<void> _createReminderLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminder_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reminder_id INTEGER,
        title TEXT NOT NULL,
        at INTEGER NOT NULL
      )
    ''');
  }

  /// جدول سجلّ جرعات الدواء (وضع العلاج).
  Future<void> _createMedTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS med_doses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        dose TEXT,
        status TEXT NOT NULL DEFAULT 'taken',
        at INTEGER NOT NULL
      )
    ''');
  }

  /// جدول قاعدة المعلومات العامة (بحث/تصفّح داخلي).
  Future<void> _createInfoTable(Database db) async {
    await db.execute('''
      CREATE TABLE info_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        main_specialty TEXT NOT NULL DEFAULT '',
        sub_specialty TEXT NOT NULL DEFAULT '',
        topic TEXT NOT NULL DEFAULT '',
        brief TEXT NOT NULL DEFAULT '',
        detail TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_info_specialty ON info_entries (main_specialty, sub_specialty)');
  }

  /// التصنيفات الافتراضية المطلوبة: شخصي، عمل، مهم، مواعيد، أفكار.
  Future<void> _seedDefaultCategories(Database db) async {
    // icon_code يخزّن *فهرس* الأيقونة في kCategoryIcons (وليس codePoint).
    final defaults = <Map<String, dynamic>>[
      {'name': 'شخصي', 'color': 0xFF42A5F5, 'icon_code': 0, 'position': 0},
      {'name': 'عمل', 'color': 0xFF7E57C2, 'icon_code': 1, 'position': 1},
      {'name': 'مهم', 'color': 0xFFEF5350, 'icon_code': 2, 'position': 2},
      {'name': 'مواعيد', 'color': 0xFF26A69A, 'icon_code': 3, 'position': 3},
      {'name': 'أفكار', 'color': 0xFFFFA726, 'icon_code': 4, 'position': 4},
    ];
    for (final c in defaults) {
      await db.insert('categories', c);
    }
  }
}
