import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../data/database/app_database.dart';
import '../encryption_service.dart';
import 'gdrive_backend.dart';
import 'sync_backend.dart';
import 'webdav_backend.dart';

/// مزوّد المزامنة المختار.
enum SyncProvider { none, webdav, googleDrive }

/// تردّد المزامنة التلقائية: كلّ فتح / عند الإغلاق / مرّة باليوم.
enum SyncFrequency { everyOpen, onClose, daily }

/// سبب محاولة المزامنة التلقائية (لمطابقتها بالتردّد المختار).
enum SyncTrigger { open, close }

/// حالة شريط المزامنة الخفيف في الأعلى.
enum SyncUi { idle, syncing, done, error }

class SyncStatus {
  final SyncUi state;
  final String message;
  const SyncStatus(this.state, [this.message = '']);
}

/// نتيجة عملية مزامنة.
class SyncResult {
  final bool ok;
  final String message;
  final int pulled; // ملاحظات حُدّثت/أُضيفت محليًّا من السحابة
  final int pushed; // إجمالي الملاحظات المرفوعة
  const SyncResult(this.ok, this.message, {this.pulled = 0, this.pushed = 0});
}

/// محرّك المزامنة السحابية: مزامنة حقيقية ثنائية الاتجاه بدمج **«آخر تعديل يفوز»
/// لكل ملاحظة** عبر معرّفها الثابت (uuid). كل ما يُرفع مشفّر طرفيًّا (E2E) بعبارة
/// مرور يحدّدها المستخدم — فلا يقرأ الخادم محتوى الملاحظات.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _kProvider = 'sync_provider';
  static const _kWebdavUrl = 'sync_webdav_url';
  static const _kWebdavUser = 'sync_webdav_user';
  static const _kAuto = 'sync_auto';
  static const _kFreq = 'sync_freq'; // تردّد المزامنة التلقائية
  static const _kSilent = 'sync_silent'; // مزامنة صامتة في الخلفية (بلا شريط)
  static const _kLast = 'sync_last';
  static const _kGDriveOn = 'sync_gdrive_on';

  static const _kWebdavPass = 'sync_webdav_pass'; // secure
  static const _kPassphrase = 'sync_passphrase'; // secure (مفتاح التشفير E2E)

  static const _fileName = 'mudhakkarati-sync.enc';

  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// حالة المزامنة لعرض شريط خفيف في الأعلى (بلا تعطيل العمل).
  final ValueNotifier<SyncStatus> status =
      ValueNotifier(const SyncStatus(SyncUi.idle));

  // ===================== الإعدادات =====================
  Future<SyncProvider> provider() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kProvider);
    return SyncProvider.values.firstWhere((e) => e.name == v,
        orElse: () => SyncProvider.none);
  }

  Future<void> setProvider(SyncProvider p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProvider, p.name);
  }

  Future<bool> autoSync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAuto) ?? false;
  }

  Future<void> setAutoSync(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAuto, v);
  }

  /// تردّد المزامنة التلقائية (افتراضيًّا: مرّة باليوم — أقلّ إزعاجًا).
  Future<SyncFrequency> syncFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kFreq);
    return SyncFrequency.values.firstWhere((e) => e.name == v,
        orElse: () => SyncFrequency.daily);
  }

  Future<void> setSyncFrequency(SyncFrequency f) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFreq, f.name);
  }

  /// مزامنة صامتة في الخلفية (دون شريط علويّ) — افتراضيًّا false (ظاهرة).
  Future<bool> silentSync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSilent) ?? false;
  }

  Future<void> setSilentSync(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSilent, v);
  }

  /// هل تحين مزامنة تلقائية الآن للسبب [trigger]، حسب التفعيل والتهيئة والتردّد؟
  Future<bool> shouldAutoSync(SyncTrigger trigger) async {
    if (!await autoSync()) return false;
    if (!await isConfigured()) return false;
    switch (await syncFrequency()) {
      case SyncFrequency.everyOpen:
        return trigger == SyncTrigger.open;
      case SyncFrequency.onClose:
        return trigger == SyncTrigger.close;
      case SyncFrequency.daily:
        if (trigger != SyncTrigger.open) return false;
        final last = await lastSync();
        return last == null ||
            DateTime.now().difference(last) >= const Duration(hours: 24);
    }
  }

  Future<DateTime?> lastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kLast);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<({String url, String user})> webdavConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      url: prefs.getString(_kWebdavUrl) ?? '',
      user: prefs.getString(_kWebdavUser) ?? '',
    );
  }

  Future<void> setWebdavConfig({
    required String url,
    required String user,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWebdavUrl, url.trim());
    await prefs.setString(_kWebdavUser, user.trim());
    await _secure.write(key: _kWebdavPass, value: password);
  }

  Future<void> setPassphrase(String passphrase) =>
      _secure.write(key: _kPassphrase, value: passphrase);

  Future<bool> hasPassphrase() async {
    final v = await _secure.read(key: _kPassphrase);
    return v != null && v.isNotEmpty;
  }

  Future<bool> isConfigured() async {
    final p = await provider();
    if (p == SyncProvider.none) return false;
    if (!await hasPassphrase()) return false;
    if (p == SyncProvider.webdav) {
      final c = await webdavConfig();
      final pass = await _secure.read(key: _kWebdavPass);
      return c.url.isNotEmpty && c.user.isNotEmpty && (pass ?? '').isNotEmpty;
    }
    if (p == SyncProvider.googleDrive) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kGDriveOn) ?? false;
    }
    return false;
  }

  /// يبني المزوّد الحالي من الإعدادات (أو null إن لم يُهيَّأ).
  Future<SyncBackend?> _backend() async {
    final p = await provider();
    if (p == SyncProvider.webdav) {
      final c = await webdavConfig();
      final pass = await _secure.read(key: _kWebdavPass) ?? '';
      if (c.url.isEmpty) return null;
      return WebDavBackend(
        baseUrl: c.url,
        username: c.user,
        password: pass,
        fileName: _fileName,
      );
    }
    if (p == SyncProvider.googleDrive) {
      return GoogleDriveBackend(fileName: _fileName);
    }
    return null;
  }

  // ===================== Google Drive =====================
  /// تسجيل الدخول بحساب Google (تفاعلي). يعيد البريد عند النجاح أو null.
  Future<String?> googleConnect() async {
    final account =
        await GoogleDriveBackend.ensureSignedIn(interactive: true);
    if (account == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGDriveOn, true);
    await setProvider(SyncProvider.googleDrive);
    return account.email;
  }

  Future<void> googleDisconnect() async {
    try {
      await GoogleDriveBackend.googleSignIn.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGDriveOn, false);
  }

  /// بريد الحساب المتّصل (يحاول الدخول الصامت)، أو null.
  Future<String?> googleEmail() async {
    final acc = await GoogleDriveBackend.ensureSignedIn(interactive: false);
    return acc?.email;
  }

  Future<SyncTestResult> testConnection() async {
    final b = await _backend();
    if (b == null) return const SyncTestResult(false, 'لم تُضبط بيانات المزامنة');
    return b.test();
  }

  // ===================== المزامنة =====================
  /// إعادة محاولة عملية شبكية عند الفشل اللحظيّ (مثل ClientException) — تحسّن
  /// موثوقية المزامنة على الشبكات غير المستقرّة. تراجع أُسّي بسيط (1ث، 2ث، 4ث).
  Future<T> _retry<T>(Future<T> Function() op, {int attempts = 3}) async {
    Object? last;
    for (var i = 0; i < attempts; i++) {
      try {
        return await op();
      } catch (e) {
        last = e;
        if (i < attempts - 1) {
          await Future.delayed(Duration(seconds: 1 << i));
        }
      }
    }
    throw last!;
  }

  /// مزامنة الآن: تنزيل السحابة، دمج لكل ملاحظة بـ«آخر تعديل يفوز»، تطبيق التغييرات
  /// محليًّا، ثم رفع النتيجة المدموجة.
  Future<SyncResult> syncNow() async {
    final backend = await _backend();
    if (backend == null) {
      return const SyncResult(false, 'لم تُضبط المزامنة');
    }
    final passphrase = await _secure.read(key: _kPassphrase) ?? '';
    if (passphrase.isEmpty) {
      return const SyncResult(false, 'لم تُضبط عبارة مرور المزامنة');
    }

    try {
      // 1) المحلّي.
      final local = await _exportLocal();
      final localByUuid = {for (final n in local) n['uuid'] as String: n};

      // 2) السحابي (مع إعادة محاولة عند فشل الشبكة اللحظيّ).
      List<Map<String, dynamic>> remote = [];
      final remoteBytes = await _retry(() => backend.download());
      if (remoteBytes != null) {
        try {
          final decrypted =
              EncryptionService.instance.decryptBytes(remoteBytes, passphrase);
          final decoded = jsonDecode(utf8.decode(decrypted));
          if (decoded is List) {
            remote = decoded
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList();
          }
        } catch (_) {
          return const SyncResult(false,
              'تعذّر فكّ تشفير نسخة السحابة — تأكّد من تطابق عبارة المرور على كل الأجهزة');
        }
      }
      final remoteByUuid = {for (final n in remote) n['uuid'] as String: n};

      // 3) الدمج لكل ملاحظة (الأحدث updated_at يفوز).
      final allUuids = {...localByUuid.keys, ...remoteByUuid.keys};
      final merged = <Map<String, dynamic>>[];
      final winnersFromRemote = <Map<String, dynamic>>[];
      for (final uuid in allUuids) {
        final l = localByUuid[uuid];
        final r = remoteByUuid[uuid];
        if (l == null) {
          merged.add(r!);
          winnersFromRemote.add(r);
        } else if (r == null) {
          merged.add(l);
        } else {
          final lu = (l['updated_at'] as num?)?.toInt() ?? 0;
          final ru = (r['updated_at'] as num?)?.toInt() ?? 0;
          if (ru > lu) {
            merged.add(r);
            winnersFromRemote.add(r);
          } else {
            merged.add(l);
          }
        }
      }

      // 4) طبّق ما فاز من السحابة محليًّا.
      for (final rec in winnersFromRemote) {
        await _importRecord(rec);
      }

      // 5) ارفع المدموج (مع إعادة محاولة). المدموج اتحاديّ فلا يقلّ أبدًا عن عدد
      //    ملاحظات السحابة ⇒ الرفع لا يُنقص النسخة السحابية إطلاقًا.
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(merged)));
      final encrypted =
          EncryptionService.instance.encryptBytes(bytes, passphrase);
      await _retry(() => backend.upload(encrypted));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLast, DateTime.now().millisecondsSinceEpoch);

      return SyncResult(
        true,
        'تمت المزامنة (${winnersFromRemote.length} محدّثة، ${merged.length} بالمجمل)',
        pulled: winnersFromRemote.length,
        pushed: merged.length,
      );
    } catch (e) {
      // الدمج اتحادي (لا يحذف المحلّي)، وأي فشل هنا غالبًا مشكلة شبكة — نطمئن
      // المستخدم أن ملاحظاته المحلية آمنة بدل عرض استثناء مخيف.
      final net = e.toString().contains('ClientException') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('HandshakeException') ||
          e.toString().contains('TimeoutException');
      return SyncResult(
          false,
          net
              ? 'تعذّرت المزامنة (الشبكة) — ملاحظاتك المحلية آمنة'
              : 'تعذّرت المزامنة — ملاحظاتك المحلية آمنة');
    }
  }

  /// مزامنة تلقائية عند الإقلاع إن كانت مفعّلة ومُهيّأة (تُستدعى دون انتظار).
  Future<SyncResult?> maybeAutoSync() async {
    if (!await autoSync()) return null;
    if (!await isConfigured()) return null;
    return syncNow();
  }

  // ===================== التصدير المحلّي =====================
  Future<List<Map<String, dynamic>>> _exportLocal() async {
    final db = await AppDatabase.instance.database;
    final noteRows = await db.query('notes');
    final cats = {
      for (final c in await db.query('categories')) c['id'] as int: c
    };

    final out = <Map<String, dynamic>>[];
    for (final row in noteRows) {
      final id = row['id'] as int;
      var uuid = (row['uuid'] as String?) ?? '';
      if (uuid.isEmpty) {
        // أمان: لو وُجدت ملاحظة بلا uuid، ولّد واحدًا وثبّته.
        uuid = _randomUuid();
        await db.update('notes', {'uuid': uuid},
            where: 'id = ?', whereArgs: [id]);
      }

      final note = Map<String, dynamic>.from(row)
        ..remove('id')
        ..remove('category_id')
        ..['uuid'] = uuid;

      final catId = row['category_id'] as int?;
      final cat = catId == null ? null : cats[catId];

      final tagRows = await db.rawQuery(
          'SELECT t.name FROM tags t '
          'JOIN note_tags nt ON nt.tag_id = t.id WHERE nt.note_id = ?',
          [id]);
      final checklist = await db.query('checklist_items',
          where: 'note_id = ?', whereArgs: [id], orderBy: 'position');

      out.add({
        'uuid': uuid,
        'updated_at': row['updated_at'],
        'note': note,
        'category': cat == null
            ? null
            : {
                'name': cat['name'],
                'color': cat['color'],
                'icon_code': cat['icon_code'],
              },
        'tags': tagRows.map((t) => t['name'] as String).toList(),
        'checklist': checklist
            .map((c) => {
                  'text': c['text'],
                  'is_done': c['is_done'],
                  'position': c['position'],
                })
            .toList(),
      });
    }
    return out;
  }

  // ===================== الاستيراد (تطبيق سجل فائز من السحابة) =====================
  Future<void> _importRecord(Map<String, dynamic> rec) async {
    final db = await AppDatabase.instance.database;
    final uuid = rec['uuid'] as String;
    final noteMap = Map<String, dynamic>.from(rec['note'] as Map)
      ..remove('id');
    noteMap['uuid'] = uuid;

    // التصنيف: طابق بالاسم أو أنشئه.
    int? categoryId;
    final cat = rec['category'];
    if (cat is Map) {
      final name = cat['name'] as String?;
      if (name != null && name.isNotEmpty) {
        final existing = await db
            .query('categories', where: 'name = ?', whereArgs: [name], limit: 1);
        if (existing.isNotEmpty) {
          categoryId = existing.first['id'] as int;
        } else {
          categoryId = await db.insert('categories', {
            'name': name,
            'color': (cat['color'] as num?)?.toInt() ?? 0xFF42A5F5,
            'icon_code': (cat['icon_code'] as num?)?.toInt() ?? 0,
            'position': 0,
          });
        }
      }
    }
    noteMap['category_id'] = categoryId;

    // upsert بالـ uuid.
    final found =
        await db.query('notes', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    int noteId;
    if (found.isNotEmpty) {
      noteId = found.first['id'] as int;
      // حماية من فقدان البيانات: لا نُطبّق «حذفًا» قادمًا من السحابة على ملاحظة
      // محلية غير محذوفة. المزامنة لا تحذف ملاحظاتك المحلية أبدًا.
      final remoteDeleted =
          ((noteMap['is_deleted'] as num?)?.toInt() ?? 0) == 1;
      final localDeleted =
          ((found.first['is_deleted'] as num?)?.toInt() ?? 0) == 1;
      if (remoteDeleted && !localDeleted) return;
      await db.update('notes', noteMap, where: 'id = ?', whereArgs: [noteId]);
    } else {
      // ملاحظة جديدة من السحابة محذوفة أصلًا ⇒ لا فائدة من استيرادها.
      if (((noteMap['is_deleted'] as num?)?.toInt() ?? 0) == 1) return;
      noteId = await db.insert('notes', noteMap,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // الوسوم: استبدل المجموعة بمجموعة السحابة.
    await db.delete('note_tags', where: 'note_id = ?', whereArgs: [noteId]);
    final tags = (rec['tags'] as List?)?.cast<dynamic>() ?? const [];
    for (final t in tags) {
      final name = t.toString();
      if (name.isEmpty) continue;
      await db.insert('tags', {'name': name},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      final tagRow = await db
          .query('tags', where: 'name = ?', whereArgs: [name], limit: 1);
      if (tagRow.isNotEmpty) {
        await db.insert(
            'note_tags', {'note_id': noteId, 'tag_id': tagRow.first['id']},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    // عناصر قائمة المهام: استبدلها بقائمة السحابة.
    await db
        .delete('checklist_items', where: 'note_id = ?', whereArgs: [noteId]);
    final checklist = (rec['checklist'] as List?)?.cast<dynamic>() ?? const [];
    for (final c in checklist) {
      if (c is! Map) continue;
      await db.insert('checklist_items', {
        'note_id': noteId,
        'text': c['text'] ?? '',
        'is_done': (c['is_done'] as num?)?.toInt() ?? 0,
        'position': (c['position'] as num?)?.toInt() ?? 0,
      });
    }
  }

  String _randomUuid() {
    // معرّف hex عشوائي 32 خانة (كافٍ كمعرّف ثابت فريد).
    final now = DateTime.now().microsecondsSinceEpoch;
    final r = now.toRadixString(16).padLeft(16, '0');
    final r2 = (now ^ 0x5DEECE66D).toRadixString(16).padLeft(16, '0');
    return (r + r2).substring(0, 32);
  }
}
