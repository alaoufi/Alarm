import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// معلومات نسخة متوفّرة للتحديث.
class UpdateInfo {
  final String version; // اسم النسخة (مثل 1.4.2)
  final int build; // رقم البناء البعيد
  final String url; // رابط ملف الـ APK
  const UpdateInfo(this.version, this.build, this.url);
}

/// خطأ وصول أثناء فحص التحديث (تمييزًا عن «أنت على أحدث نسخة»).
class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

/// تحديث التطبيق داخليًّا (لتطبيق مُثبَّت يدويًّا خارج المتجر):
/// - يقرأ `version.json` المنشور مع كل بناء على فرع apk-dist-alarm.
/// - يقارن رقم البناء البعيد برقم بناء التطبيق الحالي.
/// - عند توفّر أحدث: يحمّل الـ APK ويشغّل مثبّت النظام (يبقى تأكيد التثبيت على
///   المستخدم — إجباريّ لأي تطبيق خارج Google Play).
class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  // مصادر ملفّ النسخة (نُجرّبها بالترتيب): مرفق الإصدار عبر github.com أوثقها
  // (يتبع التحويلات)، ثم raw/jsDelivr من فرع main كاحتياط.
  static const List<String> _versionUrls = [
    'https://github.com/alaoufi/Alarm/releases/download/latest/version.json',
    'https://raw.githubusercontent.com/alaoufi/Alarm/main/version.json',
    'https://cdn.jsdelivr.net/gh/alaoufi/Alarm@main/version.json',
  ];
  // تنزيل الـAPK من Releases عبر github.com (أوثق من raw، ويتبع التحويلات).
  static const _fallbackApk =
      'https://github.com/alaoufi/Alarm/releases/download/latest/Alerts.apk';

  /// رابط تنزيل أحدث APK مباشرةً (مسار احتياطيّ عبر المتصفّح حين يتعذّر الفحص/التثبيت
  /// داخل التطبيق — يعمل ما دام المتصفّح يصل إلى github.com).
  static String get downloadUrl => _fallbackApk;

  /// يعيد معلومات التحديث إن توفّرت نسخة أحدث، أو null إن كنت على الأحدث.
  /// يرمي [UpdateException] عند فشل الوصول (تمييزًا عن «أنت محدّث»).
  Future<UpdateInfo?> check() async {
    Map<String, dynamic>? j;
    for (final u in _versionUrls) {
      try {
        final body = await _fetch(u, const Duration(seconds: 12));
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          j = decoded;
          break;
        }
      } catch (_) {/* جرّب المصدر التالي */}
    }
    if (j == null) {
      throw const UpdateException('تعذّر التحقّق من التحديث. تأكّد من اتصال الإنترنت ثم أعد المحاولة.');
    }
    final remoteBuild = (j['build'] as num?)?.toInt() ?? 0;
    final remoteVer = (j['version'] as String?) ?? '';
    final url = (j['url'] as String?) ?? _fallbackApk;

    // نقارن بـ**اسم النسخة** (1.7.4 مقابل 1.7.1) لا برقم البناء: مع `--split-per-abi`
    // يضيف Flutter إزاحة معماريّة إلى versionCode المثبَّت فيصير أكبر من الرقم
    // المنشور، فكانت المقارنة برقم البناء تقول دائمًا «أنت على الأحدث».
    final info = await PackageInfo.fromPlatform();
    if (isNewerVersion(remoteVer, info.version)) {
      return UpdateInfo(remoteVer, remoteBuild, url);
    }
    return null;
  }

  /// هل [remote] أحدث من [local] دلاليًّا (مقارنة مقاطع `x.y.z` عدديًّا)؟
  /// تتجاهل لاحقة البناء (`+NN`) وأي رموز غير رقميّة في كل مقطع.
  static bool isNewerVersion(String remote, String local) {
    List<int> parts(String v) => v
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final r = parts(remote);
    final l = parts(local);
    final n = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < n; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false; // متساويتان
  }

  /// تنزيل نصّ من [url] مع مهلة؛ يرمي عند غير 200.
  Future<String> _fetch(String url, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(timeout * 2);
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      // انتظر قراءة الجسم كاملًا **قبل** إغلاق العميل في finally.
      final body = await res.transform(utf8.decoder).join();
      return body;
    } finally {
      client.close(force: true);
    }
  }

  /// يحمّل الـ APK ثم يفتحه بمثبّت النظام. يجرّب [url] ثم المصدر البديل
  /// (github.com) عند فشله. يعيد رسالة خطأ عند الفشل، أو null عند النجاح.
  Future<String?> downloadAndInstall(String url,
      {void Function(double progress)? onProgress}) async {
    final urls = <String>{url, _fallbackApk}.toList();
    File? file;
    var lastErr = 'تعذّر التحميل';
    for (final u in urls) {
      try {
        file = await _downloadApk(u, onProgress);
        break;
      } catch (e) {
        lastErr = 'تعذّر التحميل من المصدر: $e';
      }
    }
    if (file == null) return lastErr;

    // الأفضل (أندرويد): نطلق مثبّت النظام مباشرةً عبر قناة أصليّة (بلا فتح ملف
    // ولا منتقي تطبيقات). إن لم تُمنح صلاحية «تثبيت تطبيقات غير معروفة» نفتحها مرّة.
    if (Platform.isAndroid) {
      try {
        final can = await _installer.invokeMethod<bool>('canInstall') ?? false;
        if (!can) {
          await _installer.invokeMethod('openInstallSettings');
          return 'فعّل «السماح بتثبيت تطبيقات غير معروفة» لتطبيق Alerts ثم اضغط تحديث مرّة أخرى.';
        }
        final ok =
            await _installer.invokeMethod<bool>('install', {'path': file.path}) ??
                false;
        if (ok) return null;
      } catch (_) {/* ارجع لبديل OpenFilex */}
    }

    // بديل: OpenFilex (يفتح المثبّت عبر مزوّد الحزمة نفسه).
    try {
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) return result.message;
      return null;
    } catch (e) {
      return 'تعذّر فتح المثبّت: $e';
    }
  }

  static const MethodChannel _installer =
      MethodChannel('com.mudhakkarati.app/installer');

  Future<File> _downloadApk(
      String url, void Function(double progress)? onProgress) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/Alerts_update.apk');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) onProgress(received / total);
      }
      await sink.flush();
      await sink.close();
      return file;
    } finally {
      client.close(force: true);
    }
  }
}
