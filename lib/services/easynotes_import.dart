import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../data/models/category.dart';
import '../data/models/enums.dart';
import '../data/models/note.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/note_repository.dart';
import 'file_service.dart';

class EasyNotesImportResult {
  final bool success;
  final int imported;
  final int updated;
  final int skipped;
  final int newCategories;
  final String message;

  EasyNotesImportResult({
    required this.success,
    this.imported = 0,
    this.updated = 0,
    this.skipped = 0,
    this.newCategories = 0,
    required this.message,
  });
}

/// يستورد ملاحظات Easy Notes من ملف نسخته الاحتياطية (.backup) مع الحفاظ على
/// التنسيق (عريض/لون/تظليل/حجم/تسطير/شطب) ولون الخلفية والتصنيفات والوسوم.
class EasyNotesImporter {
  EasyNotesImporter(this.noteRepo, this.categoryRepo);

  final NoteRepository noteRepo;
  final CategoryRepository categoryRepo;

  static const _palette = [
    0xFF42A5F5, 0xFF7E57C2, 0xFFEF5350, 0xFF26A69A,
    0xFFFFA726, 0xFF66BB6A, 0xFFEC407A, 0xFF8D6E63,
  ];

  // تقريب أنماط grid_* إلى ألوان صلبة قريبة.
  static const _gridColors = {
    'grid_color_bg10': 0xFFF8BBD0,
    'grid_bg11': 0xFFC8E6C9,
    'grid_bg18': 0xFFBBDEFB,
    'grid_bg7': 0xFFFFF9C4,
    'grid_bg3': 0xFFFFE0B2,
  };

  Future<EasyNotesImportResult> importBackup(
    Uint8List bytes, {
    bool includeTrashed = false,
  }) async {
    Archive outer;
    try {
      outer = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return EasyNotesImportResult(
          success: false,
          message: 'تعذّر قراءة الملف — تأكّد أنه نسخة Easy Notes.');
    }

    final existingCats = await categoryRepo.getAll();
    final catByName = <String, int>{for (final c in existingCats) c.name: c.id!};
    var colorIdx = existingCats.length;
    var imported = 0, updated = 0, skipped = 0, newCats = 0;

    // مفتاح منع التكرار: تاريخ الإنشاء + العنوان → معرّف الملاحظة.
    final existingNotes = await noteRepo.getEverything();
    final byKey = <String, int>{
      for (final n in existingNotes)
        '${n.createdAt.millisecondsSinceEpoch}|${n.title}': n.id!
    };

    Future<int?> ensureCategory(String? name) async {
      final n = name?.trim() ?? '';
      if (n.isEmpty) return null;
      if (catByName.containsKey(n)) return catByName[n];
      final id = await categoryRepo.insert(Category(
        name: n,
        color: _palette[colorIdx++ % _palette.length],
        iconCode: 7,
        position: catByName.length,
      ));
      catByName[n] = id;
      newCats++;
      return id;
    }

    for (final entry in outer.files) {
      if (!entry.isFile || !entry.name.toLowerCase().endsWith('.zip')) continue;
      try {
        final inner = ZipDecoder().decodeBytes(entry.content as List<int>);
        final noteFile = inner.findFile('note.json');
        if (noteFile == null) continue;
        final d = jsonDecode(utf8.decode(noteFile.content as List<int>))
            as Map<String, dynamic>;

        final trashed = d['trashed'] == true;
        if (trashed && !includeTrashed) {
          skipped++;
          continue;
        }

        final title = (d['title'] as String?)?.trim() ?? '';
        final plain = (d['content'] as String?) ?? '';
        if (title.isEmpty && plain.trim().isEmpty) {
          skipped++;
          continue;
        }

        int? catId;
        final bc = d['baseCategory'];
        if (bc is Map && bc['name'] is String) {
          catId = await ensureCategory(bc['name'] as String);
        }

        final tags = ((d['tags'] as String?) ?? '')
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        final imagePath = await _extractFirstImage(inner, d['attachmentsList']);

        // النص: صورة → نص عادي، وإلا نص غني (Delta) مع التنسيق.
        // المقاطع مفصولة بفاصلة أو علامة + (نتعامل مع كليهما).
        final spans = <String>[
          ...((d['address'] as String?) ?? '').split(RegExp(r'[,+]')),
          ...((d['richText'] as String?) ?? '').split(RegExp(r'[,+]')),
        ];
        final content = imagePath != null
            ? plain
            : _toDelta(plain, spans);

        final created = _ms(d['creation']) ?? DateTime.now();
        final base = Note(
          title: title,
          content: content,
          type: imagePath != null ? NoteType.image : NoteType.text,
          color: _bgColor(d['stickyColor'] as String?),
          isFavorite: _truthy(d['favorite']),
          isPinned: _truthy(d['isPined']),
          isArchived: d['archived'] == true,
          isDeleted: trashed,
          isLocked: d['locked'] == true,
          categoryId: catId,
          imagePath: imagePath,
          createdAt: created,
          updatedAt: _ms(d['lastModification']) ?? created,
          tags: tags,
        );

        final key = '${created.millisecondsSinceEpoch}|$title';
        final existingId = byKey[key];
        if (existingId != null) {
          await noteRepo.updateNote(base.copyWith(id: existingId));
          updated++;
        } else {
          final id = await noteRepo.insertNote(base);
          byKey[key] = id;
          imported++;
        }
      } catch (_) {
        skipped++;
      }
    }

    final total = imported + updated;
    return EasyNotesImportResult(
      success: total > 0,
      imported: imported,
      updated: updated,
      skipped: skipped,
      newCategories: newCats,
      message: total > 0
          ? 'تم: $imported جديدة، $updated محدّثة، $newCats تصنيف.'
          : 'لم يتم استيراد أي ملاحظة.',
    );
  }

