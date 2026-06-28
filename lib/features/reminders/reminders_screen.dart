import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/time/hijri_recurrence.dart';
import '../../data/models/enums.dart';
import '../../data/models/reminder.dart';
import '../../services/calendar_export.dart';
import '../../services/med_occurrences.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/ui_kit.dart';
import '../editor/editor_attachments.dart';
import '../editor/note_editor_screen.dart';
import '../meds/medication_screen.dart';
import '../settings/settings_screen.dart';
import '../sounds/sound_library_screen.dart';
import 'notification_center_screen.dart';
import 'reliability_test_screen.dart';
import 'reminder_defaults_screen.dart';
import 'reminder_stats_screen.dart';
import 'reminder_templates_sheet.dart';
import 'reminders_provider.dart';
import 'standalone_reminder_dialog.dart';
import 'today_dashboard_screen.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  String _query = '';
  bool _searching = false;
  bool _gridView = false; // false = قائمة، true = مربّعات (شبكة).
  static const _kViewPref = 'reminders_grid_view';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _gridView = p.getBool(_kViewPref) ?? false);
    });
  }

  Future<void> _toggleView() async {
    setState(() => _gridView = !_gridView);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kViewPref, _gridView);
  }

  static const _weekdayAr = {
    1: 'الإثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
    6: 'السبت',
    7: 'الأحد',
  };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final provider = context.watch<RemindersProvider>();
    final q = _query.trim().toLowerCase();
    // ترتيب التنبيهات: المُفعَّلة أولًا، ثم الأقرب موعدًا.
    final items = [...provider.items]..sort((a, b) {
        final aOn = a.reminder.isActive, bOn = b.reminder.isActive;
        if (aOn != bOn) return aOn ? -1 : 1;
        return _nextFire(a.reminder).compareTo(_nextFire(b.reminder));
      });
    final filtered = q.isEmpty
        ? items
        : items.where((v) => _labelOf(v).toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: _searching
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _searching = false;
                  _query = '';
                }),
              ),
              title: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'ابحث في التنبيهات…',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              actions: [
                if (_query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _query = ''),
                  ),
              ],
            )
          : gradientAppBar(context, s.t('reminders'), actions: [
              IconButton(
                icon: Icon(_gridView ? Icons.view_agenda_outlined : Icons.grid_view),
                tooltip: _gridView ? 'عرض قائمة' : 'عرض مربّعات',
                onPressed: _toggleView,
              ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'بحث',
                onPressed: () => setState(() => _searching = true),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: s.t('settings'),
                onPressed: () => _open(context, const SettingsScreen()),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: s.t('reminder_tools'),
                onSelected: (v) {
                  switch (v) {
                    case 'dashboard':
                      _open(context, const TodayDashboardScreen());
                      break;
                    case 'templates':
                      showReminderTemplates(context);
                      break;
                    case 'stats':
                      _open(context, const ReminderStatsScreen());
                      break;
                    case 'med_mode':
                      _open(context, const MedicationScreen());
                      break;
                    case 'reminder_defaults':
                      _open(context, const ReminderDefaultsScreen());
                      break;
                    case 'notif_center':
                      _open(context, const NotificationCenterScreen());
                      break;
                    case 'sound_library':
                      _open(context, const SoundLibraryScreen());
                      break;
                    case 'reliability_test':
                      _open(context, const ReliabilityTestScreen());
                      break;
                  }
                },
                itemBuilder: (context) => [
                  _menuItem('dashboard', Icons.dashboard_outlined, 'لوحة اليوم'),
                  _menuItem('templates', Icons.dashboard_customize_outlined,
                      'قوالب جاهزة'),
                  _menuItem('stats', Icons.bar_chart, 'الإحصاءات'),
                  _menuItem(
                      'med_mode', Icons.medication_outlined, s.t('med_mode')),
                  _menuItem('reminder_defaults', Icons.tune,
                      s.t('reminder_defaults')),
                  _menuItem('notif_center', Icons.notifications_active_outlined,
                      s.t('notif_center')),
                  _menuItem('sound_library', Icons.library_music_outlined,
                      s.t('sound_library')),
                  _menuItem('reliability_test',
                      Icons.health_and_safety_outlined, s.t('reliability_test')),
                ],
              ),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showStandaloneReminderDialog(context),
        icon: const Icon(Icons.add_alarm),
        label: const Text('تنبيه جديد'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 96),
        children: [
          if (filtered.isEmpty)
            (q.isEmpty ? _emptyInline(context, s) : _noResults(context, q))
          else ...[
            if (q.isEmpty) _nextBanner(context, filtered),
            ..._groupedChildren(context, s, provider, filtered),
          ],
        ],
      ),
    );
  }

  /// نصّ التنبيه المعروض (للعرض والبحث).
  String _labelOf(ReminderView v) {
    final r = v.reminder;
    final note = v.note;
    return r.isStandalone
        ? (r.title?.isNotEmpty == true ? r.title! : 'تنبيه')
        : (note?.title.isNotEmpty == true
            ? note!.title
            : (note?.content ?? 'ملاحظة'));
  }

  Widget _noResults(BuildContext context, String q) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
        child: Column(
          children: [
            Icon(Icons.search_off,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('لا نتائج لـ «$q»',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ]),
      );

  /// لافتة «المنبّه التالي بعد…» لأقرب منبّه مُفعَّل.
  Widget _nextBanner(BuildContext context, List<ReminderView> items) {
    final active = items.where((v) => v.reminder.isActive);
    if (active.isEmpty) return const SizedBox.shrink();
    DateTime? soonest;
    for (final v in active) {
      final n = _nextFire(v.reminder);
      if (soonest == null || n.isBefore(soonest)) soonest = n;
    }
    if (soonest == null) return const SizedBox.shrink();
    final diff = soonest.difference(DateTime.now());
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          scheme.primaryContainer,
          scheme.primaryContainer.withOpacity(0.6),
        ]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.alarm_on, color: scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text('المنبّه التالي ${_countdown(diff)}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimaryContainer)),
          ),
        ],
      ),
    );
  }

  /// يجمع التنبيهات تحت عناوين زمنية: اليوم / غدًا / هذا الأسبوع / لاحقًا / متوقّف.
  List<Widget> _groupedChildren(BuildContext context, S s,
      RemindersProvider provider, List<ReminderView> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <String, List<ReminderView>>{
      'today': [],
      'tomorrow': [],
      'week': [],
      'later': [],
      'stopped': [],
    };
    for (final v in items) {
      final r = v.reminder;
      final expired =
          r.repeat == ReminderRepeat.once && r.time.isBefore(now);
      if (!r.isActive || expired) {
        groups['stopped']!.add(v);
        continue;
      }
      final n = _nextFire(r);
      final diff = DateTime(n.year, n.month, n.day).difference(today).inDays;
      if (diff <= 0) {
        groups['today']!.add(v);
      } else if (diff == 1) {
        groups['tomorrow']!.add(v);
      } else if (diff <= 7) {
        groups['week']!.add(v);
      } else {
        groups['later']!.add(v);
      }
    }
    const titles = {
      'today': '📅 اليوم',
      'tomorrow': '🌅 غدًا',
      'week': '🗓️ هذا الأسبوع',
      'later': '⏳ لاحقًا',
      'stopped': '🔕 متوقّف / منتهٍ',
    };
    // لون مميّز لكل مجال زمنيّ.
    const colors = {
      'today': Color(0xFF00897B), // أخضر مزرقّ
      'tomorrow': Color(0xFF1E88E5), // أزرق
      'week': Color(0xFF8E24AA), // بنفسجي
      'later': Color(0xFFF57C00), // برتقالي
      'stopped': Color(0xFF9E9E9E), // رمادي
    };
    final out = <Widget>[];
    for (final key in groups.keys) {
      final list = groups[key]!;
      if (list.isEmpty) continue;
      final accent = colors[key]!;
      out.add(_groupHeader(context, '${titles[key]}  (${list.length})', accent));
      Color itemAccent(ReminderView v) =>
          v.reminder.color != null ? Color(v.reminder.color!) : accent;
      if (_gridView) {
        out.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.92,
            children: [
              for (final v in list)
                _gridCard(context, s, provider, v, itemAccent(v)),
            ],
          ),
        ));
      } else {
        for (final v in list) {
          out.add(_tile(context, s, provider, v, itemAccent(v)));
        }
      }
    }
    return out;
  }

  Widget _groupHeader(BuildContext context, String text, Color accent) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      );

  Widget _emptyInline(BuildContext context, S s) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
        child: Column(
          children: [
            Icon(Icons.notifications_off_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(s.t('no_reminders'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'أضف تنبيهًا سريعًا من الأعلى، أو بزرّ «تنبيه جديد».',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ],
        ),
      );

  /// بطاقة تنبيه مدمجة بلون المجال الزمنيّ (شريط جانبي + شارة + تدرّج خفيف).
  /// إجراءات الحذف/الموقع/المرفق عبر الضغط المطوّل لإبقاء البطاقة صغيرة.
  Widget _tile(BuildContext context, S s, RemindersProvider provider,
      ReminderView v, Color accent) {
    final r = v.reminder;
    final note = v.note;
    final on = r.isActive;
    // تنبيه «مرّة واحدة» فات وقته ⇒ منتهٍ: نعرضه باهتًا (كأنه غير نشِط).
    final expired =
        r.repeat == ReminderRepeat.once && r.time.isBefore(DateTime.now());
    final dim = !on || expired;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final timeStr = DateFormat('h:mm a', 'ar').format(r.time);
    final label = _labelOf(v);
    // وصف التكرار (مع اليوم عند الأسبوعي، وفاصل/مدّة الدواء إن وُجدت).
    String repeatInfo;
    if (r.intervalDays >= 2) {
      repeatInfo = 'كل ${r.intervalDays} يوم';
    } else if (r.repeat == ReminderRepeat.weekly) {
      repeatInfo = '${_repeatLabel(s, r.repeat)} • ${_weekdayAr[r.time.weekday]}';
    } else {
      repeatInfo = _repeatLabel(s, r.repeat);
    }
    if (r.doseCount > 0) repeatInfo += ' • ${r.doseCount} جرعة';

    final surface = scheme.surface;
    final gradTop = Color.alphaBlend(accent.withOpacity(0.18), surface);
    final gradBottom = Color.alphaBlend(accent.withOpacity(0.05), surface);

    final onTap = r.isStandalone
        ? () => showStandaloneReminderDialog(context, existing: r)
        : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NoteEditorScreen(noteId: note!.id),
              ),
            );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [gradTop, gradBottom],
          ),
          border: BorderDirectional(
            start: BorderSide(color: accent, width: 4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.45 : 0.12),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
            if (!dim)
              BoxShadow(
                color: accent.withOpacity(dark ? 0.28 : 0.16),
                blurRadius: 12,
                spreadRadius: -4,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            onLongPress: () => _showActions(context, s, provider, v),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 6, 8),
              child: Row(
                children: [
                  _alarmBadge(accent, dim, expired, dark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              timeStr,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: dim ? scheme.outline : scheme.onSurface,
                                decoration: expired
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: _chip(
                                accent,
                                expired
                                    ? Icons.history_toggle_off
                                    : Icons.repeat,
                                expired ? s.t('nc_expired') : repeatInfo,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                            color: dim
                                ? scheme.outline
                                : scheme.onSurface.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (r.location.trim().isNotEmpty)
                    Icon(Icons.place, size: 16, color: accent),
                  if (r.attachmentPath.trim().isNotEmpty)
                    Icon(Icons.attach_file, size: 16, color: accent),
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: on,
                      onChanged: (val) => provider.setActive(v, val),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// بطاقة مربّعة ثلاثية الأبعاد لعرض الشبكة (مربّعات).
  Widget _gridCard(BuildContext context, S s, RemindersProvider provider,
      ReminderView v, Color accent) {
    final r = v.reminder;
    final note = v.note;
    final on = r.isActive;
    final expired =
        r.repeat == ReminderRepeat.once && r.time.isBefore(DateTime.now());
    final dim = !on || expired;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final timeStr = DateFormat('h:mm a', 'ar').format(r.time);
    final label = _labelOf(v);
    String repeatInfo;
    if (r.intervalDays >= 2) {
      repeatInfo = 'كل ${r.intervalDays} يوم';
    } else if (r.repeat == ReminderRepeat.weekly) {
      repeatInfo = '${_repeatLabel(s, r.repeat)} • ${_weekdayAr[r.time.weekday]}';
    } else {
      repeatInfo = _repeatLabel(s, r.repeat);
    }
    if (r.doseCount > 0) repeatInfo += ' • ${r.doseCount} جرعة';

    final surface = scheme.surface;
    final gradTop = Color.alphaBlend(accent.withOpacity(0.20), surface);
    final gradBottom = Color.alphaBlend(accent.withOpacity(0.06), surface);

    final onTap = r.isStandalone
        ? () => showStandaloneReminderDialog(context, existing: r)
        : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NoteEditorScreen(noteId: note!.id),
              ),
            );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradTop, gradBottom],
        ),
        border: Border.all(color: accent.withOpacity(0.30), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.45 : 0.13),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          if (!dim)
            BoxShadow(
              color: accent.withOpacity(dark ? 0.30 : 0.18),
              blurRadius: 14,
              spreadRadius: -4,
              offset: const Offset(0, 5),
            ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onLongPress: () => _showActions(context, s, provider, v),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _alarmBadge(accent, dim, expired, dark),
                    const Spacer(),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: on,
                        onChanged: (val) => provider.setActive(v, val),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  timeStr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: dim ? scheme.outline : scheme.onSurface,
                    decoration:
                        expired ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: dim
                        ? scheme.outline
                        : scheme.onSurface.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 6),
                _chip(
                  accent,
                  expired ? Icons.history_toggle_off : Icons.repeat,
                  expired ? s.t('nc_expired') : repeatInfo,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// قائمة إجراءات سريعة عند الضغط المطوّل: تأجيل / نسخ / حذف.
  Future<void> _showActions(BuildContext context, S s,
      RemindersProvider provider, ReminderView v) async {
    final scheme = Theme.of(context).colorScheme;
    final r = v.reminder;
    final t = r.time;
    final now = DateTime.now();
    final tomorrowSame =
        DateTime(now.year, now.month, now.day + 1, t.hour, t.minute);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  Icon(Icons.alarm, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_labelOf(v),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.snooze),
              title: const Text('تأجيل ١٠ دقائق'),
              onTap: () {
                Navigator.pop(ctx);
                _postpone(context, provider, v,
                    DateTime.now().add(const Duration(minutes: 10)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: const Text('تأجيل ساعة'),
              onTap: () {
                Navigator.pop(ctx);
                _postpone(context, provider, v,
                    DateTime.now().add(const Duration(hours: 1)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.wb_twilight),
              title: const Text('تأجيل إلى الغد (نفس الوقت)'),
              onTap: () {
                Navigator.pop(ctx);
                _postpone(context, provider, v, tomorrowSame);
              },
            ),
            if (r.location.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: const Text('فتح الموقع'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final u = Uri.tryParse(r.location.trim());
                  if (u == null) return;
                  try {
                    await launchUrl(u, mode: LaunchMode.externalApplication);
                  } catch (_) {/* لا تطبيق يفتح الرابط */}
                },
              ),
            if (r.attachmentPath.trim().isNotEmpty)
              ListTile(
                leading: Icon(r.attachmentPath.toLowerCase().endsWith('.pdf')
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined),
                title: const Text('فتح الدعوة/المرفق'),
                onTap: () {
                  Navigator.pop(ctx);
                  EditorAttachments.openFile(r.attachmentPath);
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('نسخ التنبيه'),
              onTap: () async {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                await provider.duplicate(v);
                messenger.showSnackBar(
                    const SnackBar(content: Text('تم نسخ التنبيه')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('مشاركة'),
              onTap: () async {
                Navigator.pop(ctx);
                final at = DateFormat('h:mm a', 'ar').format(r.time);
                await SharePlus.instance.share(ShareParams(
                    text: '⏰ ${_labelOf(v)}\nالوقت: $at'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('إضافة للتقويم'),
              onTap: () async {
                Navigator.pop(ctx);
                await CalendarExport.addToCalendar(r, _labelOf(v));
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('حذف', style: TextStyle(color: scheme.error)),
              onTap: () async {
                Navigator.pop(ctx);
                if (await confirmDelete(context,
                    title: 'حذف التنبيه؟',
                    message: 'سيُحذف هذا التنبيه ولن يُذكّرك بعد الآن.')) {
                  await provider.removeReminder(r);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _postpone(BuildContext context, RemindersProvider provider,
      ReminderView v, DateTime newTime) async {
    final messenger = ScaffoldMessenger.of(context);
    await provider.postpone(v, newTime);
    final at = DateFormat('h:mm a', 'ar').format(newTime);
    messenger
        .showSnackBar(SnackBar(content: Text('تم التأجيل إلى $at')));
  }

  /// شارة منبّه دائرية مدمجة بلون المجال.
  Widget _alarmBadge(Color accent, bool dim, bool expired, bool dark) {
    final c2 = Color.alphaBlend(Colors.black.withOpacity(0.22), accent);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, c2],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(dim ? 0.2 : 0.45),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        expired
            ? Icons.alarm_off_rounded
            : (dim ? Icons.notifications_off_rounded : Icons.alarm_on_rounded),
        color: Colors.white,
        size: 22,
      ),
    );
  }

  /// شريحة معلومات صغيرة (التكرار/الحالة).
  Widget _chip(Color accent, IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: accent),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: accent),
              ),
            ),
          ],
        ),
      );

  // ===== مساعدات =====

  DateTime _nextFire(Reminder r) {
    final now = DateTime.now();
    final t = r.time;
    // كورس دواء (فاصل أيام/عدد جرعات): أوّل موعد قادم، أو لا شيء إن انتهى.
    if (r.intervalDays >= 2 || r.doseCount > 0) {
      final next =
          medOccurrencesBetween(r, now, now.add(const Duration(days: 3650)));
      return next.isEmpty ? DateTime(9999) : next.first;
    }
    switch (r.repeat) {
      case ReminderRepeat.once:
        return t;
      case ReminderRepeat.daily:
        var d = DateTime(now.year, now.month, now.day, t.hour, t.minute);
        if (!d.isAfter(now)) d = d.add(const Duration(days: 1));
        return d;
      case ReminderRepeat.weekly:
        var d = DateTime(now.year, now.month, now.day, t.hour, t.minute);
        while (d.weekday != t.weekday || !d.isAfter(now)) {
          d = DateTime(d.year, d.month, d.day + 1, t.hour, t.minute);
        }
        return d;
      case ReminderRepeat.monthly:
      case ReminderRepeat.yearly:
        return t.isAfter(now) ? t : t;
      case ReminderRepeat.hijriYearly:
        return nextHijriAnniversary(t, now);
    }
  }

  String _countdown(Duration d) {
    if (d.isNegative) return 'الآن';
    final days = d.inDays;
    final hours = d.inHours % 24;
    final mins = d.inMinutes % 60;
    if (days > 0) return 'بعد $days يوم و$hours ساعة';
    if (hours > 0) return 'بعد $hours ساعة و$mins دقيقة';
    if (mins > 0) return 'بعد $mins دقيقة';
    return 'خلال ثوانٍ';
  }

  String _repeatLabel(S s, ReminderRepeat r) => switch (r) {
        ReminderRepeat.once => s.t('repeat_once'),
        ReminderRepeat.daily => s.t('repeat_daily'),
        ReminderRepeat.weekly => s.t('repeat_weekly'),
        ReminderRepeat.monthly => s.t('repeat_monthly'),
        ReminderRepeat.yearly => s.t('repeat_yearly'),
        ReminderRepeat.hijriYearly => s.t('repeat_hijri_yearly'),
      };
}
