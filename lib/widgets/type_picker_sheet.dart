import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import '../data/models/enums.dart';

/// شيت لاختيار نوع الملاحظة الجديدة.
Future<NoteType?> showTypePicker(BuildContext context) {
  final s = S.of(context);
  return showModalBottomSheet<NoteType>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final items = <(NoteType, IconData, String)>[
        (NoteType.text, Icons.notes, s.t('note_text')),
        (NoteType.checklist, Icons.checklist, s.t('note_checklist')),
        (NoteType.image, Icons.image, s.t('note_image')),
        (NoteType.audio, Icons.mic, s.t('note_audio')),
        (NoteType.pdf, Icons.picture_as_pdf, s.t('note_pdf')),
        (NoteType.drawing, Icons.brush, s.t('note_drawing')),
        (NoteType.password, Icons.vpn_key, s.t('note_password')),
      ];
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(s.t('choose_type'),
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: items
                    .map((e) => _typeTile(context, e.$1, e.$2, e.$3))
                    .toList(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _typeTile(BuildContext context, NoteType type, IconData icon, String label) {
  final scheme = Theme.of(context).colorScheme;
  return Material(
    color: scheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop(context, type),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30, color: scheme.primary),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}
