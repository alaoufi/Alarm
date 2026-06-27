/// سجلّ تنبيه مُنفَّذ: عنوان التنبيه ووقت تنفيذه (لحظة فوات الموعد).
class ReminderLogEntry {
  final int? id;
  final int? reminderId;
  final String title;
  final DateTime at;

  const ReminderLogEntry({
    this.id,
    this.reminderId,
    required this.title,
    required this.at,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'reminder_id': reminderId,
        'title': title,
        'at': at.millisecondsSinceEpoch,
      };

  factory ReminderLogEntry.fromMap(Map<String, dynamic> map) => ReminderLogEntry(
        id: map['id'] as int?,
        reminderId: map['reminder_id'] as int?,
        title: (map['title'] as String?) ?? 'تنبيه',
        at: DateTime.fromMillisecondsSinceEpoch((map['at'] as int?) ?? 0),
      );
}
