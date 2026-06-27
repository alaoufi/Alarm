/// أنواع الملاحظات المدعومة في التطبيق.
enum NoteType {
  text, // ملاحظة نصية
  checklist, // قائمة مهام
  image, // ملاحظة بصورة
  audio, // ملاحظة صوتية
  pdf, // ملاحظة مع ملف PDF
  drawing, // رسم / كتابة يدوية
  password, // ملاحظة كلمات مرور (حقول منظمة، كلمة المرور مشفّرة)
}

extension NoteTypeX on NoteType {
  String get dbValue => name;

  static NoteType fromDb(String? value) {
    return NoteType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => NoteType.text,
    );
  }
}

/// تكرار التذكير.
enum ReminderRepeat {
  once, // مرة واحدة
  daily, // يومي
  weekly, // أسبوعي
  monthly, // شهري
  yearly, // سنوي (ميلادي)
  hijriYearly, // سنوي هجري (مناسبات: نفس اليوم/الشهر الهجريين كل عام)
}

extension ReminderRepeatX on ReminderRepeat {
  String get dbValue => name;

  static ReminderRepeat fromDb(String? value) {
    return ReminderRepeat.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ReminderRepeat.once,
    );
  }
}

/// مستوى أهمية التذكير — يحدّد سلوك التنبيه (صوت/اهتزاز/شاشة كاملة/إصرار).
enum ReminderImportance {
  low, // إشعار عادي (بلا صوت)
  medium, // إشعار + صوت
  high, // إشعار + صوت + اهتزاز
  critical, // منبّه حقيقي: شاشة كاملة + إصرار حتى التفاعل
}

extension ReminderImportanceX on ReminderImportance {
  String get dbValue => name;

  static ReminderImportance fromDb(String? value) {
    return ReminderImportance.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ReminderImportance.high,
    );
  }
}

/// طريقة عرض الملاحظات في الصفحة الرئيسية.
enum NoteLayout { grid, list }

/// طرق فرز الملاحظات في القائمة.
enum NoteSort { updatedDesc, createdDesc, createdAsc, titleAsc }
