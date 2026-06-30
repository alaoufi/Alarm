import 'package:flutter/material.dart';

import '../settings/settings_provider.dart';

/// عند تفعيل وضع «لا يُفوَّت» (الانتقال من «معطّل» إلى أرقام/كلمة) نعرض تحذيرًا
/// صريحًا ونطلب الموافقة قبل الحفظ. التبديل بين أرقام/كلمة أو الإيقاف لا يحذّر.
Future<void> selectDismissChallenge(
    BuildContext context, SettingsProvider st, int value) async {
  final turningOn = value != 0 && st.dismissChallenge == 0;
  if (turningOn) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.gpp_maybe_outlined, color: Color(0xFFE53935)),
        title: const Text('لا يمكن تفويته'),
        content: const Text(
          'للعلم: لن يصمت التنبيه إلا بعد حلّ التحدّي.\n'
          'لا غفوة، ولا تأجيل، ولا رجوع — الصوت والشاشة يستمرّان حتى تحلّه.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('موافق')),
        ],
      ),
    );
    if (ok != true) return;
  }
  await st.setDismissChallenge(value);
}
