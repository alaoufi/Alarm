import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'tone_preview.dart';

/// تنظيف عميق للذاكرة والملفّات المؤقّتة التي يخلّفها التطبيق.
///
/// أثناء العمل يتراكم في مجلّد المؤقّت (temp/cache) ملفّاتٌ كبيرة: ملف تحديث
/// التطبيق (‎Alerts_update.apk، عشرات الميغابايت)، وملفّات التصدير المؤقّتة
/// (PDF/Word/ICS/صور المشاركة) والنُّسخ الاحتياطية المؤقّتة. لا يحتاجها التطبيق
/// بعد انتهاء عمليّتها، فنحذف القديم منها. كما نُفرِغ ذاكرة الصور المفكوكة
/// (imageCache) عند مغادرة التطبيق لتحرير الذاكرة فورًا.
class CleanupService {
  CleanupService._();
  static final CleanupService instance = CleanupService._();

  /// امتدادات/أسماء الملفّات المؤقّتة التي نُنشئها ويمكن حذفها بأمان.
  static const _disposableExt = {
    '.apk', '.pdf', '.docx', '.ics', '.png', '.jpg', '.jpeg', '.zip', '.tmp',
  };
  static const _disposableNames = {'Alerts_update.apk'};

  bool _purging = false;

  /// يحذف الملفّات المؤقّتة الأقدم من [olderThan] (افتراضيًّا 3 دقائق) كي لا نمسّ
  /// ملفًّا قيد الإنشاء/المشاركة الآن. يُستدعى عند الإقلاع وعند مغادرة التطبيق.
  /// يعيد عدد الملفّات المحذوفة (للتشخيص).
  Future<int> purgeTempFiles(
      {Duration olderThan = const Duration(minutes: 3)}) async {
    if (_purging) return 0;
    _purging = true;
    var removed = 0;
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return 0;
      final now = DateTime.now();
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        final dot = name.lastIndexOf('.');
        final ext = dot < 0 ? '' : name.substring(dot).toLowerCase();
        final disposable =
            _disposableNames.contains(name) || _disposableExt.contains(ext);
        if (!disposable) continue;
        try {
          final stat = await entity.stat();
          if (now.difference(stat.modified) < olderThan) continue; // قيد الاستخدام.
          await entity.delete();
          removed++;
        } catch (_) {/* ملف مقفول/محذوف أصلًا — نتجاهل */}
      }
    } catch (_) {
      // التنظيف مساعدٌ لا حرِج — لا يجب أن يُعطّل التطبيق أبدًا.
    } finally {
      _purging = false;
    }
    return removed;
  }

  /// يُحرّر ذاكرة العمل عند مغادرة التطبيق: يوقف أي معاينة صوتية، ويُفرِغ ذاكرة
  /// الصور المفكوكة (تُعاد تحميلها عند الحاجة) — تنظيفٌ حقيقيّ للذاكرة.
  Future<void> releaseMemory() async {
    try {
      await TonePreview.stop();
    } catch (_) {}
    try {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    } catch (_) {}
  }
}
