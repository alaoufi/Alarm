import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/alarm_volume.dart';
import '../../services/notification_service.dart';
import '../settings/settings_provider.dart';
import 'alarm_permissions.dart';

/// شاشة «اختبار الموثوقية»: تتأكّد من أن الإشعارات والمنبّه يعملان فعليًّا على
/// الجهاز — إشعار فوري + منبّه حرج مجدول + تشخيص أذونات (إشعارات/منبّه دقيق).
class ReliabilityTestScreen extends StatefulWidget {
  const ReliabilityTestScreen({super.key});

  @override
  State<ReliabilityTestScreen> createState() => _ReliabilityTestScreenState();
}

class _ReliabilityTestScreenState extends State<ReliabilityTestScreen> {
  final _ns = NotificationService.instance;
  Duration _delay = const Duration(seconds: 10);

  bool? _notifEnabled;
  bool? _exactAllowed;
  bool? _batteryOk; // غير مقيّد بتوفير البطارية (مهمّ ليعمل المنبّه مغلقًا)
  bool _checking = true;

  static const _delays = <(String, Duration)>[
    ('10 ثوانٍ', Duration(seconds: 10)),
    ('30 ثانية', Duration(seconds: 30)),
    ('دقيقة', Duration(minutes: 1)),
    ('5 دقائق', Duration(minutes: 5)),
  ];

  @override
  void initState() {
    super.initState();
    _refreshDiagnostics();
  }

  Future<void> _refreshDiagnostics() async {
    setState(() => _checking = true);
    final notif = await _ns.areNotificationsEnabled();
    final exact = await _ns.canScheduleExactAlarms();
    final battery = await AlarmVolume.isBatteryUnrestricted();
    if (!mounted) return;
    setState(() {
      _notifEnabled = notif;
      _exactAllowed = exact;
      _batteryOk = battery;
      _checking = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _testNow() async {
    await _ns.showTestNotificationNow();
    _snack('أُطلق إشعار فوري — تحقّق من شريط الإشعارات والنغمة 🔔');
  }

  Future<void> _testAlarm() async {
    await _ns.scheduleTestAlarm(_delay);
    final label = _delays.firstWhere((d) => d.$2 == _delay).$1;
    _snack('سيظهر منبّه تجريبي بعد $label — يمكنك إغلاق التطبيق للتأكّد ⏰');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(s.t('reliability_test'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          // بطاقة التشخيص.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.health_and_safety_outlined,
                        color: scheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('فحص الأذونات',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    IconButton(
                      tooltip: 'إعادة الفحص',
                      icon: const Icon(Icons.refresh),
                      onPressed: _checking ? null : _refreshDiagnostics,
                    ),
                  ]),
                  const SizedBox(height: 6),
                  if (_checking)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    _statusRow('الإشعارات مُفعّلة', _notifEnabled),
                    _statusRow('المنبّه الدقيق مسموح', _exactAllowed),
                    _statusRow('غير مقيّد بتوفير البطارية', _batteryOk),
                    if (_notifEnabled == false || _exactAllowed == false) ...[
                      const SizedBox(height: 8),
                      Text(
                        'بعض الأذونات غير مفعّلة — قد تتأخّر التنبيهات أو لا تظهر.',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.error),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _ns.requestPermissions();
                          await _refreshDiagnostics();
                        },
                        icon: const Icon(Icons.lock_open_outlined),
                        label: const Text('طلب الأذونات'),
                      ),
                    ],
                    if (_batteryOk == false) ...[
                      const SizedBox(height: 8),
                      Text(
                        'توفير البطارية قد يُوقف المنبّه عندما يكون التطبيق مغلقًا — '
                        'استثنِ التطبيق ليعمل المنبّه بموثوقية.',
                        style: TextStyle(fontSize: 12.5, color: scheme.error),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await AlarmVolume.requestBatteryUnrestricted();
                          await _refreshDiagnostics();
                        },
                        icon: const Icon(Icons.battery_saver_outlined),
                        label: const Text('استثناء من توفير البطارية'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // تفعيل كل القيود دفعةً واحدة.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                await showAlarmReliabilitySheet(context);
                await _refreshDiagnostics();
              },
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('تفعيل موثوقية المنبّه (فكّ القيود)'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
            ),
          ),
          const SizedBox(height: 6),

          // اختبار فوري.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardTitle(
                      icon: Icons.notifications_active_outlined,
                      title: 'إشعار فوري'),
                  const SizedBox(height: 4),
                  const Text(
                      'يُطلق إشعارًا الآن (صوت + اهتزاز) للتأكّد أن الإشعارات '
                      'والنغمة المختارة تعمل.',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _testNow,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('إطلاق إشعار فوري'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // اختبار المنبّه المجدول.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardTitle(
                      icon: Icons.alarm_on_outlined,
                      title: 'منبّه حرج مجدول'),
                  const SizedBox(height: 4),
                  const Text(
                      'يجدول منبّهًا حرجًا (شاشة كاملة) بعد المدّة المختارة. '
                      'أغلق التطبيق وانتظر للتأكّد أنه يعمل حتى في الخلفية.',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final (label, d) in _delays)
                        ChoiceChip(
                          label: Text(label),
                          selected: _delay == d,
                          onSelected: (_) => setState(() => _delay = d),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _testAlarm,
                    icon: const Icon(Icons.alarm_add),
                    label: const Text('جدولة منبّه تجريبي'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // وضع «لا يمكن تفويته»: تفعيله واختيار نوع التحدّي (أرقام/كلمة)
          // لتجربته مع المنبّه التجريبيّ أعلاه.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardTitle(
                      icon: Icons.gpp_maybe_outlined,
                      title: 'لا يمكن تفويته'),
                  const SizedBox(height: 4),
                  const Text(
                      'عند تفعيله يلزم حلّ تحدٍّ قبل إيقاف المنبّه (يُخفى زرّ '
                      'الإيقاف من الإشعار). جرّبه مع المنبّه التجريبيّ أعلاه.',
                      style: TextStyle(fontSize: 13)),
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
                    selected: {settings.dismissChallenge},
                    onSelectionChanged: (v) =>
                        settings.setDismissChallenge(v.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Center(
            child: TextButton.icon(
              onPressed: () async {
                await _ns.cancelTests();
                _snack('أُلغيت اختبارات التنبيه المعلّقة');
              },
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('إلغاء الاختبارات المعلّقة'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, bool? ok) {
    final color = ok == null
        ? Colors.grey
        : (ok ? Colors.green : Colors.red);
    final icon = ok == null
        ? Icons.help_outline
        : (ok ? Icons.check_circle : Icons.cancel);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Text(ok == null ? '—' : (ok ? 'نعم' : 'لا'),
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _CardTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
    ]);
  }
}
