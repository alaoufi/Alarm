import 'package:flutter_test/flutter_test.dart';
import 'package:mudhakkarati/data/models/enums.dart';
import 'package:mudhakkarati/data/models/reminder.dart';

void main() {
  group('Reminder serialization roundtrip', () {
    test('preserves all fields through toMap/fromMap', () {
      final r = Reminder(
        id: 7,
        noteId: 3,
        title: 'دواء',
        time: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        repeat: ReminderRepeat.weekly,
        isActive: true,
        importance: ReminderImportance.critical,
        preAlerts: const [5, 15, 60, 1440],
        location: 'https://maps.google.com/?q=24.7,46.6',
        attachmentPath: '/data/attachments/invite.pdf',
        notificationId: 12345,
      );
      final back = Reminder.fromMap(r.toMap());
      expect(back.noteId, 3);
      expect(back.title, 'دواء');
      expect(back.repeat, ReminderRepeat.weekly);
      expect(back.importance, ReminderImportance.critical);
      expect(back.preAlerts, [5, 15, 60, 1440]);
      expect(back.location, 'https://maps.google.com/?q=24.7,46.6');
      expect(back.attachmentPath, '/data/attachments/invite.pdf');
      expect(back.notificationId, 12345);
      expect(back.time.millisecondsSinceEpoch, 1700000000000);
    });

    test('location defaults to empty when column missing (old rows)', () {
      final r = Reminder.fromMap({
        'note_id': null,
        'title': 't',
        'time': 0,
        'repeat': 'once',
        'is_active': 1,
        'notification_id': 1,
        'importance': 'high',
        'pre_alerts': '',
      });
      expect(r.location, '');
      expect(r.attachmentPath, '');
    });

    test('copyWith preserves location and other fields', () {
      final r = Reminder(
        time: DateTime.fromMillisecondsSinceEpoch(0),
        notificationId: 9,
        location: 'geo:1,2',
      );
      final c = r.copyWith(title: 'x');
      expect(c.location, 'geo:1,2');
      expect(c.notificationId, 9);
      expect(c.title, 'x');
    });

    test('importance unknown value falls back to high', () {
      expect(ReminderImportanceX.fromDb('garbage'), ReminderImportance.high);
      expect(ReminderImportanceX.fromDb(null), ReminderImportance.high);
      expect(ReminderImportanceX.fromDb('low'), ReminderImportance.low);
    });

    test('pre_alerts parsing ignores empty/garbage/<=0', () {
      Reminder fromPre(String s) => Reminder.fromMap({
            'note_id': 1,
            'title': 't',
            'time': 0,
            'repeat': 'once',
            'is_active': 1,
            'notification_id': 1,
            'importance': 'high',
            'pre_alerts': s,
          });
      expect(fromPre('').preAlerts, isEmpty);
      expect(fromPre(',,').preAlerts, isEmpty);
      expect(fromPre('0,5,-3,15,x').preAlerts, [5, 15]);
    });
  });

  group('Notification ID block scheme', () {
    const stride = 1 << 26;
    const slots = [0, 1, 2, 3, 4, 10, 11, 12, 13];
    test('no 32-bit overflow at max base', () {
      const base = 1 << 26;
      final maxId = base + 13 * stride;
      expect(maxId < (1 << 31) - 1, isTrue);
    });
    test('blocks are internally unique for many bases', () {
      for (var base = 1; base < (1 << 26); base += 97777) {
        final ids = slots.map((k) => base + k * stride).toSet();
        expect(ids.length, slots.length);
      }
    });

    // معرّفات شاشة «اختبار الموثوقية» كبيرة (خارج نطاق التذكيرات العادية).
    // الخطأ السابق: base كان 1.9e9، فعند إلغاء التوابع (base + k·stride) تجاوز
    // 2^31 ورمى النظام «Invalid argument (id)». نضمن بقاءها ضمن 32-بت.
    test('reliability-test ids never overflow the followup cancel sweep', () {
      const maxId = 0x7fffffff; // 2^31 - 1
      // القيم المستخدمة فعليًّا في NotificationService.
      for (final base in [200000000, 200000001]) {
        expect(base, lessThanOrEqualTo(maxId));
        // أكبر من stride ⇒ لا تُجدول إعادات «عدم النسيان».
        expect(base, greaterThanOrEqualTo(stride));
        // مسح الإلغاء يصل إلى k=15 — يجب أن يبقى كلّه ضمن 32-بت.
        for (var k = 1; k <= 15; k++) {
          expect(base + k * stride, lessThanOrEqualTo(maxId),
              reason: 'base $base k $k يتجاوز 32-بت');
        }
      }
    });
  });
}
