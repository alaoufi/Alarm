import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/note.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/ui_kit.dart';
import '../editor/note_editor_screen.dart';
import '../editor/rich_text_field.dart';
import '../home/notes_provider.dart';

/// صفحة صيانة وتنظيف: تجمع الملاحظات «غير المرتّبة» وتتيح فتحها أو نقلها للسلة.
class CleanupScreen extends StatefulWidget {
  const CleanupScreen({super.key});

  @override
  State<CleanupScreen> createState() => _CleanupScreenState();
}

class _CleanupScreenState extends State<CleanupScreen> {
  bool _loading = true;
  List<Note> _noTitle = [], _noCategory = [], _veryShort = [], _duplicates = [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _loading = true);
    final provider = context.read<NotesProvider>();
    final all = (await provider.notes.getEverything())
        .where((n) => !n.isDeleted && !n.isArchived)
        .toList();

    final noTitle = <Note>[];
    final noCategory = <Note>[];
    final veryShort = <Note>[];
    final seen = <String, Note>{};
    final dups = <Note>[];

    for (final n in all) {
      final plain = richToPlainText(n.content).trim();
      if (n.title.trim().isEmpty) noTitle.add(n);
      if (n.categoryId == null) noCategory.add(n);
      if ((n.title.trim().length + plain.length) < 15 &&
          n.imagePath == null &&
          n.audioPath == null &&
          n.pdfPath == null &&
          n.drawingPath == null) {
        veryShort.add(n);
      }
      final key = '${n.title.trim()}|$plain';
      if (key != '|') {
        if (seen.containsKey(key)) {
          dups.add(n);
        } else {
          seen[key] = n;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _noTitle = noTitle;
      _noCategory = noCategory;
      _veryShort = veryShort;
      _duplicates = dups;
      _loading = false;
    });
  }

  Future<void> _open(Note n) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: n.id)));
    if (mounted) _scan();
  }

  Future<void> _trashAll(List<Note> notes, String label) async {
    final ok = await confirmDelete(context,
        title: 'نقل إلى السلة؟',
        message: 'نقل ${notes.length} ملاحظة ($label) إلى سلة المهملات؟',
        confirmLabel: 'نقل للسلة',
        icon: Icons.delete_sweep_outlined);
    if (!ok) return;
    final provider = context.read<NotesProvider>();
    for (final n in notes) {
      if (n.id != null) await provider.moveToTrash(n);
    }
    if (mounted) _scan();
  }

  @override
  Widget build(BuildContext context) {
    final allClean = _noTitle.isEmpty &&
        _noCategory.isEmpty &&
        _veryShort.isEmpty &&
        _duplicates.isEmpty;
    return Scaffold(
      appBar: gradientAppBar(context, 'تنظيف المذكرات', actions: [
        IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'إعادة الفحص',
            onPressed: _scan),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : allClean
              ? const EmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'كل شيء مرتّب 🎉',
                  subtitle: 'لا توجد ملاحظات تحتاج تنظيفًا')
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _section('ملاحظات بلا عنوان', Icons.title, _noTitle,
                        canTrash: true),
                    _section('ملاحظات بلا تصنيف', Icons.folder_off, _noCategory),
                    _section('ملاحظات قصيرة جدًّا', Icons.short_text, _veryShort,
                        canTrash: true),
                    _section('ملاحظات مكرّرة', Icons.copy_all, _duplicates,
                        canTrash: true),
                  ],
                ),
    );
  }

  Widget _section(String label, IconData icon, List<Note> notes,
      {bool canTrash = false}) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: GradientIcon(icon, size: 40),
          title: Text(label,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${notes.length} ملاحظة'),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
        for (final n in notes.take(50))
          ListTile(
            dense: true,
            title: Text(
              n.title.trim().isEmpty
                  ? richToPlainText(n.content).trim().isEmpty
                      ? '(فارغة)'
                      : richToPlainText(n.content).trim()
                  : n.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_left, size: 18),
            onTap: () => _open(n),
          ),
        if (canTrash)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                label: const Text('نقل الكل للسلة',
                    style: TextStyle(color: Colors.red)),
                onPressed: () => _trashAll(notes, label),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}
