import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/security_service.dart';
import '../home/root_screen.dart';
import 'pin_entry.dart';

/// بوابة تتحقق من قفل التطبيق قبل عرض المحتوى.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  bool? _locked; // null = جارٍ التحقق
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final enabled = await SecurityService.instance.isLockEnabled();
    if (!enabled) {
      setState(() {
        _locked = false;
        _checking = false;
      });
      return;
    }
    setState(() {
      _locked = true;
      _checking = false;
    });
    // محاولة البصمة تلقائيًا مرة واحدة إن كانت مفعّلة.
    if (await SecurityService.instance.isBiometricEnabled()) {
      final ok = await SecurityService.instance
          .authenticateBiometric('افتح قفل Alaoufi Notes');
      if (ok && mounted) setState(() => _locked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_locked == true) {
      return Scaffold(
        body: SafeArea(
          child: PinEntry(
            title: S.of(context).t('enter_pin'),
            showBiometric: true,
            onSubmit: (pin) async {
              final ok = await SecurityService.instance.verifyPin(pin);
              if (ok && mounted) setState(() => _locked = false);
              return ok;
            },
            onBiometric: () async {
              final ok = await SecurityService.instance
                  .authenticateBiometric('افتح قفل Alaoufi Notes');
              if (ok && mounted) setState(() => _locked = false);
              return ok;
            },
          ),
        ),
      );
    }
    return const RootScreen();
  }
}
