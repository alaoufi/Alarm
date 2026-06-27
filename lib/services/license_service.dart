import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// حالة الترخيص الحالية على هذا الجهاز.
enum LicenseState {
  /// لم يُضبط مفتاح عام بعد (وضع التطوير) — التطبيق مفتوح دون ترخيص.
  disabled,

  /// لم يُفعَّل بعد.
  none,

  /// مفعّل وسارٍ (بمدّة أو دائم).
  active,

  /// كان مفعّلًا وانتهت مدّته.
  expired,
}

/// معلومات الترخيص للعرض.
class LicenseInfo {
  final LicenseState state;
  final bool permanent;
  final DateTime? expiry; // تاريخ الانتهاء (null للدائم).
  final int daysLeft; // الأيام المتبقّية (0 للدائم/غير المفعّل).
  const LicenseInfo(this.state, this.permanent, this.expiry, this.daysLeft);
}

/// تفعيل التطبيق المربوط بالجهاز (يعمل دون إنترنت بالكامل).
///
/// - لكل جهاز معرّف ثابت (Device ID) يُشتقّ من عتاد الجهاز ويُعرض للمستخدم.
/// - رمز التفعيل = توقيع Ed25519 (غير متماثل) على «معرّف الجهاز + المدّة»،
///   يولّده المالك بمفتاحه الخاصّ عبر **تطبيق المولّد المستقلّ**.
/// - التطبيق يتحقّق بالمفتاح العامّ المدمج فقط ⇒ يستحيل تزوير رمز دون المفتاح
///   الخاصّ، ويعمل الرمز على جهاز واحد فقط (لا ينتقل)، فنشر الـAPK بلا فائدة.
/// - المالك يحدّد المدّة: عدد أيام أو **دائم**. تُحسب الصلاحية من لحظة التفعيل،
///   مع حارس ضدّ تأخير الساعة (لا يمكن تمديدها بإرجاع وقت الجهاز).
class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  // المفتاح العامّ للمالك (Base64 لـ 32 بايت Ed25519). التحقق فقط — لا يمكن
  // توليد رموز منه. وُلّد مرّة واحدة؛ مفتاحه الخاصّ يبقى في تطبيق المولّد فقط.
  static const String _publicKeyB64 =
      'Wu3tven4KhEEuNqUNLatFTLljCgjFnJXtFc3QHYlhk8=';

  // بادئة الرسالة الموقَّعة (إصدار الصيغة). يجب أن تطابق المولّد حرفيًّا.
  static const String _msgPrefix = 'MDKL1';

  static const _kDeviceId = 'lic_device_id';
  static const _kRecord = 'lic_record'; // سجلّ التفعيل (JSON).
  static const _licenseFile = '.mdk_license'; // نسخة احتياطية دائمة.

  static const _dayMs = 86400000;

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _ed = Ed25519();

  bool get _keyConfigured =>
      _publicKeyB64.isNotEmpty && !_publicKeyB64.startsWith('REPLACE_');

  // ---- معرّف الجهاز ----

  /// معرّف الجهاز الخام (16 حرفًا Base32) — يبقى ثابتًا عبر التحديثات.
  Future<String> deviceId() async {
    final cached = await _storage.read(key: _kDeviceId);
    if (cached != null && cached.isNotEmpty) return cached;

    String? raw = await _hardwareFingerprint();
    if (raw == null || raw.isEmpty) {
      final rnd = Random.secure();
      raw = base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    }
    final digest = crypto.sha256.convert(utf8.encode('mudhakkarati:$raw'));
    final id = base32(digest.bytes.sublist(0, 10)); // 16 حرفًا.
    await _storage.write(key: _kDeviceId, value: id);
    return id;
  }

  /// معرّف الجهاز مُجمّلًا بمجموعات من 4 (XXXX-XXXX-XXXX-XXXX).
  Future<String> deviceIdPretty() async {
    final id = await deviceId();
    final out = StringBuffer();
    for (var i = 0; i < id.length; i++) {
      if (i > 0 && i % 4 == 0) out.write('-');
      out.write(id[i]);
    }
    return out.toString();
  }

  Future<String?> _hardwareFingerprint() async {
    try {
      if (Platform.isAndroid) {
        final aid = await const AndroidId().getId();
        if (aid != null && aid.isNotEmpty) return aid;
      }
      if (Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        return i.identifierForVendor;
      }
    } catch (_) {/* ارجع للاحتياط */}
    return null;
  }

  // ---- الحالة ----

  /// متوافق مع البوابة القديمة: مفعّل وسارٍ؟ (أو غير مقفل في وضع التطوير).
  Future<bool> isActivated() async {
    final s = (await info()).state;
    return s == LicenseState.active || s == LicenseState.disabled;
  }

  /// معلومات الترخيص الحالية (مع حساب الانتهاء وحارس الساعة).
  Future<LicenseInfo> info() async {
    if (!_keyConfigured) {
      return const LicenseInfo(LicenseState.disabled, false, null, 0);
    }
    final rec = await _readRecord();
    if (rec == null) return const LicenseInfo(LicenseState.none, false, null, 0);

    final duration = rec['d'] as int; // 0 = دائم.
    final activated = rec['a'] as int;
    final lastSeen = (rec['s'] as int?) ?? activated;

    final now = DateTime.now().millisecondsSinceEpoch;
    // حارس ضدّ إرجاع الساعة: «الآن الفعلي» لا يقلّ عن آخر وقت رأيناه.
    final effNow = now > lastSeen ? now : lastSeen;
    if (effNow != lastSeen) {
      rec['s'] = effNow;
      await _writeRecord(rec); // ثبّت أعلى وقت رأيناه.
    }

    if (duration == 0) {
      return const LicenseInfo(LicenseState.active, true, null, 0);
    }
    final expiryMs = activated + duration * _dayMs;
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiryMs);
    if (effNow < expiryMs) {
      final daysLeft = ((expiryMs - effNow) / _dayMs).ceil();
      return LicenseInfo(LicenseState.active, false, expiry, daysLeft);
    }
    return LicenseInfo(LicenseState.expired, false, expiry, 0);
  }

  // ---- التفعيل ----

  /// يتحقّق من رمز التفعيل ويُفعّل عند صحّته. يعيد true عند النجاح.
  Future<bool> tryActivate(String code) async {
    if (!_keyConfigured) return true;
    try {
      final bytes = base32Decode(_normalizeKey(code));
      if (bytes.length != 66) return false; // مدّة(2) + توقيع(64).
      final duration = (bytes[0] << 8) | bytes[1];
      final sig = bytes.sublist(2);

      final id = await deviceId();
      final msg = utf8.encode('$_msgPrefix|$id|$duration');
      final pub = SimplePublicKey(base64Decode(_publicKeyB64),
          type: KeyPairType.ed25519);
      final ok = await _ed.verify(msg, signature: Signature(sig, publicKey: pub));
      if (!ok) return false;

      await _activate(duration);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// استرجاع المالك (احتياط أمان): بإدخال المفتاح الخاصّ (Seed) يتحقّق أنّه
  /// يطابق المفتاح العامّ المدمج ثم يفعّل دائمًا — كي لا يُحبَس المالك أبدًا عن
  /// بياناته إن تعذّر المولّد. لا يفيد غير المالك لأنّه لا يملك المفتاح الخاصّ.
  Future<bool> recoverWithOwnerSeed(String seedInput) async {
    try {
      final hex = seedInput.trim().toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
      if (hex.length != 64) return false;
      final seed = <int>[
        for (var i = 0; i < 64; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)
      ];
      final kp = await _ed.newKeyPairFromSeed(seed);
      final derived = await kp.extractPublicKey();
      final embedded = base64Decode(_publicKeyB64);
      if (!_ctEquals(derived.bytes, embedded)) return false; // ليس مفتاح المالك.
      await _activate(0); // دائم.
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _activate(int duration) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _writeRecord({'d': duration, 'a': now, 's': now});
  }

  /// إلغاء التفعيل (للاختبار/إعادة الضبط من إعدادات المالك).
  Future<void> deactivate() async {
    await _storage.delete(key: _kRecord);
    try {
      final f = await _fileRef();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ---- التخزين (تخزين آمن + نسخة ملفّ دائمة لمقاومة فشل القراءة المؤقّت) ----

  Future<File> _fileRef() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_licenseFile');
  }

  Future<Map<String, dynamic>?> _readRecord() async {
    String? raw;
    try {
      raw = await _storage.read(key: _kRecord);
    } catch (_) {}
    if (raw == null || raw.isEmpty) {
      // احتياط: اقرأ من الملفّ الدائم وأعد المزامنة للتخزين الآمن.
      try {
        final f = await _fileRef();
        if (await f.exists()) {
          raw = await f.readAsString();
          if (raw.isNotEmpty) {
            try {
              await _storage.write(key: _kRecord, value: raw);
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) return m;
    } catch (_) {}
    return null;
  }

  Future<void> _writeRecord(Map<String, dynamic> rec) async {
    final raw = jsonEncode(rec);
    try {
      await _storage.write(key: _kRecord, value: raw);
    } catch (_) {}
    // اكتب أيضًا نسخة دائمة (تنجو من فشل قراءة التخزين الآمن المؤقّت).
    try {
      final f = await _fileRef();
      await f.writeAsString(raw, flush: true);
    } catch (_) {}
  }

  // ---- ترميز ----

  // نُكبّر الحروف ونحذف الفواصل فقط. لا نُبدّل حروفًا (L وU صحيحان في الأبجدية،
  // وأيّ رمز خارجها يتجاهله فكّ Base32 تلقائيًّا).
  String _normalizeKey(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// مقارنة ثابتة الزمن (لا تُسرّب الفروق).
  bool _ctEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a[i] ^ b[i];
    }
    return r == 0;
  }

  static const _b32 = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// ترميز Base32 (Crockford-ish) بلا حروف ملتبسة (I L O U).
  static String base32(List<int> bytes) {
    var bits = 0, value = 0;
    final out = StringBuffer();
    for (final b in bytes) {
      value = (value << 8) | b;
      bits += 8;
      while (bits >= 5) {
        out.write(_b32[(value >> (bits - 5)) & 31]);
        bits -= 5;
      }
      value &= (1 << bits) - 1; // أبقِ البتات المتبقّية فقط (تفادي تجاوز 64-بت).
    }
    if (bits > 0) out.write(_b32[(value << (5 - bits)) & 31]);
    return out.toString();
  }

  /// فكّ ترميز Base32 (يقابل [base32]). يتجاهل الحروف غير المعروفة.
  static List<int> base32Decode(String s) {
    var bits = 0, value = 0;
    final out = <int>[];
    for (final ch in s.split('')) {
      final idx = _b32.indexOf(ch);
      if (idx < 0) continue;
      value = (value << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        out.add((value >> (bits - 8)) & 0xff);
        bits -= 8;
      }
      value &= (1 << bits) - 1; // تفادي تجاوز 64-بت على المدخلات الطويلة.
    }
    return out;
  }
}
