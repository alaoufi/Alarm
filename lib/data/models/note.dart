import 'package:uuid/uuid.dart';

import 'enums.dart';

/// نموذج الملاحظة الأساسي.
///
/// يغطّي كل أنواع الملاحظات (نص، قائمة مهام، صورة، صوت، PDF، رسم).
/// المرفقات تُخزَّن كمسارات ملفات داخل مجلد التطبيق الخاص.
class Note {
  final int? id;

  /// معرّف عالمي ثابت عبر الأجهزة (للمزامنة السحابية والدمج «آخر تعديل يفوز»).
  final String uuid;
  final String title;
  final String content;
  final NoteType type;

  /// لون البطاقة (قيمة ARGB int). null يعني اللون الافتراضي.
  final int? color;

  final bool isPinned;
  final bool isFavorite;
  final bool isArchived;
  final bool isLocked;

  /// عند الحذف ننقل الملاحظة إلى سلة المحذوفات بدل الحذف النهائي.
  final bool isDeleted;
  final DateTime? deletedAt;

  final int? categoryId;

  // مسارات المرفقات داخل الجهاز.
  final String? imagePath;
  final String? audioPath;
  final String? pdfPath;
  final String? drawingPath;

  /// نمط خلفية الصفحة: 0=سادة، 1=مسطّر، 2=شبكي، 3=نقاط.
  final int bgStyle;

  /// تدرّج لوني للخلفية (مُرمَّز نصيًّا). null يعني لون سادة.
  final String? gradient;

  // ---- تسطير خاص بهذه الملاحظة (null = استخدام الافتراضي العام) ----
  /// محاذاة الكتابة على السطر (true) أو بين السطرين (false).
  final bool? ruleOnLine;

  /// سماكة أسطر التسطير.
  final double? ruleThickness;

  /// شفافية أسطر التسطير (0..1).
  final double? ruleOpacity;

  /// تباعد أسطر التسطير (مضاعف ارتفاع السطر؛ يضبط تباعد الكتابة والأسطر معًا).
  final double? ruleLineHeight;

  final DateTime createdAt;
  final DateTime updatedAt;

  // تُحمَّل من جداول مرتبطة (ليست أعمدة في جدول الملاحظات).
  final List<String> tags;

  const Note({
    this.id,
    this.uuid = '',
    this.title = '',
    this.content = '',
    this.type = NoteType.text,
    this.color,
    this.isPinned = false,
    this.isFavorite = false,
    this.isArchived = false,
    this.isLocked = false,
    this.isDeleted = false,
    this.deletedAt,
    this.categoryId,
    this.imagePath,
    this.audioPath,
    this.pdfPath,
    this.drawingPath,
    this.bgStyle = 0,
    this.gradient,
    this.ruleOnLine,
    this.ruleThickness,
    this.ruleOpacity,
    this.ruleLineHeight,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
  });

  factory Note.create({NoteType type = NoteType.text, int? categoryId}) {
    final now = DateTime.now();
    return Note(
      uuid: const Uuid().v4(),
      type: type,
      categoryId: categoryId,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool get isEmpty =>
      title.trim().isEmpty &&
      content.trim().isEmpty &&
      imagePath == null &&
      audioPath == null &&
      pdfPath == null &&
      drawingPath == null;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'uuid': uuid.isEmpty ? const Uuid().v4() : uuid,
      'title': title,
      'content': content,
      'type': type.dbValue,
      'color': color,
      'is_pinned': isPinned ? 1 : 0,
      'is_favorite': isFavorite ? 1 : 0,
      'is_archived': isArchived ? 1 : 0,
      'is_locked': isLocked ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
      'category_id': categoryId,
      'image_path': imagePath,
      'audio_path': audioPath,
      'pdf_path': pdfPath,
      'drawing_path': drawingPath,
      'bg_style': bgStyle,
      'gradient': gradient,
      'rule_on_line': ruleOnLine == null ? null : (ruleOnLine! ? 1 : 0),
      'rule_thickness': ruleThickness,
      'rule_opacity': ruleOpacity,
      'rule_line_height': ruleLineHeight,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map, {List<String> tags = const []}) {
    return Note(
      id: map['id'] as int?,
      uuid: (map['uuid'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
      type: NoteTypeX.fromDb(map['type'] as String?),
      color: map['color'] as int?,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      isLocked: (map['is_locked'] as int? ?? 0) == 1,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      deletedAt: map['deleted_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['deleted_at'] as int)
          : null,
      categoryId: map['category_id'] as int?,
      imagePath: map['image_path'] as String?,
      audioPath: map['audio_path'] as String?,
      pdfPath: map['pdf_path'] as String?,
      drawingPath: map['drawing_path'] as String?,
      bgStyle: (map['bg_style'] as int?) ?? 0,
      gradient: map['gradient'] as String?,
      ruleOnLine:
          map['rule_on_line'] == null ? null : (map['rule_on_line'] as int) == 1,
      ruleThickness: (map['rule_thickness'] as num?)?.toDouble(),
      ruleOpacity: (map['rule_opacity'] as num?)?.toDouble(),
      ruleLineHeight: (map['rule_line_height'] as num?)?.toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      tags: tags,
    );
  }

  Note copyWith({
    int? id,
    String? uuid,
    String? title,
    String? content,
    NoteType? type,
    int? color,
    bool clearColor = false,
    bool? isPinned,
    bool? isFavorite,
    bool? isArchived,
    bool? isLocked,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    int? categoryId,
    bool clearCategory = false,
    String? imagePath,
    String? audioPath,
    String? pdfPath,
    String? drawingPath,
    int? bgStyle,
    String? gradient,
    bool clearGradient = false,
    bool? ruleOnLine,
    double? ruleThickness,
    double? ruleOpacity,
    double? ruleLineHeight,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
  }) {
    return Note(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      color: clearColor ? null : (color ?? this.color),
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
      isLocked: isLocked ?? this.isLocked,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      imagePath: imagePath ?? this.imagePath,
      audioPath: audioPath ?? this.audioPath,
      pdfPath: pdfPath ?? this.pdfPath,
      drawingPath: drawingPath ?? this.drawingPath,
      bgStyle: bgStyle ?? this.bgStyle,
      gradient: clearGradient ? null : (gradient ?? this.gradient),
      ruleOnLine: ruleOnLine ?? this.ruleOnLine,
      ruleThickness: ruleThickness ?? this.ruleThickness,
      ruleOpacity: ruleOpacity ?? this.ruleOpacity,
      ruleLineHeight: ruleLineHeight ?? this.ruleLineHeight,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
    );
  }
}
