import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/enums.dart';
import '../../widgets/ui_kit.dart';
import '../home/notes_provider.dart';

const _typeLabels = {
  NoteType.text: 'نص',
  NoteType.checklist: 'مهام',
  NoteType.image: 'صورة',
  NoteType.audio: 'صوت',
  NoteType.pdf: 'PDF',
  NoteType.drawing: 'رسم',
  NoteType.password: 'كلمة مرور',
};

/// ورقة البحث المتقدّم — عصرية ثلاثية الأبعاد: خيارات عالية التباين، وخطّ متدرّج
/// جميل يفصل بين الأقسام. تصفية حسب النوع/الحالة/المرفقات/التاريخ.
Future<void> showAdvancedFilter(BuildContext context) async {
  final provider = context.read<NotesProvider>();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) {
        final scheme = Theme.of(sheetCtx).colorScheme;
        final dark = Theme.of(sheetCtx).brightness == Brightness.dark;
        final surface = dark ? const Color(0xFF1E2230) : Colors.white;
        final chipBg = dark ? const Color(0xFF2A3040) : const Color(0xFFEFF2F6);

        Future<void> pickDate(bool isFrom) async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: sheetCtx,
            initialDate: (isFrom ? provider.fFrom : provider.fTo) ?? now,
            firstDate: DateTime(2015),
            lastDate: DateTime(now.year + 2),
          );
          if (d != null) {
            setSheet(() {
              if (isFrom) {
                provider.fFrom = DateTime(d.year, d.month, d.day);
              } else {
                provider.fTo = DateTime(d.year, d.month, d.day, 23, 59, 59);
              }
            });
          }
        }

        // رأس قسم: أيقونة + عنوان غامق.
        Widget header(String title, IconData icon) => Row(children: [
              Icon(icon, size: 19, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                      color: scheme.onSurface)),
            ]);

        // خطّ متدرّج جميل يفصل بين الأقسام (يخفت عند الطرفين).
        Widget divider() => Container(
              height: 2.5,
              margin: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(colors: [
                  scheme.primary.withOpacity(0.0),
                  scheme.primary.withOpacity(0.55),
                  scheme.primary.withOpacity(0.0),
                ]),
              ),
            );

        // رقاقة عالية التباين: محدّدة = ممتلئة بالأساسي + نص أبيض، وإلا حدّ واضح.
        Widget chip(String label, bool selected, ValueChanged<bool> on) =>
            ChoiceChip(
              label: Text(label),
              selected: selected,
              showCheckmark: true,
              checkmarkColor: Colors.white,
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(
                color: selected ? Colors.white : scheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
              ),
              selectedColor: scheme.primary,
              backgroundColor: chipBg,
              side: BorderSide(
                color: selected
                    ? scheme.primary
                    : scheme.outlineVariant.withOpacity(0.9),
                width: 1.3,
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: on,
            );

        Widget dateBtn(String label, IconData icon, VoidCallback onTap) =>
            Expanded(
              child: Material(
                color: chipBg,
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: onTap,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                          color: scheme.outlineVariant.withOpacity(0.9),
                          width: 1.3),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 13),
                    child: Row(children: [
                      Icon(icon, size: 17, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(label,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface)),
                    ]),
                  ),
                ),
              ),
            );

        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  offset: const Offset(0, -6),
                  blurRadius: 24,
                  spreadRadius: -4),
            ],
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetCtx).size.height * 0.82),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // مقبض السحب.
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: scheme.onSurface.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      // الترويسة: رجوع + شارة متدرّجة + عنوان.
                      Row(children: [
                        IconButton(
                          tooltip: 'رجوع',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                        gradientBadge(Icons.tune, scheme.primary,
                            size: 40, radius: 12, iconSize: 21),
                        const SizedBox(width: 10),
                        Text('بحث متقدّم',
                            style: Theme.of(sheetCtx)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ]),
                      divider(),

                      // النوع.
                      header('النوع', Icons.category_outlined),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in _typeLabels.entries)
                            chip(e.value, provider.fType == e.key,
                                (sel) => setSheet(() =>
                                    provider.fType = sel ? e.key : null)),
                        ],
                      ),
                      divider(),

                      // الحالة والمرفقات.
                      header('الحالة والمرفقات', Icons.label_outline),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          chip('مفضّلة', provider.fFav,
                              (v) => setSheet(() => provider.fFav = v)),
                          chip('مثبّتة', provider.fPinned,
                              (v) => setSheet(() => provider.fPinned = v)),
                          chip('مقفلة', provider.fLocked,
                              (v) => setSheet(() => provider.fLocked = v)),
                          chip('تحتوي صورة', provider.fImage,
                              (v) => setSheet(() => provider.fImage = v)),
                          chip('تحتوي صوت', provider.fAudio,
                              (v) => setSheet(() => provider.fAudio = v)),
                          chip('تحتوي PDF', provider.fPdf,
                              (v) => setSheet(() => provider.fPdf = v)),
                        ],
                      ),
                      divider(),

                      // نطاق التاريخ.
                      header('نطاق التاريخ (آخر تعديل)',
                          Icons.date_range_outlined),
                      const SizedBox(height: 10),
                      Row(children: [
                        dateBtn(
                            provider.fFrom == null
                                ? 'من'
                                : _fmt(provider.fFrom!),
                            Icons.calendar_today,
                            () => pickDate(true)),
                        const SizedBox(width: 10),
                        dateBtn(
                            provider.fTo == null ? 'إلى' : _fmt(provider.fTo!),
                            Icons.event,
                            () => pickDate(false)),
                      ]),

                      const SizedBox(height: 20),
                      // أزرار: مسح + تطبيق (متدرّج بظلّ).
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                side: BorderSide(
                                    color: scheme.outline, width: 1.3),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            onPressed: () {
                              provider.clearAdvancedFilter();
                              Navigator.pop(sheetCtx);
                            },
                            child: const Text('مسح الفلاتر',
                                style: TextStyle(fontWeight: FontWeight.bold)),
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
                                      Colors.white.withOpacity(0.18),
                                      scheme.primary),
                                  scheme.primary,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                    color: scheme.primary.withOpacity(0.45),
                                    offset: const Offset(0, 6),
                                    blurRadius: 14,
                                    spreadRadius: -3),
                              ],
                            ),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14))),
                              onPressed: () {
                                provider.applyAdvancedFilter();
                                Navigator.pop(sheetCtx);
                              },
                              icon: const Icon(Icons.search, size: 20),
                              label: const Text('تطبيق',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

String _fmt(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
