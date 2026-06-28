import 'package:flutter/material.dart';

/// لوحة ألوان التطبيق وهويته البصرية الخاصة (مختلفة عن أي تطبيق آخر).
class AppColors {
  AppColors._();

  /// ألوان السمة (Theme) المتاحة للاختيار من الإعدادات — تدرّجات هادئة وأنيقة
  /// يشتقّ منها النظام درجات فاتحة للخلفيات وداكنة للوضع الليلي.
  static const Map<String, Color> themeSeeds = {
    'أخضر زمردي': Color(0xFF2E7D6B),
    'أزرق هادئ': Color(0xFF3F6FB5),
    'بنفسجي': Color(0xFF7E57C2),
    'برتقالي دافئ': Color(0xFFE8772E),
    'وردي': Color(0xFFC2476B),
    'رمادي أنيق': Color(0xFF546E7A),
    // تدرّجات إضافية ناعمة وجميلة.
    'فيروزي': Color(0xFF159A8C),
    'سماوي': Color(0xFF3FA7DD),
    'نيليّ': Color(0xFF5C6BC0),
    'خزاميّ': Color(0xFF9B6FD0),
    'مرجانيّ': Color(0xFFEF6C57),
    'كهرمانيّ': Color(0xFFD4A12A),
    'برقوقيّ': Color(0xFF995C82),
    'نعناعيّ': Color(0xFF3DB389),
    'أزرق بترولي': Color(0xFF2D7C8A),
    'زهريّ': Color(0xFFE389AC),
    'تُوتيّ': Color(0xFF8E5BA6),
    'عنّابيّ': Color(0xFFB14A57),
  };

  static const Color defaultSeed = Color(0xFF2E7D6B);

  /// ألوان بطاقات الملاحظات (هادئة ومريحة للعين، نهارية) — مع تدرّجات.
  static const List<Color> noteColorsLight = [
    Color(0xFFFFFFFF), // أبيض (افتراضي)
    Color(0xFFFFF9C4), // أصفر فاتح جدًا
    Color(0xFFFFF1B8), // أصفر
    Color(0xFFFCE49E), // أصفر دافئ (مرجعي)
    Color(0xFFFFE0B2), // برتقالي فاتح
    Color(0xFFFFD9C7), // مشمشي
    Color(0xFFFFCCBC), // مرجاني فاتح
    Color(0xFFFFCDD2), // وردي
    Color(0xFFF8BBD0), // وردي مزهر
    Color(0xFFE1BEE7), // بنفسجي فاتح
    Color(0xFFD1C4E9), // بنفسجي مزرق
    Color(0xFFC5CAE9), // أزرق بنفسجي
    Color(0xFFBBDEFB), // أزرق فاتح
    Color(0xFFB3E5FC), // أزرق سماوي
    Color(0xFFB2EBF2), // سماوي مخضر
    Color(0xFFB2DFDB), // فيروزي فاتح
    Color(0xFFC8E6C9), // أخضر فاتح
    Color(0xFFDCEDC8), // أخضر ليموني
    Color(0xFFF0F4C3), // ليموني
    Color(0xFFD7CCC8), // بيج
    Color(0xFFCFD8DC), // رمادي مزرق
  ];

  /// نسخ داكنة من نفس الألوان للوضع الليلي.
  static const List<Color> noteColorsDark = [
    Color(0xFF2A2A2E), // رمادي داكن (افتراضي)
    Color(0xFF45431B), // أصفر فاتح جدًا داكن
    Color(0xFF4A431F), // أصفر داكن
    Color(0xFF4D451F), // أصفر دافئ داكن (مرجعي)
    Color(0xFF49381F), // برتقالي داكن
    Color(0xFF4A2E20), // مشمشي داكن
    Color(0xFF492A1F), // مرجاني داكن
    Color(0xFF4A2226), // وردي داكن
    Color(0xFF45202F), // وردي مزهر داكن
    Color(0xFF3A2540), // بنفسجي داكن
    Color(0xFF322945), // بنفسجي مزرق داكن
    Color(0xFF272A45), // أزرق بنفسجي داكن
    Color(0xFF1B2F45), // أزرق داكن
    Color(0xFF173947), // أزرق سماوي داكن
    Color(0xFF15383D), // سماوي مخضر داكن
    Color(0xFF173A36), // فيروزي داكن
    Color(0xFF1F3A22), // أخضر داكن
    Color(0xFF273A1E), // أخضر ليموني داكن
    Color(0xFF383F1C), // ليموني داكن
    Color(0xFF332B26), // بيج داكن
    Color(0xFF2A3338), // رمادي مزرق داكن
  ];

  /// يحوّل لون بطاقة (نهاري) إلى ما يناسب الوضع الحالي.
  static Color resolveNoteColor(int? stored, bool isDark) {
    if (stored == null) {
      return isDark ? noteColorsDark.first : noteColorsLight.first;
    }
    final index = noteColorsLight.indexWhere((c) => c.value == stored);
    if (index == -1) {
      return Color(stored);
    }
    return isDark ? noteColorsDark[index] : noteColorsLight[index];
  }
}
