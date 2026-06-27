import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/ringtone_picker.dart';
import '../../services/tone_preview.dart';
import '../settings/settings_provider.dart';
import 'sound_catalog.dart';

/// «مكتبة الأصوات»: نغمات أصلية مصنّفة مع معاينة، تعيين افتراضيّ، ومفضّلة.
/// تعمل أوفلاين بالكامل (كل الأصوات مضمّنة داخل التطبيق).
class SoundLibraryScreen extends StatefulWidget {
  const SoundLibraryScreen({super.key});

  @override
  State<SoundLibraryScreen> createState() => _SoundLibraryScreenState();
}

class _SoundLibraryScreenState extends State<SoundLibraryScreen> {
  String? _playing;
  bool _favOnly = false;

  @override
  void dispose() {
    TonePreview.stop();
    super.dispose();
  }

  Future<void> _preview(String id) async {
    setState(() => _playing = id);
    await TonePreview.play(id);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final st = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('sound_library')),
        actions: [
          IconButton(
            tooltip: s.t('favorites'),
            icon: Icon(_favOnly ? Icons.favorite : Icons.favorite_border,
                color: _favOnly ? Colors.pink : null),
            onPressed: () => setState(() => _favOnly = !_favOnly),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final uri = await RingtonePicker.pick(current: st.customToneUri);
          if (uri != null) {
            final title = await RingtonePicker.title(uri);
            await st.setCustomTone(uri, title);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.t('done'))));
            }
          }
        },
        icon: const Icon(Icons.library_add),
        label: Text(s.t('import_tone')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
        children: [
          // نغمة الجهاز المستوردة (تظهر هنا بعد الاستيراد، قابلة للتعيين/التغيير).
          if (st.customToneUri != null && !_favOnly) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
              child: Row(children: [
                Icon(Icons.smartphone, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(s.t('device_tones'),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: scheme.onSurface)),
              ]),
            ),
            _DeviceToneTile(
              title: st.customToneTitle ?? s.t('device_tones'),
              selected: st.alarmTone == 'custom',
              onSetDefault: () => st.setAlarmTone('custom'),
              onChange: () async {
                final uri = await RingtonePicker.pick(current: st.customToneUri);
                if (uri == null) return;
                final title = await RingtonePicker.title(uri);
                await st.setCustomTone(uri, title);
              },
            ),
          ],
          for (final cat in soundCategories) ...[
            () {
              final tones = soundCatalog
                  .where((t) => t.categoryKey == cat.key)
                  .where((t) => !_favOnly || st.isFavoriteTone(t.id))
                  .toList();
              if (tones.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                    child: Row(children: [
                      Icon(cat.icon, color: cat.color, size: 20),
                      const SizedBox(width: 8),
                      Text(s.t(cat.key),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: scheme.onSurface)),
                    ]),
                  ),
                  for (final tone in tones)
                    _ToneTile(
                      tone: tone,
                      color: cat.color,
                      selected: st.alarmTone == tone.id,
                      favorite: st.isFavoriteTone(tone.id),
                      playing: _playing == tone.id,
                      onPreview: () => _preview(tone.id),
                      onSetDefault: () => st.setAlarmTone(tone.id),
                      onFav: () => st.toggleFavoriteTone(tone.id),
                    ),
                ],
              );
            }(),
          ],
        ],
      ),
    );
  }
}

/// بطاقة نغمة الجهاز المستوردة (تعيين كافتراضيّ / تغييرها).
class _DeviceToneTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onSetDefault;
  final VoidCallback onChange;
  const _DeviceToneTile({
    required this.title,
    required this.selected,
    required this.onSetDefault,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.primary;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: selected ? color.withOpacity(0.10) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: selected
            ? BorderSide(color: color, width: 1.5)
            : BorderSide(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.music_note, color: color, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14.5)),
            ),
            TextButton(onPressed: onChange, child: Text(s.t('change'))),
            selected
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.check_circle, color: color),
                  )
                : TextButton(
                    onPressed: onSetDefault,
                    child: Text(s.t('set_as_default')),
                  ),
          ],
        ),
      ),
    );
  }
}

class _ToneTile extends StatelessWidget {
  final SoundTone tone;
  final Color color;
  final bool selected;
  final bool favorite;
  final bool playing;
  final VoidCallback onPreview;
  final VoidCallback onSetDefault;
  final VoidCallback onFav;
  const _ToneTile({
    required this.tone,
    required this.color,
    required this.selected,
    required this.favorite,
    required this.playing,
    required this.onPreview,
    required this.onSetDefault,
    required this.onFav,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: selected ? color.withOpacity(0.10) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: selected
            ? BorderSide(color: color, width: 1.5)
            : BorderSide(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            // معاينة.
            IconButton(
              onPressed: onPreview,
              icon: Icon(playing ? Icons.graphic_eq : Icons.play_circle_fill,
                  color: color, size: 30),
              tooltip: s.t('preview'),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tone.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5)),
                  const SizedBox(height: 3),
                  // مستوى الهدوء (نقاط).
                  Row(children: [
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Icon(
                          i < tone.calm ? Icons.circle : Icons.circle_outlined,
                          size: 8,
                          color: i < tone.calm
                              ? color
                              : scheme.onSurface.withOpacity(0.3),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text(s.t('calm_level'),
                        style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurface.withOpacity(0.5))),
                  ]),
                ],
              ),
            ),
            // مفضّلة.
            IconButton(
              onPressed: onFav,
              icon: Icon(favorite ? Icons.favorite : Icons.favorite_border,
                  color: favorite ? Colors.pink : scheme.outline, size: 22),
            ),
            // تعيين افتراضيّ.
            selected
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.check_circle, color: color),
                  )
                : TextButton(
                    onPressed: onSetDefault,
                    child: Text(s.t('set_as_default')),
                  ),
          ],
        ),
      ),
    );
  }
}
