import '../core/time/hijri_recurrence.dart';
import '../data/models/enums.dart';
import '../data/models/reminder.dart';

/// منطق مواعيد جرعات الدواء (نقيّ، بلا قاعدة بيانات) — يشاركه المُجدول وسجلّ
/// الجرعات. يدعم:
/// - فاصل أيام مخصّص [Reminder.intervalDays] ≥ 2 («يوم بعد يوم»، «كل ٣ أيام»…).
/// - عدد جرعات محدّد [Reminder.doseCount] (> 0) أو مستمر (= 0).
/// وإلا فالتكرار العاديّ (يومي/أسبوعي/شهري/سنوي/مرّة).

/// زمن الجرعة رقم [index] (يبدأ من 0) منذ بداية المنبّه.
DateTime medOccurrenceAt(Reminder r, int index) {
  final base = r.time;
  if (r.intervalDays >= 2) {
    return base.add(Duration(days: index * r.intervalDays));
  }
  switch (r.repeat) {
    case ReminderRepeat.once:
      return index == 0 ? base : DateTime(9999);
    case ReminderRepeat.daily:
      return base.add(Duration(days: index));
    case ReminderRepeat.weekly:
      return base.add(Duration(days: 7 * index));
    case ReminderRepeat.monthly:
      return DateTime(
          base.year, base.month + index, base.day, base.hour, base.minute);
    case ReminderRepeat.yearly:
      return DateTime(
          base.year + index, base.month, base.day, base.hour, base.minute);
    case ReminderRepeat.hijriYearly:
      return hijriAnniversaryAt(base, index);
  }
}

/// مواعيد الجرعات الواقعة **بعد** [after] وحتى [until] (شاملة)، مع احترام عدد
/// جرعات الكورس إن كان محدّدًا. محدودة بسقف أمان لتفادي أي حلقة طويلة.
List<DateTime> medOccurrencesBetween(
    Reminder r, DateTime after, DateTime until) {
  // قصّ النهاية على آخر جرعة في كورس محدود العدد.
  var end = until;
  if (r.doseCount > 0) {
    final last = medOccurrenceAt(r, r.doseCount - 1);
    if (last.isBefore(end)) end = last;
  }
  if (after.isAfter(end)) return const [];

  final res = <DateTime>[];
  final base = r.time;

  // مرّة واحدة (بلا فاصل أيام).
  if (r.intervalDays < 2 && r.repeat == ReminderRepeat.once) {
    if (base.isAfter(after) && !base.isAfter(end)) res.add(base);
    return res;
  }

  // خطوة بالأيام (فاصل مخصّص / يومي / أسبوعي) — قفزة سريعة لأول موعد بعد after.
  final stepDays = r.intervalDays >= 2
      ? r.intervalDays
      : r.repeat == ReminderRepeat.daily
          ? 1
          : r.repeat == ReminderRepeat.weekly
              ? 7
              : 0;
  if (stepDays > 0) {
    var i = 0;
    final gap = after.difference(base).inDays;
    if (gap > 0) i = gap ~/ stepDays;
    var t = base.add(Duration(days: i * stepDays));
    while (!t.isAfter(after)) {
      i++;
      t = base.add(Duration(days: i * stepDays));
    }
    while (!t.isAfter(end) && res.length < 500) {
      res.add(t);
      i++;
      t = base.add(Duration(days: i * stepDays));
    }
    return res;
  }

  // شهري / سنوي.
  if (r.repeat == ReminderRepeat.monthly) {
    var t = DateTime(after.year, after.month, base.day, base.hour, base.minute);
    while (!t.isAfter(after)) {
      t = DateTime(t.year, t.month + 1, base.day, base.hour, base.minute);
    }
    while (!t.isAfter(end) && res.length < 120) {
      res.add(t);
      t = DateTime(t.year, t.month + 1, base.day, base.hour, base.minute);
    }
  } else if (r.repeat == ReminderRepeat.yearly) {
    var t = DateTime(after.year, base.month, base.day, base.hour, base.minute);
    while (!t.isAfter(after)) {
      t = DateTime(t.year + 1, base.month, base.day, base.hour, base.minute);
    }
    while (!t.isAfter(end) && res.length < 50) {
      res.add(t);
      t = DateTime(t.year + 1, base.month, base.day, base.hour, base.minute);
    }
  }
  return res;
}
