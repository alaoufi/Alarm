import 'package:flutter/material.dart';

/// خلفية ورقية للملاحظة:
/// سادة (0) / مسطّر (1) / شبكي (2) / نقاط (3) /
/// شبكة دقيقة (4) / نقاط كبيرة (5) / أسطر متقاربة (6) / مربعات كبيرة (7).
///
/// التسطير «الاحترافي»: عند الأنماط المسطّرة (1 و6) تُرسم الأسطر بتباعد [gap]
/// المطابق لارتفاع سطر النص، فتنتظم الكتابة إمّا **على السطر** ([onLine] = true)
/// أو **بين السطرين** ([onLine] = false). كما يمكن التحكّم في [thickness]
/// (سماكة الأسطر) و[opacity] (شفافيتها).
///
/// عند تمرير [scrollController] (محرّر النص الغني) تتحرّك الأسطر **مع** الكتابة
/// وتبقى محاذيةً لها مهما طال النص، بدل أن تبقى ثابتة بينما يتحرّك الكلام.
class PaperBackground extends StatelessWidget {
  final int style;
  final Color lineColor;
  final Widget child;

  /// تباعد الأسطر المسطّرة (يُفضَّل أن يساوي ارتفاع سطر النص لمحاذاة دقيقة).
  final double gap;

  /// سماكة الخطوط.
  final double thickness;

  /// شفافية الخطوط (0..1) تُطبَّق على [lineColor].
  final double opacity;

  /// إزاحة بداية أول سطر من الأعلى (لمطابقة حشوة المحرّر).
  final double topPadding;

  /// محاذاة الكتابة على السطر (true) أو بين السطرين (false).
  final bool onLine;

  /// حجم خط المتن (يُستخدم لتقدير موضع خط الأساس عند المحاذاة على السطر).
  final double fontSize;

  /// وحدة تمرير المحرّر — عند توفّرها تُزاح الأسطر بمقدار التمرير فتتحرك مع النص.
  final ScrollController? scrollController;

  const PaperBackground({
    super.key,
    required this.style,
    required this.child,
    this.lineColor = const Color(0xFF000000),
    this.gap = 28,
    this.thickness = 1,
    this.opacity = 0.12,
    this.topPadding = 8,
    this.onLine = true,
    this.fontSize = 16,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (style == 0) return child;
    return CustomPaint(
      painter: _PaperPainter(
        style: style,
        color: lineColor.withValues(alpha: opacity.clamp(0.0, 1.0)),
        thickness: thickness,
        gap: gap,
        topPadding: topPadding,
        onLine: onLine,
        fontSize: fontSize,
        scroll: scrollController,
      ),
      child: child,
    );
  }
}

class _PaperPainter extends CustomPainter {
  final int style;
  final Color color;
  final double thickness;
  final double gap;
  final double topPadding;
  final bool onLine;
  final double fontSize;
  final ScrollController? scroll;

  _PaperPainter({
    required this.style,
    required this.color,
    required this.thickness,
    required this.gap,
    required this.topPadding,
    required this.onLine,
    required this.fontSize,
    this.scroll,
  }) : super(repaint: scroll);

  /// إزاحة التمرير الحالية للمحرّر (0 إن لم يُربط أو لم يُهيّأ بعد).
  double get _scrollOffset =>
      (scroll != null && scroll!.hasClients) ? scroll!.offset : 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;

    switch (style) {
      case 1: // مسطّر: خطوط أفقية منتظمة مع ارتفاع السطر
        _ruled(canvas, size, paint, gap);
        break;
      case 2: // شبكي: أفقي + رأسي
        for (double y = gap; y < size.height; y += gap) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        for (double x = gap; x < size.width; x += gap) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        break;
      case 3: // نقاط
        final dot = Paint()..color = color;
        for (double y = gap; y < size.height; y += gap) {
          for (double x = gap; x < size.width; x += gap) {
            canvas.drawCircle(Offset(x, y), 1.2 * thickness, dot);
          }
        }
        break;
      case 4: // شبكة دقيقة
        const g = 16.0;
        for (double y = g; y < size.height; y += g) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        for (double x = g; x < size.width; x += g) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        break;
      case 5: // نقاط كبيرة
        final dot = Paint()..color = color;
        const g = 38.0;
        for (double y = g; y < size.height; y += g) {
          for (double x = g; x < size.width; x += g) {
            canvas.drawCircle(Offset(x, y), 2.2 * thickness, dot);
          }
        }
        break;
      case 6: // أسطر متقاربة (نصف تباعد السطر)
        _ruled(canvas, size, paint, gap / 2);
        break;
      case 7: // مربعات كبيرة
        const g = 46.0;
        for (double y = g; y < size.height; y += g) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        for (double x = g; x < size.width; x += g) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        break;
    }
  }

  /// يرسم خطوطًا أفقية متباعدة بمقدار [lineGap]، محاذاةً على السطر أو بينه،
  /// ومُزاحةً بمقدار تمرير المحرّر كي تتحرّك الأسطر مع الكتابة وتبقى محاذية.
  void _ruled(Canvas canvas, Size size, Paint paint, double lineGap) {
    if (lineGap <= 0) return;
    // «على السطر»: نرفع الخط بمقدار نصف الفراغ الزائد (leading) فيلامس أسفل
    // الحروف تمامًا. «بين السطرين»: الخط عند حدّ صندوق السطر (منتصف الفراغ).
    final descent =
        onLine ? ((lineGap - fontSize) / 2).clamp(0.0, lineGap) : 0.0;
    // موضع أول حدّ سطر في إحداثيات العرض بعد طرح التمرير (الطور).
    final base = topPadding - descent - _scrollOffset;
    final start = base % lineGap; // ضمن [0, lineGap)
    for (double y = start; y < size.height; y += lineGap) {
      if (y >= 0) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PaperPainter old) =>
      old.style != style ||
      old.color != color ||
      old.thickness != thickness ||
      old.gap != gap ||
      old.topPadding != topPadding ||
      old.onLine != onLine ||
      old.fontSize != fontSize ||
      old.scroll != scroll;
}
