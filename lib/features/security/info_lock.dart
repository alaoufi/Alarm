import 'package:flutter/material.dart';

import '../../services/security_service.dart';
import 'pin_entry.dart';

/// إعداد رمز مستقل لصفحة المعلومات (إدخال ثم تأكيد). يعيد الرمز أو null.
Future<String?> setupInfoPin(BuildContext context) async {
  String? first;
  String? result;
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: PinEntry(
          title: first == null ? 'اضبط رمز المعلومات' : 'أكّد رمز المعلومات',
          onSubmit: (pin) async {
            if (first == null) {
              setSheet(() => first = pin);
              return false; // اطلب التأكيد.
            }
            if (first == pin) {
              result = pin;
              if (ctx.mounted) Navigator.pop(ctx, true);
              return true;
            }
            setSheet(() => first = null); // غير متطابق، أعد البداية.
            return false;
          },
        ),
      ),
    ),
  );
  return result;
}

/// يطلب فتح قفل صفحة المعلومات برمزها المستقل. يعيد true عند النجاح.
Future<bool> ensureInfoUnlocked(BuildContext context) async {
  final sec = SecurityService.instance;
  if (!await sec.hasInfoPin()) return true; // لا رمز = لا قفل.
  if (!context.mounted) return false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: PinEntry(
        title: 'أدخل رمز المعلومات',
        showBiometric: false,
        onSubmit: (pin) async {
          final v = await sec.verifyInfoPin(pin);
          if (v && ctx.mounted) Navigator.pop(ctx, true);
          return v;
        },
      ),
    ),
  );
  return ok ?? false;
}
