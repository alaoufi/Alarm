import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/alarm_volume.dart';
import '../../services/notification_service.dart';

const _kPromptedKey = 'alarm_reliability_prompted';

/// يعرض ورقة «فكّ قيود المنبّه» **مرّة واحدة** — تُستدعى عند أول إنشاء تنبيه جديد.
Future<void> ensureAlarmReliabilityOnce(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kPromptedKey) ?? false) return;
  await prefs.setBool(_kPromptedKey, true);
  if (context.mounted) await showAlarmReliabilitySheet(context);
}

/// ورقة تفعيل كل صلاحيات/قيود المنبّه دفعةً واحدة (قابلة للاستدعاء يدويًّا أيضًا).
Future<void> showAlarmReliabilitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ReliabilitySheet(),
  );
}

class _ReliabilitySheet extends StatefulWidget {
  const _ReliabilitySheet();

  @override
  State<_ReliabilitySheet> createState() => _ReliabilitySheetState();
}

class _ReliabilitySheetState extends State<_ReliabilitySheet> {
  final _ns = NotificationService.instance;
  bool? _notif, _exact, _battery;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final n = await _ns.areNotificationsEnabled();
    final e = await _ns.canScheduleExactAlarms();
    final b = await AlarmVolume.isBatteryUnrestricted();
    if (mounted) setState(() {
      _notif = n;
      _exact = e;
      _battery = b;
    });
  }

  Future<void> _enableAll() async {
    setState(() => _busy = true);
    // يفتح نوافذ النظام تباعًا: الإشعارات + المنبّه الدقيق + الشاشة الكاملة.
    await _ns.requestPermissions();
    // ثمّ استثناء البطارية.
    await AlarmVolume.requestBatteryUnrestricted();
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            18, 4, 18, MediaQuery.of(context).viewInsets.bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.verified_user_outlined, color: scheme.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('اجعل المنبّه يعمل في كل الظروف',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'حتى يرنّ المنبّه في وقته بالضبط ويظهر ملء الشاشة — رغم إغلاق التطبيق '
              'أو إعادة التشغيل أو ضعف البطارية أو الصامت — فعّل القيود التالية:',
              style: TextStyle(
                  fontSize: 13, color: scheme.onSurface.withOpacity(0.75)),
            ),
            const SizedBox(height: 14),
            _row(Icons.notifications_active_outlined, 'الإشعارات', _notif),
            _row(Icons.alarm_on_outlined, 'المنبّه الدقيق', _exact),
            _row(Icons.battery_saver_outlined, 'استثناء توفير البطارية',
                _battery),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _enableAll,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.flash_on),
                label: const Text('تفعيل الكل'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50)),
              ),
            ),
            const SizedBox(height: 8),
            // التشغيل التلقائي لا يمكن منحه برمجيًّا — نوجّه المستخدم إليه.
            OutlinedButton.icon(
              onPressed: () => AlarmVolume.openAutoStart(),
              icon: const Icon(Icons.restart_alt),
              label: const Text('فتح «التشغيل التلقائي» (Autostart)'),
              style:
                  OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 6),
            Text(
              'ملاحظة: «التشغيل التلقائي» إعداد من نظام جهازك (شاومي/هواوي…) لا '
              'يستطيع أي تطبيق تفعيله تلقائيًّا — فعّله مرّة واحدة ليبقى المنبّه يعمل '
              'بعد الإغلاق وإعادة التشغيل.',
              style: TextStyle(
                  fontSize: 11.5, color: scheme.onSurface.withOpacity(0.55)),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('تم'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, bool? ok) {
    final color = ok == null
        ? Colors.grey
        : (ok ? Colors.green : Theme.of(context).colorScheme.error);
    final tick = ok == null
        ? Icons.help_outline
        : (ok ? Icons.check_circle : Icons.cancel);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5))),
        Icon(tick, color: color, size: 20),
      ]),
    );
  }
}
