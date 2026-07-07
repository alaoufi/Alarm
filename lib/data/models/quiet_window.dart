/// نافذة إسكات: فترة زمنية يوميّة (بالدقائق منذ منتصف الليل) لا يصدر فيها صوت
/// المنبّه — يبقى الإشعار ظاهرًا وواضحًا لكن بلا صوت أو اهتزاز. تدعم العبور بعد
/// منتصف الليل (مثل 23:00 → 06:00).
class QuietWindow {
  /// بداية الفترة بالدقائق منذ منتصف الليل (0..1439).
  final int startMinutes;

  /// نهاية الفترة بالدقائق منذ منتصف الليل (0..1439).
  final int endMinutes;

  const QuietWindow(this.startMinutes, this.endMinutes);

  /// هل الدقيقة [minuteOfDay] (0..1439) تقع ضمن هذه الفترة؟
  bool contains(int minuteOfDay) {
    if (startMinutes == endMinutes) return false; // فترة صفريّة ⇒ لا شيء.
    if (startMinutes < endMinutes) {
      // فترة ضمن نفس اليوم (مثل 02:00 → 07:00).
      return minuteOfDay >= startMinutes && minuteOfDay < endMinutes;
    }
    // فترة تعبر منتصف الليل (مثل 23:00 → 06:00).
    return minuteOfDay >= startMinutes || minuteOfDay < endMinutes;
  }

  /// هل الوقت [t] يقع ضمن هذه الفترة؟
  bool containsTime(DateTime t) => contains(t.hour * 60 + t.minute);

  int get startHour => startMinutes ~/ 60;
  int get startMinute => startMinutes % 60;
  int get endHour => endMinutes ~/ 60;
  int get endMinute => endMinutes % 60;

  /// ترميز للحفظ في SharedPreferences: «start-end» (بالدقائق).
  String encode() => '$startMinutes-$endMinutes';

  /// فكّ الترميز — يعيد null عند خطأ في الصيغة أو تجاوز النطاق.
  static QuietWindow? decode(String s) {
    final parts = s.split('-');
    if (parts.length != 2) return null;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return null;
    if (a < 0 || a > 1439 || b < 0 || b > 1439) return null;
    return QuietWindow(a, b);
  }
}
