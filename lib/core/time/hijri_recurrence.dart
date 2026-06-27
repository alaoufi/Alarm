import 'package:hijri/hijri_calendar.dart';

/// أدوات التكرار **السنويّ الهجريّ** (المناسبات): يتكرّر التذكير في نفس اليوم
/// والشهر الهجريّين كل عام هجريّ — لا الميلاديّ — مع الحفاظ على ساعة/دقيقة الأصل.
///
/// يُقصّ اليوم إلى طول الشهر الهجريّ في تلك السنة (لو كان الأصل ٣٠ والشهر ٢٩)،
/// فلا يقفز إلى الشهر التالي.

/// التاريخ الميلاديّ الموافق لليوم/الشهر الهجريّين لـ[base] في السنة الهجريّة
/// (سنة [base] الهجريّة + [index])، محتفظًا بساعة/دقيقة [base].
DateTime hijriAnniversaryAt(DateTime base, int index) {
  final h = HijriCalendar.fromDate(base);
  final y = h.hYear + index;
  final dim = HijriCalendar().getDaysInMonth(y, h.hMonth);
  final day = h.hDay > dim ? dim : h.hDay;
  final g = HijriCalendar().hijriToGregorian(y, h.hMonth, day);
  return DateTime(g.year, g.month, g.day, base.hour, base.minute);
}

/// أقرب موعد ميلاديّ **بعد** [from] يوافق اليوم/الشهر الهجريّين لـ[base].
DateTime nextHijriAnniversary(DateTime base, DateTime from) {
  final hBase = HijriCalendar.fromDate(base);
  final hFrom = HijriCalendar.fromDate(from);
  for (var y = hFrom.hYear; y <= hFrom.hYear + 2; y++) {
    final dim = HijriCalendar().getDaysInMonth(y, hBase.hMonth);
    final day = hBase.hDay > dim ? dim : hBase.hDay;
    final g = HijriCalendar().hijriToGregorian(y, hBase.hMonth, day);
    final dt = DateTime(g.year, g.month, g.day, base.hour, base.minute);
    if (dt.isAfter(from)) return dt;
  }
  // احتياط نظريّ (لا يُفترض بلوغه): أبعد سنة محسوبة بعد [from].
  return hijriAnniversaryAt(base, (hFrom.hYear - hBase.hYear) + 3);
}
