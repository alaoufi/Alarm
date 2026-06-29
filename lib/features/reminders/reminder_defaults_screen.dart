import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/notification_service.dart';
import '../settings/settings_provider.dart';
import '../sounds/sound_library_screen.dart';
import 'reminder_helpers.dart';
import 'reminders_provider.dart';

/// صفحة «إعدادات التنبيه الافتراضية»: تُضبط مرّة واحدة (النغمة، الغفوة، رفع الصوت،
/// تنبيه قبل الوقت) وتُستخدم كقيم أوّلية لكل تنبيه جديد — قابلة للتعديل عند الإنشاء.
class ReminderDefaultsScreen extends StatelessWidget {
  const ReminderDefaultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final st = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('reminder_defaults'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
            child: Text(
              'تُطبَّق هذه القيم تلقائيًّا على كل تنبيه جديد، ويمكنك تعديلها عند الإنشاء.',
              style: TextStyle(
                  fontSize: 12.5, color: scheme.onSurface.withOpacity(0.6)),
            ),
          ),

          // النغمة.
          Card(
            child: ListTile(
              leading: Icon(Icons.library_music_outlined, color: scheme.primary),
              title: Text(s.t('alarm_tone')),
              subtitle: Text(
                st.alarmTone == 'custom'
                    ? (st.customToneTitle ?? 'نغمة الجهاز')
                    : toneName(st.alarmTone),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SoundLibraryScreen())),
            ),
          ),

          // الغفوة.
          Card(
            child: ListTile(
              leading: Icon(Icons.snooze, color: scheme.primary),
              title: Text(s.t('snooze')),
              subtitle: Text(st.snoozeMinutes == 0
                  ? 'بلا غفوة'
                  : '${st.snoozeMinutes} دقيقة'),
              trailing: DropdownButton<int>(
                value: const [0, 5, 10, 15, 30].contains(st.snoozeMinutes)
                    ? st.snoozeMinutes
                    : 10,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('بلا غفوة')),
                  DropdownMenuItem(value: 5, child: Text('5 دقائق')),
                  DropdownMenuItem(value: 10, child: Text('10 دقائق')),
                  DropdownMenuItem(value: 15, child: Text('15 دقيقة')),
                  DropdownMenuItem(value: 30, child: Text('30 دقيقة')),
                ],
                onChanged: (v) {
                  if (v != null) st.setSnoozeMinutes(v);
                },
              ),
            ),
          ),

          // الصوت.
          Card(
            child: Column(children: [
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_outlined),
                title: Text(s.t('auto_raise_volume')),
                subtitle: Text(s.t('auto_raise_volume_desc'),
                    style: const TextStyle(fontSize: 11.5)),
                value: st.autoRaiseVolume,
                onChanged: (v) => st.setAutoRaiseVolume(v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.trending_up),
                title: Text(s.t('gradual_volume')),
                subtitle: Text(s.t('gradual_volume_desc'),
                    style: const TextStyle(fontSize: 11.5)),
                value: st.gradualVolume,
                onChanged:
                    st.autoRaiseVolume ? (v) => st.setGradualVolume(v) : null,
              ),
            ]),
          ),

          // وضع «لا يمكن تفويته»: نوع التحدّي قبل إيقاف المنبّه.
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.gpp_maybe_outlined,
                        color: scheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('لا يمكن تفويته',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14.5)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('تحدٍّ قبل إيقاف المنبّه يمنع الإغلاق بالخطأ.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurface.withOpacity(0.6))),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(
                          value: 0,
                          label: Text('معطّل'),
                          icon: Icon(Icons.block, size: 16)),
                      ButtonSegment(
                          value: 1,
                          label: Text('أرقام'),
                          icon: Icon(Icons.calculate_outlined, size: 16)),
                      ButtonSegment(
                          value: 2,
                          label: Text('كلمة'),
                          icon: Icon(Icons.keyboard_outlined, size: 16)),
                    ],
                    selected: {st.dismissChallenge},
                    onSelectionChanged: (v) =>
                        st.setDismissChallenge(v.first),
                  ),
                ],
              ),
            ),
          ),

          // موجز الصباح: إشعار يوميّ بعدد التذكيرات النشطة.
          Card(
            child: Column(children: [
              SwitchListTile(
                secondary: const Icon(Icons.wb_sunny_outlined),
                title: const Text('موجز الصباح'),
                subtitle: const Text('إشعار يوميّ بعدد تذكيراتك النشطة',
                    style: TextStyle(fontSize: 11.5)),
                value: st.morningBriefing,
                onChanged: (v) async {
                  await st.setMorningBriefing(v);
                  await _applyBriefing(context);
                },
              ),
              if (st.morningBriefing)
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('وقت الموجز'),
                  trailing: Text(
                      '${st.briefingHour.toString().padLeft(2, '0')}:'
                      '${st.briefingMinute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                          hour: st.briefingHour, minute: st.briefingMinute),
                    );
                    if (picked != null) {
                      await st.setBriefingTime(picked.hour, picked.minute);
                      await _applyBriefing(context);
                    }
                  },
                ),
            ]),
          ),

          // تنبيه قبل الوقت الافتراضي.
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.timer_outlined, color: scheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(s.t('pre_alerts'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14.5)),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final (mins, lbl) in const [
                        (0, 'بلا'),
                        (5, '5د'),
                        (15, '15د'),
                        (60, 'ساعة'),
                        (1440, 'يوم'),
                      ])
                        ChoiceChip(
                          label: Text(lbl),
                          selected: st.defaultPreAlert == mins,
                          onSelected: (_) => st.setDefaultPreAlert(mins),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// يطبّق جدولة موجز الصباح فورًا بعد تغيير الإعداد (تفعيل/وقت).
  Future<void> _applyBriefing(BuildContext context) async {
    final st = context.read<SettingsProvider>();
    final count = context
        .read<RemindersProvider>()
        .items
        .where((v) => v.reminder.isActive)
        .length;
    await NotificationService.instance.updateMorningBriefing(
      enabled: st.morningBriefing,
      hour: st.briefingHour,
      minute: st.briefingMinute,
      reminderCount: count,
    );
  }
}
