import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../data/models/quiet_window.dart';
import '../reminders/reminders_provider.dart';
import 'settings_provider.dart';

/// شاشة «أوقات الإسكات»: يضيف المستخدم فترات يوميّة (من/إلى) لا يصدر فيها صوت
/// المنبّه — يبقى الإشعار ظاهرًا وواضحًا لكن دون صوت أو اهتزاز.
class QuietHoursScreen extends StatelessWidget {
  const QuietHoursScreen({super.key});

  String _fmt(BuildContext context, int minutes) {
    final t = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    // نظام ١٢ ساعة دائمًا (ص/م) حتى لو كان الجهاز على ٢٤ ساعة.
    return MaterialLocalizations.of(context)
        .formatTimeOfDay(t, alwaysUse24HourFormat: false);
  }

  /// منتقي وقت بنظام ١٢ ساعة (ص/م ظاهرة، الساعات ١–١٢، الدقائق ٠٠–٥٩) يفتح في
  /// وضع الكتابة كي يكتب المستخدم الرقم مباشرةً ضمن المدى المتاح. نُجبر تنسيق
  /// ١٢ ساعة عبر MediaQuery حتى لو كان الجهاز على نظام ٢٤ ساعة (فتختفي ص/م).
  Future<TimeOfDay?> _pickTime(
      BuildContext context, TimeOfDay initial, String help) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      helpText: help,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
  }

  Future<void> _addWindow(BuildContext context, SettingsProvider st) async {
    final start = await _pickTime(context,
        const TimeOfDay(hour: 2, minute: 0), S.of(context).t('quiet_from'));
    if (start == null || !context.mounted) return;
    final end = await _pickTime(context,
        const TimeOfDay(hour: 7, minute: 0), S.of(context).t('quiet_to'));
    if (end == null) return;
    final w = QuietWindow(
        start.hour * 60 + start.minute, end.hour * 60 + end.minute);
    await st.addQuietWindow(w);
    if (context.mounted) {
      // إعادة جدولة التنبيهات كي تُطبَّق فترة الإسكات الجديدة على المجدول مسبقًا.
      await context.read<RemindersProvider>().ensureScheduled();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final st = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final windows = st.quietWindows;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('quiet_hours'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addWindow(context, st),
        icon: const Icon(Icons.add),
        label: Text(s.t('quiet_hours_add')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
        children: [
          // بطاقة تعريفيّة.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withOpacity(0.14),
                  scheme.primary.withOpacity(0.04),
                ],
              ),
              border: Border.all(color: scheme.primary.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.nightlight_round, color: scheme.primary, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    s.t('quiet_hours_desc'),
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: scheme.onSurface.withOpacity(0.85)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (windows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Column(
                children: [
                  Icon(Icons.notifications_off_outlined,
                      size: 54, color: scheme.outline),
                  const SizedBox(height: 14),
                  Text(
                    s.t('quiet_hours_empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13.5,
                        height: 1.6,
                        color: scheme.onSurface.withOpacity(0.6)),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < windows.length; i++)
              _windowCard(context, s, st, windows[i], i, scheme),

          if (windows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 15, color: scheme.onSurface.withOpacity(0.5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.t('quiet_hours_note'),
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: scheme.onSurface.withOpacity(0.5)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _windowCard(BuildContext context, S s, SettingsProvider st,
      QuietWindow w, int index, ColorScheme scheme) {
    final overnight = w.startMinutes > w.endMinutes;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primary.withOpacity(0.14),
              child: Icon(Icons.bedtime_outlined, color: scheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${s.t('quiet_from')} ',
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withOpacity(0.6))),
                      Text(_fmt(context, w.startMinutes),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text('  ${s.t('quiet_to')} ',
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withOpacity(0.6))),
                      Text(_fmt(context, w.endMinutes),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                    ],
                  ),
                  if (overnight)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('🌙 ${s.t('quiet_overnight')}',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.primary.withOpacity(0.9))),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: s.t('quiet_delete'),
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: () async {
                await st.removeQuietWindow(index);
                if (context.mounted) {
                  await context.read<RemindersProvider>().ensureScheduled();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