  /// تحويل نص Easy Notes + مقاطع التنسيق إلى Delta JSON الخاص بـ flutter_quill.
  String _toDelta(String content, List<String> spans) {
    if (content.isEmpty) {
      return jsonEncode([
        {'insert': '\n'}
      ]);
    }
    final len = content.length;
    final bold = List<bool>.filled(len, false);
    final underline = List<bool>.filled(len, false);
    final strike = List<bool>.filled(len, false);
    final color = List<String?>.filled(len, null);
    final bg = List<String?>.filled(len, null);
    final size = List<String?>.filled(len, null);

    // مقاطع بثلاث قيم: s=عريض، f=حجم، c=لون الخط، h=تظليل (start/end/value).
    final re3 = RegExp(r'^([a-zA-Z]+)(\d+)/(\d+)/(-?\d+(?:\.\d+)?)$');
    // مقاطع بقيمتين: u=تسطير، r=شطب (start/end فقط).
    final re2 = RegExp(r'^([a-zA-Z]+)(\d+)/(\d+)$');

    void clampApply(int s, int e, void Function(int) f) {
      if (s < 0) s = 0;
      if (e > len) e = len;
      for (var i = s; i < e; i++) {
        f(i);
      }
    }

    for (final raw in spans) {
      final tok = raw.trim();
      if (tok.isEmpty) continue;
      final m = re3.firstMatch(tok);
      if (m != null) {
        final t = m.group(1)!;
        final s = int.parse(m.group(2)!);
        final e = int.parse(m.group(3)!);
        final v = double.parse(m.group(4)!).round();
        switch (t) {
          case 's': // عريض (القيمة وزن الخط؛ أي قيمة موجبة = عريض).
            if (v > 0) clampApply(s, e, (i) => bold[i] = true);
            break;
          case 'c': // لون الخط.
            clampApply(s, e, (i) => color[i] = _hex(v));
            break;
          case 'h': // خلفية الخط (تظليل).
            if (v != 0) clampApply(s, e, (i) => bg[i] = _hex(v));
            break;
          case 'f': // حجم الخط — مقياس Easy Notes كبير (≈49–56 للنص العادي)،
            // نحوّله إلى حجم مريح للمحرّر (≈16 للنص العادي).
            final px = _scaleFont(v);
            if (px != null) clampApply(s, e, (i) => size[i] = px);
            break;
        }
        continue;
      }
      final m2 = re2.firstMatch(tok);
      if (m2 != null) {
        final t = m2.group(1)!;
        final s = int.parse(m2.group(2)!);
        final e = int.parse(m2.group(3)!);
        switch (t) {
          case 'u': // تسطير.
            clampApply(s, e, (i) => underline[i] = true);
            break;
          case 'r': // شطب.
            clampApply(s, e, (i) => strike[i] = true);
            break;
        }
      }
    }

    final ops = <Map<String, dynamic>>[];
    final buf = StringBuffer();
    Map<String, dynamic> cur = {};

    void flush() {
      if (buf.isEmpty) return;
      final op = <String, dynamic>{'insert': buf.toString()};
      if (cur.isNotEmpty) op['attributes'] = Map<String, dynamic>.of(cur);
      ops.add(op);
      buf.clear();
    }

    for (var i = 0; i < len; i++) {
      final ch = content[i];
      if (ch == '\n') {
        // الأسطر الجديدة بلا تنسيق سطري (Quill يضع تنسيق الفقرة عليها).
        flush();
        ops.add({'insert': '\n'});
        cur = {};
        continue;
      }
      final a = <String, dynamic>{};
      if (bold[i]) a['bold'] = true;
      if (underline[i]) a['underline'] = true;
      if (strike[i]) a['strike'] = true;
      if (color[i] != null) a['color'] = color[i];
      if (bg[i] != null) a['background'] = bg[i];
      if (size[i] != null) a['size'] = size[i];
      if (!_sameMap(a, cur)) {
        flush();
        cur = a;
      }
      buf.write(ch);
    }
    flush();
    // يجب أن تنتهي وثيقة Quill بسطر جديد.
    if (ops.isEmpty || !(ops.last['insert'] as String).endsWith('\n')) {
      ops.add({'insert': '\n'});
    }
    return jsonEncode(ops);
  }

