import 'package:audioplayers/audioplayers.dart';

/// تشغيل معاينة صوتية قصيرة لنغمات التنبيه المضمّنة (للاستماع قبل الاختيار).
class TonePreview {
  TonePreview._();
  static final AudioPlayer _player = AudioPlayer();

  /// يشغّل نغمة مضمّنة بالاسم (forest, birds, water, ...).
  static Future<void> play(String tone) async {
    try {
      await _player.stop();
      // وضع mediaPlayer (الافتراضي) يشغّل ملفات بطول عدة ثوانٍ بموثوقية.
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(AssetSource('sounds/$tone.wav'), volume: 1.0);
    } catch (_) {
      // تجاهل أي خطأ تشغيل (لا يجب أن يُعطّل الواجهة).
    }
  }

  static Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}
