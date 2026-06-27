import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/text/line_direction.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/enums.dart';
import '../../data/models/note.dart';
import 'rich_text_field.dart';

/// معاينة الملاحظة كبطاقة أنيقة ثم مشاركتها **كصورة** (PNG).
class ShareImageScreen extends StatefulWidget {
  final Note note;
  const ShareImageScreen({super.key, required this.note});

  @override
  State<ShareImageScreen> createState() => _ShareImageScreenState();
}

class _ShareImageScreenState extends State<ShareImageScreen> {
  final _boundaryKey = GlobalKey();
  bool _busy = false;

  String _bodyText() {
    final n = widget.note;
    if (n.type == NoteType.checklist) {
      return n.content
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) {
            final m = RegExp(r'^\[([ x])\]\s?').firstMatch(l);
            if (m == null) return l;
            final done = m.group(1) == 'x';
            return '${done ? '☑' : '☐'} ${l.replaceFirst(RegExp(r'^\[.\]\s?'), '')}';
          })
          .join('\n');
    }
    return richToPlainText(n.content);
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File(p.join(dir.path, 'note_$stamp.png'));
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
      );
    } catch (_) {
      // تجاهل: قد يُلغي المستخدم المشاركة.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final n = widget.note;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = AppColors.resolveNoteColor(n.color, isDark);
    final onBg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final body = _bodyText();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('share_image')),
        actions: [
          IconButton(
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.share),
            tooltip: s.t('share'),
            onPressed: _busy ? null : _share,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: RepaintBoundary(
            key: _boundaryKey,
            child: Container(
              width: 340,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (n.title.trim().isNotEmpty) ...[
                    Text(
                      n.title,
                      textDirection: lineDirection(n.title),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          color: onBg),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (body.trim().isNotEmpty)
                    Text(
                      body,
                      textDirection: lineDirection(body),
                      style: TextStyle(
                          fontSize: 16, height: 1.5, color: onBg),
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(Icons.sticky_note_2,
                          size: 14, color: onBg.withOpacity(0.55)),
                      const SizedBox(width: 6),
                      Text(
                        s.t('app_name'),
                        style: TextStyle(
                            fontSize: 11, color: onBg.withOpacity(0.55)),
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('yyyy/MM/dd').format(n.updatedAt),
                        style: TextStyle(
                            fontSize: 11, color: onBg.withOpacity(0.55)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
