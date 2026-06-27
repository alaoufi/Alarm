import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/file_service.dart';
import '../../widgets/confirm_dialog.dart';

/// نوع الفرشاة — يحدّد الشفافية والعرض وشكل النهاية.
enum _Brush { pen, marker, highlighter, pencil }

/// خطّ واحد — يحتفظ **بلونه وسماكته وشكله الخاصّ** (تحكّم مستقلّ لكل خط).
class _Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final StrokeCap cap;
  _Stroke(this.points, this.color, this.width, this.cap);
}

/// لوحة رسم احترافية: أنواع فرش (قلم/ماركر/فسفوري/رصاص)، منتقي ألوان احترافي
/// (عجلة + شفافية)، ممحاة، لون وسماكة لكل خط. تعيد مسار صورة PNG عند الحفظ.
class DrawingScreen extends StatefulWidget {
  final String? existingPath;
  const DrawingScreen({super.key, this.existingPath});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  final _canvasKey = GlobalKey();
  final List<_Stroke> _strokes = [];
  _Stroke? _current;

  Color _penColor = Colors.black;
  double _penWidth = 4;
  _Brush _brush = _Brush.pen;
  bool _eraser = false;
  ui.Image? _bgImage; // الرسم السابق (عند التعديل) كخلفية.

  static const _palette = [
    Colors.black,
    Color(0xFF455A64),
    Color(0xFFE53935),
    Color(0xFFD81B60),
    Color(0xFF8E24AA),
    Color(0xFF3949AB),
    Color(0xFF1E88E5),
    Color(0xFF00ACC1),
    Color(0xFF43A047),
    Color(0xFFFDD835),
    Color(0xFFFB8C00),
    Color(0xFF6D4C41),
    Color(0xFFFFFFFF),
  ];

