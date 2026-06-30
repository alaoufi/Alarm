import 'package:home_widget/home_widget.dart';

import '../data/models/note.dart';

/// تحديث ويدجت الشاشة الرئيسية بآخر/أهم ملاحظة.
class WidgetService {
  WidgetService._();
  static final WidgetService instance = WidgetService._();

  static const _androidProvider = 'HomeWidgetProvider';

  /// يحدّث الويدجت ليعرض الملاحظة المثبّتة (أو آخر ملاحظة).
  Future<void> update(List<Note> notes) async {
    try {
      Note? target;
      for (final n in notes) {
        if (n.isPinned) {
          target = n;
          break;
        }
      }
      target ??= notes.isNotEmpty ? notes.first : null;

      final title = target?.title.trim().isNotEmpty == true
          ? target!.title
          : 'Alerts';
      final body = target == null
          ? 'لا توجد ملاحظات بعد'
          : (target.content.trim().isNotEmpty
              ? target.content
              : (target.title.isNotEmpty ? target.title : 'ملاحظة'));

      await HomeWidget.saveWidgetData<String>('widget_title', title);
      await HomeWidget.saveWidgetData<String>('widget_note', body);
      await HomeWidget.updateWidget(
        androidName: _androidProvider,
        name: _androidProvider,
      );
    } catch (_) {
      // الويدجت اختياري؛ نتجاهل الأخطاء بصمت.
    }
  }
}
