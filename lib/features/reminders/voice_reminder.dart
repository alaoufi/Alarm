import 'package:flutter/material.dart';

import '../../services/system_dictation.dart';
import 'standalone_reminder_dialog.dart';

/// نتيجة تحليل عبارة التذكير: الوقت المستنتج + نصّ المهمّة.
class ParsedReminder {
  final DateTime time;
  final String title;
  const ParsedReminder(this.time, this.title);
}

String _normalizeDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final ai = ar.indexOf(ch);
    final fi = fa.indexOf(ch);
    if (ai >= 0) {
      b.write(ai);
    } else if (fi >= 0) {
      b.write(fi);
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

/// محلّل عربيّ قاعديّ لعبارات التذكير الشائعة (يعمل دون إنترنت).
/// يدعم: «بعد N دقيقة/ساعة/يوم»، «دقيقتين/ساعتين/يومين»، «غدًا»، «الساعة N
/// صباحًا/مساءً»، وأوقات مسمّاة (الظهر/العصر/المغرب/العشاء/الفجر/الليلة/الصباح).
ParsedReminder parseArabicReminder(String input) {
  final now = DateTime.now();
  final text = _normalizeDigits(input);
  var title = ' $text ';
  DateTime? when;

  void strip(String? phrase) {
    if (phrase != null && phrase.isNotEmpty) {
      title = title.replaceAll(phrase, ' ');
    }
  }

  // كلمات الإطلاق.
  for (final w in const [
    'ذكّرني',
    'ذكرني',
    'ذكرنى',
    'نبّهني',
    'نبهني',
    'نبهنى',
    'تذكير',
    'عندي'
  ]) {
    strip(w);
  }

  // بعد N دقيقة / ساعة / يوم (مع المثنّى).
  final mMin = RegExp(r'بعد\s+(\d+)?\s*(دقائق|دقيقتين|دقيقة|دقيقه)').firstMatch(text);
  final mHr = RegExp(r'بعد\s+(\d+)?\s*(ساعات|ساعتين|ساعة|ساعه)').firstMatch(text);
  final mDay = RegExp(r'بعد\s+(\d+)?\s*(أيام|ايام|يومين|يوم)').firstMatch(text);

  int numOf(RegExpMatch m, String dual) {
    final g = m.group(1);
    if (g != null && g.isNotEmpty) return int.tryParse(g) ?? 1;
    return m.group(2) == dual ? 2 : 1;
  }

  if (mMin != null) {
    when = now.add(Duration(minutes: numOf(mMin, 'دقيقتين')));
    strip(mMin.group(0));
  } else if (mHr != null) {
    when = now.add(Duration(hours: numOf(mHr, 'ساعتين')));
    strip(mHr.group(0));
  } else if (mDay != null) {
    final n = numOf(mDay, 'يومين');
    when = DateTime(now.year, now.month, now.day + n, now.hour, now.minute);
    strip(mDay.group(0));
  }

  // أوقات مسمّاة / غدًا.
  final namedTimes = <String, int>{
    'الفجر': 5,
    'الصباح': 8,
    'الصبح': 8,
    'الظهر': 12,
    'العصر': 15,
    'المغرب': 18,
    'العشاء': 20,
    'الليلة': 21,
    'المساء': 19,
  };

  bool tomorrow = false;
  for (final w in const ['غدا', 'غدًا', 'بكرة', 'بكره', 'باكر']) {
    if (text.contains(w)) {
      tomorrow = true;
      strip(w);
      break;
    }
  }

  // الساعة N [: MM] [صباحًا/مساءً/...]
  final clock = RegExp(
          r'(?:الساعة|الساعه|على)?\s*(\d{1,2})(?::(\d{2}))?\s*(صباحا|صباحًا|مساء|مساءً|ظهرا|عصرا|ليلا)?')
      .firstMatch(text);

  if (when == null) {
    DateTime? namedDt;
    for (final entry in namedTimes.entries) {
      if (text.contains(entry.key)) {
        namedDt = DateTime(now.year, now.month, now.day, entry.value, 0);
        strip(entry.key);
        break;
      }
    }
    if (namedDt != null) {
      when = namedDt;
    } else if (clock != null && clock.group(1) != null) {
      var h = int.tryParse(clock.group(1)!) ?? 9;
      final min = int.tryParse(clock.group(2) ?? '0') ?? 0;
      final ap = clock.group(3) ?? '';
      final isPm = ap.startsWith('مساء') ||
          ap == 'ظهرا' ||
          ap == 'عصرا' ||
          ap == 'ليلا';
      if (isPm && h < 12) h += 12;
      if ((ap.startsWith('صباح')) && h == 12) h = 0;
      when = DateTime(now.year, now.month, now.day, h % 24, min);
      strip(clock.group(0));
    }
  }

  // طبّق «غدًا» أو انقل الوقت الماضي لليوم التالي.
  when ??= tomorrow
      ? DateTime(now.year, now.month, now.day + 1, 8, 0)
      : now.add(const Duration(hours: 1));
  if (tomorrow) {
    when = DateTime(now.year, now.month, now.day + 1, when.hour, when.minute);
  } else if (!when.isAfter(now)) {
    when = when.add(const Duration(days: 1));
  }

  // تنظيف العنوان.
  for (final c in const ['بعد', 'في', 'عند', 'الساعة', 'الساعه', 'ان', 'أن', 'ب']) {
    title = title.replaceAll(' $c ', ' ');
  }
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (title.isEmpty) title = 'تنبيه';
  return ParsedReminder(when, title);
}

/// يلتقط عبارة صوتيّة عربيّة، يحلّلها، ويفتح حوار تنبيه مُهيّأً للمراجعة.
Future<void> createReminderByVoice(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  bool available;
  try {
    available = await SystemDictation.isAvailable();
  } catch (_) {
    available = false;
  }
  if (!context.mounted) return;
  if (!available) {
    messenger.showSnackBar(
        const SnackBar(content: Text('خدمة الإملاء الصوتيّة غير متوفّرة')));
    return;
  }
  String? raw;
  try {
    raw = await SystemDictation.recognize('ar-SA');
  } catch (_) {
    raw = null;
  }
  if (!context.mounted) return;
  if (raw == null || raw.trim().isEmpty) {
    messenger
        .showSnackBar(const SnackBar(content: Text('لم يُلتقط كلام')));
    return;
  }
  final parsed = parseArabicReminder(raw);
  if (!context.mounted) return;
  await showStandaloneReminderDialog(context,
      initialTitle: parsed.title, initialTime: parsed.time);
}
