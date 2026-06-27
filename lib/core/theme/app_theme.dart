import 'package:flutter/material.dart';

/// يبني سمات التطبيق (نهاري/ليلي) انطلاقًا من لون أساسي وحجم خط.
class AppTheme {
  AppTheme._();

  static ThemeData light(Color seed, double fontScale,
          [String fontFamily = 'Cairo', ColorScheme? dynamicScheme]) =>
      _build(seed, Brightness.light, fontScale, fontFamily, dynamicScheme);

  static ThemeData dark(Color seed, double fontScale,
          [String fontFamily = 'Cairo', ColorScheme? dynamicScheme]) =>
      _build(seed, Brightness.dark, fontScale, fontFamily, dynamicScheme);

  static ThemeData _build(
      Color seed, Brightness brightness, double fontScale, String fontFamily,
      [ColorScheme? dynamicScheme]) {
    // عند تفعيل «ألوان النظام» نستعمل لوحة الجهاز (أندرويد 12+)؛ وإلا نشتقّ من
    // لون البذرة — مع ضمان مطابقة السطوع (نهاري/ليلي).
    final scheme =
        (dynamicScheme != null && dynamicScheme.brightness == brightness)
            ? dynamicScheme
            : ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final isDark = brightness == Brightness.dark;

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF121214) : const Color(0xFFF6F7F9),
      brightness: brightness,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: base.scaffoldBackgroundColor,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        // ارتفاع/ظلّ خفيف عند التمرير ⇒ إحساس طبقيّ عصري في كل الشاشات.
        scrolledUnderElevation: 3,
        surfaceTintColor: scheme.surfaceTint,
        shadowColor: scheme.shadow,
        centerTitle: false,
        // أيقونات الشريط العلوي (⋮ القائمة و≡ والباقي) أوضح وأغمق وأثخن.
        iconTheme: IconThemeData(
          color: scheme.onSurface,
          size: 28,
          weight: 700,
        ),
        actionsIconTheme: IconThemeData(
          color: scheme.onSurface,
          size: 28,
          weight: 700,
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.bold,
          fontSize: 22 * fontScale,
          color: scheme.onSurface,
        ),
      ),
      // بطاقات بارزة (ثلاثية الأبعاد) موحّدة في كل الشاشات.
      cardTheme: CardThemeData(
        elevation: 3,
        shadowColor: scheme.shadow.withOpacity(0.4),
        surfaceTintColor: scheme.surfaceTint,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
      ),
      // مجموعات قابلة للطيّ نظيفة (بلا خطوط حادّة) في كل الشاشات.
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
        childrenPadding: EdgeInsetsDirectional.only(start: 8, bottom: 8),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        side: BorderSide.none,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: _scaleTextTheme(base.textTheme, fontScale),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      // انتقالات سلسة موحّدة بين الشاشات (تلاشٍ + انزلاق خفيف من الأسفل) على كل
      // المنصّات بدل القفزة الافتراضية.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SharedAxisLikeTransitionBuilder(),
          TargetPlatform.iOS: _SharedAxisLikeTransitionBuilder(),
        },
      ),
    );
  }

  static TextTheme _scaleTextTheme(TextTheme t, double s) {
    TextStyle? sc(TextStyle? style) => style == null
        ? null
        : style.copyWith(fontSize: (style.fontSize ?? 14) * s);
    return t.copyWith(
      displayLarge: sc(t.displayLarge),
      displayMedium: sc(t.displayMedium),
      displaySmall: sc(t.displaySmall),
      headlineLarge: sc(t.headlineLarge),
      headlineMedium: sc(t.headlineMedium),
      headlineSmall: sc(t.headlineSmall),
      titleLarge: sc(t.titleLarge),
      titleMedium: sc(t.titleMedium),
      titleSmall: sc(t.titleSmall),
      bodyLarge: sc(t.bodyLarge),
      bodyMedium: sc(t.bodyMedium),
      bodySmall: sc(t.bodySmall),
      labelLarge: sc(t.labelLarge),
      labelMedium: sc(t.labelMedium),
      labelSmall: sc(t.labelSmall),
    );
  }
}

/// انتقال صفحات هادئ: تلاشٍ مع انزلاق رأسيّ خفيف للصفحة الداخلة (مستوحى من
/// Material shared-axis) — أنعم من القفزة الافتراضية ودون مكتبة خارجية.
class _SharedAxisLikeTransitionBuilder extends PageTransitionsBuilder {
  const _SharedAxisLikeTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
