import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'sync_backend.dart';

/// مزوّد مزامنة عبر **WebDAV** (Nextcloud / ownCloud / أي خادم يدعم WebDAV).
///
/// نستخدم `dart:io` مباشرةً (بدون أي اعتماد إضافي): GET للتنزيل، PUT للرفع،
/// مع مصادقة Basic. الرابط هو مجلّد على الخادم، ونكتب داخله ملفًا باسم ثابت.
class WebDavBackend implements SyncBackend {
  final String baseUrl; // مثل: https://cloud.example.com/remote.php/dav/files/USER/Notes
  final String username;
  final String password;
  final String fileName;

  WebDavBackend({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.fileName = 'mudhakkarati-sync.enc',
  });

  @override
  String get name => 'WebDAV';

  Uri get _fileUri {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse('$base$fileName');
  }

  String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  HttpClient _client() {
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 25);
    return c;
  }

  @override
  Future<Uint8List?> download() async {
    final client = _client();
    try {
      final req = await client.getUrl(_fileUri);
      req.headers.set(HttpHeaders.authorizationHeader, _authHeader);
      final res = await req.close();
      if (res.statusCode == 404) return null;
      if (res.statusCode >= 400) {
        throw HttpException('فشل التنزيل (${res.statusCode})');
      }
      final builder = BytesBuilder();
      await for (final chunk in res) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> upload(Uint8List bytes) async {
    final client = _client();
    try {
      final req = await client.openUrl('PUT', _fileUri);
      req.headers.set(HttpHeaders.authorizationHeader, _authHeader);
      req.headers.contentType = ContentType.binary;
      req.add(bytes);
      final res = await req.close();
      // 200/201/204 = نجاح (إنشاء أو استبدال).
      if (res.statusCode >= 400) {
        await res.drain();
        throw HttpException('فشل الرفع (${res.statusCode})');
      }
      await res.drain();
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<SyncTestResult> test() async {
    final client = _client();
    try {
      // PROPFIND على المجلّد للتحقق من الرابط والمصادقة.
      final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      final req = await client.openUrl('PROPFIND', Uri.parse(base));
      req.headers.set(HttpHeaders.authorizationHeader, _authHeader);
      req.headers.set('Depth', '0');
      final res = await req.close();
      await res.drain();
      if (res.statusCode == 401) {
        return const SyncTestResult(false, 'اسم المستخدم أو كلمة المرور خاطئة');
      }
      if (res.statusCode == 404) {
        return const SyncTestResult(false, 'المجلّد غير موجود على الخادم');
      }
      // 207 Multi-Status هو رد PROPFIND الناجح؛ نقبل أي 2xx أيضًا.
      if (res.statusCode == 207 ||
          (res.statusCode >= 200 && res.statusCode < 300)) {
        return const SyncTestResult(true, 'تم الاتصال بنجاح');
      }
      return SyncTestResult(false, 'استجابة غير متوقّعة (${res.statusCode})');
    } on SocketException {
      return const SyncTestResult(false, 'تعذّر الوصول إلى الخادم (تحقّق من الرابط/الإنترنت)');
    } catch (e) {
      return SyncTestResult(false, 'فشل الاتصال: $e');
    } finally {
      client.close(force: true);
    }
  }
}
