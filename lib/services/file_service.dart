import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// إدارة مرفقات الملاحظات (صور، صوت، PDF، رسومات) داخل تخزين الجهاز الخاص.
class FileService {
  FileService._();
  static final FileService instance = FileService._();

  static const _uuid = Uuid();

  /// مجلد المرفقات داخل بيانات التطبيق (لا يصل إليه إلا التطبيق).
  Future<Directory> attachmentsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'attachments'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// نسخ ملف خارجي إلى مجلد المرفقات ويعيد المسار الجديد.
  Future<String> importFile(String sourcePath, {String? extension}) async {
    final dir = await attachmentsDir();
    final ext = extension ?? p.extension(sourcePath);
    final dest = p.join(dir.path, '${_uuid.v4()}$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  /// مسار جديد فريد داخل مجلد المرفقات (دون إنشاء الملف).
  Future<String> newAttachmentPath(String extension) async {
    final dir = await attachmentsDir();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    return p.join(dir.path, '${_uuid.v4()}$ext');
  }

  Future<void> deleteIfExists(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  }
}
