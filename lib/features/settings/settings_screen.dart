import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/note_gradient.dart';
import '../../data/models/enums.dart';
import '../../services/ringtone_picker.dart';
import '../../services/tone_preview.dart';
import '../../widgets/color_picker_sheet.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/paper_background.dart';
import '../home/notes_provider.dart';
import '../backup/backup_screen.dart';
import '../backup/daily_backup_switch.dart';
import '../categories/manage_categories_screen.dart';
import '../reminders/reminders_screen.dart';
import '../security/security_settings_screen.dart';
import '../../services/update_service.dart';
import '../trash/archive_screen.dart';
import '../trash/trash_screen.dart';
import 'settings_provider.dart';

/// شاشة الإعدادات — تصميم عصري مجمّع: بطاقات بارزة (ثلاثية الأبعاد) قابلة للطيّ،
/// كل مجموعة متشابهة في بطاقة واحدة لتنظيم أوضح.
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
                  icon: Icons.sticky_note_2_outlined,
                  title: 'الملاحظة الافتراضية',
                  subtitle: 'شكل الملاحظات الجديدة',
                  children: _noteDefaults(context, s, settings),
                ),
                _groupCard(
                  context,
                  icon: Icons.format_align_justify,
                  title: 'تسطير الصفحة',
                  subtitle: 'الخطوط خلف الكتابة',
                  children: _noteRuling(context, s, settings),
                ),
                _groupCard(
                  context,
                  icon: Icons.build_outlined,
                  title: 'أزرار شريط التنسيق',
                  subtitle: 'اختر الأدوات الظاهرة في المحرّر',
                  children: _toolbarButtons(context, s, settings),
                ),
                _groupCard(
                  context,
                  icon: Icons.edit_outlined,
                  title: 'التحرير والعرض',
                  subtitle: 'سلوك المحرّر وطريقة العرض',
                  children: _editingDisplay(context, s, settings),
                ),
                _groupCard(
                  context,
                  icon: Icons.notifications_active_outlined,
                  title: 'التنبيهات',
                  subtitle: 'نغمة التذكيرات',
                  children: _notifications(context, s, settings),
                ),
                _groupCard(
                  context,
                  icon: Icons.shield_outlined,
                  title: 'الأمان والنسخ الاحتياطي',
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
                  icon: Icons.folder_outlined,
                  title: 'التنظيم',
                  children: [
                    _nav(context, Icons.category_outlined,
                        s.t('manage_categories'),
                        const ManageCategoriesScreen()),
                    _nav(context, Icons.archive_outlined, s.t('archived'),
                        const ArchiveScreen()),
                    _nav(context, Icons.delete_outline, s.t('trash'),
                        const TrashScreen()),
                  ],
                ),
                _groupCard(
                  context,
                  icon: Icons.info_outline,
                  title: s.t('about'),
                  children: _about(context, s),
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

  // ===================== المظهر =====================

  List<Widget> _appearance(BuildContext context, S s, SettingsProvider st) => [
        // اللغة — في الأعلى لسهولة الوصول، ببطاقة بارزة.
        Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primaryContainer.withOpacity(0.55),
                Theme.of(context).colorScheme.primaryContainer.withOpacity(0.20),
              ],
            ),
            border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.25)),
          ),
          child: ListTile(
            leading: Icon(Icons.language,
                color: Theme.of(context).colorScheme.primary),
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
          subtitle: Wrap(
            spacing: 10,
            children: AppColors.themeSeeds.values.map((c) {
              final selected = c.value == st.seedColor.value;
              return GestureDetector(
                onTap: () => st.setSeedColor(c),
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: c.withOpacity(0.6), blurRadius: 6)]
                        : null,
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
        ),

        // ألوان النظام (Dynamic Color) — أندرويد 12+
        SwitchListTile(
          secondary: const Icon(Icons.palette_outlined),
          title: Text(s.t('dynamic_color')),
          subtitle: Text(s.t('dynamic_color_desc')),
          value: st.dynamicColor,
          onChanged: st.setDynamicColor,
        ),

        // عرض مدمج لبطاقات الملاحظات
        SwitchListTile(
          secondary: const Icon(Icons.density_small),
          title: Text(s.t('compact_view')),
          subtitle: Text(s.t('compact_view_desc')),
          value: st.compactCards,
          onChanged: st.setCompactCards,
        ),

        // حجم الخط (واجهة التطبيق)
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

        // نوع الخط
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

  // ===================== الملاحظة الافتراضية (المظهر) =====================

  static const _styleNames = [
    'سادة', 'مسطّر', 'شبكي', 'نقاط',
    'شبكة دقيقة', 'نقاط كبيرة', 'أسطر', 'مربعات',
  ];

  List<Widget> _noteDefaults(BuildContext context, S s, SettingsProvider st) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final styleName = _styleNames[st.defaultBgStyle.clamp(0, 7)];
    final defGrad = NoteGradient.parse(st.defaultGradient);

    return [
      // معاينة حيّة
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: _NotePreview(settings: st),
      ),

      // لون الخلفية ونمط الصفحة
      ListTile(
        leading: const Icon(Icons.palette_outlined),
        title: const Text('لون/تدرّج الخلفية ونمط الصفحة'),
        subtitle: Text(defGrad != null
            ? 'تدرّج لوني • النمط: $styleName'
            : 'النمط الحالي: $styleName'),
        trailing: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: defGrad == null
                ? AppColors.resolveNoteColor(st.defaultNoteColor, isDark)
                : null,
            gradient: defGrad?.toGradient(),
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
        ),
        onTap: () async {
          final res = await showColorPicker(context, st.defaultNoteColor,
              currentStyle: st.defaultBgStyle,
              currentGradient: st.defaultGradient,
              currentOnLine: st.ruleOnLine,
              currentThickness: st.ruleThickness,
              currentOpacity: st.ruleOpacity,
              currentLineHeight: st.noteLineHeight);
          if (res != null) {
            await st.setDefaultNoteColor(res.value);
            if (res.bgStyle != null) await st.setDefaultBgStyle(res.bgStyle!);
            await st.setDefaultGradient(res.gradient);
            if (res.ruleOnLine != null) await st.setRuleOnLine(res.ruleOnLine!);
            if (res.ruleThickness != null) {
              await st.setRuleThickness(res.ruleThickness!);
            }
            if (res.ruleOpacity != null) {
              await st.setRuleOpacity(res.ruleOpacity!);
            }
            if (res.ruleLineHeight != null) {
              await st.setNoteLineHeight(res.ruleLineHeight!);
            }
          }
        },
      ),

      // تعميم نمط الصفحة (خلفية + تباعد أسطر + تسطير) على كل الملاحظات الحالية
      ListTile(
        leading: const Icon(Icons.format_paint_outlined),
        title: const Text('تطبيق نمط الصفحة على كل الملاحظات'),
        subtitle: const Text(
            'الخلفية وتباعد الأسطر والتسطير على كل ملاحظاتك دفعةً واحدة'),
        onTap: () async {
          final res = await showColorPicker(context, st.defaultNoteColor,
              currentStyle: st.defaultBgStyle,
              currentGradient: st.defaultGradient,
              currentOnLine: st.ruleOnLine,
              currentThickness: st.ruleThickness,
              currentOpacity: st.ruleOpacity,
              currentLineHeight: st.noteLineHeight);
          if (res == null || !context.mounted) return;
          if (!await confirmAction(context,
              title: 'تطبيق على كل الملاحظات؟',
              message:
                  'ستأخذ كل ملاحظاتك الحالية هذه الخلفية وتباعد الأسطر والتسطير. '
                  'خط المتن وحجمه عامّان (يطبَّقان على الكل تلقائيًّا)، والاتجاه يضبط نفسه لكل سطر. '
                  'يمكنك تغيير أي ملاحظة لاحقًا.',
              confirmLabel: 'تطبيق',
              icon: Icons.format_paint_outlined,
              destructive: false)) {
            return;
          }
          final notesProvider = context.read<NotesProvider>();
          // تباعد الأسطر يُحفظ أيضًا كافتراضي عامّ (للملاحظات الجديدة).
          if (res.ruleLineHeight != null) {
            await st.setNoteLineHeight(res.ruleLineHeight!);
          }
          final n = await notesProvider.notes.applyBackgroundToAll(
            color: res.value,
            bgStyle: res.bgStyle ?? st.defaultBgStyle,
            gradient: res.gradient,
            ruleOnLine: res.ruleOnLine,
            ruleThickness: res.ruleThickness,
            ruleOpacity: res.ruleOpacity,
            ruleLineHeight: res.ruleLineHeight,
          );
          await notesProvider.refresh();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('طُبّق نمط الصفحة على $n ملاحظة')),
            );
          }
        },
      ),

      // خط المتن
      ListTile(
        leading: const Icon(Icons.text_fields),
        title: const Text('خط المتن'),
        trailing: DropdownButton<String>(
          value: st.noteFontFamily,
          underline: const SizedBox.shrink(),
          onChanged: (v) {
            if (v != null) st.setNoteFontFamily(v);
          },
          items: _fontDropdownItems(context),
        ),
      ),

      // حجم خط المتن
      ListTile(
        leading: const Icon(Icons.format_size),
        title: const Text('حجم خط المتن'),
        subtitle: Slider(
          min: 12,
          max: 30,
          divisions: 18,
          label: st.noteFontSize.round().toString(),
          value: st.noteFontSize.clamp(12, 30),
          onChanged: st.setNoteFontSize,
        ),
      ),

      // تباعد الأسطر
      ListTile(
        leading: const Icon(Icons.format_line_spacing),
        title: const Text('تباعد الأسطر'),
        subtitle: Slider(
          min: 0.8,
          max: 3.0,
          divisions: 22,
          label: st.noteLineHeight.toStringAsFixed(2),
          value: st.noteLineHeight.clamp(0.8, 3.0),
          onChanged: st.setNoteLineHeight,
        ),
      ),

    ];
  }

  // ===================== أزرار شريط التنسيق =====================

  /// إظهار/إخفاء وترتيب كل زرّ في شريط تنسيق المحرّر.
  /// الترتيب بأسهم لأعلى/لأسفل، والإظهار بمفتاح — ويُطبَّق فورًا على المحرّر.
  List<Widget> _toolbarButtons(BuildContext context, S s, SettingsProvider st) {
    final order = st.toolOrder;
    final scheme = Theme.of(context).colorScheme;
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(
          'رتّب الأزرار بالأسهم ↑ ↓، وأظهِر/أخفِ كلًّا منها بالمفتاح. '
          'المخفيّة لا تُحذف وظيفتها — يمكنك إعادتها في أيّ وقت.',
          style: TextStyle(fontSize: 12.5, height: 1.4),
        ),
      ),
      for (var i = 0; i < order.length; i++)
        ListTile(
          dense: true,
          key: ValueKey(order[i]),
          title: Text(SettingsProvider.toolbarTools[order[i]] ?? order[i]),
          // أسهم الترتيب + مفتاح الإظهار.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                tooltip: 'تحريك لأعلى',
                visualDensity: VisualDensity.compact,
                onPressed:
                    i == 0 ? null : () => st.moveTool(order[i], up: true),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                tooltip: 'تحريك لأسفل',
                visualDensity: VisualDensity.compact,
                onPressed: i == order.length - 1
                    ? null
                    : () => st.moveTool(order[i], up: false),
              ),
              Switch(
                value: st.isToolVisible(order[i]),
                activeColor: scheme.primary,
                onChanged: (v) => st.setToolVisible(order[i], v),
              ),
            ],
          ),
        ),
    ];
  }

  // ===================== تسطير الصفحة =====================

  List<Widget> _noteRuling(BuildContext context, S s, SettingsProvider st) => [
        // تفعيل/إلغاء التسطير افتراضيًّا (إلغاء ⇒ خلفية سادة بلا خطوط).
        SwitchListTile(
          secondary: const Icon(Icons.format_align_justify),
          title: const Text('إظهار التسطير'),
          subtitle: const Text('عند الإيقاف تكون الخلفية سادة بلا خطوط'),
          value: st.defaultBgStyle != 0,
          onChanged: (on) => st.setDefaultBgStyle(on ? 1 : 0),
        ),

        // محاذاة الكتابة: على السطر / بين السطرين
        // نضع الأزرار في سطر مستقلّ تحت العنوان (subtitle) لا في trailing، وإلا
        // انضغط العنوان في عمود ضيّق فظهر حرفًا تحت حرف.
        ListTile(
          leading: const Icon(Icons.vertical_align_center),
          title: const Text('محاذاة الكتابة'),
          subtitle: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12),
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(value: true, label: Text('على السطر')),
                  ButtonSegment(value: false, label: Text('بين السطرين')),
                ],
                selected: {st.ruleOnLine},
                onSelectionChanged: (v) => st.setRuleOnLine(v.first),
              ),
            ),
          ),
        ),

        // سماكة الأسطر
        ListTile(
          leading: const Icon(Icons.line_weight),
          title: const Text('سماكة الأسطر'),
          subtitle: Slider(
            min: 0.5,
            max: 3.0,
            divisions: 10,
            label: st.ruleThickness.toStringAsFixed(1),
            value: st.ruleThickness.clamp(0.5, 3.0),
            onChanged: st.setRuleThickness,
          ),
        ),

        // شفافية الأسطر
        ListTile(
          leading: const Icon(Icons.opacity),
          title: const Text('شفافية الأسطر'),
          subtitle: Slider(
            min: 0.03,
            max: 0.6,
            divisions: 19,
            label: '${(st.ruleOpacity * 100).round()}%',
            value: st.ruleOpacity.clamp(0.03, 0.6),
            onChanged: st.setRuleOpacity,
          ),
        ),
      ];

  // ===================== التحرير والعرض =====================

  List<Widget> _editingDisplay(
          BuildContext context, S s, SettingsProvider st) =>
      [
        // إخفاء قائمة (نسخ/لصق/تحديد الكل) أثناء الكتابة
        SwitchListTile(
          secondary: const Icon(Icons.content_paste_off_outlined),
          title: const Text('إخفاء قائمة النسخ/اللصق'),
          subtitle: const Text(
              'تمنع ظهور شريط (نسخ/لصق/تحديد الكل) الذي قد يغطّي اختيار الخط والحجم أثناء التحرير.'),
          value: st.hideSelectionMenu,
          onChanged: st.setHideSelectionMenu,
        ),

        // مكان صفحة «معلومات عامة»
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('مكان صفحة «معلومات»'),
          trailing: DropdownButton<InfoPlacement>(
            value: st.infoPlacement,
            underline: const SizedBox.shrink(),
            onChanged: (v) {
              if (v != null) st.setInfoPlacement(v);
            },
            items: const [
              DropdownMenuItem(
                  value: InfoPlacement.tab, child: Text('تبويب علوي')),
              DropdownMenuItem(
                  value: InfoPlacement.menu, child: Text('قائمة النقاط')),
              DropdownMenuItem(
                  value: InfoPlacement.drawer, child: Text('القائمة الجانبية')),
            ],
          ),
        ),

        // طريقة العرض
        ListTile(
          leading: const Icon(Icons.dashboard_outlined),
          title: Text(s.t('layout')),
          trailing: SegmentedButton<NoteLayout>(
            segments: [
              ButtonSegment(
                  value: NoteLayout.grid, label: Text(s.t('layout_grid'))),
              ButtonSegment(
                  value: NoteLayout.list, label: Text(s.t('layout_list'))),
            ],
            selected: {st.layout},
            onSelectionChanged: (v) => st.setLayout(v.first),
          ),
        ),
      ];

  // ===================== التنبيهات =====================

  /// شارة عنوان مجموعة صغيرة داخل البطاقة.
  Widget _miniHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
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

  List<Widget> _notifications(BuildContext context, S s, SettingsProvider st) {
    Future<void> pickDevice() async {
      final uri = await RingtonePicker.pick(current: st.customToneUri);
      if (uri != null) {
        final title = await RingtonePicker.title(uri);
        await st.setCustomTone(uri, title);
      }
    }

    final scheme = Theme.of(context).colorScheme;
    return [
      // قائمة كل التذكيرات.
      ListTile(
        leading: const Icon(Icons.list_alt_outlined),
        title: const Text('كل التذكيرات'),
        subtitle: const Text('عرض وإدارة كل تنبيهاتك'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const RemindersScreen())),
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
      const Divider(height: 1),
      _miniHeader(context, S.of(context).t('sound_options')),
      SwitchListTile(
        secondary: const Icon(Icons.volume_up_outlined),
        title: Text(S.of(context).t('auto_raise_volume')),
        subtitle: Text(S.of(context).t('auto_raise_volume_desc')),
        value: st.autoRaiseVolume,
        onChanged: (v) => st.setAutoRaiseVolume(v),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.trending_up),
        title: Text(S.of(context).t('gradual_volume')),
        subtitle: Text(S.of(context).t('gradual_volume_desc')),
        value: st.gradualVolume,
        onChanged:
            st.autoRaiseVolume ? (v) => st.setGradualVolume(v) : null,
      ),
    ];
  }

  // ===================== حول التطبيق =====================

  List<Widget> _about(BuildContext context, S s) => [
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
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => page)),
    );
  }
}

