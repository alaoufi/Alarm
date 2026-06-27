import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import '../data/models/med_dose.dart';
import '../data/models/reminder_log_entry.dart';
import '../data/repositories/med_repository.dart';
import '../data/repositories/note_repository.dart';
import '../data/repositories/reminder_log_repository.dart';
import '../data/repositories/reminder_repository.dart';
import 'med_occurrences.dart';

/// يُسجّل تلقائيًّا كل **موعد** تنبيهٍ فات منذ آخر فحص في «سجلّ التنبيهات
/// المنفّذة» (لكل الأنواع) — ويُسجّل أيضًا جرعةً في «وضع الدواء» إن كان منبّه
/// دواء (عنوانه يحمل 💊).
///
/// لماذا «عند الفتح» لا لحظة الرنين؟ لأن أندرويد لا يتيح لـFlutter تشغيل كود
/// موثوق عند **ظهور** الإشعار والتطبيق مغلق. لذا نعوّض بحساب كل المواعيد الفائتة
/// منذ آخر مرّة وتسجيلها دفعةً عند فتح التطبيق/شاشة الأدوية — فلا تضيع أي جرعة.
class MedDoseLogger {
  MedDoseLogger._();
  static final instance = MedDoseLogger._();

  static const _prefix = 'med_logged_until_';

  Future<void> run() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reminders =
          await ReminderRepository(AppDatabase.instance).getAll();
      final medRepo = MedRepository(AppDatabase.instance);
      final logRepo = ReminderLogRepository(AppDatabase.instance);
      final notes = NoteRepository(AppDatabase.instance);
      final now = DateTime.now();

      for (final r in reminders) {
        if (!r.isActive || r.id == null) continue;

        final key = '$_prefix${r.id}';
        final lastMs = prefs.getInt(key);
        if (lastMs == null) {
          // أوّل مرّة نرى هذا المنبّه: نبدأ العدّ من الآن (لا نُسجّل الماضي).
          await prefs.setInt(key, now.millisecondsSinceEpoch);
          continue;
        }

        // عنوان السجلّ: عنوان التنبيه المستقلّ، أو عنوان الملاحظة المرتبطة.
        var logTitle = (r.title ?? '').trim();
        if (r.noteId != null) {
          final n = await notes.getNote(r.noteId!);
          if (n == null || n.isDeleted) {
            // ملاحظة محذوفة ⇒ لا نُسجّل، ونُقدّم المؤشّر لتفادي تسجيل لاحق.
            await prefs.setInt(key, now.millisecondsSinceEpoch);
            continue;
          }
          if (logTitle.isEmpty) logTitle = n.title.trim();
        }
        if (logTitle.isEmpty) logTitle = 'تنبيه';

        final after = DateTime.fromMillisecondsSinceEpoch(lastMs);
        final occ = medOccurrencesBetween(r, after, now);
        if (occ.isNotEmpty) {
          final isMed = (r.title ?? '').contains('💊');
          final parsed = isMed ? parseMedTitle(r.title!) : null;
          for (final o in occ) {
            // السجلّ العامّ: كل تنبيه مُنفَّذ (لكل الأنواع).
            await logRepo
                .insert(ReminderLogEntry(reminderId: r.id, title: logTitle, at: o));
            // الدواء: نُسجّل أيضًا جرعةً في «وضع الدواء».
            if (isMed) {
              await medRepo.insert(MedDose(
                  name: parsed!.$1, dose: parsed.$2, taken: true, at: o));
            }
          }
        }
        await prefs.setInt(key, now.millisecondsSinceEpoch);
      }
    } catch (_) {
      // لا يجب أن تُعطّل بدء التطبيق.
    }
  }

  /// اسم الدواء وجرعته من عنوان المنبّه «💊 الاسم — الجرعة».
  static (String, String?) parseMedTitle(String title) {
    var t = title.replaceAll('💊', '').trim();
    String? dose;
    final idx = t.indexOf(' — ');
    if (idx >= 0) {
      final d = t.substring(idx + 3).trim();
      if (d.isNotEmpty) dose = d;
      t = t.substring(0, idx).trim();
    }
    return (t.isEmpty ? 'دواء' : t, dose);
  }
}
