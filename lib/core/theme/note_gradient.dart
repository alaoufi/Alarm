import 'package:flutter/material.dart';

/// تدرّج لوني لخلفية الملاحظة.
///
/// يُخزَّن نصيًّا في عمود `gradient` بالصيغة: `dir:c1,c2[,c3]`
/// حيث `dir` رمز الاتجاه (0..4) و`cN` ألوان ARGB كأرقام صحيحة.
class NoteGradient {
  /// ألوان التدرّج (لونان أو ثلاثة) كقيم ARGB.
  final List<int> colors;

  /// اتجاه التدرّج:
  /// 0 = أعلى→أسفل، 1 = يمين→يسار، 2 = قُطري ↘، 3 = قُطري ↙، 4 = شعاعي.
  final int direction;

  const NoteGradient({required this.colors, this.direction = 0});

  /// أسماء الاتجاهات للعرض في الواجهة.
  static const directionNames = <String>[
    'أعلى لأسفل',
    'يمين ليسار',
    'قُطري ↘',
    'قُطري ↙',
    'شعاعي',
  ];

  String encode() => '$direction:${colors.join(',')}';

  static NoteGradient? parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final parts = raw.split(':');
      if (parts.length != 2) return null;
      final dir = int.parse(parts[0]);
      final cols = parts[1]
          .split(',')
          .where((e) => e.trim().isNotEmpty)
          .map(int.parse)
          .toList();
      if (cols.length < 2) return null;
      return NoteGradient(colors: cols, direction: dir.clamp(0, 4));
    } catch (_) {
      return null;
    }
  }

  List<Color> get _colorObjects => colors.map((c) => Color(c)).toList();

  /// يبني كائن [Gradient] لاستخدامه في [BoxDecoration].
  Gradient toGradient() {
    final cols = _colorObjects;
    switch (direction) {
      case 1:
        return LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: cols);
      case 2:
        return LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: cols);
      case 3:
        return LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: cols);
      case 4:
        return RadialGradient(radius: 1.0, colors: cols);
      case 0:
      default:
        return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: cols);
    }
  }

  /// لون نصّ مناسب (أبيض/أسود) بحسب متوسط سطوع ألوان التدرّج.
  Color get onColor {
    final avg = _colorObjects;
    double lum = 0;
    for (final c in avg) {
      lum += c.computeLuminance();
    }
    lum /= avg.length;
    return lum < 0.5 ? Colors.white : Colors.black87;
  }
}
