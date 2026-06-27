import 'package:flutter/services.dart';

/// رفع/استعادة مستوى صوت **تيّار المنبّه** (STREAM_ALARM) أصليًّا — يعمل حتى
/// عندما يكون الجهاز على الصامت أو الصوت منخفض. يُستخدم عند ظهور شاشة المنبّه.
class AlarmVolume {
  AlarmVolume._();
  static const _ch = MethodChannel('com.mudhakkarati.app/alarm_volume');

  /// يرفع صوت المنبّه إلى [targetPercent]٪ — فورًا أو بالتدرّج خلال
  /// [rampSeconds] ثانية (0 = فوري). يحفظ المستوى الأصليّ تلقائيًّا.
  static Future<void> raise({int targetPercent = 100, int rampSeconds = 0}) async {
    try {
      await _ch.invokeMethod('raise', {
        'targetPercent': targetPercent,
        'rampSeconds': rampSeconds,
      });
    } catch (_) {/* غير مدعوم/ممنوع — نتجاهل */}
  }

  /// يستعيد مستوى صوت المنبّه الأصليّ.
  static Future<void> restore() async {
    try {
      await _ch.invokeMethod('restore');
    } catch (_) {}
  }

  /// هل التطبيق مُستثنى من توفير البطارية؟ (إن لم يكن، قد يُقتل المنبّه المجدول).
  /// يعيد true عند التعذّر كي لا نُزعج المستخدم بلا داعٍ.
  static Future<bool> isBatteryUnrestricted() async {
    try {
      return await _ch.invokeMethod<bool>('isBatteryUnrestricted') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// يطلب استثناء التطبيق من توفير البطارية (نافذة النظام) — لضمان عمل المنبّه
  /// حتى لو كان التطبيق مغلقًا على أجهزة بإدارة طاقة صارمة (شاومي/هواوي…).
  static Future<void> requestBatteryUnrestricted() async {
    try {
      await _ch.invokeMethod('requestBatteryUnrestricted');
    } catch (_) {}
  }

  /// يفتح شاشة «التشغيل التلقائي» (Autostart) الخاصّة بالمُصنّع — لا يمكن منحها
  /// برمجيًّا، فنوجّه المستخدم إليها مباشرةً.
  static Future<void> openAutoStart() async {
    try {
      await _ch.invokeMethod('openAutoStart');
    } catch (_) {}
  }

  /// يفتح صفحة إعدادات التطبيق (بديل عامّ).
  static Future<void> openAppSettings() async {
    try {
      await _ch.invokeMethod('openAppSettings');
    } catch (_) {}
  }
}