/// معاينة حيّة لشكل الملاحظة الافتراضية (لون + تسطير + خط المتن).
class _NotePreview extends StatelessWidget {
  final SettingsProvider settings;
  const _NotePreview({required this.settings});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = AppColors.resolveNoteColor(settings.defaultNoteColor, isDark);
    final grad = NoteGradient.parse(settings.defaultGradient);
    final onBg = grad != null
        ? grad.onColor
        : (ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
            ? Colors.white
            : Colors.black87);
    final gap = settings.noteFontSize * settings.noteLineHeight;

    return Container(
      decoration: BoxDecoration(
        color: grad == null ? bg : null,
        gradient: grad?.toGradient(),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: PaperBackground(
        style: settings.defaultBgStyle,
        lineColor: onBg,
        gap: gap,
        thickness: settings.ruleThickness,
        opacity: settings.ruleOpacity,
        onLine: settings.ruleOnLine,
        fontSize: settings.noteFontSize,
        topPadding: 12,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in const [
                'مثال على نص الملاحظة',
                'تنتظم الكتابة مع التسطير',
                'حسب الإعدادات المختارة',
              ])
                Text(
                  line,
                  style: TextStyle(
                    color: onBg,
                    fontFamily: settings.noteFontFamily,
                    fontSize: settings.noteFontSize,
                    height: settings.noteLineHeight,
                  ),
                ),
            ],
          ),
        ),
      ),
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
