import 'package:flutter/material.dart';

import 'standalone_reminder_dialog.dart';

/// قالب جاهز: نوع التنبيه + اسم مبدئيّ + أيقونة.
class _Template {
  final String label;
  final IconData icon;
  final Color color;
  final ReminderKind kind;
  final String title;
  const _Template(this.label, this.icon, this.color, this.kind, this.title);
}

const List<_Template> _templates = [
  _Template('أدوية', Icons.medication_outlined, Color(0xFFE53935),
      ReminderKind.medication, 'دواء'),
  _Template('رحلة سفر', Icons.flight_takeoff_outlined, Color(0xFF5E35B1),
      ReminderKind.travel, 'رحلة'),
  _Template('مراجعة سيارة', Icons.directions_car_outlined, Color(0xFF6D4C41),
      ReminderKind.car, 'مراجعة دورية'),
  _Template('متابعة مريض', Icons.healing_outlined, Color(0xFF1E88E5),
      ReminderKind.appointment, 'متابعة'),
  _Template('مناسبة', Icons.celebration_outlined, Color(0xFFF9A825),
      ReminderKind.occasion, 'مناسبة'),
  _Template('مذاكرة للاختبار', Icons.menu_book_outlined, Color(0xFF00897B),
      ReminderKind.general, 'مذاكرة'),
  _Template('فاتورة', Icons.receipt_long_outlined, Color(0xFF00897B),
      ReminderKind.bills, 'فاتورة'),
];

/// يعرض ورقة قوالب جاهزة؛ عند الاختيار يفتح حوار تنبيه جديد مُهيّأً بالقالب.
Future<void> showReminderTemplates(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('قوالب جاهزة',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ),
          ),
          for (final t in _templates)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: t.color.withOpacity(0.15),
                child: Icon(t.icon, color: t.color),
              ),
              title: Text(t.label),
              onTap: () {
                Navigator.pop(ctx);
                showStandaloneReminderDialog(context,
                    initialKind: t.kind, initialTitle: t.title);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
