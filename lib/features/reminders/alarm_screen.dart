import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/alarm_volume.dart';
import '../../services/notification_service.dart';
import '../settings/settings_provider.dart';

/// شاشة المنبّه داخل التطبيق — تظهر عند الضغط على تذكير حرج: عنوان/وصف/وقت
/// مع زرّ «تم الإنجاز» وزرّ «تأجيل» (خيارات 5/10/15/30/60 دقيقة).
///
/// عند ظهورها ترفع صوت المنبّه تلقائيًّا (إن فُعِّل) ليُسمَع حتى مع الصامت/المنخفض،
/// بالتدرّج إن طُلب، وتستعيد المستوى الأصليّ عند إغلاقها.
class AlarmScreen extends StatefulWidget {
  final Map<String, String> info;
  const AlarmScreen({super.key, required this.info});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  bool _raised = false;

  int get _base => int.tryParse(widget.info['base'] ?? '') ?? 0;
  int? get _noteId {
    final n = int.tryParse(widget.info['note'] ?? '');
    return (n == null || n < 0) ? null : n;
  }

  @override
  void initState() {
    super.initState();
    // رفع صوت المنبّه إن فُعِّل (يقرأ تفضيلات المستخدم).
    final settings = context.read<SettingsProvider>();
    if (settings.autoRaiseVolume) {
      _raised = true;
      AlarmVolume.raise(
        targetPercent: 100,
        rampSeconds: settings.gradualVolume ? 15 : 0,
      );
    }
  }

  @override
  void dispose() {
    // نستعيد مستوى الصوت الأصليّ مهما كانت طريقة الإغلاق (إنجاز/تأجيل/رجوع).
    if (_raised) AlarmVolume.restore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final info = widget.info;
    final now = TimeOfDay.now();
    final date = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A237E), Color(0xFFB71C1C)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // سهم رجوع: يُغلق شاشة المنبّه دون إنجاز/تأجيل (يبقى التذكير).
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: BackButton(
                    color: Colors.white,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
                const Icon(Icons.crisis_alert, color: Colors.white, size: 56),
                const Spacer(),
                // الوقت الكبير.
                Text('${two(now.hour)}:${two(now.minute)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 64,
                        fontWeight: FontWeight.bold)),
                Text('${date.year}/${two(date.month)}/${two(date.day)}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 16)),
                const SizedBox(height: 28),
                // العنوان والوصف.
                Text(info['title'] ?? '⏰',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700)),
                if ((info['body'] ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(info['body']!,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.9), fontSize: 16)),
                ],
                const Spacer(),
                // تأجيل.
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => _snooze(context, s),
                  icon: const Icon(Icons.snooze),
                  label: Text(s.t('alarm_snooze')),
                ),
                const SizedBox(height: 12),
                // تم الإنجاز.
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFB71C1C),
                    minimumSize: const Size.fromHeight(58),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    await NotificationService.instance.acknowledgeAlarm(_base);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check_circle),
                  label: Text(s.t('alarm_done')),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _snooze(BuildContext context, S s) async {
    final mins = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in const [5, 10, 15, 30, 60])
              ListTile(
                leading: const Icon(Icons.snooze),
                title: Text('$m ${s.t('minutes')}'),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (mins == null) return;
    await NotificationService.instance.snoozeAlarm(
      _base,
      widget.info['title'] ?? '⏰',
      widget.info['body'] ?? '',
      mins,
      _noteId,
    );
    if (context.mounted) Navigator.pop(context);
  }
}
