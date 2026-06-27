import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../data/models/note.dart';
import '../../widgets/ui_kit.dart';
import '../editor/note_editor_screen.dart';
import '../home/notes_provider.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<Note> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return; // قد تُستدعى بعد إغلاق الشاشة (عند العودة من المحرّر)
    final items = await context.read<NotesProvider>().getArchived();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final provider = context.read<NotesProvider>();

    return Scaffold(
      appBar: gradientAppBar(context, s.t('archived')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const EmptyState(
                  icon: Icons.archive_outlined,
                  title: 'لا توجد ملاحظات مؤرشفة',
                  subtitle: 'الملاحظات المؤرشفة تظهر هنا')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final n = _items[i];
                    return AppCard(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NoteEditorScreen(noteId: n.id),
                          ),
                        );
                        await _load();
                      },
                      child: ListTile(
                        leading: const GradientIcon(Icons.archive_outlined),
                        title: Text(
                          n.title.isNotEmpty ? n.title : n.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: IconButton(
                          tooltip: s.t('unarchive'),
                          icon: const Icon(Icons.unarchive_outlined),
                          onPressed: () async {
                            await provider.setArchived(n, false);
                            await _load();
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
