import 'package:flutter/material.dart';

import '../../data/database/app_database.dart';
import '../../data/models/reminder_log_entry.dart';
import '../../data/repositories/reminder_log_repository.dart';
import '../../widgets/ui_kit.dart';

/// إحصاءات التنبيهات: من سجلّ التنبيهات المنفّذة (عدد، هذا الأسبوع، أكثر وقت/تنبيه).
class ReminderStatsScreen extends StatelessWidget {
  const ReminderStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, 'الإحصاءات'),
      body: FutureBuilder<List<ReminderLogEntry>>(
        future: ReminderLogRepository(AppDatabase.instance).getAll(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final log = snap.data!;
          if (log.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا توجد بيانات بعد — ستظهر بعد انطلاق تنبيهاتك.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final now = DateTime.now();
          final weekAgo = now.subtract(const Duration(days: 7));
          final thisWeek = log.where((e) => e.at.isAfter(weekAgo)).length;

          // أكثر ساعة في اليوم.
          final byHour = List<int>.filled(24, 0);
          for (final e in log) {
            byHour[e.at.hour]++;
          }
          var peakHour = 0;
          for (var h = 0; h < 24; h++) {
            if (byHour[h] > byHour[peakHour]) peakHour = h;
          }

          // أكثر تنبيه تكرارًا.
          final counts = <String, int>{};
          for (final e in log) {
            counts[e.title] = (counts[e.title] ?? 0) + 1;
          }
          String topTitle = '—';
          var topCount = 0;
          counts.forEach((k, v) {
            if (v > topCount) {
              topCount = v;
              topTitle = k;
            }
          });

          final maxHour =
              byHour.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.5,
                children: [
                  _stat(context, Icons.history, 'إجمالي المنفّذة', '${log.length}',
                      const Color(0xFF1E88E5)),
                  _stat(context, Icons.calendar_view_week, 'هذا الأسبوع',
                      '$thisWeek', const Color(0xFF00897B)),
                  _stat(context, Icons.schedule, 'أكثر وقت',
                      '${peakHour.toString().padLeft(2, '0')}:00',
                      const Color(0xFFF57C00)),
                  _stat(context, Icons.repeat, 'الأكثر تكرارًا', '$topCount×',
                      const Color(0xFF8E24AA)),
                ],
              ),
              const SizedBox(height: 8),
              AppCard(
                child: ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: const Text('أكثر تنبيه تكرارًا'),
                  subtitle: Text(topTitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('التوزيع حسب الساعة',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary)),
              ),
              const SizedBox(height: 8),
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      for (var h = 0; h < 24; h++)
                        if (byHour[h] > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 46,
                                  child: Text(
                                      '${h.toString().padLeft(2, '0')}:00',
                                      style: const TextStyle(fontSize: 12)),
                                ),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: byHour[h] / maxHour,
                                      minHeight: 12,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('${byHour[h]}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String label, String value,
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [
                  color,
                  Color.alphaBlend(Colors.black.withOpacity(0.2), color),
                ]),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 19,
                          color: color)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
