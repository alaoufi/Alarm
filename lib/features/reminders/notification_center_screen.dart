import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../data/database/app_database.dart';
import '../../data/models/enums.dart';
import '../../data/models/reminder_log_entry.dart';
import '../../data/repositories/reminder_log_repository.dart';
import '../../services/med_dose_logger.dart';
import '../../widgets/confirm_dialog.dart';
import 'reminders_provider.dart';

/// مركز التنبيهات: يعرض التذكيرات مجمّعة (اليوم/القادمة/المتأخرة) مع بحث.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  String _q = '';
  bool _showLog = false; // false = القادمة، true = السجل

  final _logRepo = ReminderLogRepository(AppDatabase.instance);
  List<ReminderLogEntry>? _log;
  bool _logLoading = false;

  /// يُحدِّث السجلّ: يُسجّل أوّلًا أي تنبيهات فاتت منذ آخر فتح، ثم يقرأ السجلّ.
  Future<void> _loadLog() async {
    setState(() => _logLoading = true);
    await MedDoseLogger.instance.run();
    final list = await _logRepo.getAll();
    if (!mounted) return;
    setState(() {
      _log = list;
      _logLoading = false;
    });
  }

  Future<void> _deleteLogEntry(ReminderLogEntry e) async {
    if (e.id == null) return;
    await _logRepo.delete(e.id!);
    if (!mounted) return;
    setState(() => _log = _log?.where((x) => x.id != e.id).toList());
  }

  Future<void> _clearLog() async {
    final s = S.of(context);
    if (!await confirmDelete(context,
        title: s.t('nc_log_clear_q'), message: s.t('nc_log_clear_msg'))) {
      return;
    }
    await _logRepo.deleteAll();
    if (!mounted) return;
    setState(() => _log = const []);
  }

  String _titleOf(ReminderView v) {
    final t = v.note?.title.trim();
    if (t != null && t.isNotEmpty) return t;
    final st = v.reminder.title?.trim();
    return (st != null && st.isNotEmpty) ? st : 'تذكير';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final provider = context.watch<RemindersProvider>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final items = provider.items
        .where((v) =>
            _q.isEmpty || _titleOf(v).toLowerCase().contains(_q.toLowerCase()))
        .toList();

    final overdue = <ReminderView>[];
    final todayL = <ReminderView>[];
    final upcoming = <ReminderView>[];
    for (final v in items) {
      final r = v.reminder;
      if (r.repeat != ReminderRepeat.once) {
        upcoming.add(v); // المتكرّرة تُعتبر قادمة
      } else if (r.time.isBefore(now)) {
        if (r.isActive) overdue.add(v);
      } else if (r.time.isBefore(tomorrow)) {
        todayL.add(v);
      } else {
        upcoming.add(v);
      }
    }
    int byTime(ReminderView a, ReminderView b) =>
        a.reminder.time.compareTo(b.reminder.time);
    overdue.sort(byTime);
    todayL.sort(byTime);
    upcoming.sort(byTime);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('notif_center'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: false,
                    label: Text(s.t('nc_tab_upcoming')),
                    icon: const Icon(Icons.upcoming)),
                ButtonSegment(
                    value: true,
                    label: Text(s.t('nc_tab_log')),
                    icon: const Icon(Icons.history)),
              ],
              selected: {_showLog},
              onSelectionChanged: (sel) => setState(() {
                _showLog = sel.first;
                if (_showLog && _log == null) _loadLog();
              }),
            ),
          ),
          if (!_showLog)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: s.t('search'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          Expanded(
            child: _showLog
                ? _logView(s)
                : (overdue.isEmpty && todayL.isEmpty && upcoming.isEmpty)
                    ? Center(child: Text(s.t('no_reminders')))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        children: [
                          _statsCard(context, s, items.length, todayL.length,
                              upcoming.length, overdue.length),
                          _section(s.t('nc_overdue'), Icons.error_outline,
                              Colors.red, overdue),
                          _section(s.t('nc_today'), Icons.today, Colors.blue,
                              todayL),
                          _section(s.t('nc_upcoming'), Icons.upcoming,
                              Colors.teal, upcoming),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  /// تبويب «السجل»: كل تنبيه فات وقته (لكل الأنواع)، مجمّعًا بالأيام، مع حذف.
  Widget _logView(S s) {
    if (_logLoading && _log == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final log = _log ?? const <ReminderLogEntry>[];
    if (log.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(s.t('nc_log_empty'), textAlign: TextAlign.center),
        ),
      );
    }
    String two(int n) => n.toString().padLeft(2, '0');
    String dayKey(DateTime d) => '${d.year}/${two(d.month)}/${two(d.day)}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text('${log.length} ${s.t('nc_log_unit')}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearLog,
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                label: Text(s.t('nc_log_clear')),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: log.length,
            itemBuilder: (context, i) {
              final e = log[i];
              final showHeader =
                  i == 0 || dayKey(log[i - 1].at) != dayKey(e.at);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showHeader)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                      child: Text(dayKey(e.at),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary)),
                    ),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle,
                          color: Colors.green),
                      title: Text(e.title),
                      subtitle:
                          Text('${two(e.at.hour)}:${two(e.at.minute)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: s.t('delete'),
                        onPressed: () => _deleteLogEntry(e),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// بطاقة إحصائيات: الإجماليّ + اليوم/القادمة/المتأخرة + نسبة «على المسار»
  /// (التذكيرات غير المتأخرة ÷ الإجماليّ).
  Widget _statsCard(BuildContext context, S s, int total, int today,
      int upcoming, int overdue) {
    final scheme = Theme.of(context).colorScheme;
    final onTrack = total == 0 ? 1.0 : (total - overdue) / total;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(s.t('stats'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                Text('${(onTrack * 100).round()}% ${s.t('on_track')}',
                    style: TextStyle(
                        color: onTrack > 0.7
                            ? Colors.green
                            : (onTrack > 0.4 ? Colors.orange : Colors.red),
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: onTrack,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                color: onTrack > 0.7
                    ? Colors.green
                    : (onTrack > 0.4 ? Colors.orange : Colors.red),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metric('$total', s.t('nc_total'), scheme.onSurface),
                _metric('$today', s.t('nc_today'), Colors.blue),
                _metric('$upcoming', s.t('nc_upcoming'), Colors.teal),
                _metric('$overdue', s.t('nc_overdue'), Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String value, String label, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );

  Widget _section(
      String title, IconData icon, Color color, List<ReminderView> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 6),
            Text('(${list.length})',
                style: TextStyle(color: color, fontSize: 12)),
          ]),
        ),
        for (final v in list) _tile(v, color),
      ],
    );
  }

  Widget _tile(ReminderView v, Color sectionColor) {
    final s = S.of(context);
    final r = v.reminder;
    final t = r.time;
    // تنبيه «مرّة واحدة» فات وقته ⇒ منتهٍ (لن يرنّ ثانيةً): نعرضه باهتًا مع زرّ
    // إعادة تنشيط (إعادة جدولته لوقت جديد).
    final expired =
        r.repeat == ReminderRepeat.once && t.isBefore(DateTime.now());
    final hint = Theme.of(context).hintColor;
    String two(int n) => n.toString().padLeft(2, '0');
    final when = '${t.year}/${two(t.month)}/${two(t.day)}  '
        '${two(t.hour)}:${two(t.minute)}';
    final impColor = switch (r.importance) {
      ReminderImportance.low => const Color(0xFF78909C),
      ReminderImportance.medium => const Color(0xFF42A5F5),
      ReminderImportance.high => const Color(0xFFEF6C00),
      ReminderImportance.critical => const Color(0xFFE53935),
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          radius: 6,
          backgroundColor: expired ? hint.withOpacity(0.5) : impColor,
        ),
        title: Text(_titleOf(v),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: expired
                ? TextStyle(color: hint, decoration: TextDecoration.lineThrough)
                : null),
        subtitle: Text(
            expired ? '$when  •  ${s.t('nc_expired')}' : when,
            style: TextStyle(
                fontSize: 12, color: expired ? hint : null)),
        trailing: expired
            ? TextButton.icon(
                onPressed: () => _reactivate(v),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: Text(s.t('nc_reactivate')),
              )
            : (r.repeat != ReminderRepeat.once
                ? const Icon(Icons.repeat, size: 18)
                : null),
      ),
    );
  }

  /// إعادة تنشيط تنبيه منتهٍ: اختيار وقت جديد ثم إعادة جدولته (يبقى كما هو عدا
  /// الوقت). يعمل للتنبيهات المستقلّة والمرتبطة بملاحظة.
  Future<void> _reactivate(ReminderView v) async {
    final s = S.of(context);
    final r = v.reminder;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final tod = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (tod == null || !mounted) return;
    final when =
        DateTime(date.year, date.month, date.day, tod.hour, tod.minute);
    final provider = context.read<RemindersProvider>();
    if (v.note != null) {
      await provider.setReminder(v.note!, when, r.repeat,
          importance: r.importance, preAlerts: r.preAlerts.toList());
    } else {
      await provider.setStandalone(when, r.repeat, r.title ?? '',
          importance: r.importance,
          preAlerts: r.preAlerts.toList(),
          location: r.location,
          attachmentPath: r.attachmentPath,
          intervalDays: r.intervalDays,
          doseCount: r.doseCount,
          existing: r);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('nc_rescheduled'))));
    }
  }
}
