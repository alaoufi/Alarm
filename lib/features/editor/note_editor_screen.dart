import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/text/line_direction.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/note_gradient.dart';
import '../../data/models/checklist_item.dart';
import '../../data/models/enums.dart';
import '../../data/models/note.dart';
import '../../data/models/password_entry.dart';
import '../../services/pdf_export_service.dart';
import '../../services/word_export_service.dart';
import '../../services/secure_screen.dart';
import '../../services/vault_service.dart';
import 'password_form.dart';
import '../../widgets/color_picker_sheet.dart';
import '../../widgets/note_actions.dart';
import '../../widgets/paper_background.dart';
import '../drawing/drawing_screen.dart';
import '../home/notes_provider.dart';
import '../reminders/reminder_dialog.dart';
import '../settings/settings_provider.dart';
import 'editor_attachments.dart';
import 'rich_text_field.dart';

/// محرّر الملاحظة لكل الأنواع، مع حفظ تلقائي أثناء الكتابة.
class NoteEditorScreen extends StatefulWidget {
  final int? noteId;
  final NoteType initialType;
  final int? initialCategoryId;

  /// عند فتح «قائمة مهام» جديدة: هل يبدأ السطر الأول كمهمة (بمربع) أم نصًّا عاديًّا.
  final bool startAsTask;

