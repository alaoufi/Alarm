import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// يدير مفتاح تشفير قاعدة البيانات (SQLCipher).
///
/// **حماية من فقدان البيانات:** المفتاح يُحفظ في مكانين دائمين:
/// 1) التخزين الآمن (Keystore) — الأساسي.
/// 2) ملفّ خاصّ داخل التطبيق (sandbox) — نسخة احتياطية تُستعاد إن فُقد المفتاح
///    من Keystore (يحدث على بعض الأجهزة عند نسخ/استرجاع أندرويد أو تغيّر القفل).
/// لا يُولَّد مفتاح جديد إلا إذا فُقد من **كلا** المكانين (أول تشغيل حقيقي) — وهذا
/// يمنع توليد مفتاح جديد يجعل قاعدةً مشفّرة قائمة غير قابلة للفتح (فقدان كامل).
class DbKeyManager {
  DbKeyManager._();
  static final DbKeyManager instance = DbKeyManager._();

  static const _kKey = 'db_cipher_key';
  static const _kMigrated = 'db_encrypted_v1';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<File> _fallbackFile() async {
    final dir = await getApplicationSupportDirectory(); // خاصّ بالتطبيق
    return File(p.join(dir.path, '.dbkey'));
  }

  Future<String?> _readFallback() async {
    try {
      final f = await _fallbackFile();
      if (await f.exists()) {
        final v = (await f.readAsString()).trim();
        return v.isEmpty ? null : v;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeFallback(String key) async {
    try {
      final f = await _fallbackFile();
      await f.writeAsString(key, flush: true);
    } catch (_) {}
  }

  /// المفتاح الحالي. يُستعاد من النسخة الاحتياطية إن فُقد من Keystore، ولا يُولَّد
  /// مفتاح جديد إلا عند غيابه من كلا المصدرين.
  Future<String> getOrCreateKey() async {
    // 1) التخزين الآمن (الأساسي) — مع إعادة محاولة، لأن الفشل غالبًا **لحظيّ**
    //    (هذا بالضبط ما سبّب ظهور القاعدة فارغة: قراءة فاشلة مؤقّتة للمفتاح).
    String? secure;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        secure = await _storage.read(key: _kKey);
      } catch (_) {
        secure = null;
      }
      if (secure != null && secure.isNotEmpty) break;
      if (attempt < 2) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
    if (secure != null && secure.isNotEmpty) {
      await _writeFallback(secure); // اضمن وجود النسخة الاحتياطية.
      return secure;
    }

    // 2) النسخة الاحتياطية الدائمة (استرجاع عند فقدان Keystore).
    final fb = await _readFallback();
    if (fb != null && fb.isNotEmpty) {
      try {
        await _storage.write(key: _kKey, value: fb); // أعِد الكتابة للآمن.
      } catch (_) {}
      return fb;
    }

    // 3) أول تشغيل حقيقي → ولّد مفتاحًا جديدًا واحفظه في المكانين.
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final key = base64UrlEncode(bytes);
    try {
      await _storage.write(key: _kKey, value: key);
    } catch (_) {}
    await _writeFallback(key);
    return key;
  }

  /// ضبط المفتاح يدويًا (عند الاستعادة من نسخة احتياطية تحمل مفتاحها).
  Future<void> setKey(String key) async {
    try {
      await _storage.write(key: _kKey, value: key);
    } catch (_) {}
    await _writeFallback(key);
  }

  Future<bool> isMigrated() async {
    try {
      if ((await _storage.read(key: _kMigrated)) == 'true') return true;
    } catch (_) {}
    return false;
  }

  Future<void> markMigrated() async {
    try {
      await _storage.write(key: _kMigrated, value: 'true');
    } catch (_) {}
  }

  Future<void> clearMigrated() async {
    try {
      await _storage.delete(key: _kMigrated);
    } catch (_) {}
  }
}
