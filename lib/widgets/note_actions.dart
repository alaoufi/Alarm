import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/l10n/app_strings.dart';
import '../data/models/enums.dart';
import '../data/models/note.dart';
import '../features/editor/rich_text_field.dart';
import '../features/editor/share_image_screen.dart';
import '../features/home/notes_provider.dart';
import '../features/links/note_links.dart';
import '../features/reminders/reminder_dialog.dart';
import '../features/security/pin_setup.dart';
import '../features/settings/settings_provider.dart';
import '../services/notification_service.dart';
import '../services/pdf_export_service.dart';
import 'color_picker_sheet.dart';
import 'confirm_dialog.dart';

/// شيت إجراءات الملاحظة (عند الضغط المطوّل أو من المحرر).
///
/// [onDetails] (من المحرّر) يضيف عنصر «تفاصيل» يفتح العنوان والتاريخ والحذف.
Future<void> showNoteActions(BuildContext context, Note note,
    {VoidCallback? onDetails, VoidCallback? onSelect, VoidCallback? onStats}) async {
  final s = S.of(context);
  final provider = context.read<NotesProvider>();
  final settings = context.read<SettingsProvider>();
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      Widget tile(IconData icon, String label, VoidCallback onTap,
          {Color? color}) {
        return ListTile(
          leading: Icon(icon, color: color),
          title: Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          onTap: onTap,
        );
      }

      // قابل للتمرير ومحدود الارتفاع كي يظهر كل العناصر (ومنها «حذف») دائمًا.
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: SingleChildScrollView(
            child: Wrap(
              children: [
            if (onSelect != null) ...[
              tile(Icons.checklist_rtl, s.t('select_multiple'), () {
                Navigator.pop(context);
                onSelect();
              }),
              const Divider(height: 1),
            ],
            if (onDetails != null) ...[
              tile(Icons.info_outline, 'تفاصيل (العنوان والتاريخ)', () {
                Navigator.pop(context);
                onDetails();
              }),
              const Divider(height: 1),
            ],
            if (onStats != null) ...[
              tile(Icons.bar_chart, s.t('stats'), () {
                Navigator.pop(context);
                onStats();
              }),
              const Divider(height: 1),
            ],
            tile(
              note.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              note.isPinned ? s.t('unpin') : s.t('pin'),
              () async {
                Navigator.pop(context);
                await provider.togglePin(note);
              },
            ),
            tile(
              note.isFavorite ? Icons.star : Icons.star_border,
              note.isFavorite ? s.t('unfavorite') : s.t('favorite'),
              () async {
                Navigator.pop(context);
                await provider.toggleFavorite(note);
              },
              color: note.isFavorite ? Colors.amber.shade700 : null,
            ),
            tile(Icons.palette_outlined, s.t('color'), () async {
              Navigator.pop(context);
              final res = await showColorPicker(context, note.color,
                  currentStyle: note.bgStyle,
                  currentGradient: note.gradient,
                  currentOnLine: note.ruleOnLine ?? settings.ruleOnLine,
                  currentThickness:
                      note.ruleThickness ?? settings.ruleThickness,
                  currentOpacity: note.ruleOpacity ?? settings.ruleOpacity,
                  currentLineHeight:
                      note.ruleLineHeight ?? settings.noteLineHeight,
                  defaultColor: settings.defaultNoteColor,
                  defaultGradient: settings.defaultGradient);
              if (res != null) {
                await provider.saveNote(note.copyWith(
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
              }
            }),
            tile(Icons.alarm, s.t('reminder'), () async {
              Navigator.pop(context);
              await showReminderDialog(context, note);
            }),
            // تثبيت الملاحظة في شريط الإشعارات (إشعار صامت مستمرّ أمام المستخدم).
            if (note.id != null)
              FutureBuilder<bool>(
                future: NotificationService.instance.isPinnedId(note.id!),
                builder: (context, snap) {
                  final pinned = snap.data ?? false;
                  return tile(
                    pinned
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    pinned ? 'إزالة من الإشعارات' : 'تثبيت في الإشعارات',
                    () async {
                      Navigator.pop(context);
                      if (pinned) {
                        await NotificationService.instance
                            .cancelPinnedNote(note.id!);
                        messenger.showSnackBar(const SnackBar(
                            content: Text('أُزيلت من الإشعارات')));
                      } else {
                        await NotificationService.instance.showPinnedNote(
                            note.id!,
                            note.title,
                            richToPlainText(note.content));
                        messenger.showSnackBar(const SnackBar(
                            content: Text('ثُبّتت في الإشعارات 📌')));
                      }
                    },
                  );
                },
              ),
            tile(
              note.isLocked ? Icons.lock_open : Icons.lock_outline,
              note.isLocked ? s.t('unlock') : s.t('lock'),
              () async {
                Navigator.pop(context);
                if (!note.isLocked) {
                  // قبل قفل ملاحظة لأول مرة، تأكد من وجود رقم سري.
                  final ok = await ensurePinConfigured(context);
                  if (!ok) return;
                }
                await provider.setLocked(note, !note.isLocked);
              },
            ),
            tile(Icons.link, 'الروابط [[ ]]', () async {
              Navigator.pop(context);
              await showNoteLinks(context, note);
            }),
            tile(Icons.copy_all, s.t('duplicate'), () async {
              Navigator.pop(context);
              await provider.duplicate(note);
            }),
            tile(Icons.content_copy, s.t('copy'), () async {
              Navigator.pop(context);
              await Clipboard.setData(
                  ClipboardData(text: _asText(note)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(s.t('copied'))));
              }
            }),
            tile(Icons.share, s.t('share'), () async {
              Navigator.pop(context);
              await SharePlus.instance.share(ShareParams(text: _asText(note)));
            }),
            tile(Icons.image_outlined, s.t('share_image'), () async {
              Navigator.pop(context);
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ShareImageScreen(note: note)),
              );
            }),
            tile(Icons.picture_as_pdf_outlined, 'تصدير PDF', () async {
              Navigator.pop(context);
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(const SnackBar(
                  content: Text('جارٍ تجهيز ملف PDF…'),
                  duration: Duration(seconds: 1)));
              try {
                await PdfExportService.exportNote(note);
              } catch (e) {
                messenger.showSnackBar(
                    SnackBar(content: Text('تعذّر التصدير: $e')));
              }
            }),
            tile(
              note.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              note.isArchived ? s.t('unarchive') : s.t('archive'),
              () async {
                Navigator.pop(context);
                await provider.setArchived(note, !note.isArchived);
              },
            ),
            const Divider(height: 1),
            // حذف واضح بأسفل القائمة (أحمر) مع رسالة تأكيد.
            tile(Icons.delete_outline, s.t('delete'), () async {
              final ok = await confirmDeleteNote(context);
              if (!ok) return;
              // نحذف قبل إغلاق الشيت كي يكتشف المحرّر الحذف بشكل موثوق.
              await provider.moveToTrash(note);
              if (context.mounted) Navigator.pop(context);
            }, color: Theme.of(context).colorScheme.error),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// رسالة تحذير قبل الحذف. تعيد true إن أكّد المستخدم.
Future<bool> confirmDeleteNote(BuildContext context) {
  return confirmDelete(
    context,
    title: 'حذف الملاحظة؟',
    message: 'ستُنقل إلى المهملات ويمكنك استرجاعها منها لاحقًا.',
  );
}

/// نص النسخ/المشاركة: العنوان + المحتوى فقط — بدون التاريخ أو التصنيف.
/// لملاحظات النص الغني نحوّل Delta إلى نص صريح ليُنسخ نظيفًا.
String _asText(Note note) {
  final buffer = StringBuffer();
  if (note.title.trim().isNotEmpty) buffer.writeln(note.title);

  final body = note.type == NoteType.text
      ? richToPlainText(note.content)
      : note.content;
  if (body.trim().isNotEmpty) buffer.writeln(body);

  return buffer.toString().trim();
}
