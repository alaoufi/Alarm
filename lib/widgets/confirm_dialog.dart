import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import 'ui_kit.dart';

/// حوار تأكيد **عصري ثلاثي الأبعاد** موحّد عبر التطبيق.
///
/// يعرض شارة أيقونة بارزة بتدرّج وظلّ، عنوانًا، رسالة، وزرّي إجراء.
/// يعيد `true` عند التأكيد و`false` عند الإلغاء/الإغلاق.
/// [destructive] يلوّن الإجراء بالأحمر (مناسب للحذف).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  IconData icon = Icons.delete_outline,
  bool destructive = true,
  Color? accent,
}) async {
  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withOpacity(0.55),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final t = Curves.easeOutBack.transform(anim.value.clamp(0.0, 1.0));
      return Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.8 + 0.2 * t,
          child: _ConfirmCard(
            title: title,
            message: message,
            confirmLabel: confirmLabel,
            cancelLabel: cancelLabel,
            icon: icon,
            destructive: destructive,
            accent: accent,
          ),
        ),
      );
    },
  );
  return ok ?? false;
}

/// اختصار لتأكيد **حذف** عنصر (نمط أحمر).
Future<bool> confirmDelete(
  BuildContext context, {
  String? title,
  required String message,
  String? confirmLabel,
  IconData icon = Icons.delete_outline,
}) {
  final s = S.of(context);
  return confirmAction(
    context,
    title: title ?? '${s.t('delete')}؟',
    message: message,
    confirmLabel: confirmLabel ?? s.t('delete'),
    icon: icon,
    destructive: true,
  );
}

class _ConfirmCard extends StatelessWidget {
  final String title;
  final String message;
  final String? confirmLabel;
  final String? cancelLabel;
  final IconData icon;
  final bool destructive;
  final Color? accent;

  const _ConfirmCard({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.icon,
    required this.destructive,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color =
        accent ?? (destructive ? const Color(0xFFE53935) : scheme.primary);
    final surface = dark ? const Color(0xFF1E2230) : Colors.white;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  surface,
                  Color.alphaBlend(color.withOpacity(0.05), surface),
                ],
              ),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(dark ? 0.55 : 0.22),
                    offset: const Offset(0, 18),
                    blurRadius: 40,
                    spreadRadius: -8),
              ],
              border: Border.all(color: color.withOpacity(0.18)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // شارة أيقونة ثلاثية الأبعاد (تدرّج + توهّج).
                gradientBadge(icon, color, size: 74, iconSize: 38),
                const SizedBox(height: 18),
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                        color: scheme.onSurface)),
                const SizedBox(height: 8),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: scheme.onSurface.withOpacity(0.7))),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: scheme.onSurface,
                        backgroundColor:
                            scheme.surfaceContainerHighest.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(cancelLabel ?? s.t('cancel'),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.alphaBlend(
                                Colors.white.withOpacity(0.18), color),
                            color,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: color.withOpacity(0.45),
                              offset: const Offset(0, 6),
                              blurRadius: 14,
                              spreadRadius: -3),
                        ],
                      ),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(confirmLabel ?? s.t('delete'),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
