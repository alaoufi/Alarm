import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import '../../data/models/note.dart';
import '../../data/models/reminder.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/reminder_repository.dart';
import '../../services/file_service.dart';
import '../../services/notification_service.dart';

/// عنصر عرض يجمع التذكير مع ملاحظته.
class ReminderView {
  final Reminder reminder;
  final Note? note;
  const ReminderView(this.reminder, this.note);
}

class RemindersProvider extends ChangeNotifier {
  final ReminderRepository _repo;
  final NoteRepository _notes;

  RemindersProvider(this._repo, this._notes);

  List<ReminderView> _items = [];
  List<ReminderView> get items => _items;

  /// إعادة جدولة ذاتية عند فتح التطبيق: تضمن أن كل تذكير نشط ما زال مجدولًا في
  /// النظام (تُعيد جدولة ما قد يكون أُسقط بسبب تقييد البطارية/إيقاف التطبيق).
  /// آمنة وعديمة الأثر الجانبيّ (نفس المعرّف يَستبدل الجدولة القائمة).
  Future<void> ensureScheduled() async {
    try {
      final all = await _repo.getAll();
      final now = DateTime.now();
      for (final r in all) {
        if (!r.isActive) continue;
        // تذكيرات «مرّة واحدة» الفائتة لا يُعاد جدولتها (انتهت).
        if (r.repeat == ReminderRepeat.once && r.time.isBefore(now)) continue;
        String title = r.title ?? 'تذكير';
        String body = '';
        if (r.noteId != null) {
          final note = await _notes.getNote(r.noteId!);
          if (note == null || note.isDeleted) continue;
          if (note.title.trim().isNotEmpty) title = note.title;
          body = note.content;
        }
        await NotificationService.instance.schedule(r, title, body);
      }
    } catch (_) {
      // لا يجب أن تُعطّل بدء التطبيق.
    }
  }

  Future<void> refresh() async {
    final reminders = await _repo.getAll();
    final views = <ReminderView>[];
    for (final r in reminders) {
      if (r.isStandalone) {
        // تنبيه مستقلّ (بلا ملاحظة) — يُعرض دائمًا.
        views.add(ReminderView(r, null));
        continue;
      }
      final note = await _notes.getNote(r.noteId!);
      // نتجاهل تذكيرات الملاحظات المحذوفة نهائيًا.
      if (note != null && !note.isDeleted) {
        views.add(ReminderView(r, note));
      }
    }
    _items = views;
    notifyListeners();
  }

  /// إنشاء/تحديث تنبيه مستقلّ (غير مرتبط بملاحظة) بعنوان حرّ.
  Future<void> setStandalone(
    DateTime time,
    ReminderRepeat repeat,
    String title, {
    ReminderImportance importance = ReminderImportance.high,
    List<int> preAlerts = const [],
    String location = '',
    String attachmentPath = '',
    int intervalDays = 0,
    int doseCount = 0,
    int? color,
    Reminder? existing,
  }) async {
    if (existing != null) {
      await NotificationService.instance.cancel(existing.notificationId);
      await _repo.delete(existing.id!);
    }
    final notifId = _uniqueId(await _existingIds());
    final reminder = Reminder(
      title: title.trim().isEmpty ? 'تنبيه' : title.trim(),
      time: time,
      repeat: repeat,
      importance: importance,
      preAlerts: preAlerts,
      location: location,
      attachmentPath: attachmentPath,
      notificationId: notifId,
      intervalDays: intervalDays,
      doseCount: doseCount,
      color: color,
    );
    final id = await _repo.insert(reminder);
    await NotificationService.instance.schedule(
      reminder.copyWith(id: id),
      reminder.title!,
      '',
    );
    await refresh();
  }

  Future<Reminder?> getForNote(int noteId) => _repo.getForNote(noteId);
  Future<List<Reminder>> getAllForNote(int noteId) =>
      _repo.getAllForNote(noteId);

  /// تذكير أسبوعي لملاحظة على **أيام محدّدة**: يُلغي تذكيرات الملاحظة السابقة،
  /// ثم يُنشئ تذكيرًا أسبوعيًّا لكل يوم مختار. [weekdays] بقيم DateTime.weekday.
  Future<void> setNoteWeekly(
    Note note,
    TimeOfDay tod,
    Set<int> weekdays, {
    ReminderImportance importance = ReminderImportance.high,
  }) async {
    // إلغاء وحذف كل تذكيرات الملاحظة الحالية.
    final existing = await _repo.getAllForNote(note.id!);
    for (final r in existing) {
      await NotificationService.instance.cancel(r.notificationId);
    }
    await _repo.deleteForNote(note.id!);

    final taken = await _existingIds();
    final title = note.title.trim().isEmpty ? 'تذكير' : note.title.trim();
    for (final wd in weekdays) {
      final when = _nextWeekday(wd, tod);
      final reminder = Reminder(
        noteId: note.id!,
        time: when,
        repeat: ReminderRepeat.weekly,
        importance: importance,
        notificationId: _uniqueId(taken),
      );
      final id = await _repo.insert(reminder);
      await NotificationService.instance
          .schedule(reminder.copyWith(id: id), title, note.content);
    }
    await refresh();
  }

