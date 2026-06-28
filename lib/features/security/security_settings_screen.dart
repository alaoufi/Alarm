import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/license_service.dart';
import '../../services/security_service.dart';
import '../../widgets/ui_kit.dart';
import '../reminders/reminders_provider.dart';
import 'pin_entry.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final _sec = SecurityService.instance;
  bool _lockEnabled = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _loaded = false;
  LicenseInfo? _license;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _lockEnabled = await _sec.isLockEnabled();
    _biometricEnabled = await _sec.isBiometricEnabled();
    _biometricAvailable = await _sec.canUseBiometrics();
    _license = await LicenseService.instance.info();
    setState(() => _loaded = true);
  }

  String _licenseSubtitle() {
    final info = _license;
    if (info == null) return '';
    switch (info.state) {
      case LicenseState.disabled:
        return 'وضع التطوير (لم يُضبط مفتاح) — التطبيق مفتوح.';
      case LicenseState.none:
        return 'غير مفعّل بعد.';
      case LicenseState.expired:
        return 'انتهت مدّة التفعيل.';
      case LicenseState.active:
        return info.permanent
            ? 'مفعّل دائمًا.'
            : 'مفعّل — يتبقّى ${info.daysLeft} يوم.';
    }
  }

  Future<void> _deactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء التفعيل'),
        content: const Text(
            'سيُحذف التفعيل من هذا الجهاز ويعود التطبيق لشاشة التفعيل عند '
            'إعادة فتحه. هذا للاختبار فقط. هل تريد المتابعة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إلغاء التفعيل')),
        ],
      ),
    );
    if (ok != true) return;
    await LicenseService.instance.deactivate();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم إلغاء التفعيل — أعد فتح التطبيق لاختبار التفعيل.')));
  }

  Future<void> _setupPin() async {
    final s = S.of(context);
    String? first;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: PinEntry(
              title: first == null ? s.t('set_pin') : s.t('confirm_pin'),
              onSubmit: (pin) async {
                if (first == null) {
                  setSheet(() => first = pin);
                  return false; // اطلب التأكيد دون إغلاق.
                }
                if (first == pin) {
                  await _sec.setPin(pin);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                  return true;
                }
                setSheet(() => first = null); // غير متطابق، أعد البداية.
                return false;
              },
            ),
          );
        },
      ),
    );
    if (ok == true) await _load();
  }

  /// «التنبيهات فقط»: يحوّل تنبيهات الملاحظات إلى مستقلّة (دون فقدها) ثم يحذف كل
  /// الملاحظات المستورَدة التي لا تُعرض في هذا التطبيق.
  Future<void> _purgeNotes() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الملاحظات المستورَدة'),
        content: const Text(
            'هذا التطبيق للتنبيهات فقط. سيتم حذف كل الملاحظات المستورَدة (التي '
            'لا تظهر هنا) مع الحفاظ على جميع تنبيهاتك. لا يمكن التراجع.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف الملاحظات')),
        ],
      ),
    );
    if (ok != true) return;
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<RemindersProvider>();
    final removed = await provider.detachAndPurgeNotes();
    messenger.showSnackBar(
        SnackBar(content: Text('تم حذف $removed ملاحظة. تنبيهاتك محفوظة.')));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: gradientAppBar(context, s.t('security')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          AppCard(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const GradientIcon(Icons.lock_outline),
                  title: Text(s.t('app_lock'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(s.t('use_pin')),
                  value: _lockEnabled,
                  onChanged: (v) async {
                    if (v) {
                      await _setupPin();
                    } else {
                      await _sec.disableLock();
                      await _load();
                    }
                  },
                ),
                if (_lockEnabled)
                  ListTile(
                    leading: const Icon(Icons.password),
                    title: Text(s.t('set_pin')),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: _setupPin,
                  ),
                if (_lockEnabled && _biometricAvailable)
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: Text(s.t('use_biometric')),
                    value: _biometricEnabled,
                    onChanged: (v) async {
                      await _sec.setBiometric(v);
                      await _load();
                    },
                  ),
              ],
            ),
          ),
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: scheme.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'يمكنك قفل ملاحظة معينة من قائمة خيارات الملاحظة (اضغط مطولاً على الملاحظة). يتطلب فتحها الرقم السري أو البصمة.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_license != null && _license!.state != LicenseState.disabled)
            AppCard(
              child: Column(
                children: [
                  ListTile(
                    leading:
                        const GradientIcon(Icons.verified_user_outlined),
                    title: const Text('التفعيل',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_licenseSubtitle()),
                  ),
                  if (_license!.state == LicenseState.active ||
                      _license!.state == LicenseState.expired)
                    ListTile(
                      leading: Icon(Icons.lock_reset, color: scheme.error),
                      title: Text('إلغاء التفعيل (للاختبار)',
                          style: TextStyle(color: scheme.error)),
                      subtitle: const Text(
                          'يعيد التطبيق لشاشة التفعيل عند إعادة فتحه.'),
                      onTap: _deactivate,
                    ),
                ],
              ),
            ),
          AppCard(
            child: ListTile(
              leading: Icon(Icons.cleaning_services_outlined,
                  color: scheme.error),
              title: const Text('حذف الملاحظات المستورَدة',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'تطبيق التنبيهات فقط: يحذف الملاحظات غير المعروضة ويُبقي تنبيهاتك.'),
              onTap: _purgeNotes,
            ),
          ),
        ],
      ),
    );
  }
}
