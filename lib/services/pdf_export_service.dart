import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/models/enums.dart';
import '../data/models/note.dart';

/// خدمة تصدير ملاحظة واحدة إلى **PDF مع الحفاظ على التنسيق** (غامق/مائل/تسطير/
/// شطب/لون/حجم/عناوين/قوائم/محاذاة). نقرأ محتوى Delta (flutter_quill) ونحوّله
/// إلى عناصر PDF بنفس التنسيق، مع دعم العربية والاتجاه من اليمين لليسار.
class PdfExportService {
  PdfExportService._();

  /// يبني ملف PDF للملاحظة ثم يفتح ورقة المشاركة/الحفظ.
  static Future<void> exportNote(Note note) async {
    final bytes = await buildPdf(note);
    final dir = await getTemporaryDirectory();
    final safeName = _safeFileName(
        note.title.trim().isEmpty ? 'ملاحظة' : note.title.trim());
    final file = File('${dir.path}/$safeName.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: note.title.trim().isEmpty ? 'ملاحظة' : note.title.trim(),
      ),
    );
  }

  /// يبني بايتات PDF (يمكن استخدامها للحفظ المباشر أيضًا).
  static Future<List<int>> buildPdf(Note note) async {
    final fonts = await _loadFonts();
    final doc = pw.Document();

    final content = <pw.Widget>[];

    // صورة الملاحظة (إن وُجدت) أعلى المستند.
    final image = await _loadNoteImage(note);
    if (image != null) {
      content.add(pw.Center(
          child: pw.ClipRRect(
        horizontalRadius: 6,
        verticalRadius: 6,
        child: pw.Image(image, fit: pw.BoxFit.contain, height: 240),
      )));
      content.add(pw.SizedBox(height: 16));
    }

    // متن الملاحظة (نص غني أو نص عادي).
    if (note.type == NoteType.text) {
      content.addAll(_deltaToWidgets(note.content, fonts));
    } else if (note.content.trim().isNotEmpty) {
      content.add(pw.Text(note.content.trim(),
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: fonts.regular, fontSize: 13)));
    }

    final dateStr = _formatDate(note.updatedAt);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
          italic: fonts.regular,
          boldItalic: fonts.bold,
        ),
        margin: const pw.EdgeInsets.all(36),
        header: (ctx) => ctx.pageNumber == 1
            ? _buildHeader(note, dateStr, fonts)
            : pw.SizedBox(),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
              style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 9,
                  color: PdfColors.grey600)),
        ),
        build: (ctx) => content,
      ),
    );

    return doc.save();
  }

  // ===================== رأس المستند (العنوان + التاريخ) =====================
  static pw.Widget _buildHeader(Note note, String dateStr, _PdfFonts fonts) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (note.title.trim().isNotEmpty)
            pw.Text(note.title.trim(),
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 20,
                    color: PdfColors.blueGrey800)),
          pw.SizedBox(height: 4),
          pw.Text(dateStr,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 10,
                  color: PdfColors.grey600)),
        ],
      ),
    );
  }

  // ===================== تحويل Delta إلى عناصر PDF =====================
  static List<pw.Widget> _deltaToWidgets(String content, _PdfFonts fonts) {
    final ops = _parseOps(content);
    if (ops == null) {
      // نص عادي غير Delta.
      final text = content.trim();
      if (text.isEmpty) return [];
      return [
        pw.Text(text,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fonts.regular, fontSize: 13)),
      ];
    }

    final widgets = <pw.Widget>[];
    var spans = <pw.InlineSpan>[];
    var orderedCounter = 1;

    void flushLine(Map<String, dynamic> blockAttrs) {
      // إن كان السطر فارغًا تمامًا أضِف فراغًا صغيرًا للحفاظ على الفقرات.
      if (spans.isEmpty) {
        widgets.add(pw.SizedBox(height: 6));
        orderedCounter = 1;
        return;
      }

      final header = blockAttrs['header'];
      final list = blockAttrs['list'];
      final align = blockAttrs['align'] as String?;
      final isQuote = blockAttrs['blockquote'] == true;
      final isCode = blockAttrs['code-block'] == true;

      // محاذاة (افتراضي اليمين للعربية).
      pw.Alignment alignment = pw.Alignment.centerRight;
      pw.TextAlign textAlign = pw.TextAlign.right;
      switch (align) {
        case 'center':
          alignment = pw.Alignment.center;
          textAlign = pw.TextAlign.center;
          break;
        case 'left':
          alignment = pw.Alignment.centerLeft;
          textAlign = pw.TextAlign.left;
          break;
        case 'justify':
          alignment = pw.Alignment.centerRight;
          textAlign = pw.TextAlign.justify;
          break;
        default:
          alignment = pw.Alignment.centerRight;
          textAlign = pw.TextAlign.right;
      }

      // بادئة القوائم.
      List<pw.InlineSpan> lineSpans = spans;
      if (list != null) {
        String prefix;
        if (list == 'ordered') {
          prefix = '${orderedCounter++}. ';
        } else if (list == 'checked') {
          prefix = '☑ ';
        } else if (list == 'unchecked') {
          prefix = '☐ ';
        } else {
          prefix = '• ';
        }
        lineSpans = [
          pw.TextSpan(
              text: prefix,
              style: pw.TextStyle(font: fonts.bold, fontSize: 13)),
          ...spans,
        ];
      } else {
        orderedCounter = 1;
      }

      // حجم العنوان.
      if (header is num || (header is String && header.isNotEmpty)) {
        final h = header is num
            ? header.toInt()
            : int.tryParse(header.toString()) ?? 0;
        final hSize = h == 1
            ? 22.0
            : h == 2
                ? 18.0
                : 15.0;
        lineSpans = lineSpans
            .map((s) => s is pw.TextSpan
                ? pw.TextSpan(
                    text: s.text,
                    style: (s.style ?? const pw.TextStyle())
                        .copyWith(font: fonts.bold, fontSize: hSize),
                    children: s.children)
                : s)
            .toList();
      }

      pw.Widget line = pw.RichText(
        textDirection: pw.TextDirection.rtl,
        textAlign: textAlign,
        text: pw.TextSpan(children: lineSpans),
      );

      if (isCode) {
        line = pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          margin: const pw.EdgeInsets.symmetric(vertical: 2),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: line,
        );
      } else if (isQuote) {
        line = pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(right: 10, top: 2, bottom: 2),
          margin: const pw.EdgeInsets.symmetric(vertical: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
                right: pw.BorderSide(color: PdfColors.blueGrey300, width: 3)),
          ),
          child: line,
        );
      }

      widgets.add(pw.Container(
        alignment: alignment,
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: line,
      ));
      spans = [];
    }

    for (final op in ops) {
      final data = op['insert'];
      if (data is! String) continue; // تجاهل العناصر المضمّنة (صور...).
      final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>();
      final parts = data.split('\n');
      for (var i = 0; i < parts.length; i++) {
        final text = parts[i];
        if (text.isNotEmpty) {
          spans.add(pw.TextSpan(
              text: text, style: _inlineStyle(attrs, fonts)));
        }
        // كل '\n' داخل النص يُنهي سطرًا؛ سمات هذا الـ op هي سمات الكتلة.
        if (i < parts.length - 1) {
          flushLine(attrs ?? const {});
        }
      }
    }
    if (spans.isNotEmpty) flushLine(const {});

    return widgets;
  }

  /// يبني نمط النص المضمّن (غامق/مائل/تسطير/شطب/لون/خلفية/حجم).
  static pw.TextStyle _inlineStyle(
      Map<String, dynamic>? attrs, _PdfFonts fonts) {
    final bold = attrs?['bold'] == true;
    final italic = attrs?['italic'] == true;
    final underline = attrs?['underline'] == true;
    final strike = attrs?['strike'] == true || attrs?['strikethrough'] == true;

    final decorations = <pw.TextDecoration>[];
    if (underline) decorations.add(pw.TextDecoration.underline);
    if (strike) decorations.add(pw.TextDecoration.lineThrough);

    double fontSize = 13;
    final size = attrs?['size'];
    if (size != null) {
      if (size is num) {
        fontSize = size.toDouble();
      } else {
        final parsed = double.tryParse(size.toString());
        if (parsed != null && parsed > 0) {
          fontSize = parsed;
        } else {
          switch (size.toString()) {
            case 'small':
              fontSize = 10;
              break;
            case 'large':
              fontSize = 18;
              break;
            case 'huge':
              fontSize = 26;
              break;
          }
        }
      }
    }

    final bg = _parseColor(attrs?['background']);
    return pw.TextStyle(
      font: bold ? fonts.bold : fonts.regular,
      fontSize: fontSize,
      fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
      color: _parseColor(attrs?['color']),
      background: bg == null ? null : pw.BoxDecoration(color: bg),
      decoration: decorations.isEmpty
          ? null
          : pw.TextDecoration.combine(decorations),
    );
  }

  // ===================== مساعدات =====================
  static List<Map<String, dynamic>>? _parseOps(String content) {
    final trimmed = content.trim();
    if (!trimmed.startsWith('[')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
    } catch (_) {}
    return null;
  }

  static PdfColor? _parseColor(dynamic raw) {
    if (raw is! String) return null;
    var hex = raw.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return PdfColor.fromInt(0xff000000 | v);
    } else if (hex.length == 8) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return PdfColor.fromInt(v);
    }
    return null;
  }

  static Future<pw.ImageProvider?> _loadNoteImage(Note note) async {
    final path = note.imagePath;
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<_PdfFonts> _loadFonts() async {
    final regular = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    return _PdfFonts(
      regular: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
  }

  static String _safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').trim();
    final limited = cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
    return limited.isEmpty ? 'ملاحظة' : limited;
  }

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} - ${two(d.hour)}:${two(d.minute)}';
  }
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  _PdfFonts({required this.regular, required this.bold});
}
