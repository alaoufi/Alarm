import 'package:flutter/services.dart';

/// يفتح منتقي نغمات النظام (يعرض كل نغمات الجهاز بما فيها نغمات المُصنّع
/// مثل هواوي)، ويعيد رابط (URI) النغمة المختارة كي يقرأه نظام الإشعارات.
class RingtonePicker {
  RingtonePicker._();
  static const _ch = MethodChannel('com.mudhakkarati.app/ringtone');

  /// يفتح المنتقي. يعيد URI المختار، أو null عند الإلغاء.
  static Future<String?> pick({String? current}) async {
    try {
      return await _ch.invokeMethod<String>('pickRingtone', {'current': current});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// اسم النغمة المقروء من رابطها (للعرض في الإعدادات).
  static Future<String?> title(String? uri) async {
    if (uri == null || uri.isEmpty) return null;
    try {
      return await _ch.invokeMethod<String>('ringtoneTitle', {'uri': uri});
    } catch (_) {
      return null;
    }
  }
}
