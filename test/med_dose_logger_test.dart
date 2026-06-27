import 'package:flutter_test/flutter_test.dart';
import 'package:mudhakkarati/data/models/enums.dart';
import 'package:mudhakkarati/data/models/reminder.dart';
import 'package:mudhakkarati/services/med_dose_logger.dart';
import 'package:mudhakkarati/services/med_occurrences.dart';

/// حارس منطق تسجيل جرعات الأدوية تلقائيًّا من منبّهات 💊.
Reminder _r({
  required DateTime time,
  ReminderRepeat repeat = ReminderRepeat.daily,
  int intervalDays = 0,
  int doseCount = 0,
}) =>
    Reminder(
      title: '💊 دواء',
      time: time,
      repeat: repeat,
      intervalDays: intervalDays,
      doseCount: doseCount,
      notificationId: 1,
    );

void main() {
  group('parseMedTitle', () {
    test('اسم + جرعة', () {
      final r = MedDoseLogger.parseMedTitle('💊 فيتامين د — حبة');
      expect(r.$1, 'فيتامين د');
      expect(r.$2, 'حبة');
    });
    test('اسم بلا جرعة', () {
      final r = MedDoseLogger.parseMedTitle('💊 فيتامين د');
      expect(r.$1, 'فيتامين د');
      expect(r.$2, isNull);
    });
  });

  group('medOccurrenceAt', () {
    test('كل يومين', () {
      final r = _r(time: DateTime(2026, 1, 1, 8, 0), intervalDays: 2);
      expect(medOccurrenceAt(r, 0), DateTime(2026, 1, 1, 8, 0));
      expect(medOccurrenceAt(r, 1), DateTime(2026, 1, 3, 8, 0));
      expect(medOccurrenceAt(r, 3), DateTime(2026, 1, 7, 8, 0));
    });
    test('يومي/أسبوعي', () {
      final d = _r(time: DateTime(2026, 1, 1, 8, 0));
      expect(medOccurrenceAt(d, 5), DateTime(2026, 1, 6, 8, 0));
      final w = _r(time: DateTime(2026, 1, 1, 8, 0), repeat: ReminderRepeat.weekly);
      expect(medOccurrenceAt(w, 2), DateTime(2026, 1, 15, 8, 0));
    });
  });

  group('medOccurrencesBetween', () {
    test('يوميّ مستمر: جرعة لكل يوم', () {
      final r = _r(time: DateTime(2026, 1, 1, 8, 0));
      final occ = medOccurrencesBetween(
          r, DateTime(2026, 1, 1, 0, 0), DateTime(2026, 1, 4, 12, 0));
      expect(occ.length, 4);
      expect(occ.every((d) => d.hour == 8), isTrue);
    });

    test('كل يومين: المواعيد متباعدة يومين', () {
      final r = _r(time: DateTime(2026, 1, 1, 8, 0), intervalDays: 2);
      final occ = medOccurrencesBetween(
          r, DateTime(2026, 1, 1, 0, 0), DateTime(2026, 1, 10, 12, 0));
      // 1، 3، 5، 7، 9 يناير
      expect(occ.length, 5);
      for (var i = 1; i < occ.length; i++) {
        expect(occ[i].difference(occ[i - 1]).inDays, 2);
      }
    });

    test('عدد جرعات محدّد: يتوقّف بعد آخر جرعة', () {
      // كورس 3 جرعات يومية يبدأ 1 يناير ⇒ آخرها 3 يناير.
      final r = _r(time: DateTime(2026, 1, 1, 8, 0), doseCount: 3);
      final occ = medOccurrencesBetween(
          r, DateTime(2025, 12, 31), DateTime(2026, 12, 31));
      expect(occ.length, 3);
      expect(occ.last, DateTime(2026, 1, 3, 8, 0));
    });

    test('كورس كل يومين بثلاث جرعات', () {
      final r = _r(
          time: DateTime(2026, 1, 1, 8, 0), intervalDays: 2, doseCount: 3);
      final occ = medOccurrencesBetween(
          r, DateTime(2025, 12, 31), DateTime(2026, 12, 31));
      expect(occ.length, 3);
      expect(occ.last, DateTime(2026, 1, 5, 8, 0)); // 1، 3، 5
    });

    test('لا تكرارات إذا لم يمضِ موعد جديد', () {
      final r = _r(time: DateTime(2026, 1, 1, 8, 0));
      final t = DateTime(2026, 1, 10, 12, 0);
      expect(medOccurrencesBetween(r, t, t.add(const Duration(minutes: 1))),
          isEmpty);
    });
  });
}