  static const _brushDefs = <_Brush, ({IconData icon, String label})>{
    _Brush.pen: (icon: Icons.create, label: 'قلم'),
    _Brush.marker: (icon: Icons.brush, label: 'ماركر'),
    _Brush.highlighter: (icon: Icons.highlight, label: 'فسفوري'),
    _Brush.pencil: (icon: Icons.draw_outlined, label: 'رصاص'),
  };

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    if (widget.existingPath == null) return;
    try {
      final bytes = await File(widget.existingPath!).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _bgImage = frame.image);
    } catch (_) {/* نبدأ بلوحة بيضاء */}
  }

  double get _brushOpacity => switch (_brush) {
        _Brush.pen => 1.0,
        _Brush.marker => 1.0,
        _Brush.highlighter => 0.32,
        _Brush.pencil => 0.7,
      };
  double get _brushWidthMul => switch (_brush) {
        _Brush.pen => 1.0,
        _Brush.marker => 2.0,
        _Brush.highlighter => 3.4,
        _Brush.pencil => 0.6,
      };

  Color get _effectiveColor =>
      _eraser ? Colors.white : _penColor.withOpacity(_brushOpacity);
  double get _effectiveWidth =>
      _eraser ? _penWidth * 2.6 : _penWidth * _brushWidthMul;
  StrokeCap get _effectiveCap =>
      (!_eraser && _brush == _Brush.highlighter)
          ? StrokeCap.square
          : StrokeCap.round;

  void _start(Offset p) => setState(() =>
      _current = _Stroke([p], _effectiveColor, _effectiveWidth, _effectiveCap));

  void _add(Offset p) {
    if (_current == null) return;
    setState(() => _current!.points.add(p));
  }

  void _end() {
    if (_current == null) return;
    setState(() {
      _strokes.add(_current!);
      _current = null;
    });
  }

  Future<void> _pickColor() async {
    var temp = _penColor;
    final chosen = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر لونًا'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _penColor,
            onColorChanged: (c) => temp = c,
            enableAlpha: true,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
            portraitOnly: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, temp),
              child: const Text('تم')),
        ],
      ),
    );
    if (chosen != null) {
      setState(() {
        _penColor = chosen;
        _eraser = false;
      });
    }
  }

  Future<void> _save() async {
    if (_strokes.isEmpty && _bgImage == null) {
      Navigator.pop(context);
      return;
    }
    try {
      final boundary = _canvasKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final path = await FileService.instance.newAttachmentPath('png');
      await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (mounted) Navigator.pop(context, path);
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('drawing')),
        actions: [
          IconButton(
            tooltip: s.t('undo'),
            icon: const Icon(Icons.undo),
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() => _strokes.removeLast()),
          ),
          IconButton(
            tooltip: s.t('clear'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirmDelete(context,
                  title: 'مسح الرسم؟',
                  message: 'سيُمسح الرسم بالكامل ولا يمكن التراجع.',
                  confirmLabel: s.t('clear'),
                  icon: Icons.delete_sweep_outlined)) {
                setState(() {
                  _strokes.clear();
                  _current = null;
                  _bgImage = null;
                });
              }
            },
          ),
          IconButton(
            tooltip: s.t('save'),
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RepaintBoundary(
              key: _canvasKey,
              child: GestureDetector(
                onPanStart: (d) => _start(d.localPosition),
                onPanUpdate: (d) => _add(d.localPosition),
                onPanEnd: (_) => _end(),
                child: CustomPaint(
                  painter: _StrokePainter(_strokes, _current, _bgImage),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          _tools(context, scheme),
        ],
      ),
    );
  }

  Widget _tools(BuildContext context, ColorScheme scheme) {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // أنواع الفرش + الممحاة.
              Row(
                children: [
                  for (final e in _brushDefs.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _toolBtn(e.value.icon, !_eraser && _brush == e.key,
                          () => setState(() {
                                _brush = e.key;
                                _eraser = false;
                              }),
                          label: e.value.label),
                    ),
                  const Spacer(),
                  _toolBtn(Icons.cleaning_services_outlined, _eraser,
                      () => setState(() => _eraser = true),
                      label: 'ممحاة'),
                ],
              ),
              const SizedBox(height: 4),
              // السماكة.
              Row(
                children: [
                  const Icon(Icons.line_weight, size: 20),
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 30,
                      value: _penWidth,
                      label: _penWidth.round().toString(),
                      divisions: 29,
                      onChanged: (v) => setState(() => _penWidth = v),
                    ),
                  ),
                  // معاينة حجم الفرشاة.
                  Container(
                    width: 34,
                    alignment: Alignment.center,
                    child: Container(
                      width: (_effectiveWidth).clamp(2, 26).toDouble(),
                      height: (_effectiveWidth).clamp(2, 26).toDouble(),
                      decoration: BoxDecoration(
                        color: _eraser ? Colors.grey.shade400 : _effectiveColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ),
                ],
              ),
              // الألوان + منتقي احترافي.
              SizedBox(
                height: 40,
                child: Row(children: [
                  // زرّ المنتقي الاحترافي (يعرض اللون الحالي).
                  GestureDetector(
                    onTap: _pickColor,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: const SweepGradient(colors: [
                          Color(0xFFE53935),
                          Color(0xFFFDD835),
                          Color(0xFF43A047),
                          Color(0xFF1E88E5),
                          Color(0xFF8E24AA),
                          Color(0xFFE53935),
                        ]),
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const VerticalDivider(width: 8),
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _palette.map((c) {
                        final selected =
                            !_eraser && c.value == _penColor.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _penColor = c;
                              _eraser = false;
                            }),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? scheme.primary
                                      : (c == Colors.white
                                          ? Colors.black26
                                          : Colors.black12),
                                  width: selected ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, bool selected, VoidCallback onTap,
      {String? label}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 22, color: selected ? scheme.primary : scheme.onSurface),
            if (label != null)
              Text(label,
                  style: TextStyle(
                      fontSize: 9.5,
                      color: selected ? scheme.primary : scheme.onSurface)),
          ],
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? current;
  final ui.Image? bg;
  _StrokePainter(this.strokes, this.current, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    if (bg != null) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: bg!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    }
    for (final st in [...strokes, if (current != null) current!]) {
      final paint = Paint()
        ..color = st.color
        ..strokeWidth = st.width
        ..strokeCap = st.cap
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (st.points.length == 1) {
        canvas.drawCircle(
            st.points.first, st.width / 2, Paint()..color = st.color);
      } else {
        final path = Path()..moveTo(st.points.first.dx, st.points.first.dy);
        for (var i = 1; i < st.points.length; i++) {
          path.lineTo(st.points[i].dx, st.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}
