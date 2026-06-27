import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../data/models/note.dart';
import '../../services/secure_screen.dart';
import '../../widgets/note_actions.dart';
import '../../widgets/note_card.dart';
import '../../widgets/ui_kit.dart';
import '../editor/note_editor_screen.dart';
import '../home/notes_provider.dart';

/// قسم الملاحظات السرية (المقفلة). يُدخَل إليه بعد فتح القفل،
/// ويُفعّل منع التصوير (FLAG_SECURE) طوال وجوده.
class SecretNotesScreen extends StatefulWidget {
  const SecretNotesScreen({super.key});

  @override
  State<SecretNotesScreen> createState() => _SecretNotesScreenState();
}

class _SecretNotesScreenState extends State<SecretNotesScreen> {
  List<Note> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SecureScreen.enable();
    _load();
  }

  @override
  void dispose() {
    SecureScreen.disable();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return; // قد تُستدعى بعد إغلاق الشاشة (عند العودة من المحرّر)
    final items = await context.read<NotesProvider>().getLocked();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final provider = context.watch<NotesProvider>();

    return Scaffold(
      appBar: gradientAppBar(context, s.t('secret_notes'),
          leading: const Icon(Icons.lock)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? EmptyState(
                  icon: Icons.lock_outline,
                  title: s.t('secret_empty'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: _items
                      .map((n) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: NoteCard(
                              note: n,
                              revealLocked: true,
                              category: provider.categoryById(n.categoryId),
                              onTap: () async {
                                // داخل القسم السري المستخدم موثّق؛ نفتح مباشرة.
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
