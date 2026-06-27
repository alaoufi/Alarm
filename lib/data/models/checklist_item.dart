/// عنصر في قائمة مهام (Checklist) مرتبط بملاحظة.
class ChecklistItem {
  final int? id;
  final int noteId;
  final String text;
  final bool isDone;
  final int position;

  /// true = سطر مهمة (بمربع اختيار)، false = سطر نصّ عادي (بلا مربع).
  final bool isTask;

  const ChecklistItem({
    this.id,
    required this.noteId,
    required this.text,
    this.isDone = false,
    this.position = 0,
    this.isTask = true,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'note_id': noteId,
      'text': text,
      'is_done': isDone ? 1 : 0,
      'position': position,
      'is_task': isTask ? 1 : 0,
    };
  }

  factory ChecklistItem.fromMap(Map<String, dynamic> map) {
    return ChecklistItem(
      id: map['id'] as int?,
      noteId: map['note_id'] as int,
      text: (map['text'] as String?) ?? '',
      isDone: (map['is_done'] as int? ?? 0) == 1,
      position: map['position'] as int? ?? 0,
      isTask: (map['is_task'] as int? ?? 1) == 1,
    );
  }

  ChecklistItem copyWith({
    int? id,
    int? noteId,
    String? text,
    bool? isDone,
    int? position,
    bool? isTask,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      text: text ?? this.text,
      isDone: isDone ?? this.isDone,
      position: position ?? this.position,
      isTask: isTask ?? this.isTask,
    );
  }
}
