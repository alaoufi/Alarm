import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import '../data/database/db_key.dart';
import '../data/models/note.dart';
import '../data/models/reminder.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/note_repository.dart';
import '../data/repositories/reminder_repository.dart';
import 'encryption_service.dart';
import 'file_service.dart';

/// نتيجة عملية النسخ الاحتياطي.
class BackupResult {
  final bool success;
  final String message;
  final String? filePath;
  const BackupResult(this.success, this.message, {this.filePath});
}

/// إنشاء/استعادة نسخة احتياطية محلية مشفّرة.
///
/// النسخة عبارة عن ملف ZIP (قاعدة البيانات + كل المرفقات) مشفّر بـ AES-256،
/// يُحفظ في ملفات الجهاز التي يختارها المستخدم. تعمل بالكامل دون إنترنت.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _ext = 'mdkbak';

  // مفاتيح حفظ وقت آخر عملية لكل وجهة.
  static const _kLastLocal = 'last_backup_local';
  static const _kLastShare = 'last_backup_share';
  static const _kLastRestore = 'last_restore';

  // ---- إعدادات النسخ الاحتياطي التلقائي ----
  static const _kAutoEnabled = 'auto_backup_enabled';
  static const _kAutoIntervalDays = 'auto_backup_interval_days';
  static const _kAutoKeep = 'auto_backup_keep';
  static const _kLastAuto = 'last_auto_backup';
  static const _kAutoDir = 'auto_backup_dir'; // مجلّد مخصّص يختاره المستخدم
  // علامة تفعيل النسخ التلقائي افتراضيًا عند أول تشغيل (مرّة واحدة فقط).
  static const _kBootstrapped = 'auto_backup_bootstrapped';
  // كلمة مرور النسخ التلقائي تُحفظ في التخزين الآمن (Keystore) حتى تعمل
  // النسخة دون تدخّل المستخدم.
  static const _kAutoPwd = 'auto_backup_password';

  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> _stamp(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
  }

  Future<DateTime?> _readStamp(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<DateTime?> lastLocalBackup() => _readStamp(_kLastLocal);
  Future<DateTime?> lastShareBackup() => _readStamp(_kLastShare);
  Future<DateTime?> lastRestore() => _readStamp(_kLastRestore);
  Future<DateTime?> lastAutoBackup() => _readStamp(_kLastAuto);

  // ---- تذكير النسخة الخارجية (سحابة/ملف) قبل التحديثات ----
  static const _kExtReminderSnooze = 'ext_backup_reminder_snooze';

  /// آخر نسخة **خارجية** (حفظ محلي بمنتقي الملفات أو مشاركة سحابية) — الأحدث
  /// بينهما. النسخة الخارجية وحدها تنجو من إلغاء التثبيت/فقدان الجهاز.
  Future<DateTime?> lastExternalBackup() async {
    final a = await lastLocalBackup();
    final b = await lastShareBackup();
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// هل نُذكّر المستخدم بأخذ نسخة خارجية؟ (لم يأخذ نسخة خارجية منذ ≥ 7 أيام،
  /// ولم يؤجّل التذكير مؤخّرًا).
  Future<bool> needsExternalBackupReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final snoozeMs = prefs.getInt(_kExtReminderSnooze);
    if (snoozeMs != null &&
        DateTime.now().isBefore(DateTime.fromMillisecondsSinceEpoch(snoozeMs))) {
      return false;
    }
    final last = await lastExternalBackup();
    if (last == null) return true;
    return DateTime.now().difference(last) >= const Duration(days: 7);
  }

  /// يؤجّل تذكير النسخة الخارجية [days] يومًا (افتراضي 3).
  Future<void> snoozeExternalBackupReminder({int days = 3}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kExtReminderSnooze,
        DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch);
  }

  // ---- قراءة/ضبط إعدادات النسخ التلقائي ----

  Future<bool> autoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoEnabled) ?? false;
  }

  /// الفاصل الزمني بين النسخ التلقائية بالأيام (1 = يومي، 7 = أسبوعي).
  Future<int> autoBackupIntervalDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kAutoIntervalDays) ?? 1;
  }

  /// عدد النسخ التلقائية المحفوظة قبل حذف الأقدم.
  Future<int> autoBackupKeep() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kAutoKeep) ?? 5;
  }

  Future<void> setAutoBackupEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoEnabled, v);
  }

  Future<void> setAutoBackupIntervalDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAutoIntervalDays, days);
  }

  Future<void> setAutoBackupKeep(int n) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAutoKeep, n);
  }

  Future<void> setAutoBackupPassword(String password) async {
    await _secure.write(key: _kAutoPwd, value: password);
  }

  Future<bool> hasAutoBackupPassword() async {
    final v = await _secure.read(key: _kAutoPwd);
    return v != null && v.isNotEmpty;
  }

  /// المجلّد المخصّص الذي اختاره المستخدم لحفظ النسخ (أو null = الافتراضي الداخلي).
  Future<String?> autoBackupCustomDir() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kAutoDir);
    return (v == null || v.isEmpty) ? null : v;
  }

  /// يضبط مجلّد الحفظ بعد اختبار قابليته للكتابة. يعيد true عند النجاح.
  Future<bool> setAutoBackupCustomDir(String path) async {
    try {
      final d = Directory(path);
      if (!await d.exists()) await d.create(recursive: true);
      final test = File(p.join(path, '.write_test'));
      await test.writeAsString('ok', flush: true);
      await test.delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAutoDir, path);
      return true;
    } catch (_) {
      return false; // غير قابل للكتابة على هذا النظام (مثلًا قيود التخزين).
    }
  }

  /// يعيد مجلّد الحفظ إلى الداخلي الافتراضي.
  Future<void> clearAutoBackupCustomDir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAutoDir);
  }

  /// مجلّد النسخ التلقائية: المخصّص إن وُجد وكان قابلًا للكتابة، وإلا الداخلي.
  Future<Directory> autoBackupDir() async {
    final custom = await autoBackupCustomDir();
    if (custom != null) {
      try {
        final d = Directory(custom);
        if (!await d.exists()) await d.create(recursive: true);
        return d;
      } catch (_) {/* تعذّر — نرجع للداخلي */}
    }
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'auto_backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// قائمة ملفات النسخ التلقائية (الأحدث أولًا حسب وقت التعديل).
  Future<List<File>> listAutoBackups() async {
    final dir = await autoBackupDir();
    if (!await dir.exists()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.$_ext'))
        .toList();
    files.sort((a, b) =>
        b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  /// تفعيل النسخة اليومية التلقائية بضغطة واحدة: يضبط الفترة يومًا، ويولّد كلمة
  /// مرور عشوائية تُحفظ بأمان (تُستخدم تلقائيًا عند الاستعادة الداخلية)، ثم ينشئ
  /// نسخة فورًا. لا يحتاج المستخدم لإدخال أي شيء.
  Future<void> enableDailyAutoBackup() async {
    await setAutoBackupIntervalDays(1);
    if (!await hasAutoBackupPassword()) {
      final rnd = Random.secure();
      final pwd = List.generate(
              24, (_) => rnd.nextInt(36).toRadixString(36))
          .join();
      await setAutoBackupPassword(pwd);
    }
    await setAutoBackupEnabled(true);
    await runAutoBackup(); // نسخة فورية أولى.
  }

  /// يُفعّل النسخ الاحتياطي اليومي التلقائي **افتراضيًا عند أول تشغيل** (مرّة
  /// واحدة فقط) ليضمن وجود نسخة قابلة للاستعادة دائمًا — شبكة أمان ضدّ فقدان
  /// الملاحظات. لا يتطلّب أي تدخّل من المستخدم (كلمة مرور عشوائية محفوظة بأمان)،
  /// ويحترم قراره لاحقًا: إن أوقفه يدويًا لا نُعيد تفعيله.
  Future<void> ensureDefaultAutoBackup() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kBootstrapped) ?? false) return;
    await prefs.setBool(_kBootstrapped, true);
    try {
      await enableDailyAutoBackup();
    } catch (_) {/* لا يجب أن يُعطّل الإقلاع */}
  }

  /// أحدث نسخة تلقائية محفوظة (أو null إن لم توجد).
  Future<File?> latestAutoBackup() async {
    final files = await listAutoBackups(); // الأحدث أولًا
    return files.isEmpty ? null : files.first;
  }

  /// ينشئ نسخة تلقائية الآن في **خانة يوم الأسبوع الحالي**: نسخة كل يوم تستبدل
  /// نسخة نفس اليوم من الأسبوع الماضي ⇒ 7 نسخ دائمة دوريّة (واحدة لكل يوم).
  Future<BackupResult> runAutoBackup() async {
    try {
      // حارس ضدّ فقدان البيانات: لا نكتب نسخة فارغة فوق نسخة جيدة. إن لم توجد
      // أي ملاحظة حالية بينما توجد نسخة سابقة، نتخطّى (نحفظ نسخك القديمة).
      final db = await AppDatabase.instance.database;
      final rows = await db
          .rawQuery('SELECT COUNT(*) AS c FROM notes WHERE is_deleted = 0');
      final liveCount = (rows.first['c'] as int?) ?? 0;
      if (liveCount == 0 && (await listAutoBackups()).isNotEmpty) {
        return const BackupResult(
            false, 'تُخطّي النسخ التلقائي (لا ملاحظات) — حماية لنسخك السابقة');
      }

      final pwd = await _secure.read(key: _kAutoPwd);
      if (pwd == null || pwd.isEmpty) {
        return const BackupResult(false, 'لم تُضبط كلمة مرور النسخ التلقائي');
      }
      final encrypted = await _buildEncrypted(pwd);
      // تحقّق من سلامة النسخة قبل كتابتها (حتى لا تُستبدل نسخة سليمة بأخرى تالفة).
      if (!await _verifyEncrypted(encrypted, pwd)) {
        return const BackupResult(false, 'فشل التحقّق من سلامة النسخة التلقائية');
      }
      final dir = await autoBackupDir();
      // خانة ثابتة لكل يوم من الأسبوع (1=الإثنين .. 7=الأحد) — تُستبدل أسبوعيًّا.
      final file = File(p.join(dir.path, 'auto_w${DateTime.now().weekday}.$_ext'));
      await file.writeAsBytes(encrypted, flush: true);
      await _stamp(_kLastAuto);
      return BackupResult(true, 'تم إنشاء نسخة تلقائية', filePath: file.path);
    } catch (e) {
      return BackupResult(false, 'فشل النسخ التلقائي: $e');
    }
  }

  /// يُستدعى عند إقلاع التطبيق: ينفّذ نسخة تلقائية إن حان موعدها فقط.
  Future<void> maybeRunAutoBackup() async {
    if (!await autoBackupEnabled()) return;
    if (!await hasAutoBackupPassword()) return;
    final last = await lastAutoBackup();
    if (last != null) {
      final intervalDays = await autoBackupIntervalDays();
      final due = last.add(Duration(days: intervalDays));
      if (DateTime.now().isBefore(due)) return; // لم يحن الموعد بعد
    }
    await runAutoBackup();
  }

  /// استعادة من نسخة تلقائية محدّدة (مسار داخلي) بكلمة مرور النسخ التلقائي.
  Future<BackupResult> restoreAutoBackup(File file) async {
    try {
      final pwd = await _secure.read(key: _kAutoPwd);
      if (pwd == null || pwd.isEmpty) {
        return const BackupResult(false, 'لا توجد كلمة مرور للنسخ التلقائي');
      }
      final encrypted = await file.readAsBytes();
      await _safetySnapshotBeforeRestore();
      return _restoreFromBytes(encrypted, pwd);
    } catch (e) {
      return BackupResult(false, 'فشل الاستعادة: $e');
    }
  }

  // ===== شبكة أمان الاستعادة: لقطة تلقائية قبل أي استعادة، مع تراجع بضغطة. =====
  static const _safetyName = 'pre_restore';

  /// يحفظ الحالة الحالية (قبل الاستعادة) في ملفّ داخليّ مشفّر بمفتاح القاعدة —
  /// كي يستطيع المستخدم **التراجع** لو استعاد نسخةً خاطئة. لا يُعطّل الاستعادة.
  Future<void> _safetySnapshotBeforeRestore() async {
    try {
      final pwd = await DbKeyManager.instance.getOrCreateKey();
      final encrypted = await _buildEncrypted(pwd);
      final dir = await autoBackupDir();
      final file = File(p.join(dir.path, '$_safetyName.$_ext'));
      await file.writeAsBytes(encrypted, flush: true);
    } catch (_) {
      // لقطة الأمان ليست حرجة؛ لا نمنع الاستعادة إن فشلت.
    }
  }

  Future<bool> hasPreRestoreSnapshot() async {
    try {
      final dir = await autoBackupDir();
      return File(p.join(dir.path, '$_safetyName.$_ext')).exists();
    } catch (_) {
      return false;
    }
  }

  /// يتراجع عن آخر استعادة بإرجاع لقطة ما-قبل-الاستعادة (لا يأخذ لقطة جديدة).
  Future<BackupResult> undoLastRestore() async {
    try {
      final dir = await autoBackupDir();
      final file = File(p.join(dir.path, '$_safetyName.$_ext'));
      if (!await file.exists()) {
        return const BackupResult(false, 'لا توجد لقطة قبل الاستعادة');
      }
      final pwd = await DbKeyManager.instance.getOrCreateKey();
      final encrypted = await file.readAsBytes();
      return _restoreFromBytes(encrypted, pwd);
    } catch (e) {
      return BackupResult(false, 'تعذّر التراجع: $e');
    }
  }

  /// إنشاء نسخة احتياطية مشفّرة وحفظها عبر منتقي الملفات.
  Future<BackupResult> exportBackup(String password) async {
    try {
      final archive = Archive();

      // 1) قاعدة البيانات.
      final dbPath = await AppDatabase.instance.path;
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        final bytes = await dbFile.readAsBytes();
        archive.addFile(ArchiveFile('database.db', bytes.length, bytes));
      }

      // 1ب) مفتاح تشفير القاعدة (محميّ أصلًا بكلمة مرور النسخة) — ليعمل
      // فكّ التشفير عند الاستعادة على أي جهاز.
      final key = await DbKeyManager.instance.getOrCreateKey();
      final keyBytes = utf8.encode(key);
      archive.addFile(ArchiveFile('dbkey.txt', keyBytes.length, keyBytes));

      // 2) كل المرفقات.
      final attDir = await FileService.instance.attachmentsDir();
      if (await attDir.exists()) {
        for (final entity in attDir.listSync()) {
          if (entity is File) {
            final bytes = await entity.readAsBytes();
            final name = 'attachments/${p.basename(entity.path)}';
            archive.addFile(ArchiveFile(name, bytes.length, bytes));
          }
        }
      }

      final zipped = ZipEncoder().encode(archive);
      if (zipped == null) {
        return const BackupResult(false, 'تعذّر إنشاء الأرشيف');
      }

      // 3) التشفير.
      final encrypted = EncryptionService.instance
          .encryptBytes(Uint8List.fromList(zipped), password);

      // 3ب) تحقّق فوريّ من سلامة النسخة (فكّ تشفير اختباريّ) قبل إعلان النجاح.
      if (!await _verifyEncrypted(encrypted, password)) {
        return const BackupResult(false, 'فشل التحقّق من سلامة النسخة');
      }

      // 4) الحفظ: نكتب أولًا في الملفات المؤقتة ثم نتيح حفظه للمستخدم.
      final stamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final fileName = 'Notes_$stamp.$_ext';

      final tmpDir = await getTemporaryDirectory();
      final tmpPath = p.join(tmpDir.path, fileName);
      await File(tmpPath).writeAsBytes(encrypted, flush: true);

      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ النسخة الاحتياطية',
        fileName: fileName,
        bytes: encrypted,
      );

      await _stamp(_kLastLocal);
      return BackupResult(
        true,
        'تم إنشاء النسخة الاحتياطية والتحقّق من سلامتها ✓',
        filePath: savedPath ?? tmpPath,
      );
    } catch (e) {
      return BackupResult(false, 'فشل التصدير: $e');
    }
  }

  /// تصدير الملاحظات (مع التصنيفات والوسوم) إلى ملفّ **JSON** مقروء وقابل للنقل
  /// — غير مشفّر، لمشاركته أو الاحتفاظ به أو نقله لتطبيق آخر. لا يشمل المرفقات.
  Future<BackupResult> exportNotesJson() async {
    try {
      final repo = NoteRepository(AppDatabase.instance);
      final catRepo = CategoryRepository(AppDatabase.instance);
      final notes =
          (await repo.getEverything()).where((n) => !n.isDeleted).toList();
      final cats = await catRepo.getAll();
      // التنبيهات المستقلّة فقط (المرتبطة بملاحظة تُستعاد مع نسختها الكاملة).
      final reminders =
          (await ReminderRepository(AppDatabase.instance).getAll())
              .where((r) => r.isStandalone)
              .toList();
      final data = <String, dynamic>{
        'app': 'Alerts',
        'type': 'notes-json',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'categories': cats.map((c) => c.toMap()).toList(),
        'notes': notes.map((n) {
          final m = Map<String, dynamic>.from(n.toMap());
          m['tags'] = n.tags;
          return m;
        }).toList(),
        'reminders': reminders.map((r) => r.toMap()).toList(),
      };
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      final stamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final fileName = 'Alerts_$stamp.json';
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ ملف JSON',
        fileName: fileName,
        bytes: bytes,
      );
      if (saved == null) {
        // المستخدم ألغى الحفظ (على بعض الأجهزة يُكتفى بالبايتات أعلاه).
        final tmp = p.join((await getTemporaryDirectory()).path, fileName);
        await File(tmp).writeAsBytes(bytes, flush: true);
        return BackupResult(true, 'تم التصدير (${notes.length})', filePath: tmp);
      }
      return BackupResult(true, 'تم تصدير ${notes.length} ملاحظة',
          filePath: saved);
    } catch (e) {
      return BackupResult(false, 'فشل التصدير: $e');
    }
  }

  /// استيراد ملاحظات من ملفّ JSON (يدمج بلا حذف): يتخطّى المكرّر حسب المعرّف
  /// الفريد uuid، ويعيد ربط التصنيفات بالاسم. يعيد عدد الملاحظات المضافة.
  Future<BackupResult> importNotesJson() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر ملف JSON',
        type: FileType.any,
      );
      final path = picked?.files.single.path;
      if (path == null) return const BackupResult(false, 'لم يتم اختيار ملف');

      final raw = await File(path).readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const BackupResult(false, 'الملف ليس بصيغة JSON صحيحة');
      }

      // تطبيق «التنبيهات فقط»: نستورد التنبيهات المستقلّة فقط ونتجاهل الملاحظات.
      var addedReminders = 0;
      final remList = decoded['reminders'];
      if (remList is List) {
        final remRepo = ReminderRepository(AppDatabase.instance);
        final existR = await remRepo.getAll();
        String key(Reminder r) =>
            '${r.title}|${r.time.millisecondsSinceEpoch}|${r.repeat.index}|${r.intervalDays}';
        final existKeys =
            existR.where((r) => r.isStandalone).map(key).toSet();
        var maxNid = existR.fold<int>(
            1000, (mx, r) => r.notificationId > mx ? r.notificationId : mx);
        for (final raw in remList) {
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          if (m['note_id'] != null) continue; // المستقلّة فقط.
          m.remove('id');
          final r0 = Reminder.fromMap(m);
          if (existKeys.contains(key(r0))) continue;
          maxNid += 1;
          await remRepo.insert(r0.copyWith(notificationId: maxNid));
          existKeys.add(key(r0));
          addedReminders++;
        }
      } else if (decoded['notes'] is! List) {
        return const BackupResult(false, 'الملف لا يحتوي تنبيهات');
      }

      return BackupResult(true, 'تم استيراد $addedReminders تنبيه');
    } catch (e) {
      return BackupResult(false, 'فشل الاستيراد: $e');
    }
  }

  /// إنشاء نسخة مشفّرة ومشاركتها مباشرة إلى أي تطبيق سحابي
  /// (Google Drive / سحابة هواوي / Telegram / البريد...) بضغطة واحدة.
  Future<BackupResult> shareBackupToCloud(String password) async {
    try {
      final encrypted = await _buildEncrypted(password);
      if (!await _verifyEncrypted(encrypted, password)) {
        return const BackupResult(false, 'فشل التحقّق من سلامة النسخة');
      }
      final stamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final fileName = 'Notes_$stamp.$_ext';
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = p.join(tmpDir.path, fileName);
      await File(tmpPath).writeAsBytes(encrypted, flush: true);

      await SharePlus.instance.share(ShareParams(
        files: [XFile(tmpPath, mimeType: 'application/octet-stream')],
        text: 'نسخة Alerts الاحتياطية المشفّرة',
        subject: fileName,
      ));
      await _stamp(_kLastShare);
      return BackupResult(true, 'تمت مشاركة النسخة', filePath: tmpPath);
    } catch (e) {
      return BackupResult(false, 'فشل المشاركة: $e');
    }
  }

  /// يبني أرشيف (قاعدة بيانات + مرفقات) مشفّرًا بكلمة المرور.
  Future<Uint8List> _buildEncrypted(String password) async {
    final archive = Archive();
    final dbPath = await AppDatabase.instance.path;
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      final bytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('database.db', bytes.length, bytes));
    }
    final key = await DbKeyManager.instance.getOrCreateKey();
    final keyBytes = utf8.encode(key);
    archive.addFile(ArchiveFile('dbkey.txt', keyBytes.length, keyBytes));
    final attDir = await FileService.instance.attachmentsDir();
    if (await attDir.exists()) {
      for (final entity in attDir.listSync()) {
        if (entity is File) {
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(
              'attachments/${p.basename(entity.path)}', bytes.length, bytes));
        }
      }
    }
    final zipped = ZipEncoder().encode(archive);
    if (zipped == null) throw Exception('تعذّر إنشاء الأرشيف');
    return EncryptionService.instance
        .encryptBytes(Uint8List.fromList(zipped), password);
  }

  /// يتيح للمستخدم اختيار ملفّ نسخة والتأكّد من سلامته (فكّ تشفير اختباريّ) دون
  /// استعادته — للاطمئنان أنّ النسخة قابلة للاستعادة وقت الحاجة.
  Future<BackupResult> verifyBackupFile(String password) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر ملف النسخة للتحقّق',
        type: FileType.any,
      );
      final path = picked?.files.single.path;
      if (path == null) return const BackupResult(false, 'لم يتم اختيار ملف');
      final bytes = await File(path).readAsBytes();
      final ok = await _verifyEncrypted(bytes, password);
      return BackupResult(
          ok,
          ok
              ? 'النسخة سليمة وقابلة للاستعادة ✓'
              : 'النسخة تالفة أو كلمة المرور خاطئة');
    } catch (e) {
      return BackupResult(false, 'تعذّر التحقّق: $e');
    }
  }

  /// استعادة نسخة احتياطية من ملف يختاره المستخدم.
  Future<BackupResult> importBackup(String password) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر ملف النسخة الاحتياطية',
        type: FileType.any,
      );
      if (picked == null || picked.files.isEmpty) {
        return const BackupResult(false, 'لم يتم اختيار ملف');
      }

      final path = picked.files.single.path;
      if (path == null) {
        return const BackupResult(false, 'تعذّر قراءة الملف');
      }

      final encrypted = await File(path).readAsBytes();
      await _safetySnapshotBeforeRestore();
      return _restoreFromBytes(encrypted, password);
    } catch (e) {
      return BackupResult(false, 'فشل الاستيراد: $e');
    }
  }

  /// يتحقّق أنّ بايتات نسخةٍ مشفّرة **قابلة للفكّ** وتحوي قاعدة بيانات صالحة —
  /// دون أيّ تعديل على بيانات التطبيق. يُستخدم للتأكّد من سلامة النسخة فور
  /// إنشائها، فلا تُكتشف نسخة تالفة وقت الحاجة الماسّة للاستعادة.
  Future<bool> _verifyEncrypted(Uint8List encrypted, String password) async {
    try {
      final zipped =
          EncryptionService.instance.decryptBytes(encrypted, password);
      final archive = ZipDecoder().decodeBytes(zipped);
      for (final f in archive) {
        if (f.isFile && f.name == 'database.db') {
          // ترويسة SQLite ("SQLite format 3\0") = 16 بايت على الأقل.
          return (f.content as List<int>).length > 16;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// المنطق المشترك لاستعادة نسخة مشفّرة من بايتاتها (يستخدمه الاستيراد اليدوي
  /// والاستعادة من النسخ التلقائية).
  Future<BackupResult> _restoreFromBytes(
      Uint8List encrypted, String password) async {
    late Uint8List zipped;
    try {
      zipped = EncryptionService.instance.decryptBytes(encrypted, password);
    } catch (_) {
      return const BackupResult(false, 'كلمة المرور خاطئة أو الملف تالف');
    }

    final archive = ZipDecoder().decodeBytes(zipped);

    // استبدال قاعدة البيانات.
    final dbPath = await AppDatabase.instance.path;
    final attDir = await FileService.instance.attachmentsDir();

    // تنظيف المرفقات القديمة.
    if (await attDir.exists()) {
      for (final e in attDir.listSync()) {
        if (e is File) await e.delete();
      }
    }

    String? restoredKey;
    for (final file in archive) {
      if (!file.isFile) continue;
      final data = file.content as List<int>;
      if (file.name == 'database.db') {
        await File(dbPath).writeAsBytes(data, flush: true);
      } else if (file.name == 'dbkey.txt') {
        restoredKey = utf8.decode(data);
      } else if (file.name.startsWith('attachments/')) {
        final dest = p.join(attDir.path, p.basename(file.name));
        await File(dest).writeAsBytes(data, flush: true);
      }
    }

    // ضبط مفتاح التشفير ليطابق القاعدة المستعادة.
    if (restoredKey != null && restoredKey.isNotEmpty) {
      // نسخة مشفّرة: استخدم مفتاحها وتجاوز الترحيل.
      await DbKeyManager.instance.setKey(restoredKey);
      await DbKeyManager.instance.markMigrated();
    } else {
      // نسخة قديمة (غير مشفّرة): أعد الترحيل لتشفيرها بمفتاح هذا الجهاز.
      await DbKeyManager.instance.clearMigrated();
    }

    // إعادة فتح قاعدة البيانات بالبيانات المستعادة.
    await AppDatabase.instance.reopen();

    await _stamp(_kLastRestore);
    return const BackupResult(true, 'تمت الاستعادة بنجاح');
  }
}