  /// تعيين (أو تحديث) تذكير لملاحظة وجدولته كإشعار محلي.
  Future<void> setReminder(
    Note note,
    DateTime time,
    ReminderRepeat repeat, {
    ReminderImportance importance = ReminderImportance.high,
    List<int> preAlerts = const [],
  }) async {
    // إلغاء القديم إن وُجد.
    final existing = await _repo.getForNote(note.id!);
    if (existing != null) {
      await NotificationService.instance.cancel(existing.notificationId);
      await _repo.delete(existing.id!);
    }

    final notifId = _uniqueId(await _existingIds());
    final reminder = Reminder(
      noteId: note.id!,
      time: time,
      repeat: repeat,
      importance: importance,
      preAlerts: preAlerts,
      notificationId: notifId,
    );
    final id = await _repo.insert(reminder);
    await NotificationService.instance.schedule(
      reminder.copyWith(id: id),
      note.title.isNotEmpty ? note.title : 'تذكير',
      note.content,
    );
    await refresh();
  }

  /// تنبيه أسبوعي على **أيام محدّدة**: يُنشئ تذكيرًا أسبوعيًّا لكل يوم مختار
  /// عند أقرب وقوع له بالوقت المطلوب. [weekdays] بقيم DateTime.weekday (1..7).
  Future<void> setStandaloneWeekly(
    String title,
    TimeOfDay tod,
    Set<int> weekdays, {
    ReminderImportance importance = ReminderImportance.high,
    int? color,
    Reminder? existing,
  }) async {
    if (existing != null) {
      await NotificationService.instance.cancel(existing.notificationId);
      await _repo.delete(existing.id!);
    }
    final name = title.trim().isEmpty ? 'تنبيه' : title.trim();
    final taken = await _existingIds();
    for (final wd in weekdays) {
      final when = _nextWeekday(wd, tod);
      final reminder = Reminder(
        title: name,
        time: when,
        repeat: ReminderRepeat.weekly,
        importance: importance,
        notificationId: _uniqueId(taken),
        color: color,
      );
      final id = await _repo.insert(reminder);
      await NotificationService.instance
          .schedule(reminder.copyWith(id: id), name, '');
    }
    await refresh();
  }

  /// أقرب تاريخ مستقبلي ليومٍ من الأسبوع [weekday] عند الوقت [tod].
  DateTime _nextWeekday(int weekday, TimeOfDay tod) {
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    while (d.weekday != weekday || !d.isAfter(now)) {
      d = DateTime(d.year, d.month, d.day + 1, tod.hour, tod.minute);
    }
    return d;
  }

  /// تفعيل/إيقاف منبّه دون حذفه (يجدول الإشعار أو يلغيه).
  Future<void> setActive(ReminderView v, bool active) async {
    final r = v.reminder;
    // تنبيه «مرّة واحدة» فات وقته لا يمكن جدولته (وقت ماضٍ ⇒ تُرمى استثناء).
    // نتخطّى الجدولة لكن نحفظ الحالة دائمًا كي يعمل المفتاح بلا تعطّل.
    final isPastOnce =
        r.repeat == ReminderRepeat.once && r.time.isBefore(DateTime.now());
    if (active) {
      if (!isPastOnce) {
        final title = r.isStandalone
            ? (r.title ?? 'تنبيه')
            : (v.note?.title.isNotEmpty == true ? v.note!.title : 'تذكير');
        final body = r.isStandalone ? '' : (v.note?.content ?? '');
        try {
          await NotificationService.instance
              .schedule(r.copyWith(isActive: true), title, body);
        } catch (_) {/* لا تمنع حفظ الحالة عند تعذّر الجدولة */}
      }
    } else {
      await NotificationService.instance.cancel(r.notificationId);
    }
    await _repo.update(r.copyWith(isActive: active));
    await refresh();
  }

  String _titleFor(ReminderView v) => v.reminder.isStandalone
      ? (v.reminder.title?.isNotEmpty == true ? v.reminder.title! : 'تنبيه')
      : (v.note?.title.isNotEmpty == true ? v.note!.title : 'تذكير');

