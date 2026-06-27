/// عنصر في قاعدة المعلومات العامة.
class InfoEntry {
  final int? id;
  final String mainSpecialty; // التخصص الرئيسي
  final String subSpecialty; // التخصص الفرعي
  final String topic; // الموضوع
  final String brief; // المختصر
  final String detail; // التفصيل
  final String notes; // ملاحظات
  final String source; // المصدر
  final DateTime createdAt; // تاريخ الإضافة

  const InfoEntry({
    this.id,
    this.mainSpecialty = '',
    this.subSpecialty = '',
    this.topic = '',
    this.brief = '',
    this.detail = '',
    this.notes = '',
    this.source = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'main_specialty': mainSpecialty,
        'sub_specialty': subSpecialty,
        'topic': topic,
        'brief': brief,
        'detail': detail,
        'notes': notes,
        'source': source,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory InfoEntry.fromMap(Map<String, dynamic> m) => InfoEntry(
        id: m['id'] as int?,
        mainSpecialty: (m['main_specialty'] as String?) ?? '',
        subSpecialty: (m['sub_specialty'] as String?) ?? '',
        topic: (m['topic'] as String?) ?? '',
        brief: (m['brief'] as String?) ?? '',
        detail: (m['detail'] as String?) ?? '',
        notes: (m['notes'] as String?) ?? '',
        source: (m['source'] as String?) ?? '',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
      );

  InfoEntry copyWith({
    int? id,
    String? mainSpecialty,
    String? subSpecialty,
    String? topic,
    String? brief,
    String? detail,
    String? notes,
    String? source,
    DateTime? createdAt,
  }) =>
      InfoEntry(
        id: id ?? this.id,
        mainSpecialty: mainSpecialty ?? this.mainSpecialty,
        subSpecialty: subSpecialty ?? this.subSpecialty,
        topic: topic ?? this.topic,
        brief: brief ?? this.brief,
        detail: detail ?? this.detail,
        notes: notes ?? this.notes,
        source: source ?? this.source,
        createdAt: createdAt ?? this.createdAt,
      );
}
