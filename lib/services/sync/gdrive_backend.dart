import 'dart:async';
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'sync_backend.dart';

/// مزوّد مزامنة عبر **Google Drive** — يخزّن ملف المزامنة في «مجلّد التطبيق
/// المخفي» (appDataFolder) الخاص بالتطبيق داخل حساب المستخدم، فلا يظهر بين ملفاته
/// ولا يحتاج صلاحية الوصول لكامل الدرايف (نطاق drive.appdata فقط).
class GoogleDriveBackend implements SyncBackend {
  final String fileName;
  GoogleDriveBackend({this.fileName = 'mudhakkarati-sync.enc'});

  /// نطلب نطاق appdata فقط (الأقل صلاحيةً والأكثر خصوصية).
  static final GoogleSignIn googleSignIn = GoogleSignIn(
    scopes: const [drive.DriveApi.driveAppdataScope],
  );

  @override
  String get name => 'Google Drive';

  /// يضمن تسجيل الدخول: يحاول الصامت أولًا، ثم التفاعلي إن سُمح.
  static Future<GoogleSignInAccount?> ensureSignedIn(
      {bool interactive = false}) async {
    var account = googleSignIn.currentUser;
    account ??= await googleSignIn.signInSilently();
    if (account == null && interactive) {
      account = await googleSignIn.signIn();
    }
    return account;
  }

  Future<drive.DriveApi?> _api() async {
    final account = await ensureSignedIn(interactive: false);
    if (account == null) return null;
    final client = await googleSignIn.authenticatedClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  Future<String?> _findFileId(drive.DriveApi api) async {
    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$fileName'",
      $fields: 'files(id, name)',
    );
    final files = res.files;
    if (files == null || files.isEmpty) return null;
    return files.first.id;
  }

  @override
  Future<Uint8List?> download() async {
    final api = await _api();
    if (api == null) {
      throw Exception('لم يتم تسجيل الدخول بحساب Google');
    }
    final id = await _findFileId(api);
    if (id == null) return null;
    final media = await api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final builder = BytesBuilder();
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    return bytes.isEmpty ? null : bytes;
  }

  @override
  Future<void> upload(Uint8List bytes) async {
    final api = await _api();
    if (api == null) {
      throw Exception('لم يتم تسجيل الدخول بحساب Google');
    }
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);
    final existingId = await _findFileId(api);
    if (existingId == null) {
      final file = drive.File()
        ..name = fileName
        ..parents = ['appDataFolder'];
      await api.files.create(file, uploadMedia: media);
    } else {
      await api.files.update(drive.File(), existingId, uploadMedia: media);
    }
  }

  @override
  Future<SyncTestResult> test() async {
    try {
      final api = await _api();
      if (api == null) {
        return const SyncTestResult(false, 'لم يتم تسجيل الدخول بحساب Google');
      }
      await _findFileId(api); // استعلام بسيط للتحقق من الصلاحيات.
      final email = googleSignIn.currentUser?.email ?? '';
      return SyncTestResult(
          true, 'متّصل بـ Google Drive${email.isEmpty ? '' : ' ($email)'}');
    } catch (e) {
      return SyncTestResult(false, 'فشل الاتصال بـ Google Drive: $e');
    }
  }
}