  String _bodyFor(ReminderView v) =>
      v.reminder.isStandalone ? '' : (v.note?.content ?? '');

  /// تأجيل تنبيه إلى وقت جديد (يعيد جدولته بنفس المعرّف ويُعيد تفعيله).
  Future<void> postpone(ReminderView v, DateTime newTime) async {
    final r = v.reminder;
    await NotificationService.instance.cancel(r.notificationId);
    final updated = r.copyWith(time: newTime, isActive: true);
    await _repo.update(updated);
    await NotificationService.instance
        .schedule(updated, _titleFor(v), _bodyFor(v));
    await refresh();
  }

  /// نسخ تنبيه (إنشاء نسخة مطابقة بمعرّف إشعار جديد). لا تُنسخ المرفقات لتفادي
  /// مشاركة ملفّ واحد بين تنبيهين (حذف أحدهما قد يحذف ملفّ الآخر).
  Future<void> duplicate(ReminderView v) async {
    final r = v.reminder;
    final notifId = _uniqueId(await _existingIds());
    final copy = Reminder(
      noteId: r.noteId,
      title: r.title,
      time: r.time,
      repeat: r.repeat,
      importance: r.importance,
      preAlerts: r.preAlerts,
      location: r.location,
      attachmentPath: '',
      notificationId: notifId,
      intervalDays: r.intervalDays,
      doseCount: r.doseCount,
      color: r.color,
    );
    final id = await _repo.insert(copy);
    await NotificationService.instance
        .schedule(copy.copyWith(id: id), _titleFor(v), _bodyFor(v));
    await refresh();
  }

  Future<void> removeReminder(Reminder reminder) async {
    await NotificationService.instance.cancel(reminder.notificationId);
    // احذف مرفق الدعوة المرتبط (إن وُجد) من القرص.
    if (reminder.attachmentPath.isNotEmpty) {
      await FileService.instance.deleteIfExists(reminder.attachmentPath);
    }
    await _repo.delete(reminder.id!);
    await refresh();
  }

  /// تطبيق «التنبيهات فقط»: يحوّل تنبيهات الملاحظات إلى تنبيهات مستقلّة (بحفظ
  /// عنوان الملاحظة كعنوان للتنبيه) ثم يحذف كل الملاحظات. لا يُفقد أي تنبيه.
  /// يعيد عدد الملاحظات المحذوفة.
  Future<int> detachAndPurgeNotes() async {
    final all = await _repo.getAll();
    for (final r in all) {
      if (r.noteId == null) continue;
      final note = await _notes.getNote(r.noteId!);
      var t = (note?.title.trim().isNotEmpty == true)
          ? note!.title.trim()
          : (note?.content.trim().isNotEmpty == true
              ? note!.content.trim()
              : 'تنبيه');
      if (t.length > 80) t = t.substring(0, 80);
      // إعادة بناء التنبيه مستقلًّا (copyWith لا يستطيع تصفير note_id).
      final detached = Reminder(
        id: r.id,
        noteId: null,
        title: t,
        time: r.time,
        repeat: r.repeat,
        isActive: r.isActive,
        importance: r.importance,
        preAlerts: r.preAlerts,
        location: r.location,
        attachmentPath: r.attachmentPath,
        notificationId: r.notificationId,
        intervalDays: r.intervalDays,
        doseCount: r.doseCount,
        color: r.color,
      );
      await _repo.update(detached);
    }
    final removed = await _notes.deleteAllNotes();
    await refresh();
    return removed;
  }

  Future<void> removeForNote(int noteId) async {
    final all = await _repo.getAllForNote(noteId);
    if (all.isEmpty) return;
    for (final r in all) {
      await NotificationService.instance.cancel(r.notificationId);
    }
    await _repo.deleteForNote(noteId);
    await refresh();
  }

  // نطاق مضغوط (<2^26) كي تبقى معرّفات «عدم النسيان»/التنبيهات المسبقة
  // (base + k·2^26) ضمن 32-بت. **مضمون عدم التصادم**: نتجنّب أي معرّف مستعمَل
  // مسبقًا (يمنع ضياع تذكير بسبب تطابق نادر للأرقام العشوائية).
  Future<Set<int>> _existingIds() async {
    final all = await _repo.getAll();
    return all.map((r) => r.notificationId).toSet();
  }

  int _uniqueId(Set<int> taken) {
    int id;
    do {
      id = Random().nextInt(1 << 26) + 1;
    } while (taken.contains(id));
    taken.add(id);
    return id;
  }
}
