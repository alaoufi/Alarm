import 'dart:typed_data';

/// نتيجة اختبار الاتصال بخادم المزامنة.
class SyncTestResult {
  final bool ok;
  final String message;
  const SyncTestResult(this.ok, this.message);
}

/// واجهة مزوّد التخزين السحابي للمزامنة (WebDAV الآن، Google Drive لاحقًا).
///
/// المزامنة تتعامل مع «ملف واحد مشفّر» يحوي كل الملاحظات؛ فالمزوّد يحتاج فقط
/// إلى رفع/تنزيل هذا الملف واختبار الاتصال.
abstract class SyncBackend {
  /// اسم المزوّد للعرض.
  String get name;

  /// ينزّل بايتات ملف المزامنة، أو null إذا لم يكن موجودًا بعد (أول مزامنة).
  Future<Uint8List?> download();

  /// يرفع بايتات ملف المزامنة (يستبدل الموجود).
  Future<void> upload(Uint8List bytes);

  /// يختبر الاتصال والمصادقة.
  Future<SyncTestResult> test();
}
