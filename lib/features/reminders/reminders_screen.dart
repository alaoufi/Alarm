import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/time/hijri_recurrence.dart';
import '../../data/models/enums.dart';
import '../../data/models/reminder.dart';
import '../../services/med_occurrences.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/ui_kit.dart';
import '../editor/editor_attachments.dart';
import '../editor/note_editor_screen.dart';
import '../meds/medication_screen.dart';
import '../sounds/sound_library_screen.dart';
import 'notification_center_screen.dart';
import 'reliability_test_screen.dart';
import 'reminder_defaults_screen.dart';
import 'reminders_provider.dart';
import 'standalone_reminder_dialog.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  static const _weekdayAr = {
    1: 'الإثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
    6: 'السبت',
    7: 'الأحد',
  };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final provider = context.watch<RemindersProvider>();
    final standalone =
        provider.items.where((v) => v.reminder.isStandalone).toList();
    final noteLinked =
        provider.items.where((v) => !v.reminder.isStandalone).toList();

    return Scaffold(
      appBar: gradientAppBar(context, s.t('reminders'), actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.settings),
          tooltip: s.t('reminder_tools'),
          onSelected: (v) {
            switch (v) {
              case 'med_mode':
                _open(context, const MedicationScreen());
                break;
              case 'reminder_defaults':
                _open(context, const ReminderDefaultsScreen());
                break;
              case 'notif_center':
                _open(context, const NotificationCenterScreen());
                break;
              case 'sound_library':
                _open(context, const SoundLibraryScreen());
                break;
              case 'reliability_test':
                _open(context, const ReliabilityTestScreen());
                break;
            }
          },
          itemBuilder: (context) => [
            _menuItem('med_mode', Icons.medication_outlined, s.t('med_mode')),
            _menuItem('reminder_defaults', Icons.tune,
                s.t('reminder_defaults')),
            _menuItem('notif_center', Icons.notifications_active_outlined,
                s.t('notif_center')),
            _menuItem('sound_library', Icons.library_music_outlined,
                s.t('sound_library')),
            _menuItem('reliability_test', Icons.health_and_safety_outlined,
                s.t('reliability_test')),
          ],
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showStandaloneReminderDialog(context),
        icon: const Icon(Icons.add_alarm),
        label: const Text('تنبيه جديد'),
      ),
      body: provider.items.isEmpty
          ? _empty(context, s)
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 90),
              children: [
                _nextBanner(context, provider.items),
                if (standalone.isNotEmpty) ...[
                  _header(context, '⏰ تنبيهات مستقلّة'),
                  for (final v in standalone) _tile(context, s, provider, v),
                ],
                if (noteLinked.isNotEmpty) ...[
                  _header(context, '📝 تنبيهات الملاحظات'),
                  for (final v in noteLinked) _tile(context, s, provider, v),
                ],
              ],
            ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ]),
      );

  /// لافتة «المنبّه التالي بعد…» لأقرب منبّه مُفعَّل.
  Widget _nextBanner(BuildContext context, List<ReminderView> items) {
    final active = items.where((v) => v.reminder.isActive);
    if (active.isEmpty) return const SizedBox.shrink();
    DateTime? soonest;
    for (final v in active) {
      final n = _nextFire(v.reminder);
      if (soonest == null || n.isBefore(soonest)) soonest = n;
    }
    if (soonest == null) return const SizedBox.shrink();
    final diff = soonest.difference(DateTime.now());
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          scheme.primaryContainer,
          scheme.primaryContainer.withOpacity(0.6),
        ]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.alarm_on, color: scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text('المنبّه التالي ${_countdown(diff)}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimaryContainer)),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      );

  Widget _tile(BuildContext context, S s, RemindersProvider provider,
      ReminderView v) {
    final r = v.reminder;
    final note = v.note;
    final on = r.isActive;
    // تنبيه «مرّة واحدة» فات وقته ⇒ منتهٍ: نعرضه باهتًا (كأنه غير نشِط).
    final expired =
        r.repeat == ReminderRepeat.once && r.time.isBefore(DateTime.now());
    final dim = !on || expired;
    final scheme = Theme.of(context).colorScheme;
    final timeStr = DateFormat('h:mm a', 'ar').format(r.time);
    final label = r.isStandalone
        ? (r.title?.isNotEmpty == true ? r.title! : 'تنبيه')
        : (note?.title.isNotEmpty == true
            ? note!.title
            : (note?.content ?? 'ملاحظة'));
    // وصف التكرار (مع اليوم عند الأسبوعي، وفاصل/مدّة الدواء إن وُجدت).
    String repeatInfo;
    if (r.intervalDays >= 2) {
      repeatInfo = 'كل ${r.intervalDays} يوم';
    } else if (r.repeat == ReminderRepeat.weekly) {
      repeatInfo = '${_repeatLabel(s, r.repeat)} • ${_weekdayAr[r.time.weekday]}';
    } else {
      repeatInfo = _repeatLabel(s, r.repeat);
    }
    if (r.doseCount > 0) repeatInfo += ' • ${r.doseCount} جرعة';

    return AppCard(
      onTap: r.isStandalone
          ? () => showStandaloneReminderDialog(context, existing: r)
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NoteEditorScreen(noteId: note!.id),
                ),
              ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeStr,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: dim ? scheme.outline : null,
                          decoration:
                              expired ? TextDecoration.lineThrough : null,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    expired
                        ? '$label  •  $repeatInfo  •  ${s.t('nc_expired')}'
                        : '$label  •  $repeatInfo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: dim
                            ? scheme.outline
                            : Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            // فتح موقع الموعد على الخرائط (إن وُجد رابط).
            if (r.location.trim().isNotEmpty)
              IconButton(
                tooltip: 'فتح الموقع',
                icon: Icon(Icons.place_outlined, color: scheme.primary),
                onPressed: () async {
                  final u = Uri.tryParse(r.location.trim());
                  if (u == null) return;
                  try {
                    await launchUrl(u, mode: LaunchMode.externalApplication);
                  } catch (_) {/* لا يوجد تطبيق يفتح الرابط */}
                },
              ),
            // فتح مرفق الدعوة (صورة/PDF) إن وُجد.
            if (r.attachmentPath.trim().isNotEmpty)
              IconButton(
                tooltip: 'الدعوة',
                icon: Icon(
                    r.attachmentPath.toLowerCase().endsWith('.pdf')
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                    color: scheme.primary),
                onPressed: () => EditorAttachments.openFile(r.attachmentPath),
              ),
            IconButton(
              tooltip: 'حذف',
              icon: Icon(Icons.delete_outline, color: scheme.outline),
              onPressed: () async {
                if (await confirmDelete(context,
                    title: 'حذف التنبيه؟',
                    message: 'سيُحذف هذا التنبيه ولن يُذكّرك بعد الآن.')) {
                  await provider.removeReminder(r);
                }
              },
            ),
            Switch(
              value: on,
              onChanged: (val) => provider.setActive(v, val),
            ),
          ],
        ),
      ),
    );
  }

  // ===== مساعدات =====

  DateTime _nextFire(Reminder r) {
    final now = DateTime.now();
    final t = r.time;
    // كورس دواء (فاصل أيام/عدد جرعات): أوّل موعد قادم، أو لا شيء إن انتهى.
    if (r.intervalDays >= 2 || r.doseCount > 0) {
      final next =
          medOccurrencesBetween(r, now, now.add(const Duration(days: 3650)));
      return next.isEmpty ? DateTime(9999) : next.first;
    }
    switch (r.repeat) {
      case ReminderRepeat.once:
        return t;
      case ReminderRepeat.daily:
        var d = DateTime(now.year, now.month, now.day, t.hour, t.minute);
        if (!d.isAfter(now)) d = d.add(const Duration(days: 1));
        return d;
      case ReminderRepeat.weekly:
        var d = DateTime(now.year, now.month, now.day, t.hour, t.minute);
        while (d.weekday != t.weekday || !d.isAfter(now)) {
          d = DateTime(d.year, d.month, d.day + 1, t.hour, t.minute);
        }
        return d;
      case ReminderRepeat.monthly:
      case ReminderRepeat.yearly:
        return t.isAfter(now) ? t : t;
      case ReminderRepeat.hijriYearly:
        return nextHijriAnniversary(t, now);
    }
  }

  String _countdown(Duration d) {
    if (d.isNegative) return 'الآن';
    final days = d.inDays;
    final hours = d.inHours % 24;
    final mins = d.inMinutes % 60;
    if (days > 0) return 'بعد $days يوم و$hours ساعة';
    if (hours > 0) return 'بعد $hours ساعة و$mins دقيقة';
    if (mins > 0) return 'بعد $mins دقيقة';
    return 'خلال ثوانٍ';
  }

  String _repeatLabel(S s, ReminderRepeat r) => switch (r) {
        ReminderRepeat.once => s.t('repeat_once'),
        ReminderRepeat.daily => s.t('repeat_daily'),
        ReminderRepeat.weekly => s.t('repeat_weekly'),
        ReminderRepeat.monthly => s.t('repeat_monthly'),
        ReminderRepeat.yearly => s.t('repeat_yearly'),
        ReminderRepeat.hijriYearly => s.t('repeat_hijri_yearly'),
      };

  Widget _empty(BuildContext context, S s) => EmptyState(
        icon: Icons.notifications_off_outlined,
        title: s.t('no_reminders'),
        subtitle: 'أنشئ تنبيهًا مستقلًّا بزرّ «تنبيه جديد»',
      );
}
