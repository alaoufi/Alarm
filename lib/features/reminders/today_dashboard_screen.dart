import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/time/hijri_recurrence.dart';
import '../../data/models/enums.dart';
import '../../data/models/reminder.dart';
import '../../services/med_occurrences.dart';
import '../../widgets/ui_kit.dart';
import 'reminders_provider.dart';

/// لوحة اليوم: ملخّص سريع (القادمة اليوم / الفائتة / الحرجة / النشطة) + قائمة اليوم.
class TodayDashboardScreen extends StatelessWidget {
  const TodayDashboardScreen({super.key});

  DateTime _nextFire(Reminder r) {
    final now = DateTime.now();
    final t = r.time;
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
        return t;
      case ReminderRepeat.hijriYearly:
        return nextHijriAnniversary(t, now);
    }
  }

  String _labelOf(ReminderView v) {
    final r = v.reminder;
    final note = v.note;
    return r.isStandalone
        ? (r.title?.isNotEmpty == true ? r.title! : 'تنبيه')
        : (note?.title.isNotEmpty == true
            ? note!.title
            : (note?.content ?? 'ملاحظة'));
  }

  bool _expired(Reminder r) =>
      r.repeat == ReminderRepeat.once && r.time.isBefore(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RemindersProvider>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final all = provider.items;
    final active =
        all.where((v) => v.reminder.isActive && !_expired(v.reminder)).toList();
    final overdue = all.where((v) => _expired(v.reminder)).toList();
    final critical = active
        .where((v) => v.reminder.importance == ReminderImportance.critical)
        .toList();
    final todays = active.where((v) {
      final n = _nextFire(v.reminder);
      return DateTime(n.year, n.month, n.day) == today;
    }).toList()
      ..sort((a, b) => _nextFire(a.reminder).compareTo(_nextFire(b.reminder)));

    DateTime? soonest;
    for (final v in active) {
      final n = _nextFire(v.reminder);
      if (soonest == null || n.isBefore(soonest)) soonest = n;
    }

    return Scaffold(
      appBar: gradientAppBar(context, 'لوحة اليوم'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (soonest != null && soonest.year != 9999)
            _nextBanner(context, soonest, todays.isNotEmpty ? todays.first : null),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.5,
            children: [
              _statCard(context, Icons.today, 'قادمة اليوم',
                  todays.length, const Color(0xFF00897B)),
              _statCard(context, Icons.priority_high, 'حرِجة',
                  critical.length, const Color(0xFFE53935)),
              _statCard(context, Icons.history_toggle_off, 'فائتة',
                  overdue.length, const Color(0xFFF57C00)),
              _statCard(context, Icons.notifications_active, 'نشطة',
                  active.length, const Color(0xFF1E88E5)),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('📅 تنبيهات اليوم',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary)),
          ),
          const SizedBox(height: 6),
          if (todays.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('لا تنبيهات لليوم 🎉')),
            )
          else
            for (final v in todays) _todayTile(context, v),
        ],
      ),
    );
  }

  Widget _nextBanner(BuildContext context, DateTime soonest, ReminderView? v) {
    final scheme = Theme.of(context).colorScheme;
    final diff = soonest.difference(DateTime.now());
    String when;
    if (diff.isNegative) {
      when = 'الآن';
    } else if (diff.inHours >= 1) {
      when = 'بعد ${diff.inHours} ساعة و${diff.inMinutes % 60} دقيقة';
    } else {
      when = 'بعد ${diff.inMinutes} دقيقة';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: [
          scheme.primary,
          Color.alphaBlend(Colors.black.withOpacity(0.18), scheme.primary),
        ]),
        boxShadow: [
          BoxShadow(
              color: scheme.primary.withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Row(children: [
        const Icon(Icons.alarm_on, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('المنبّه التالي $when',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              if (v != null)
                Text(_labelOf(v),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 12.5)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _statCard(BuildContext context, IconData icon, String label, int count,
      Color color) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(color.withOpacity(0.18), scheme.surface),
            Color.alphaBlend(color.withOpacity(0.05), scheme.surface),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.30)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.4 : 0.12),
              blurRadius: 10,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [
                  color,
                  Color.alphaBlend(Colors.black.withOpacity(0.2), color),
                ]),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$count',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          color: color)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayTile(BuildContext context, ReminderView v) {
    final scheme = Theme.of(context).colorScheme;
    final crit = v.reminder.importance == ReminderImportance.critical;
    final at = DateFormat('h:mm a', 'ar').format(_nextFire(v.reminder));
    return AppCard(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              (crit ? const Color(0xFFE53935) : scheme.primary).withOpacity(0.15),
          child: Icon(crit ? Icons.priority_high : Icons.alarm,
              color: crit ? const Color(0xFFE53935) : scheme.primary),
        ),
        title: Text(_labelOf(v),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(at,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
