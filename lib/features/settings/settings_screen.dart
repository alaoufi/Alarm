import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../services/ringtone_picker.dart';
import '../../services/tone_preview.dart';
import '../../services/update_service.dart';
import '../backup/backup_screen.dart';
import '../backup/daily_backup_switch.dart';
import '../help/help_guide_screen.dart';
import '../reminders/dismiss_challenge_prompt.dart';
import '../reminders/reminder_defaults_screen.dart';
import '../reminders/reliability_test_screen.dart';
import '../security/security_settings_screen.dart';
import '../sounds/sound_library_screen.dart';
import 'settings_provider.dart';

/// شاشة الإعدادات — مخصّصة لتطبيق التنبيهات: بطاقات بارزة ثلاثية الأبعاد قابلة
/// للطيّ، مجمّعة في أربعة محاور واضحة (المظهر واللغة · التنبيهات والصوت ·
/// الأمان والنسخ · حول ومساعدة).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // رأس عصري بتدرّج لوني.
          SliverAppBar.large(
            pinned: true,
            title: Text(s.t('settings'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            flexibleSpace: FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      scheme.primaryContainer.withOpacity(0.7),
                      scheme.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 28),
            sliver: SliverList.list(
              children: [
                _groupCard(
                  context,
                  icon: Icons.palette_outlined,
                  title: s.t('appearance'),
                  subtitle: 'اللغة، الوضع، اللون، الخط',
                  initiallyExpanded: true,
                  children: _appearance(context, s, settings),
                ),
                _groupCard(
                  context,
                  icon: Icons.notifications_active_outlined,
                  title: 'التنبيهات والصوت',
                  subtitle: 'النغمة، رفع الصوت، الإعدادات الافتراضية',
                  children: _remindersSound(context, s, settings),
                ),
                _groupCard(
                  context,
                  icon: Icons.shield_outlined,
                  title: 'الأمان والنسخ الاحتياطي',
                  subtitle: 'القفل، النسخ، المزامنة السحابية',
                  children: [
                    const DailyBackupSwitch(),
                    _nav(context, Icons.lock_outline, s.t('security'),
                        const SecuritySettingsScreen()),
                    _nav(context, Icons.backup_outlined,
                        'النسخ الاحتياطي والمشاركة السحابية',
                        const BackupScreen()),
                  ],
                ),
                _groupCard(
                  context,
                  icon: Icons.info_outline,
                  title: 'حول ومساعدة',
                  subtitle: 'الإصدار، التحديث، الدليل',
                  children: _aboutHelp(context, s),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===================== بطاقة مجموعة قابلة للطيّ (ثلاثية الأبعاد) =====================

  Widget _groupCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(14, 7, 14, 7),
      elevation: 4,
      shadowColor: scheme.shadow.withOpacity(0.5),
      surfaceTintColor: scheme.surfaceTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // إزالة خطوط ExpansionTile العلوية/السفلية لمظهر أنظف.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer,
                  scheme.primaryContainer.withOpacity(0.6),
                ],
              ),
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer, size: 23),
          ),
          title: Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: subtitle == null
              ? null
              : Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          initiallyExpanded: initiallyExpanded,
          childrenPadding: const EdgeInsets.only(bottom: 10),
          children: children,
        ),
      ),
    );
  }

  // ===================== المظهر واللغة =====================

  List<Widget> _appearance(BuildContext context, S s, SettingsProvider st) {
    final scheme = Theme.of(context).colorScheme;
    return [
      // اللغة — في الأعلى لسهولة الوصول، ببطاقة بارزة.
      Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer.withOpacity(0.55),
              scheme.primaryContainer.withOpacity(0.20),
            ],
          ),
          border: Border.all(color: scheme.primary.withOpacity(0.25)),
        ),
        child: ListTile(
          leading: Icon(Icons.language, color: scheme.primary),
          title: Text(s.t('language'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          trailing: DropdownButton<String>(
            value: st.locale.languageCode,
            underline: const SizedBox.shrink(),
            items: [
              for (final e in S.languages.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => st.setLocale(Locale(v ?? 'en')),
          ),
        ),
      ),

      // الوضع (نهاري/ليلي/النظام)
      ListTile(
        leading: const Icon(Icons.brightness_6_outlined),
        title: Text(s.t('theme_mode')),
        trailing: DropdownButton<ThemeMode>(
          value: st.themeMode,
          underline: const SizedBox.shrink(),
          items: [
            DropdownMenuItem(
                value: ThemeMode.system, child: Text(s.t('mode_system'))),
            DropdownMenuItem(
                value: ThemeMode.light, child: Text(s.t('mode_light'))),
            DropdownMenuItem(
                value: ThemeMode.dark, child: Text(s.t('mode_dark'))),
          ],
          onChanged: (v) => st.setThemeMode(v ?? ThemeMode.system),
        ),
      ),

      // لون السمة
      ListTile(
        leading: const Icon(Icons.color_lens_outlined),
        title: Text(s.t('theme_color')),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: AppColors.themeSeeds.values.map((c) {
              final selected = c.value == st.seedColor.value;
              return GestureDetector(
                onTap: () => st.setSeedColor(c),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.alphaBlend(Colors.white.withOpacity(0.30), c),
                        c,
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: c.withOpacity(selected ? 0.7 : 0.35),
                          blurRadius: selected ? 8 : 4,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
        ),
      ),

      // ألوان النظام (Dynamic Color) — أندرويد 12+
      SwitchListTile(
        secondary: const Icon(Icons.auto_awesome_outlined),
        title: Text(s.t('dynamic_color')),
        subtitle: Text(s.t('dynamic_color_desc')),
        value: st.dynamicColor,
        onChanged: st.setDynamicColor,
      ),

      // حجم خطّ الواجهة
      ListTile(
        leading: const Icon(Icons.format_size),
        title: Text(s.t('font_size')),
        subtitle: Slider(
          min: 0.85,
          max: 1.4,
          divisions: 11,
          label: '${(st.fontScale * 100).round()}%',
          value: st.fontScale,
          onChanged: st.setFontScale,
        ),
      ),

      // نوع خطّ الواجهة
      ListTile(
        leading: const Icon(Icons.font_download_outlined),
        title: const Text('نوع الخط'),
        trailing: DropdownButton<String>(
          value: st.fontFamily,
          underline: const SizedBox.shrink(),
          onChanged: (v) {
            if (v != null) st.setFontFamily(v);
          },
          items: _fontDropdownItems(context),
        ),
      ),
    ];
  }

  // ===================== التنبيهات والصوت =====================

  /// شارة عنوان مجموعة صغيرة داخل البطاقة.
  Widget _miniHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      );

  /// عنصر نغمة قابل للاختيار (أيقونة + اسم + زرّ سماع + علامة تحديد).
  Widget _toneTile(BuildContext context, SettingsProvider st,
      {required String value, required IconData icon, required String label}) {
    final selected = st.alarmTone == value;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: selected ? scheme.primary : null),
      title: Text(label,
          style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'سماع',
            icon: Icon(Icons.play_circle_outline, color: scheme.primary),
            onPressed: () => TonePreview.play(value),
          ),
          selected
              ? Icon(Icons.check_circle, color: scheme.primary)
              : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
        ],
      ),
      onTap: () => st.setAlarmTone(value),
    );
  }

  List<Widget> _remindersSound(BuildContext context, S s, SettingsProvider st) {
    Future<void> pickDevice() async {
      final uri = await RingtonePicker.pick(current: st.customToneUri);
      if (uri != null) {
        final title = await RingtonePicker.title(uri);
        await st.setCustomTone(uri, title);
      }
    }

    final scheme = Theme.of(context).colorScheme;
    return [
      // إعدادات افتراضية للتنبيه (نغمة/غفوة/قبل الوقت…).
      _nav(context, Icons.tune, s.t('reminder_defaults'),
          const ReminderDefaultsScreen()),
      // وضع «لا يُفوَّت»: اختيار نوع التحدّي قبل إيقاف المنبّه.
      ListTile(
        leading: const Icon(Icons.gpp_maybe_outlined),
        title: const Text('وضع لا يُفوَّت'),
        subtitle: const Text('تحدٍّ قبل إيقاف المنبّه يمنع الإغلاق بالخطأ'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(
                  value: 0,
                  label: Text('معطّل'),
                  icon: Icon(Icons.block, size: 16)),
              ButtonSegment(
                  value: 1,
                  label: Text('أرقام'),
                  icon: Icon(Icons.calculate_outlined, size: 16)),
              ButtonSegment(
                  value: 2,
                  label: Text('كلمة'),
                  icon: Icon(Icons.keyboard_outlined, size: 16)),
            ],
            selected: {st.dismissChallenge},
            onSelectionChanged: (v) =>
                selectDismissChallenge(context, st, v.first),
          ),
        ),
      ),
      const Divider(height: 1),
      _miniHeader(context, 'نغمات كلاسيكية'),
      _toneTile(context, st,
          value: 'alarm', icon: Icons.notifications_active, label: 'إنذار'),
      _toneTile(context, st,
          value: 'chime', icon: Icons.notifications_none, label: 'لطيفة'),
      _toneTile(context, st,
          value: 'bell', icon: Icons.notifications, label: 'جرس'),
      const Divider(height: 1),
      _miniHeader(context, 'نغمات طبيعية ناعمة 🌿'),
      _toneTile(context, st,
          value: 'forest', icon: Icons.forest, label: 'غابة 🌳'),
      _toneTile(context, st,
          value: 'birds', icon: Icons.flutter_dash, label: 'طيور 🐦'),
      _toneTile(context, st,
          value: 'water', icon: Icons.water_drop, label: 'ماء 💧'),
      _toneTile(context, st,
          value: 'rain', icon: Icons.grain, label: 'مطر 🌧️'),
      _toneTile(context, st,
          value: 'ocean', icon: Icons.waves, label: 'محيط 🌊'),
      const Divider(height: 1),
      _miniHeader(context, 'من جهازك'),
      ListTile(
        leading: Icon(Icons.library_music_outlined,
            color: st.alarmTone == 'custom' ? scheme.primary : null),
        title: const Text('اختر نغمة من الجهاز'),
        subtitle: Text(
          st.alarmTone == 'custom'
              ? 'الحالية: ${st.customToneTitle ?? 'نغمة مخصّصة'}'
              : 'كل نغمات جهازك (بما فيها نغمات هواوي)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: st.alarmTone == 'custom'
            ? Icon(Icons.check_circle, color: scheme.primary)
            : const Icon(Icons.chevron_left),
        onTap: pickDevice,
      ),
      _nav(context, Icons.library_music_outlined, s.t('sound_library'),
          const SoundLibraryScreen()),
      const Divider(height: 1),
      _miniHeader(context, s.t('sound_options')),
      SwitchListTile(
        secondary: const Icon(Icons.volume_up_outlined),
        title: Text(s.t('auto_raise_volume')),
        subtitle: Text(s.t('auto_raise_volume_desc')),
        value: st.autoRaiseVolume,
        onChanged: (v) => st.setAutoRaiseVolume(v),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.trending_up),
        title: Text(s.t('gradual_volume')),
        subtitle: Text(s.t('gradual_volume_desc')),
        value: st.gradualVolume,
        onChanged: st.autoRaiseVolume ? (v) => st.setGradualVolume(v) : null,
      ),
    ];
  }

  // ===================== حول ومساعدة =====================

  List<Widget> _aboutHelp(BuildContext context, S s) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(s.t('about_desc'),
              style: Theme.of(context).textTheme.bodySmall),
        ),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) {
            final info = snap.data;
            final label = info == null
                ? '...'
                : 'الإصدار ${info.version}  •  رقم النسخة ${info.buildNumber}';
            return ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('إصدار التطبيق'),
              subtitle: Text(label),
            );
          },
        ),
        const _UpdateTile(),
        const Divider(height: 1),
        _nav(context, Icons.menu_book_outlined, s.t('user_guide'),
            const HelpGuideScreen()),
        _nav(context, Icons.health_and_safety_outlined,
            s.t('reliability_test'), const ReliabilityTestScreen()),
      ];

  /// عناصر قائمة اختيار الخط: مجمّعة حسب العائلة (نسخ/كوفي/…) برؤوس غير قابلة
  /// للاختيار، وكل خط باسمه العربيّ ومعروضًا بخطّه نفسه.
  List<DropdownMenuItem<String>> _fontDropdownItems(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final items = <DropdownMenuItem<String>>[];
    for (final g in SettingsProvider.fontGroups) {
      items.add(DropdownMenuItem<String>(
        enabled: false,
        value: '__g_${g.$1}',
        child: Text('— ${g.$1} —',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: hint)),
      ));
      for (final f in g.$2) {
        items.add(DropdownMenuItem<String>(
          value: f,
          child: Text(SettingsProvider.fontLabel(f),
              style: TextStyle(fontFamily: f)),
        ));
      }
    }
    return items;
  }

  Widget _nav(BuildContext context, IconData icon, String title, Widget page) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_left),
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
    );
  }
}

