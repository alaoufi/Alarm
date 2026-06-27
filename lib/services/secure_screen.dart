import 'package:flutter/services.dart';

/// تفعيل/إلغاء FLAG_SECURE (منع تصوير الشاشة وإخفاء المعاينة في «التطبيقات
/// الأخيرة») عبر قناة أصلية مع MainActivity. يُستخدم في الشاشات الحسّاسة فقط.
class SecureScreen {
  SecureScreen._();
  static const _channel = MethodChannel('alaoufi/secure');

  static Future<void> enable() async {
    try {
      await _channel.invokeMethod('enable');
    } catch (_) {}
  }

  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('disable');
    } catch (_) {}
  }
}
