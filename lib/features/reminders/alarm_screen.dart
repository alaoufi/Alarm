import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Timer? _escalateTimer; // تصعيد متعدّد المراحل إن لم يتفاعل المستخدم.
  int _stage = 0;

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
    // تصعيد متعدّد المراحل: كل 12 ثانية بلا تفاعل يزيد الإلحاح (صوت أقصى +
    // اهتزاز متصاعد) — للمنبّهات الحرجة التي يجب ألّا تُفوَّت.
    _escalateTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted) return;
      setState(() => _stage++);
      if (_raised) AlarmVolume.raise(targetPercent: 100);
      final pulses = _stage.clamp(1, 4);
      for (var i = 0; i < pulses; i++) {
        Future.delayed(Duration(milliseconds: i * 200),
            () => HapticFeedback.heavyImpact());
      }
    });
  }

  @override
  void dispose() {
    _escalateTimer?.cancel();
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
                Icon(Icons.crisis_alert,
                    color: Colors.white, size: 56.0 + _stage * 4),
                if (_stage > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('🔴 التنبيه يتصاعد',
                        style: TextStyle(
                            color: Colors.amberAccent.shade100,
                            fontWeight: FontWeight.bold)),
                  ),
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
                    if (!await _confirmDismiss()) return;
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

  /// «لا يُفوَّت»: عند تفعيل الخيار، يطلب حلّ مسألة بسيطة قبل إيقاف المنبّه.
  Future<bool> _confirmDismiss() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.mathToDismiss) return true;
    final rnd = Random();
    final a = rnd.nextInt(8) + 2;
    final b = rnd.nextInt(8) + 2;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('لإيقاف المنبّه، احسب:'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$a + $b = ؟',
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              if (int.tryParse(ctrl.text.trim()) == a + b) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    return ok == true;
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
