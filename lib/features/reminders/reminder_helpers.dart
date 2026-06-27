import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../data/models/enums.dart';
import '../sounds/sound_catalog.dart';

/// مساعدات مشتركة بين حواري التذكير (تذكير الملاحظة + التنبيه المستقلّ)
/// لتجنّب تكرار منطق مستوى الأهمية وأسماء النغمات.

String impLabel(S s, ReminderImportance imp) => switch (imp) {
      ReminderImportance.low => s.t('imp_low'),
      ReminderImportance.medium => s.t('imp_medium'),
      ReminderImportance.high => s.t('imp_high'),
      ReminderImportance.critical => s.t('imp_critical'),
    };

IconData impIcon(ReminderImportance imp) => switch (imp) {
      ReminderImportance.low => Icons.notifications_none,
      ReminderImportance.medium => Icons.notifications_active_outlined,
      ReminderImportance.high => Icons.vibration,
      ReminderImportance.critical => Icons.crisis_alert,
    };

Color impColor(ReminderImportance imp) => switch (imp) {
      ReminderImportance.low => const Color(0xFF78909C),
      ReminderImportance.medium => const Color(0xFF42A5F5),
      ReminderImportance.high => const Color(0xFFEF6C00),
      ReminderImportance.critical => const Color(0xFFE53935),
    };

/// اسم النغمة للعرض من مكتبة الأصوات (يشمل كل النغمات الـ23).
String toneName(String id) {
  for (final t in soundCatalog) {
    if (t.id == id) return t.name;
  }
  return id;
}
