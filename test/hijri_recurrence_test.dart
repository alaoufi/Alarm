import 'package:flutter_test/flutter_test.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:mudhakkarati/core/time/hijri_recurrence.dart';

/// يضمن أنّ التذكير السنويّ الهجريّ يقع في نفس اليوم/الشهر الهجريّين، بعد الآن.
void main() {
  group('nextHijriAnniversary', () {
    final base = DateTime(2024, 3, 10, 9, 30); // وقت ثابت للاختبار

    test('الموعد القادم بعد «الآن»', () {
      final from = DateTime(2026, 1, 1);
      final next = nextHijriAnniversary(base, from);
      expect(next.isAfter(from), isTrue);
    });

    test('يحافظ على اليوم والشهر الهجريّين وعلى الوقت', () {
      final hBase = HijriCalendar.fromDate(base);
      final next = nextHijriAnniversary(base, DateTime(2026, 1, 1));
      final hNext = HijriCalendar.fromDate(next);
      expect(hNext.hMonth, hBase.hMonth);
      // اليوم نفسه (أو مقصوص لطول الشهر — هنا التاريخ المختار غير حدّيّ).
      expect(hNext.hDay, hBase.hDay);
      expect(next.hour, 9);
      expect(next.minute, 30);
    });

    test('الذكرى بفهرس تتقدّم سنة هجريّة (~٣٥٤ يومًا)', () {
      final y0 = hijriAnniversaryAt(base, 0);
      final y1 = hijriAnniversaryAt(base, 1);
      final gap = y1.difference(y0).inDays;
      expect(gap, inInclusiveRange(353, 356));
    });
  });
}
