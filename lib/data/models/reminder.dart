import 'enums.dart';

/// تذكير — قد يكون مرتبطًا بملاحظة ([noteId]) أو مستقلًّا بعنوان حرّ ([title]).
class Reminder {
  final int? id;
  final int? noteId; // null ⇒ تنبيه مستقلّ غير مرتبط بملاحظة
  final String? title; // عنوان التنبيه المستقلّ
  final DateTime time;
  final ReminderRepeat repeat;
  final bool isActive;

  /// مستوى الأهمية (يحدّد سلوك التنبيه: صوت/اهتزاز/شاشة كاملة/إصرار).
  final ReminderImportance importance;

  /// تنبيهات مسبقة قبل الموعد (بالدقائق): مثل [5, 15, 60, 1440].
  final List<int> preAlerts;

  /// موقع التذكير (رابط خرائط جوجل) — للمواعيد. فارغ = بلا موقع.
  final String location;

  /// مرفق الدعوة (صورة أو PDF) — للمواعيد. مسار ملف داخل التطبيق، أو فارغ.
  final String attachmentPath;

  /// معرّف الإشعار في flutter_local_notifications (لإلغائه لاحقًا).
  final int notificationId;

  /// **دواء**: فاصل الأيام بين الجرعات (≥ 2 ⇒ «كل N يوم»). 0 = تكرار عاديّ.
  final int intervalDays;

  /// **دواء**: عدد جرعات الكورس (> 0 ⇒ يتوقّف بعدها). 0 = مستمر.
  final int doseCount;

  /// لون اختياريّ للتنبيه (قيمة ARGB) — null = اللون التلقائيّ حسب المجال الزمنيّ.
  final int? color;

  const Reminder({
    this.id,
    this.noteId,
    this.title,
    required this.time,
    this.repeat = ReminderRepeat.once,
    this.isActive = true,
    this.importance = ReminderImportance.high,
    this.preAlerts = const [],
    this.location = '',
    this.attachmentPath = '',
    required this.notificationId,
    this.intervalDays = 0,
    this.doseCount = 0,
    this.color,
  });

  /// تنبيه مستقلّ (غير مرتبط بملاحظة).
  bool get isStandalone => noteId == null;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'note_id': noteId,
      'title': title,
      'time': time.millisecondsSinceEpoch,
      'repeat': repeat.dbValue,
      'is_active': isActive ? 1 : 0,
      'notification_id': notificationId,
      'importance': importance.dbValue,
      'pre_alerts': preAlerts.join(','),
      'location': location,
      'attachment': attachmentPath,
      'interval_days': intervalDays,
      'dose_count': doseCount,
      'color': color,
    };
  }

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'] as int?,
      noteId: map['note_id'] as int?,
      title: map['title'] as String?,
      time: DateTime.fromMillisecondsSinceEpoch(map['time'] as int),
      repeat: ReminderRepeatX.fromDb(map['repeat'] as String?),
      isActive: (map['is_active'] as int? ?? 1) == 1,
      notificationId: map['notification_id'] as int,
      importance: ReminderImportanceX.fromDb(map['importance'] as String?),
      preAlerts: ((map['pre_alerts'] as String?) ?? '')
          .split(',')
          .map((e) => int.tryParse(e.trim()) ?? -1)
          .where((e) => e > 0)
          .toList(),
      location: (map['location'] as String?) ?? '',
      attachmentPath: (map['attachment'] as String?) ?? '',
      intervalDays: (map['interval_days'] as int?) ?? 0,
      doseCount: (map['dose_count'] as int?) ?? 0,
      color: map['color'] as int?,
    );
  }

  Reminder copyWith({
    int? id,
    int? noteId,
    String? title,
    DateTime? time,
    ReminderRepeat? repeat,
    bool? isActive,
    ReminderImportance? importance,
    List<int>? preAlerts,
    String? location,
    String? attachmentPath,
    int? notificationId,
    int? intervalDays,
    int? doseCount,
    int? color,
  }) {
    return Reminder(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      title: title ?? this.title,
      time: time ?? this.time,
      repeat: repeat ?? this.repeat,
      isActive: isActive ?? this.isActive,
      importance: importance ?? this.importance,
      preAlerts: preAlerts ?? this.preAlerts,
      location: location ?? this.location,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      notificationId: notificationId ?? this.notificationId,
      intervalDays: intervalDays ?? this.intervalDays,
      doseCount: doseCount ?? this.doseCount,
      color: color ?? this.color,
    );
  }
}
