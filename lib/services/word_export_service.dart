import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/text/line_direction.dart';
import '../data/models/enums.dart';
import '../data/models/note.dart';

/// خدمة تصدير ملاحظة واحدة إلى **مستند Word (.doc)** مع الحفاظ على التنسيق
/// (غامق/مائل/تسطير/شطب/لون/حجم/عناوين/قوائم/محاذاة/تباعد الأسطر) واتجاه كل سطر.
///
/// نُولّد مستند Word بصيغة HTML (يفتحه Word وGoogle Docs وWPS مباشرةً ويعرض
/// التنسيق كاملًا) — دون أي حزمة إضافية. اتجاه كل سطر يُحسب من نصّه عبر
/// [lineDirection] فتبقى الشرطة/الرمز في بداية السطر بصريًّا.
class WordExportService {
  WordExportService._();

  /// يبني ملف .doc للملاحظة ثم يفتح ورقة المشاركة/الحفظ.
  static Future<void> exportNote(Note note) async {
    final html = buildHtml(note);
    final dir = await getTemporaryDirectory();
    final safeName = _safeFileName(
        note.title.trim().isEmpty ? 'ملاحظة' : note.title.trim());
    final file = File('${dir.path}/$safeName.doc');
    await file.writeAsString(html, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/msword')],
        subject: note.title.trim().isEmpty ? 'ملاحظة' : note.title.trim(),
      ),
    );
  }

  /// يبني نصّ HTML المتوافق مع Word.
  static String buildHtml(Note note) {
    final body = StringBuffer();
    final title = note.title.trim();

    // العنوان + التاريخ.
    if (title.isNotEmpty) {
      body.write('<h1 dir="${_dirAttr(title)}" style="margin:0 0 4px;'
          'color:#37474f;">${_esc(title)}</h1>');
    }
    body.write('<p style="margin:0 0 14px;color:#777;font-size:10pt;'
        'border-bottom:1px solid #ccc;padding-bottom:8px;">'
        '${_esc(_formatDate(note.updatedAt))}</p>');

    // المتن.
    if (note.type == NoteType.text) {
      body.write(_deltaToHtml(note.content));
    } else {
      for (final line in note.content.split('\n')) {
        body.write(_paragraph(line, _esc(line), const {}));
      }
    }

    return '<html xmlns:o="urn:schemas-microsoft-com:office:office" '
        'xmlns:w="urn:schemas-microsoft-com:office:word" '
        'xmlns="http://www.w3.org/TR/REC-html40">'
        '<head><meta charset="utf-8"><title>${_esc(title)}</title>'
        '<style>body{font-family:Cairo,Arial,sans-serif;font-size:13pt;'
        'line-height:1.5;}p{margin:2px 0;}</style></head>'
        '<body dir="rtl">${body.toString()}</body></html>';
  }

  // ===================== تحويل Delta إلى HTML =====================
  static String _deltaToHtml(String content) {
    final ops = _parseOps(content);
    if (ops == null) {
      // نص عادي (غير Delta).
      final out = StringBuffer();
      for (final line in content.split('\n')) {
        out.write(_paragraph(line, _esc(line), const {}));
      }
      return out.toString();
    }

    final out = StringBuffer();
    final spanBuf = StringBuffer(); // HTML المنسّق للسطر الحالي
    final plainBuf = StringBuffer(); // نصّ السطر الخام (لتحديد الاتجاه)
    var orderedCounter = 1;

    void flushLine(Map<String, dynamic> blockAttrs) {
      final list = blockAttrs['list'];
      var prefix = '';
      if (list == 'ordered') {
        prefix = '${orderedCounter++}. ';
      } else if (list == 'checked') {
        prefix = '☑ ';
      } else if (list == 'unchecked') {
        prefix = '☐ ';
      } else if (list != null) {
        prefix = '• ';
      } else {
        orderedCounter = 1;
      }
      final plain = prefix + plainBuf.toString();
      final inner = (prefix.isEmpty ? '' : _esc(prefix)) + spanBuf.toString();
      out.write(_paragraph(plain, inner, blockAttrs));
      spanBuf.clear();
      plainBuf.clear();
    }

    for (final op in ops) {
      final data = op['insert'];
      if (data is! String) continue;
      final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>();
      final parts = data.split('\n');
      for (var i = 0; i < parts.length; i++) {
        final text = parts[i];
        if (text.isNotEmpty) {
          plainBuf.write(text);
          spanBuf.write(_span(text, attrs));
        }
        if (i < parts.length - 1) flushLine(attrs ?? const {});
      }
    }
    if (spanBuf.isNotEmpty || plainBuf.isNotEmpty) flushLine(const {});
    return out.toString();
  }

  /// يبني فقرة <p> باتجاهها (من نصّها الخام) ومحاذاتها وتباعدها وأنماط الكتلة.
  static String _paragraph(
      String plain, String innerHtml, Map<String, dynamic> blockAttrs) {
    if (plain.trim().isEmpty && innerHtml.isEmpty) {
      return '<p style="margin:6px 0;">&nbsp;</p>';
    }
    final dir = _dirAttr(plain);
    final styles = <String>[];

    final align = blockAttrs['align'] as String?;
    if (align == 'center') {
      styles.add('text-align:center');
    } else if (align == 'left') {
      styles.add('text-align:left');
    } else if (align == 'right') {
      styles.add('text-align:right');
    } else if (align == 'justify') {
      styles.add('text-align:justify');
    } else {
      styles.add('text-align:${dir == 'rtl' ? 'right' : 'left'}');
    }

    final lh = blockAttrs['line-height'];
    if (lh is num) styles.add('line-height:$lh');

    final isQuote = blockAttrs['blockquote'] == true;
    final isCode = blockAttrs['code-block'] == true;
    if (isQuote) {
      styles.add('border-right:3px solid #90a4ae');
      styles.add('padding:2px 10px 2px 0');
      styles.add('color:#546e7a');
    }
    if (isCode) {
      styles.add('font-family:Consolas,monospace');
      styles.add('background:#f0f0f0');
      styles.add('padding:6px');
      styles.add('border-radius:4px');
    }

    // العناوين: حجم أكبر + غامق.
    final header = blockAttrs['header'];
    final h = header is num
        ? header.toInt()
        : int.tryParse('${header ?? ''}') ?? 0;
    if (h >= 1 && h <= 3) {
      final size = h == 1 ? 22 : (h == 2 ? 18 : 15);
      styles.add('font-size:${size}pt');
      styles.add('font-weight:bold');
    }

    return '<p dir="$dir" style="${styles.join(';')};">$innerHtml</p>';
  }

  /// يبني <span> منسّقًا (غامق/مائل/تسطير/شطب/لون/خلفية/حجم).
  static String _span(String text, Map<String, dynamic>? attrs) {
    final esc = _esc(text);
    if (attrs == null || attrs.isEmpty) return esc;
    final styles = <String>[];
    if (attrs['bold'] == true) styles.add('font-weight:bold');
    if (attrs['italic'] == true) styles.add('font-style:italic');
    final deco = <String>[];
    if (attrs['underline'] == true) deco.add('underline');
    if (attrs['strike'] == true || attrs['strikethrough'] == true) {
      deco.add('line-through');
    }
    if (deco.isNotEmpty) styles.add('text-decoration:${deco.join(' ')}');
    final color = _color(attrs['color']);
    if (color != null) styles.add('color:$color');
    final bg = _color(attrs['background']);
    if (bg != null) styles.add('background-color:$bg');
    final size = _fontSize(attrs['size']);
    if (size != null) styles.add('font-size:${size}pt');
    if (styles.isEmpty) return esc;
    return '<span style="${styles.join(';')};">$esc</span>';
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

  static String _dirAttr(String text) =>
      lineDirection(text) == TextDirection.rtl ? 'rtl' : 'ltr';

  static String? _color(dynamic raw) {
    if (raw is! String) return null;
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('#') || v.startsWith('rgb')) return v;
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(v)) return '#$v';
    return null;
  }

  static num? _fontSize(dynamic size) {
    if (size == null) return null;
    if (size is num) return size;
    final parsed = double.tryParse(size.toString());
    if (parsed != null && parsed > 0) return parsed;
    switch (size.toString()) {
      case 'small':
        return 10;
      case 'large':
        return 18;
      case 'huge':
        return 26;
    }
    return null;
  }

  static String _esc(String s) => const HtmlEscape().convert(s);

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
