import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/enums.dart';
import '../../data/models/note.dart';
import '../editor/note_editor_screen.dart';
import '../home/notes_provider.dart';

/// قالب ملاحظة جاهز (عنوان + أيقونة + محتوى مبدئي).
class NoteTemplate {
  final String title;
  final IconData icon;
  final String body;
  const NoteTemplate(this.title, this.icon, this.body);
}

const kNoteTemplates = <NoteTemplate>[
  NoteTemplate('مذكرة يومية', Icons.today,
      '• أهم شيء اليوم:\n\n• مهام اليوم:\n- \n\n• ملاحظات:\n\n• ملخص اليوم:\n'),
  NoteTemplate('محضر اجتماع', Icons.groups,
      'عنوان الاجتماع:\nالتاريخ:\nالحضور:\n\nالقرارات:\n- \n\nالمهام المطلوبة:\n- \n\nتاريخ المتابعة:\nالملخص:\n'),
  NoteTemplate('خطة مذاكرة', Icons.school,
      'المادة:\nالأهداف:\n- \n\nالجدول:\n- \n\nالمراجعة:\n- \n'),
  NoteTemplate('قائمة مشتريات', Icons.shopping_cart,
      '- \n- \n- \n- \n'),
  NoteTemplate('فكرة مشروع', Icons.lightbulb,
      'الفكرة:\nالمشكلة التي تحلّها:\nالحل المقترح:\nالخطوات:\n- \n\nالموارد المطلوبة:\n'),
  NoteTemplate('متابعة مصروفات', Icons.account_balance_wallet,
      'الشهر:\n\nالبند | المبلغ\n- \n- \n\nالإجمالي:\n'),
  NoteTemplate('ملاحظة سفر', Icons.flight,
      'الوجهة:\nالتواريخ:\nالحجوزات:\n- \n\nقائمة الحقائب:\n- \n\nمهام قبل السفر:\n- \n'),
  NoteTemplate('متابعة علاج', Icons.medical_services,
      'الدواء:\nالجرعة:\nمواعيد الأخذ:\n- \n\nملاحظات:\nموعد المراجعة:\n'),
  NoteTemplate('أذكار يومية', Icons.menu_book,
      'أذكار الصباح:\n- \n\nأذكار المساء:\n- \n\nورد اليوم:\n'),
  NoteTemplate('بيانات مهمة', Icons.info,
      'العنوان:\nالقيمة:\nملاحظات:\n'),
];

/// يعرض منتقي القوالب؛ عند الاختيار يُنشئ ملاحظة في «الوارد» ويفتح المحرّر.
Future<void> showTemplatePicker(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('القوالب الجاهزة',
                style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 12),
            Flexible(
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.6,
                children: [
                  for (final t in kNoteTemplates)
                    _TemplateTile(template: t),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TemplateTile extends StatelessWidget {
  final NoteTemplate template;
  const _TemplateTile({required this.template});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _useTemplate(context, template),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        child: Row(
          children: [
            Icon(template.icon, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(template.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _useTemplate(BuildContext context, NoteTemplate t) async {
    final nav = Navigator.of(context);
    final provider = context.read<NotesProvider>();
    final id = await provider.saveNote(
      Note.create(type: NoteType.text, categoryId: provider.inboxId)
          .copyWith(title: t.title, content: t.body),
    );
    nav.pop(); // إغلاق منتقي القوالب
    await nav.push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)),
    );
  }
}
