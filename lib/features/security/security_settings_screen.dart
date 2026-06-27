import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/security_service.dart';
import '../../widgets/ui_kit.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _lockEnabled = await _sec.isLockEnabled();
    _biometricEnabled = await _sec.isBiometricEnabled();
    _biometricAvailable = await _sec.canUseBiometrics();
    setState(() => _loaded = true);
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
        ],
      ),
    );
  }
}
