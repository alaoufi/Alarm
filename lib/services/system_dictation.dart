import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// جسر إلى **خدمة الإملاء الأصلية في النظام** عبر `RecognizerIntent`
/// (`ACTION_RECOGNIZE_SPEECH`) — نفس نافذة الإملاء التي يعرضها الجهاز.
///
/// أكثر موثوقية من واجهة `SpeechRecognizer` المباشرة لأنها تستخدم نشاط النظام
/// الكامل الذي يتولّى الاستماع والتعرّف وعرض الواجهة.
class SystemDictation {
  static const _ch = MethodChannel('com.mudhakkarati.app/dictation');

  /// هل يدعم الجهاز الإملاء الصوتيّ (محرّك تعرّف + نشاط يستقبل الـIntent)؟
  static Future<bool> isAvailable() async {
    try {
      final ok = await _ch.invokeMethod<bool>('available');
      debugPrint('[STT] speech recognition available = $ok');
      return ok ?? false;
    } catch (e) {
      debugPrint('[STT] available check error: $e');
      return false;
    }
  }

  /// يفتح نافذة الإملاء الأصلية باللغة [locale] (مثل `ar-SA`) ويعيد النصّ
  /// المتعرَّف عليه، أو null عند الإلغاء. قد يرمي [PlatformException] عند الخطأ.
  static Future<String?> recognize(String locale) async {
    debugPrint('[STT] recognizer intent → locale=$locale');
    final text = await _ch.invokeMethod<String>('recognize', {'locale': locale});
    debugPrint('[STT] result text = "${text ?? '(cancelled)'}"');
    return text;
  }
}