/// عنصر «تحديث التطبيق»: يتحقّق من أحدث نسخة، وإن توفّرت يحمّلها ويشغّل المثبّت.
class _UpdateTile extends StatefulWidget {
  const _UpdateTile();

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  UpdateInfo? _available;
  String? _status;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      final upd = await UpdateService.instance.check();
      if (!mounted) return;
      setState(() {
        _checking = false;
        _available = upd;
        // null هنا = «أنت على الأحدث» فعلًا (لا فشل اتصال — فالفشل يرمي استثناءً).
        _status = upd == null ? S.of(context).t('upd_latest') : null;
      });
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _status = e.message; // سبب الفشل الحقيقيّ بدل «أنت على الأحدث».
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _status = 'تعذّر التحقّق من التحديث.';
      });
    }
  }

  Future<void> _update() async {
    final upd = _available;
    if (upd == null) return;
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    final err = await UpdateService.instance.downloadAndInstall(
      upd.url,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() => _downloading = false);
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  /// مسار احتياطيّ دائم: تنزيل أحدث APK عبر المتصفّح — يعمل حتى لو تعذّر الفحص أو
  /// التثبيت داخل التطبيق (ما دام المتصفّح يصل إلى github.com).
  Future<void> _openInBrowser() async {
    await launchUrl(Uri.parse(UpdateService.downloadUrl),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;

    final Widget tile;
    if (_downloading) {
      tile = ListTile(
        leading: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2, value: _progress > 0 ? _progress : null),
        ),
        title: Text(s.t('upd_downloading')),
        subtitle: Text('${(_progress * 100).round()}%'),
      );
    } else if (_available != null) {
      tile = Card(
        color: scheme.primaryContainer,
        child: ListTile(
          leading: Icon(Icons.system_update, color: scheme.onPrimaryContainer),
          title: Text('${s.t('upd_available')} ${_available!.version}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: scheme.onPrimaryContainer)),
          subtitle: Text(s.t('upd_tap_install'),
              style: TextStyle(color: scheme.onPrimaryContainer)),
          trailing: FilledButton(
              onPressed: _update, child: Text(s.t('upd_update'))),
          onTap: _update,
        ),
      );
    } else {
      tile = ListTile(
        leading: const Icon(Icons.system_update_outlined),
        title: Text(s.t('upd_check')),
        subtitle: _status != null ? Text(_status!) : null,
        trailing: _checking
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_left),
        onTap: _checking ? null : _check,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        // زرّ احتياطيّ دائم يضمن التحديث حتى لو لم يعمل الفحص داخل التطبيق.
        if (!_downloading)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: const Text('تنزيل أحدث نسخة عبر المتصفّح'),
              onPressed: _openInBrowser,
            ),
          ),
      ],
    );
  }
}
