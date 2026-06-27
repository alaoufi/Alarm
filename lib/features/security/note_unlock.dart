import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/security_service.dart';
import 'pin_entry.dart';

/// يطلب من المستخدم فتح القفل (بصمة ثم رقم سري) لعرض ملاحظة مقفلة.
/// يعيد true عند النجاح.
Future<bool> ensureUnlocked(BuildContext context) async {
  final sec = SecurityService.instance;

  // إن لم يكن هناك قفل أصلًا (لا رقم سري)، نطلب من المستخدم تفعيله من الإعدادات.
  if (!await sec.hasPin()) {
    return true;
  }

  // جرّب البصمة أولًا إن كانت متاحة.
  if (await sec.isBiometricEnabled() && await sec.canUseBiometrics()) {
    final ok = await sec.authenticateBiometric('افتح الملاحظة المقفلة');
    if (ok) return true;
  }

  if (!context.mounted) return false;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: PinEntry(
        title: S.of(ctx).t('unlock_to_view'),
        showBiometric: false,
        onSubmit: (pin) async {
          final ok = await sec.verifyPin(pin);
          if (ok && ctx.mounted) Navigator.pop(ctx, true);
          return ok;
        },
      ),
    ),
  );
  return result ?? false;
}
