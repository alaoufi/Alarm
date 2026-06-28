import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models/enums.dart';
import '../data/models/reminder.dart';

/// تصدير تنبيه كحدث iCalendar (.ics) وفتحه بتطبيق التقويم لإضافته.
/// يعمل دون أي إضافة native — يعتمد فقط على open_filex وملفّ نصّيّ.
class CalendarExport {
  CalendarExport._();

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// وقت محلّيّ «عائم» بصيغة iCalendar: YYYYMMDDTHHMMSS.
  static String _fmt(DateTime d) =>
      '${d.year}${_two(d.month)}${_two(d.day)}T${_two(d.hour)}${_two(d.minute)}00';

  static const _byDay = {
    1: 'MO',
    2: 'TU',
    3: 'WE',
    4: 'TH',
    5: 'FR',
    6: 'SA',
    7: 'SU',
  };

  static String? _rrule(Reminder r) {
    if (r.intervalDays >= 2) return 'FREQ=DAILY;INTERVAL=${r.intervalDays}';
    switch (r.repeat) {
      case ReminderRepeat.once:
      case ReminderRepeat.hijriYearly: // لا يقابلها تكرار قياسيّ في ICS.
        return null;
      case ReminderRepeat.daily:
        return 'FREQ=DAILY';
      case ReminderRepeat.weekly:
        return 'FREQ=WEEKLY;BYDAY=${_byDay[r.time.weekday]}';
      case ReminderRepeat.monthly:
        return 'FREQ=MONTHLY';
      case ReminderRepeat.yearly:
        return 'FREQ=YEARLY';
    }
  }

  static Future<void> addToCalendar(Reminder r, String title) async {
    final rrule = _rrule(r);
    final summary = title.replaceAll('\n', ' ').replaceAll(',', r'\,');
    final uid =
        '${r.notificationId}-${r.time.millisecondsSinceEpoch}@alerts';
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Alerts//AR',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'BEGIN:VEVENT',
      'UID:$uid',
      'DTSTAMP:${_fmt(DateTime.now())}',
      'DTSTART:${_fmt(r.time)}',
      'DURATION:PT30M',
      'SUMMARY:$summary',
      if (rrule != null) 'RRULE:$rrule',
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:$summary',
      'TRIGGER:-PT0M',
      'END:VALARM',
      'END:VEVENT',
      'END:VCALENDAR',
    ];
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/alert_event.ics');
    await file.writeAsString(lines.join('\r\n'), flush: true);
    await OpenFilex.open(file.path, type: 'text/calendar');
  }
}
