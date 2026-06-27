import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/security_service.dart';
import 'pin_entry.dart';

/// يضمن وجود رقم سري قبل إنشاء محتوى سري/كلمة مرور.
///
/// إن لم يكن مُعيَّنًا، يعرض تدفّق تعيين رقم سري (إدخال + تأكيد).
/// يعيد true إذا كان موجودًا أصلًا أو تم تعيينه الآن.
Future<bool> ensurePinConfigured(BuildContext context) async {
  final sec = SecurityService.instance;
  if (await sec.hasPin()) return true;
  if (!context.mounted) return false;

  final s = S.of(context);
  String? first;

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('🔒 ${s.t('set_pin')}',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            PinEntry(
              title: first == null ? s.t('set_pin') : s.t('confirm_pin'),
              onSubmit: (pin) async {
                if (first == null) {
                  setSheet(() => first = pin);
                  return false; // اطلب التأكيد.
                }
                if (first == pin) {
                  await sec.setPin(pin);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                  return true;
                }
                setSheet(() => first = null); // غير متطابق، أعد البداية.
                return false;
              },
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}
