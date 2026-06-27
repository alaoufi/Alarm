import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/enums.dart';
import '../../data/models/note.dart';
import '../editor/note_editor_screen.dart';
import '../editor/rich_text_field.dart';
import '../home/notes_provider.dart';

/// روابط الملاحظات الداخلية: اكتب [[اسم الملاحظة]] داخل النص لربطها.
///
/// هذه الورقة تعرض الروابط الصادرة من الملاحظة (وتفتحها أو تُنشئها)،
/// والروابط الخلفية (ملاحظات تشير إلى هذه الملاحظة).
Future<void> showNoteLinks(BuildContext context, Note note) async {
  final provider = context.read<NotesProvider>();
  final plain = richToPlainText(note.content);
  final outgoing = RegExp(r'\[\[([^\[\]]+)\]\]')
      .allMatches(plain)
      .map((m) => m.group(1)!.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
  final backlinks = await provider.notes.findBacklinks(note.title);

  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الروابط', style: Theme.of(sheetCtx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('اكتب [[اسم الملاحظة]] داخل النص لإنشاء رابط.',
                  style: Theme.of(sheetCtx).textTheme.bodySmall),
              const SizedBox(height: 12),
              Text('روابط صادرة (${outgoing.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (outgoing.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('لا روابط في هذه الملاحظة بعد.'),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final name in outgoing)
                      ActionChip(
                        avatar: const Icon(Icons.link, size: 18),
                        label: Text(name),
                        onPressed: () => _openLink(sheetCtx, name),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              Text('روابط خلفية (${backlinks.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (backlinks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('لا توجد ملاحظات تشير إلى هذه الملاحظة.'),
                )
              else
                ...backlinks.map((n) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.subdirectory_arrow_left),
                      title: Text(
                        n.title.trim().isEmpty ? '(بلا عنوان)' : n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        final nav = Navigator.of(sheetCtx);
                        nav.pop();
                        nav.push(MaterialPageRoute(
                            builder: (_) => NoteEditorScreen(noteId: n.id)));
                      },
                    )),
            ],
          ),
        ),
      ),
    ),
  );
}

/// يفتح ملاحظة بالاسم، أو يُنشئها إن لم تكن موجودة.
Future<void> _openLink(BuildContext context, String name) async {
  final nav = Navigator.of(context);
  final provider = context.read<NotesProvider>();
  nav.pop(); // إغلاق ورقة الروابط
  final existing = await provider.notes.findByTitle(name);
  final id = existing?.id ??
      await provider.saveNote(
        Note.create(type: NoteType.text, categoryId: provider.inboxId)
            .copyWith(title: name),
      );
  await nav.push(
    MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)),
  );
}

