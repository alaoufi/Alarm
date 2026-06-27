import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../data/models/note.dart';
import '../../widgets/note_actions.dart';
import '../../widgets/ui_kit.dart';
import '../../widgets/note_card.dart';
import '../editor/note_editor_screen.dart';
import '../home/notes_provider.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Note> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return; // قد تُستدعى بعد إغلاق الشاشة (عند العودة من المحرّر)
    final items = await context.read<NotesProvider>().getFavorites();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final provider = context.watch<NotesProvider>();

    return Scaffold(
      appBar: gradientAppBar(context, s.t('favorites')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? EmptyState(
                  icon: Icons.star_border, title: s.t('no_favorites'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: _items
                      .map((n) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: NoteCard(
                              note: n,
                              category: provider.categoryById(n.categoryId),
                              onTap: () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            NoteEditorScreen(noteId: n.id)));
                                await _load();
                              },
                              onLongPress: () async {
                                await showNoteActions(context, n);
                                await _load();
                              },
                            ),
                          ))
                      .toList(),
                ),
    );
  }
}