  bool _sameMap(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (b[k] != a[k]) return false;
    }
    return true;
  }

  /// يحوّل حجم خط Easy Notes (مقياس داخلي كبير) إلى حجم بكسل مريح للمحرّر.
  ///
  /// في بيانات Easy Notes النص العادي ≈ 49–56 والعناوين ≈ 63–105؛ نضرب في
  /// معامل بحيث يصبح النص العادي ≈ 16 والعناوين متناسبة معه.
  String? _scaleFont(int v) {
    if (v <= 0) return null;
    final px = (v * 0.30).round().clamp(9, 64);
    return px.toString();
  }

  String _hex(int signed) {
    final rgb = (signed & 0xFFFFFF);
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  int? _bgColor(String? sticky) {
    final s = sticky?.trim() ?? '';
    if (s.isEmpty) return null;
    if (s.startsWith('#')) {
      final hex = s.substring(1);
      if (hex.length == 6) {
        final v = int.tryParse(hex, radix: 16);
        return v == null ? null : (0xFF000000 | v);
      } else if (hex.length == 8) {
        // #AARRGGBB في Easy Notes — ندمجه فوق الأبيض ليطابق مظهره الفاتح الأصلي.
        final v = int.tryParse(hex, radix: 16);
        return v == null ? null : _overWhite(v);
      }
    }
    return _gridColors[s];
  }

  /// يدمج لونًا شبه شفّاف فوق خلفية بيضاء ويعيد لونًا معتمًا مكافئًا.
  int _overWhite(int argb) {
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final af = a / 255.0;
    int mix(int c) => (c * af + 255 * (1 - af)).round().clamp(0, 255);
    return (0xFF << 24) | (mix(r) << 16) | (mix(g) << 8) | mix(b);
  }

  Future<String?> _extractFirstImage(
      Archive inner, dynamic attachmentsList) async {
    if (attachmentsList is! List) return null;
    for (final a in attachmentsList) {
      if (a is! Map) continue;
      final mime = a['mime_type']?.toString() ?? '';
      if (!mime.startsWith('image/')) continue;
      final name = a['name']?.toString();
      ArchiveFile? img = (name != null) ? inner.findFile(name) : null;
      img ??= inner.files
          .where((f) => f.isFile && f.name != 'note.json' && _isImage(f.name))
          .cast<ArchiveFile?>()
          .firstWhere((_) => true, orElse: () => null);
      if (img != null) {
        try {
          final path =
              await FileService.instance.newAttachmentPath(_ext(img.name));
          await File(path).writeAsBytes(img.content as List<int>);
          return path;
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  bool _truthy(dynamic v) => v == 1 || v == true || v == '1';

  DateTime? _ms(dynamic v) =>
      (v is int && v > 0) ? DateTime.fromMillisecondsSinceEpoch(v) : null;

  bool _isImage(String n) {
    final l = n.toLowerCase();
    return l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.png') ||
        l.endsWith('.webp');
  }

  String _ext(String n) {
    final i = n.lastIndexOf('.');
    return i >= 0 ? n.substring(i) : '.jpg';
  }
}
