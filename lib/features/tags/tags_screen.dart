import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../widgets/ui_kit.dart';
import '../home/notes_provider.dart';

/// صفحة العلامات (الوسوم): اختيار وسم يفلتر القائمة الرئيسية، وتلوين كل وسم
/// بلون يختاره المستخدم (ضغطة مطوّلة) أو لون تلقائيّ مشتقّ من اسمه.
class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key});

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  List<({String name, int color})> _tags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tags = await context.read<NotesProvider>().allTagsWithColors();
    if (mounted) {
      setState(() {
        _tags = tags;
        _loading = false;
      });
    }
  }

  /// لون الوسم: المختار إن وُجد (≠0)، وإلا مشتقّ ثابت من نصّه.
  Color _colorOf(({String name, int color}) t) {
    if (t.color != 0) return Color(t.color);
    final hue = (t.name.hashCode % 360).abs().toDouble();
    return HSLColor.fromAHSL(1, hue, 0.5, 0.55).toColor();
  }

  /// لوحة ألوان لاختيار لون الوسم (مع خيار «تلقائي»).
  static const _palette = <Color>[
    Color(0xFFE53935), Color(0xFFD81B60), Color(0xFF8E24AA),
    Color(0xFF5E35B1), Color(0xFF3949AB), Color(0xFF1E88E5),
    Color(0xFF039BE5), Color(0xFF00897B), Color(0xFF43A047),
    Color(0xFF7CB342), Color(0xFFF9A825), Color(0xFFFB8C00),
    Color(0xFF6D4C41), Color(0xFF546E7A),
  ];

  Future<void> _pickColor(({String name, int color}) t) async {
    final s = S.of(context);
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${s.t('tag_color')} — ${t.name}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in _palette)
                    _swatch(ctx, t, c.value, c),
                  // تلقائي (يعيد اللون المشتقّ من الاسم).
                  _swatch(ctx, t, 0, null),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(
      BuildContext ctx, ({String name, int color}) t, int value, Color? c) {
    final selected = t.color == value;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () async {
        await context.read<NotesProvider>().setTagColor(t.name, value);
        if (ctx.mounted) Navigator.pop(ctx);
        await _load();
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: c ?? Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Theme.of(ctx).dividerColor,
            width: selected ? 3 : 1,
          ),
          boxShadow: selected && c != null
              ? [BoxShadow(color: c.withOpacity(0.6), blurRadius: 6)]
              : null,
        ),
        // «تلقائي» يظهر كأيقونة عجلة ألوان.
        child: c == null
            ? const Icon(Icons.auto_awesome, size: 20)
            : (selected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: gradientAppBar(context, s.t('tags_page')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tags.isEmpty
              ? const EmptyState(
                  icon: Icons.tag,
                  title: 'لا توجد وسوم بعد',
                  subtitle: 'أضف وسومًا للملاحظات لتظهر هنا')
              : Column(
                  children: [
                    // تلميح: اضغط مطوّلًا لتغيير اللون.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          Icon(Icons.palette_outlined,
                              size: 16,
                              color: Theme.of(context).hintColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(s.t('tag_color_hint'),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).hintColor)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _tags.map((t) {
                            final c = _colorOf(t);
                            return Material(
                              elevation: 2,
                              borderRadius: BorderRadius.circular(24),
                              shadowColor: c.withOpacity(0.5),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () {
                                  context
                                      .read<NotesProvider>()
                                      .setTagFilter(t.name);
                                  Navigator.pop(context);
                                },
                                onLongPress: () => _pickColor(t),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    gradient: LinearGradient(colors: [
                                      c.withOpacity(0.85),
                                      c.withOpacity(0.6),
                                    ]),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.tag,
                                          size: 18, color: Colors.white),
                                      const SizedBox(width: 6),
                                      Text(t.name,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
