import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../data/models/enums.dart';
import '../../data/models/note.dart';
import '../../services/ringtone_picker.dart';
import '../../services/tone_preview.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/time_wheel.dart';
import '../sounds/sound_catalog.dart';
import 'alarm_permissions.dart';
import 'reminder_helpers.dart';
import '../settings/settings_provider.dart';
import 'reminders_provider.dart';

/// أيام الأسبوع (تبدأ بالسبت) — القيمة بمعيار DateTime.weekday (الإثنين=1..الأحد=7).
const List<(int, String)> _weekdayDefs = [
  (6, 'السبت'),
  (7, 'الأحد'),
  (1, 'الإثنين'),
  (2, 'الثلاثاء'),
  (3, 'الأربعاء'),
  (4, 'الخميس'),
  (5, 'الجمعة'),
];

/// حوار إضافة/تعديل تذكير **لملاحظة** — بنفس شكل «التنبيه العام» (المستقلّ):
/// رأس بارز، بطاقات منتقي، أقسام معنونة، النغمة + خيارات الصوت + الغفوة، وشريط
/// حفظ ثابت. الموضوع هو الملاحظة نفسها (لا حقل عنوان منفصل).
Future<void> showReminderDialog(BuildContext context, Note note) async {
  final s = S.of(context);
  final provider = context.read<RemindersProvider>();
  final settings = context.read<SettingsProvider>();

  DateTime date = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay time = TimeOfDay.fromDateTime(date);
  ReminderRepeat repeat = ReminderRepeat.once;
  ReminderImportance importance = ReminderImportance.critical;
  final Set<int> preAlerts = {
    if (settings.defaultPreAlert > 0) settings.defaultPreAlert,
  };

  // حمّل التذكير الحالي إن وُجد.
  final all = await provider.getAllForNote(note.id!);
  final existing = all.isEmpty ? null : all.first;
  final Set<int> weekdays = {date.weekday};
  if (existing != null) {
    date = existing.time;
    time = TimeOfDay.fromDateTime(existing.time);
    repeat = existing.repeat;
    importance = existing.importance;
    preAlerts
      ..clear()
      ..addAll(existing.preAlerts);
    if (all.length > 1 || existing.repeat == ReminderRepeat.weekly) {
      weekdays
        ..clear()
        ..addAll(all
            .where((r) => r.repeat == ReminderRepeat.weekly)
            .map((r) => r.time.weekday));
      if (weekdays.isEmpty) weekdays.add(date.weekday);
    }
  }

  if (!context.mounted) return;

  // عند **أول** إنشاء تذكير جديد: اطلب فكّ القيود لضمان عمل المنبّه.
  if (existing == null) {
    await ensureAlarmReliabilityOnce(context);
    if (!context.mounted) return;
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final scheme = Theme.of(context).colorScheme;
          String two(int n) => n.toString().padLeft(2, '0');
          DateTime combined() => DateTime(
              date.year, date.month, date.day, time.hour, time.minute);
          String repeatLabel(ReminderRepeat r) => switch (r) {
                ReminderRepeat.once => s.t('repeat_once'),
                ReminderRepeat.daily => s.t('repeat_daily'),
                ReminderRepeat.weekly => s.t('repeat_weekly'),
                ReminderRepeat.monthly => s.t('repeat_monthly'),
                ReminderRepeat.yearly => s.t('repeat_yearly'),
                ReminderRepeat.hijriYearly => s.t('repeat_hijri_yearly'),
              };

          Widget label(String t) => Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(t,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.bold)),
              );

          Widget pickerCard(
                  IconData icon, String lbl, String value, VoidCallback onTap) =>
              Expanded(
                child: Material(
                  color: Theme.of(context).inputDecorationTheme.fillColor,
                  elevation: 1,
                  shadowColor: scheme.shadow.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      child: Row(children: [
                        Icon(icon, size: 20, color: scheme.primary),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(lbl,
                                style: Theme.of(context).textTheme.bodySmall),
                            Text(value,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ),
              );

          Future<void> pickDate() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => date = picked);
          }

          Future<void> pickTime() async {
            final picked = await pickTimeWheel(context, time);
            if (picked != null) setState(() => time = picked);
          }

          final showDate = repeat != ReminderRepeat.weekly &&
              repeat != ReminderRepeat.daily;

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // الرأس — يعرض عنوان الملاحظة كموضوع للتذكير.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                    child: Row(children: [
                      Icon(Icons.add_alarm, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                existing == null
                                    ? 'تذكير الملاحظة'
                                    : 'تعديل التذكير',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            if (note.title.trim().isNotEmpty)
                              Text(note.title.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: scheme.primary)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Row(children: [
                            if (showDate) ...[
                              pickerCard(
                                  Icons.calendar_today,
                                  'التاريخ',
                                  '${date.year}/${two(date.month)}/${two(date.day)}',
                                  pickDate),
                              const SizedBox(width: 10),
                            ],
                            pickerCard(Icons.access_time, 'الوقت',
                                time.format(context), pickTime),
                          ]),
                          const SizedBox(height: 14),
                          label(s.t('repeat')),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: ReminderRepeat.values.map((r) {
                              return ChoiceChip(
                                label: Text(repeatLabel(r)),
                                selected: repeat == r,
                                onSelected: (_) => setState(() => repeat = r),
                              );
                            }).toList(),
                          ),
                          if (repeat == ReminderRepeat.weekly) ...[
                            const SizedBox(height: 14),
                            label('أيام الأسبوع'),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final d in _weekdayDefs)
                                  FilterChip(
                                    label: Text(d.$2),
                                    selected: weekdays.contains(d.$1),
                                    onSelected: (sel) => setState(() {
                                      if (sel) {
                                        weekdays.add(d.$1);
                                      } else {
                                        weekdays.remove(d.$1);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          label(s.t('importance')),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: ReminderImportance.values.map((imp) {
                              return ChoiceChip(
                                avatar: Icon(impIcon(imp),
                                    size: 18, color: impColor(imp)),
                                label: Text(impLabel(s, imp)),
                                selected: importance == imp,
                                onSelected: (_) =>
                                    setState(() => importance = imp),
                              );
                            }).toList(),
                          ),
                          if (repeat == ReminderRepeat.once) ...[
                            const SizedBox(height: 14),
                            label(s.t('pre_alerts')),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final (mins, lbl) in const [
                                  (5, '5د'),
                                  (15, '15د'),
                                  (60, 'ساعة'),
                                  (1440, 'يوم'),
                                ])
                                  FilterChip(
                                    label: Text(lbl),
                                    selected: preAlerts.contains(mins),
                                    onSelected: (sel) => setState(() {
                                      if (sel) {
                                        preAlerts.add(mins);
                                      } else {
                                        preAlerts.remove(mins);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          label('النغمة'),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: IconButton(
                              tooltip: 'سماع',
                              icon: const Icon(Icons.play_circle_outline),
                              onPressed: () {
                                if (settings.alarmTone != 'custom') {
                                  TonePreview.play(settings.alarmTone);
                                }
                              },
                            ),
                            title: Text(settings.alarmTone == 'custom'
                                ? (settings.customToneTitle ?? 'نغمة مخصّصة')
                                : toneName(settings.alarmTone)),
                            trailing: DropdownButton<String>(
                              value: soundCatalog
                                      .any((t) => t.id == settings.alarmTone)
                                  ? settings.alarmTone
                                  : 'custom',
                              isDense: true,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final t in soundCatalog)
                                  DropdownMenuItem(
                                      value: t.id, child: Text(t.name)),
                                if (settings.alarmTone == 'custom')
                                  DropdownMenuItem(
                                      value: 'custom',
                                      child: Text(
                                          settings.customToneTitle ?? 'مخصّصة 🎵',
                                          overflow: TextOverflow.ellipsis)),
                                const DropdownMenuItem(
                                    value: 'pick', child: Text('من الجهاز… 📱')),
                              ],
                              onChanged: (v) async {
                                if (v == null) return;
                                if (v == 'pick') {
                                  final uri = await RingtonePicker.pick(
                                      current: settings.customToneUri);
                                  if (uri != null) {
                                    final t = await RingtonePicker.title(uri);
                                    await settings.setCustomTone(uri, t);
                                  }
                                } else {
                                  await settings.setAlarmTone(v);
                                }
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          label(s.t('sound_options')),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.volume_up_outlined),
                            title: Text(s.t('auto_raise_volume')),
                            subtitle: Text(s.t('auto_raise_volume_desc'),
                                style: const TextStyle(fontSize: 11.5)),
                            value: settings.autoRaiseVolume,
                            onChanged: (v) async {
                              await settings.setAutoRaiseVolume(v);
                              setState(() {});
                            },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.trending_up),
                            title: Text(s.t('gradual_volume')),
                            subtitle: Text(s.t('gradual_volume_desc'),
                                style: const TextStyle(fontSize: 11.5)),
                            value: settings.gradualVolume,
                            onChanged: settings.autoRaiseVolume
                                ? (v) async {
                                    await settings.setGradualVolume(v);
                                    setState(() {});
                                  }
                                : null,
                          ),
                          const SizedBox(height: 10),
                          label('الغفوة'),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.snooze),
                            title: const Text('مدّة الغفوة'),
                            subtitle: Text(settings.snoozeMinutes == 0
                                ? 'بلا غفوة'
                                : '${settings.snoozeMinutes} دقيقة'),
                            trailing: DropdownButton<int>(
                              value: const [0, 5, 10, 15, 30]
                                      .contains(settings.snoozeMinutes)
                                  ? settings.snoozeMinutes
                                  : 10,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(
                                    value: 0, child: Text('بلا غفوة')),
                                DropdownMenuItem(
                                    value: 5, child: Text('5 دقائق')),
                                DropdownMenuItem(
                                    value: 10, child: Text('10 دقائق')),
                                DropdownMenuItem(
                                    value: 15, child: Text('15 دقيقة')),
                                DropdownMenuItem(
                                    value: 30, child: Text('30 دقيقة')),
                              ],
                              onChanged: (v) async {
                                if (v == null) return;
                                await settings.setSnoozeMinutes(v);
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // شريط الحفظ الثابت.
                  Material(
                    elevation: 10,
                    color: scheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Row(
                        children: [
                          if (existing != null)
                            TextButton.icon(
                              onPressed: () async {
                                if (!await confirmDelete(context,
                                    title: 'حذف التذكير؟',
                                    message:
                                        'سيُحذف تذكير هذه الملاحظة ولن يُذكّرك بعد الآن.')) {
                                  return;
                                }
                                await provider.removeForNote(note.id!);
                                if (context.mounted) Navigator.pop(context);
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: Text(s.t('delete')),
                            ),
                          const Spacer(),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(130, 48)),
                            onPressed: () async {
                              if (repeat == ReminderRepeat.weekly &&
                                  weekdays.isNotEmpty) {
                                await provider.setNoteWeekly(
                                    note, time, weekdays,
                                    importance: importance);
                              } else {
                                await provider.setReminder(
                                    note, combined(), repeat,
                                    importance: importance,
                                    preAlerts: preAlerts.toList()..sort());
                              }
                              if (context.mounted) Navigator.pop(context);
                            },
                            icon: const Icon(Icons.check),
                            label: Text(s.t('save')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