  const NoteEditorScreen({
    super.key,
    this.noteId,
    this.initialType = NoteType.text,
    this.initialCategoryId,
    this.startAsTask = true,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  late Note _note;
  List<ChecklistItem> _checklist = [];
  final List<TextEditingController> _itemCtrls = [];
  final List<FocusNode> _itemFocus = [];
  PasswordEntry _passwordEntry = const PasswordEntry();
  String _richContent = ''; // محتوى النص الغني (Delta JSON) لنوع النص
  RichTextController? _richCtrl; // وحدة تحكّم النص الغني (لنوع النص فقط)

  Timer? _debounce;
  Color _fgColor = Colors.black87; // لون نص المتن المناسب للخلفية الحالية
  bool _loaded = false;
  bool _dirty = false;
  bool _drawingPrompted = false;
  bool _secured = false;
  bool _deleted = false; // نُقلت للمهملات ⇒ لا تُحفظ ثانيةً عند الإغلاق
  // هل حملت الملاحظة محتوًى حقيقيًّا (عند التحميل أو أثناء الجلسة)؟ نميّز به بين
  // ملاحظة أُفرِغت بعد محتوى (⇒ للسلّة، قابلة للاسترجاع) وأخرى لم تحوِ شيئًا قطّ
  // (⇒ حذف نهائيّ، مثل ملاحظة أُنشئت مؤقّتًا لفتح قائمة).
  bool _hadRealContent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<NotesProvider>();
    await VaultService.instance.ensureKey();
    if (widget.noteId != null) {
      final n = await provider.notes.getNote(widget.noteId!);
      if (n != null) {
        _note = n;
        _titleCtrl.text = n.title;
        _contentCtrl.text = n.content;
        if (n.type == NoteType.checklist) {
          _checklist = await provider.notes.getChecklist(n.id!);
          if (_checklist.isEmpty) _checklist = [ChecklistItem(noteId: n.id!, text: '')];
          _rebuildItemCtrls();
        } else if (n.type == NoteType.password) {
          _passwordEntry = PasswordEntry.fromStoredJson(n.content);
        } else if (n.type == NoteType.text) {
          _richContent = n.content;
        }
      } else {
        _note = Note.create(type: widget.initialType);
      }
    } else {
      // ملاحظة جديدة: طبّق الافتراضي (لون الخلفية ونمط الصفحة) من الإعدادات.
      final settings = context.read<SettingsProvider>();
      _note = Note.create(
              type: widget.initialType, categoryId: widget.initialCategoryId)
          .copyWith(
        color: settings.defaultNoteColor,
        clearColor: settings.defaultNoteColor == null,
        bgStyle: settings.defaultBgStyle,
        gradient: settings.defaultGradient,
      );
      if (_note.type == NoteType.checklist) {
        _checklist = [
          ChecklistItem(noteId: 0, text: '', isTask: widget.startAsTask)
        ];
        _rebuildItemCtrls();
      } else if (_note.type == NoteType.password) {
        // ملاحظات كلمات المرور مقفلة افتراضيًا (تتطلب فتح القفل لعرضها).
        _note = _note.copyWith(isLocked: true);
      }
    }
    // وحدة تحكّم النص الغني (لنوع النص) — تُهيّأ بعد معرفة المحتوى.
    if (_note.type == NoteType.text) {
      _richCtrl = RichTextController(_richContent, (json) {
        _richContent = json;
        _onChanged();
      });
    }

    setState(() => _loaded = true);
    // ملاحظة مُحمّلة بمحتوى ⇒ احفظ أنها حملت محتوًى حقيقيًّا (لتذهب للسلّة لو أُفرِغت).
    _hadRealContent = !_isCurrentlyEmpty();

    _titleCtrl.addListener(_onChanged);
    _contentCtrl.addListener(_onChanged);

    // منع التصوير للملاحظات الحسّاسة (سرية/كلمات مرور).
    if (_note.type == NoteType.password || _note.isLocked) {
      _secured = true;
      SecureScreen.enable();
    }
  }

  void _rebuildItemCtrls() {
    for (final c in _itemCtrls) {
      c.dispose();
    }
    for (final f in _itemFocus) {
      f.dispose();
    }
    _itemCtrls.clear();
    _itemFocus.clear();
    for (final item in _checklist) {
      _itemCtrls.add(TextEditingController(text: item.text));
      _itemFocus.add(FocusNode());
    }
  }

  /// إدراج عنصر جديد بعد [i] مباشرةً والانتقال إليه (عند ضغط Enter).
  /// يرث نوع السطر الحالي (مهمة/نص) كما في تطبيقات المذكرات.
  /// [text]: النصّ المنقول لما بعد المؤشّر عند تقسيم سطر (وإلا سطر فارغ).
  void _addItemAfter(int i, {String text = ''}) {
    final inheritTask =
        (i >= 0 && i < _checklist.length) ? _checklist[i].isTask : true;
    setState(() {
      _checklist.insert(
          i + 1,
          ChecklistItem(
              noteId: _note.id ?? 0, text: text, isTask: inheritTask));
      _itemCtrls.insert(i + 1, TextEditingController(text: text));
      _itemFocus.insert(i + 1, FocusNode());
    });
    _onChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (i + 1 < _itemFocus.length) {
        _itemFocus[i + 1].requestFocus();
        // المؤشّر في بداية النص المنقول (حيث ضُغط Enter).
        _itemCtrls[i + 1].selection =
            const TextSelection.collapsed(offset: 0);
      }
    });
  }

  void _onChanged() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _save);
  }

  String _checklistToContent() {
    return _checklist
        .map((i) => i.isTask
            ? '${i.isDone ? '[x]' : '[ ]'} ${i.text}'
            : i.text)
        .where((l) => l.trim().isNotEmpty)
        .join('\n');
  }

  Future<void> _save({bool force = false}) async {
    if (!_loaded || _deleted) return;
    final provider = context.read<NotesProvider>();

    final title = _titleCtrl.text;
    var content = _contentCtrl.text;
    var emptyPassword = false;
    var emptyRich = false;
    if (_note.type == NoteType.checklist) {
      // زامن النصوص من الحقول.
      for (var i = 0; i < _checklist.length && i < _itemCtrls.length; i++) {
        _checklist[i] = _checklist[i].copyWith(text: _itemCtrls[i].text);
      }
      content = _checklistToContent();
    } else if (_note.type == NoteType.text) {
      content = _richContent;
      emptyRich = richToPlainText(_richContent).trim().isEmpty;
    } else if (_note.type == NoteType.password) {
      final e = _passwordEntry;
      emptyPassword = e.site.trim().isEmpty &&
          e.app.trim().isEmpty &&
          e.username.trim().isEmpty &&
          e.password.trim().isEmpty &&
          e.notes.trim().isEmpty;
      content = e.toStoredJson();
    }

    final candidate = _note.copyWith(
      title: title,
      content: content,
      updatedAt: DateTime.now(),
    );

    // لا تحفظ ملاحظة فارغة تمامًا.
    final bool isEmpty;
    if (_note.type == NoteType.password) {
      isEmpty = title.trim().isEmpty && emptyPassword;
    } else if (_note.type == NoteType.text) {
      isEmpty = title.trim().isEmpty && emptyRich;
    } else {
      isEmpty = candidate.isEmpty;
    }
    if (isEmpty && !force) return;
    if (!isEmpty) _hadRealContent = true; // حملت محتوًى حقيقيًّا في هذه الجلسة.

    // أثناء التحرير لا نُعيد تحميل كامل القائمة (مئات الملاحظات) مع كل حفظ
    // مؤجَّل — هذا كان سبب البطء عند كتابة سطر جديد. التحديث يحدث مرّة واحدة
    // في الخلفية عند إغلاق المحرّر (انظر [_onWillPop]).
    final id = await provider.saveNote(
      candidate,
      checklist: _note.type == NoteType.checklist ? _checklist : null,
      reload: false,
    );
    _note = candidate.copyWith(id: id);
    _dirty = false;
  }

  Future<bool> _onWillPop() async {
    _debounce?.cancel();
    // التقط آخر محتوى حيّ من المحرّر (قد يكون مؤقّت الحفظ المؤجَّل لم ينقضِ بعد).
    if (_richCtrl != null) _richContent = _richCtrl!.currentContent;
    final provider = context.read<NotesProvider>();
    if (!_deleted) {
      // لا نُبقي ملاحظة فارغة (كُتب فيها ثم مُحي، أو أُنشئت مؤقّتًا لفتح قائمة):
      // إن كانت محفوظة سابقًا نحذفها نهائيًّا، وإن كانت جديدة لا نُنشئها.
      if (_isCurrentlyEmpty()) {
        if (_note.id != null) {
          // كانت تحوي محتوًى ثم أُفرِغت ⇒ للسلّة (قابلة للاسترجاع تفاديًا لفقد
          // بالخطأ). لم تحوِ محتوًى قطّ (أُنشئت مؤقّتًا) ⇒ حذف نهائيّ بلا أثر.
          if (_hadRealContent) {
            await provider.moveToTrash(_note);
          } else {
            await provider.deleteForever(_note);
          }
        }
        _deleted = true;
      } else if (_dirty || _note.id == null) {
        await _save();
      }
    }
    // حدّث القائمة مرّة واحدة في الخلفية (بصمت، بلا وميض تحميل) كي لا يتأخّر
    // الرجوع للملاحظات ويظلّ الانتقال سلسًا.
    unawaited(provider.refresh(silent: true));
    return true;
  }

  /// هل الملاحظة فارغة فعليًّا الآن (من حالة المحرّر الحيّة)؟ فارغة = بلا عنوان،
  /// وبلا مرفق (صورة/صوت/PDF/رسم)، وبلا محتوى حسب نوعها. تُستخدم كي لا نحفظ/نُبقي
  /// ملاحظة لا كتابة فيها.
  bool _isCurrentlyEmpty() {
    if (_titleCtrl.text.trim().isNotEmpty) return false;
    if (_note.imagePath != null ||
        _note.audioPath != null ||
        _note.pdfPath != null ||
        _note.drawingPath != null) {
      return false;
    }
    switch (_note.type) {
      case NoteType.password:
        final e = _passwordEntry;
        return e.site.trim().isEmpty &&
            e.app.trim().isEmpty &&
            e.username.trim().isEmpty &&
            e.password.trim().isEmpty &&
            e.notes.trim().isEmpty;
      case NoteType.checklist:
        return !_itemCtrls.any((c) => c.text.trim().isNotEmpty);
      case NoteType.text:
        // النصّ الحيّ من المحرّر (لا _richContent المؤجَّل ~600ms) كي يُلتقط
        // الحذف فورًا عند الخروج السريع.
        final live = _richCtrl != null
            ? _richCtrl!.plainText
            : richToPlainText(_richContent);
        return live.trim().isEmpty;
      default:
        return _contentCtrl.text.trim().isEmpty;
    }
  }

  @override
  void dispose() {
    if (_secured) SecureScreen.disable();
    _debounce?.cancel();
    _richCtrl?.dispose();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    for (final c in _itemCtrls) {
      c.dispose();
    }
    for (final f in _itemFocus) {
      f.dispose();
    }
    super.dispose();
  }

  // ---- المرفقات ----

  Future<void> _ensureSaved() async {
    if (_note.id == null) await _save(force: true);
  }

  Future<void> _attachImage() async {
    final path = await EditorAttachments.pickImage(context);
    if (path == null) return;
    setState(() => _note = _note.copyWith(imagePath: path));
    _dirty = true;
    await _save(force: true);
  }

  Future<void> _attachPdf() async {
    final path = await EditorAttachments.pickPdf();
    if (path == null) return;
    setState(() => _note = _note.copyWith(pdfPath: path));
    _dirty = true;
    await _save(force: true);
  }

  /// تصدير الملاحظة (النص الغني) إلى PDF مع الحفاظ على التنسيق.
  Future<void> _exportPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    // احفظ آخر تعديل أولًا كي يُصدَّر المحتوى المحدّث.
    await _save(force: true);
    final exportNote = _note.copyWith(content: _richContent);
    messenger.showSnackBar(const SnackBar(
        content: Text('جارٍ تجهيز ملف PDF…'),
        duration: Duration(seconds: 1)));
    try {
      await PdfExportService.exportNote(exportNote);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('تعذّر التصدير: $e')));
    }
  }

  /// تصدير الملاحظة إلى مستند Word‏ (.doc) مع الحفاظ على التنسيق.
  Future<void> _exportWord() async {
    final messenger = ScaffoldMessenger.of(context);
    await _save(force: true);
    final exportNote = _note.copyWith(content: _richContent);
    messenger.showSnackBar(const SnackBar(
        content: Text('جارٍ تجهيز ملف Word…'),
        duration: Duration(seconds: 1)));
    try {
      await WordExportService.exportNote(exportNote);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('تعذّر التصدير: $e')));
    }
  }

  Future<void> _editDrawing() async {
    await _ensureSaved();
    if (!mounted) return;
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => DrawingScreen(existingPath: _note.drawingPath),
      ),
    );
    if (path != null) {
      setState(() => _note = _note.copyWith(drawingPath: path));
      _dirty = true;
      await _save(force: true);
    }
  }

  void _onDrawingSetup() {
    // النوع رسم لكن لا يوجد رسم بعد: افتح لوحة الرسم مرة واحدة فقط.
    if (_drawingPrompted) return;
    if (_note.type == NoteType.drawing && _note.drawingPath == null) {
      _drawingPrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _editDrawing());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _onDrawingSetup();

    final settings = context.watch<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = AppColors.resolveNoteColor(_note.color, isDark);
    final grad = NoteGradient.parse(_note.gradient);
    final onBg = grad != null
        ? grad.onColor
        : (ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
            ? Colors.white
            : Colors.black87);
    _fgColor = onBg;

    final scaffold = Scaffold(
      backgroundColor: grad != null ? Colors.transparent : bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
          backgroundColor: grad != null ? Colors.transparent : bg,
          actions: [
            IconButton(
              tooltip: _note.isPinned ? s.t('unpin') : s.t('pin'),
              icon: Icon(_note.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () async {
                await _ensureSaved();
                setState(() => _note = _note.copyWith(isPinned: !_note.isPinned));
                await context.read<NotesProvider>().togglePin(
                    _note.copyWith(isPinned: !_note.isPinned));
              },
            ),
            IconButton(
              tooltip: s.t('color'),
              icon: const Icon(Icons.palette_outlined),
              onPressed: () async {
                final res = await showColorPicker(context, _note.color,
                    currentStyle: _note.bgStyle,
                    currentGradient: _note.gradient,
                    currentOnLine: _note.ruleOnLine ?? settings.ruleOnLine,
                    currentThickness:
                        _note.ruleThickness ?? settings.ruleThickness,
                    currentOpacity: _note.ruleOpacity ?? settings.ruleOpacity,
                    currentLineHeight:
                        _note.ruleLineHeight ?? settings.noteLineHeight,
                    defaultColor: settings.defaultNoteColor,
                    defaultGradient: settings.defaultGradient);
                if (res != null) {
                  setState(() => _note = _note.copyWith(
                        color: res.value,
                        clearColor: res.value == null,
                        bgStyle: res.bgStyle,
                        gradient: res.gradient,
                        clearGradient: res.gradient == null,
                        ruleOnLine: res.ruleOnLine,
                        ruleThickness: res.ruleThickness,
                        ruleOpacity: res.ruleOpacity,
                        ruleLineHeight: res.ruleLineHeight,
                      ));
                  _dirty = true;
                  await _ensureSaved();
                  await _save(force: true);
                }
              },
            ),
            IconButton(
              tooltip: _note.isFavorite ? s.t('unfavorite') : s.t('favorite'),
              icon: Icon(_note.isFavorite ? Icons.star : Icons.star_border,
                  color: _note.isFavorite ? Colors.amber : null),
              onPressed: () async {
                await _ensureSaved();
                final updated = _note.copyWith(isFavorite: !_note.isFavorite);
                setState(() => _note = updated);
                await context.read<NotesProvider>().toggleFavorite(_note.copyWith(isFavorite: !updated.isFavorite));
              },
            ),
            IconButton(
              tooltip: s.t('reminder'),
              icon: const Icon(Icons.alarm),
              onPressed: () async {
                await _ensureSaved();
                if (mounted) await showReminderDialog(context, _note);
              },
            ),
            IconButton(
              tooltip: s.t('tags'),
              icon: const Icon(Icons.label_outline),
              onPressed: () => _editTags(s),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () async {
                await _ensureSaved();
                if (mounted) {
                  await showNoteActions(context, _note,
                      onDetails: () => _showDetails(s),
                      onStats: (_note.type == NoteType.text ||
                              _note.type == NoteType.checklist)
                          ? () => _showStats(s)
                          : null);
                }
                // أعد التحميل لتحديث الحالة (لون/تثبيت/قفل).
                final fresh = await context
                    .read<NotesProvider>()
                    .notes
                    .getNote(_note.id!);
                if (!mounted) return;
                // حُذفت (نُقلت للمهملات) ⇒ أغلق المحرّر دون إعادة حفظها.
                if (fresh == null || fresh.isDeleted) {
                  _deleted = true;
                  Navigator.pop(context);
                  return;
                }
                setState(() => _note = fresh);
              },
            ),
          ],
        ),
        body: SafeArea(
          child: DefaultTextStyle.merge(
            style: TextStyle(color: _fgColor),
            child: Column(
            children: [
              Expanded(
                child: _note.type == NoteType.text
                    ? _textLayout(s, onBg, settings)
                    : ListView(
                        // حشوة سفلية بقدر لوحة المفاتيح كي تبقى العناصر السفلية
                        // (ومنها مربعات الاختيار) قابلة للتمرير فوقها والضغط عليها.
                        padding: EdgeInsets.fromLTRB(16, 8, 16,
                            24 + MediaQuery.of(context).viewInsets.bottom),
                        children: [
                          PaperBackground(
                            style: _note.bgStyle,
                            lineColor: onBg,
                            gap: noteLineGap(settings,
                                lineHeight: _note.ruleLineHeight),
                            thickness:
                                _note.ruleThickness ?? settings.ruleThickness,
                            opacity:
                                _note.ruleOpacity ?? settings.ruleOpacity,
                            onLine: _note.ruleOnLine ?? settings.ruleOnLine,
                            fontSize: settings.noteFontSize,
                            topPadding: 0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _typeBody(s),
                            ),
                          ),
                        ],
                      ),
              ),
              // شريط أدوات التنسيق فوق لوحة المفاتيح مباشرة (يرتفع معها).
              // عند إخفاء الكيبورد نرفعه قليلًا عن الحافة كي لا يقع سحبه الأفقي
              // في منطقة إيماءات النظام السفلية (تبديل التطبيق/الرجوع).
              if (_note.type == NoteType.text && _richCtrl != null)
                Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom > 0
                          ? MediaQuery.of(context).viewInsets.bottom
                          : 6),
                  child: RichTextToolbar(
                    controller: _richCtrl!,
                    onExportPdf: _exportPdf,
                    onExportWord: _exportWord,
                  ),
                ),
            ],
          ),
          ),
        ),
    );

    final decorated = grad != null
        ? Container(
            decoration: BoxDecoration(gradient: grad.toGradient()),
            child: scaffold,
          )
        : scaffold;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onWillPop();
        if (mounted) Navigator.pop(context);
      },
      child: decorated,
    );
  }

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  // يُستخدم داخل شيت «التفاصيل» (خارج build) ⇒ نقرأ القائمة بـ read، ونحدّث
  // القيمة المعروضة محليًّا عبر StatefulBuilder.
  Widget _categorySelector(S s) {
    final provider = context.read<NotesProvider>();
    return StatefulBuilder(
      builder: (context, setSel) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: DropdownButton<int?>(
          value: _note.categoryId,
          isExpanded: true,
          isDense: true,
          hint: Text(s.t('no_category')),
          underline: const SizedBox.shrink(),
          items: [
            DropdownMenuItem(value: null, child: Text(s.t('no_category'))),
            ...provider.categories.map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 6, backgroundColor: Color(c.color)),
                    const SizedBox(width: 8),
                    Text(c.name),
                  ]),
                )),
          ],
          onChanged: (v) async {
            setState(
                () => _note = _note.copyWith(categoryId: v, clearCategory: v == null));
            setSel(() {});
            _dirty = true;
            await _save(force: true);
          },
        ),
      ),
    );
  }

  /// «تفاصيل» الملاحظة: تحرير العنوان والتصنيف، عرض التواريخ، وزر الحذف.
  Future<void> _showDetails(S s) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 4,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تفاصيل الملاحظة',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (ctx, setTitle) => TextField(
                controller: _titleCtrl,
                textInputAction: TextInputAction.done,
                textDirection: lineDirection(_titleCtrl.text),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: s.t('title_hint'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) {
                  _dirty = true;
                  setTitle(() {}); // تحديث اتجاه العنوان فورًا
                  if (mounted) setState(() {});
                },
              ),
            ),
            const SizedBox(height: 12),
            _categorySelector(s),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 18, color: Theme.of(context).hintColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'أُنشئت: ${_formatDate(_note.createdAt)}\n'
                    'عُدّلت: ${_formatDate(_note.updatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetCtx);
                  await _deleteNote();
                },
                icon: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                label: Text(s.t('delete'),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ينقل الملاحظة إلى المهملات ويُغلق المحرّر دون إعادة حفظها (بعد تأكيد).
  Future<void> _deleteNote() async {
    if (!await confirmDeleteNote(context)) return;
    await _ensureSaved();
    if (_note.id != null) {
      await context.read<NotesProvider>().moveToTrash(_note);
    }
    _deleted = true;
    if (mounted) Navigator.pop(context);
  }

  /// تخطيط ملاحظة النص: العنوان ثابت بالأعلى، والمحرّر يملأ الباقي ويمرّر
  /// داخليًا (viewport) — أداء سلس حتى مع المستندات الطويلة جدًّا.
  Widget _textLayout(S s, Color onBg, SettingsProvider settings) {
    // العنوان والتاريخ مخفيّان من الصفحة (يظهران في «تفاصيل» بقائمة الثلاث نقاط)
    // لتوفير أقصى مساحة للكتابة.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _richCtrl == null
              ? const SizedBox.shrink()
              // يُعاد بناء التسطير فقط (لا المحرّر) عند تغيّر المحتوى/الحجم.
              // نستمع لـ docRevision (تغيّر المستند) لا لكامل وحدة التحكّم، كي لا
              // يُعاد حساب التسطير في كل تحريك مؤشّر/سحب تحديد ⇒ تحديد ناعم.
              : ValueListenableBuilder<int>(
                  valueListenable: _richCtrl!.docRevision,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: RichTextEditorBody(
                        controller: _richCtrl!,
                        expand: true,
                        lineHeight: _note.ruleLineHeight),
                  ),
                  builder: (context, _, child) {
                    final lh = _note.ruleLineHeight ?? settings.noteLineHeight;
                    // حجم موحّد ⇒ تسطير منضبط معه؛ أحجام مختلطة (null) ⇒ نُلغي
                    // التسطير (نمط سادة) لأنه لا ينضبط مع أسطر متفاوتة الارتفاع.
                    final rulingSize =
                        noteRulingFontSize(_richCtrl!.quill, settings.noteFontSize);
                    final baseFont = rulingSize ?? settings.noteFontSize;
                    return PaperBackground(
                      style: rulingSize == null ? 0 : _note.bgStyle,
                      lineColor: onBg,
                      gap: baseFont * lh,
                      thickness: _note.ruleThickness ?? settings.ruleThickness,
                      opacity: _note.ruleOpacity ?? settings.ruleOpacity,
                      onLine: _note.ruleOnLine ?? settings.ruleOnLine,
                      fontSize: baseFont,
                      topPadding: 8,
                      // تتحرّك الأسطر مع تمرير الكتابة وتبقى محاذية لها.
                      scrollController: _richCtrl?.scroll,
                      child: child!,
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// النصّ الخام للإحصاء (من المحرّر الحيّ إن توفّر، وإلا من المحتوى المحفوظ).
  String _statsText() {
    if (_note.type == NoteType.checklist) {
      return _itemCtrls.map((c) => c.text).join('\n');
    }
    if (_richCtrl != null) {
      return _richCtrl!.quill.document.toPlainText();
    }
    return richToPlainText(_note.content);
  }

  /// ورقة إحصائيات الملاحظة: كلمات/أحرف/أسطر + زمن قراءة تقريبيّ.
  void _showStats(S s) {
    final text = _statsText();
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final chars = text.replaceAll('\n', '').length;
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).length;
    final minutes = (words / 200).ceil();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget row(IconData i, String label, String v) => ListTile(
              leading: Icon(i, color: Theme.of(ctx).colorScheme.primary),
              title: Text(label),
              trailing: Text(v,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(children: [
                  Icon(Icons.bar_chart,
                      color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(s.t('stats'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 17)),
                ]),
              ),
              row(Icons.text_fields, s.t('words'), '$words'),
              row(Icons.abc, s.t('characters'), '$chars'),
              row(Icons.notes, s.t('lines'), '$lines'),
              row(Icons.schedule, s.t('reading_time'),
                  '$minutes ${s.t('minute')}'),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _typeBody(S s) {
    switch (_note.type) {
      case NoteType.checklist:
        return _checklistBody(s);
      case NoteType.image:
        return _imageBody(s);
      case NoteType.audio:
        return _audioBody(s);
      case NoteType.pdf:
        return _pdfBody(s);
      case NoteType.drawing:
        return _drawingBody(s);
      case NoteType.password:
        return [
          PasswordForm(
            initial: _passwordEntry,
            onChanged: (entry) {
              _passwordEntry = entry;
              _onChanged();
            },
          ),
        ];
      case NoteType.text:
        return [
          if (_richCtrl != null) RichTextEditorBody(controller: _richCtrl!),
        ];
    }
  }

  Widget _contentField(S s) {
    return TextField(
      controller: _contentCtrl,
      maxLines: null,
      minLines: 8,
      textDirection: lineDirection(_contentCtrl.text),
      style: TextStyle(fontSize: 16, height: 1.5, color: _fgColor),
      decoration: InputDecoration(
        hintText: s.t('content_hint'),
        border: InputBorder.none,
        filled: false,
      ),
    );
  }

  /// شريط تقدّم قائمة المهام: نسبة المنجَز + «منجَز/الإجمالي» (يتلوّن أخضرَ عند
  /// اكتمال كل المهام).
  Widget _checklistProgress(S s, int done, int total) {
    final ratio = total == 0 ? 0.0 : done / total;
    final complete = done == total;
    final scheme = Theme.of(context).colorScheme;
    final color = complete ? Colors.green : scheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(complete ? Icons.check_circle : Icons.checklist,
                  size: 18, color: color),
              const SizedBox(width: 6),
              Text('${s.t('checklist_progress')}: $done/$total',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: color, fontSize: 13)),
              const Spacer(),
              Text('${(ratio * 100).round()}%',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: color, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _checklistBody(S s) {
    // نمط الكتابة من إعدادات الصفحة الافتراضية (الخط/الحجم/التباعد/اللون).
    final settings = context.read<SettingsProvider>();
    final base = TextStyle(
      fontFamily: settings.noteFontFamily,
      fontSize: settings.noteFontSize,
      height: settings.noteLineHeight,
      color: _fgColor,
    );
    final total = _checklist.where((c) => c.isTask).length;
    final done = _checklist.where((c) => c.isTask && c.isDone).length;
    return [
      if (total > 0) _checklistProgress(s, done, total),
      for (var i = 0; i < _checklist.length; i++)
        ChecklistTile(
          key: ValueKey('item_${_itemCtrls[i].hashCode}'),
          controller: _itemCtrls[i],
          focusNode: _itemFocus[i],
          baseStyle: base,
          isDone: _checklist[i].isDone,
          isTask: _checklist[i].isTask,
          onToggle: (v) {
            setState(() => _checklist[i] = _checklist[i].copyWith(isDone: v));
            _onChanged();
          },
          onToggleType: () {
            setState(() => _checklist[i] = _checklist[i]
                .copyWith(isTask: !_checklist[i].isTask, isDone: false));
            _onChanged();
          },
          onTextChanged: _onChanged,
          onSubmit: (rest) => _addItemAfter(i, text: rest),
          onDelete: () {
            setState(() {
              _checklist.removeAt(i);
              _itemCtrls.removeAt(i).dispose();
              _itemFocus.removeAt(i).dispose();
            });
            _onChanged();
          },
        ),
      TextButton.icon(
        onPressed: () {
          setState(() {
            _checklist.add(ChecklistItem(noteId: _note.id ?? 0, text: ''));
            _itemCtrls.add(TextEditingController());
            _itemFocus.add(FocusNode());
          });
        },
        icon: const Icon(Icons.add),
        label: Text(s.t('add_item')),
      ),
    ];
  }

  List<Widget> _imageBody(S s) {
    return [
      if (_note.imagePath != null && File(_note.imagePath!).existsSync())
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(File(_note.imagePath!), fit: BoxFit.cover),
        )
      else
        _attachButton(s.t('note_image'), Icons.add_photo_alternate, _attachImage),
      const SizedBox(height: 8),
      if (_note.imagePath != null)
        TextButton.icon(
          onPressed: _attachImage,
          icon: const Icon(Icons.edit),
          label: Text(s.t('note_image')),
        ),
      _contentField(s),
    ];
  }

  List<Widget> _audioBody(S s) {
    return [
      AudioNoteWidget(
        existingPath: _note.audioPath,
        onRecorded: (path) async {
          setState(() => _note = _note.copyWith(audioPath: path));
          _dirty = true;
          await _ensureSaved();
          await _save(force: true);
        },
      ),
      const SizedBox(height: 12),
      _contentField(s),
    ];
  }

  List<Widget> _pdfBody(S s) {
    return [
      if (_note.pdfPath != null)
        ListTile(
          leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
          title: Text(_note.pdfPath!.split('/').last,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () => EditorAttachments.openFile(_note.pdfPath!),
          ),
        )
      else
        _attachButton(s.t('note_pdf'), Icons.attach_file, _attachPdf),
      const SizedBox(height: 8),
      _contentField(s),
    ];
  }

  List<Widget> _drawingBody(S s) {
    return [
      if (_note.drawingPath != null && File(_note.drawingPath!).existsSync())
        GestureDetector(
          onTap: _editDrawing,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: Colors.white,
              child: Image.file(File(_note.drawingPath!), fit: BoxFit.contain),
            ),
          ),
        )
      else
        _attachButton(s.t('drawing'), Icons.brush, _editDrawing),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _editDrawing,
        icon: const Icon(Icons.edit),
        label: Text(s.t('drawing')),
      ),
      _contentField(s),
    ];
  }

  Widget _attachButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Theme.of(context).dividerColor, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(label),
          ],
        ),
      ),
    );
  }

  /// تحرير وسوم الملاحظة في ورقة سفلية تُفتح عند الطلب فقط (لا تشغل حيّزًا دائمًا).
  Future<void> _editTags(S s) async {
    await _ensureSaved();
    if (!mounted) return;
    final ctrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('tags'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (_note.tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in _note.tags)
                      Chip(
                        label: Text('#$t'),
                        onDeleted: () async {
                          final updated = List<String>.from(_note.tags)
                            ..remove(t);
                          _note = _note.copyWith(tags: updated);
                          await _save(force: true);
                          setSheet(() {});
                          if (mounted) setState(() {});
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: s.t('add_tag'),
                  prefixIcon: const Icon(Icons.tag),
                ),
                onSubmitted: (value) async {
                  final v = value.trim();
                  if (v.isEmpty) return;
                  final updated = List<String>.from(_note.tags)..add(v);
                  _note = _note.copyWith(tags: updated);
                  ctrl.clear();
                  await _save(force: true);
                  setSheet(() {});
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// عنصر سطر في قائمة المهام: مربع اختيار يعمل + كتابة بمحاذاة تلقائية لكل سطر.
///
/// عنصر مستقلّ بحالته الخاصة كي يتحدّث اتجاهه دون إعادة بناء القائمة كلها (ما
/// كان يُفسد لمس بعض المربعات). عربي ⇒ المربع يمين والكتابة يمين، إنجليزي ⇒ العكس.
class ChecklistTile extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle baseStyle; // نمط الكتابة من إعدادات الصفحة الافتراضية
  final bool isDone;
  final bool isTask; // مهمة (بمربع) أو نصّ عادي (بلا مربع)
  final ValueChanged<bool> onToggle;
  final VoidCallback onToggleType; // تحويل مهمة⇄نص
  final VoidCallback onTextChanged;
  // Enter ⇒ سطر/مهمة جديدة. الوسيط = النصّ المنقول لما بعد المؤشّر (عند التقسيم).
  final ValueChanged<String> onSubmit;
  final VoidCallback onDelete;

  const ChecklistTile({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.baseStyle,
    required this.isDone,
    required this.isTask,
    required this.onToggle,
    required this.onToggleType,
    required this.onTextChanged,
    required this.onSubmit,
    required this.onDelete,
  });

  /// اتجاه النص حسب أول حرف قويّ (الدالة المشتركة الموحّدة في كل التطبيق).
  static TextDirection dirOf(String s) => lineDirection(s);

  @override
  State<ChecklistTile> createState() => _ChecklistTileState();
}

class _ChecklistTileState extends State<ChecklistTile> {
  late TextDirection _dir;

  @override
  void initState() {
    super.initState();
    _dir = ChecklistTile.dirOf(widget.controller.text);
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant ChecklistTile old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
      _dir = ChecklistTile.dirOf(widget.controller.text);
    }
  }

  void _onText() {
    final text = widget.controller.text;
    // كشف موثوق لـ Enter على **كل** لوحات المفاتيح: في حقل متعدّد الأسطر يُدرج
    // Enter محرف سطر جديد دائمًا (بخلاف onSubmitted الذي قد لا يُطلَق على حقل
    // فارغ في بعض اللوحات — وهو سبب «لا ينزل سطر جديد إلا بعد الكتابة»).
    if (text.contains('\n')) {
      final idx = text.indexOf('\n');
      final before = text.substring(0, idx);
      final after = text.substring(idx + 1);
      // أبقِ ما قبل Enter في السطر الحالي (دفعة واحدة لتفادي وميض سطرين).
      widget.controller.value = TextEditingValue(
        text: before,
        selection: TextSelection.collapsed(offset: before.length),
      );
      final d = ChecklistTile.dirOf(before);
      if (d != _dir && mounted) setState(() => _dir = d);
      widget.onSubmit(after); // أنشئ سطرًا جديدًا (مع النص المنقول إن وُجد).
      return;
    }
    final d = ChecklistTile.dirOf(text);
    if (d != _dir && mounted) setState(() => _dir = d);
    widget.onTextChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: _dir,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // مهمة: مربع اختيار (لمس = تعليم، لمس مطوّل = تحويل لنصّ).
          // نصّ عادي: دائرة باهتة (لمس = تحويل لمهمة).
          if (widget.isTask)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onToggle(!widget.isDone),
              onLongPress: widget.onToggleType,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Icon(
                  widget.isDone
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 22,
                  color: widget.isDone ? scheme.primary : scheme.outline,
                ),
              ),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onToggleType,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Icon(Icons.radio_button_unchecked,
                    size: 16, color: scheme.outline.withValues(alpha: 0.5)),
              ),
            ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              textDirection: _dir,
              // حقل متعدّد الأسطر كي يُدرج Enter محرف سطر نلتقطه في [_onText]
              // ونحوّله إلى عنصر جديد — يعمل حتى على السطر الأول الفارغ.
              minLines: 1,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: widget.baseStyle.copyWith(
                decoration: (widget.isTask && widget.isDone)
                    ? TextDecoration.lineThrough
                    : null,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDelete,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(Icons.close, size: 18, color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}
