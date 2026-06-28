import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/time/hijri_recurrence.dart';
import '../../data/models/enums.dart';
import '../../data/models/reminder.dart';
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
import 'reminders_provider.dart';
import 'standalone_reminder_dialog.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  String _query = '';
  bool _searching = false;

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
          if (!_searching) _quickAddBar(context),
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

  /// شريط الإضافة السريعة: أزرار تُنشئ تنبيهًا «مرّة واحدة» فورًا بنقرة.
  Widget _quickAddBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(IconData icon, String label, DateTime Function() when) =>
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: ActionChip(
            avatar: Icon(icon, size: 18, color: scheme.primary),
            label: Text(label),
            onPressed: () => _quickAdd(context, when(), label),
          ),
        );
    final now0 = DateTime.now();
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          chip(Icons.bolt, 'بعد ١٠ د',
              () => DateTime.now().add(const Duration(minutes: 10))),
          chip(Icons.timelapse, 'بعد ٣٠ د',
              () => DateTime.now().add(const Duration(minutes: 30))),
          chip(Icons.hourglass_bottom, 'بعد ساعة',
              () => DateTime.now().add(const Duration(hours: 1))),
          chip(Icons.wb_sunny_outlined, 'غدًا ٨ص', () {
            final t = now0.add(const Duration(days: 1));
            return DateTime(t.year, t.month, t.day, 8);
          }),
          chip(Icons.nightlight_outlined, 'الليلة ٩م',
              () => DateTime(now0.year, now0.month, now0.day, 21)),
        ],
      ),
    );
  }

  Future<void> _quickAdd(
      BuildContext context, DateTime time, String label) async {
    // لو كان الوقت المحسوب قد فات (مثل «الليلة ٩م» بعد التاسعة) ⇒ انقله للغد.
    var t = time;
    if (!t.isAfter(DateTime.now())) t = t.add(const Duration(days: 1));
    final provider = context.read<RemindersProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await provider.setStandalone(t, ReminderRepeat.once, 'تنبيه سريع');
    final at = DateFormat('h:mm a', 'ar').format(t);
    messenger.showSnackBar(
      SnackBar(content: Text('تم ضبط تنبيه ($label) عند $at')),
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
    final out = <Widget>[];
    for (final key in groups.keys) {
      final list = groups[key]!;
      if (list.isEmpty) continue;
      out.add(_groupHeader(context, '${titles[key]}  (${list.length})'));
      for (final v in list) {
        out.add(_tile(context, s, provider, v));
      }
    }
    return out;
  }

  Widget _groupHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
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

  /// بطاقة تنبيه ثلاثية الأبعاد: تدرّج لوني + ظلال متعدّدة الطبقات (عمق وارتفاع)
  /// + شارة منبّه دائرية بارزة. المُفعَّل يلمع بلون السمة، والمنتهي/المطفأ باهت.
  Widget _tile(BuildContext context, S s, RemindersProvider provider,
      ReminderView v) {
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

    // ألوان التدرّج والشارة حسب الحالة.
    final accent = dim ? scheme.outline : scheme.primary;
    final surface = scheme.surface;
    final gradTop = dim
        ? Color.alphaBlend(scheme.outline.withOpacity(0.06), surface)
        : Color.alphaBlend(scheme.primary.withOpacity(0.16), surface);
    final gradBottom = dim
        ? Color.alphaBlend(scheme.outline.withOpacity(0.12), surface)
        : Color.alphaBlend(scheme.primary.withOpacity(0.04), surface);

    final onTap = r.isStandalone
        ? () => showStandaloneReminderDialog(context, existing: r)
        : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NoteEditorScreen(noteId: note!.id),
              ),
            );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [gradTop, gradBottom],
          ),
          border: Border.all(
            color: Colors.white.withOpacity(dark ? 0.06 : 0.65),
            width: 1,
          ),
          boxShadow: [
            // ظلّ عميق أسفل-يمين يمنح الارتفاع.
            BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.55 : 0.16),
              blurRadius: 18,
              offset: const Offset(0, 9),
            ),
            // وهج لوني للمُفعَّل.
            if (!dim)
              BoxShadow(
                color: scheme.primary.withOpacity(dark ? 0.32 : 0.22),
                blurRadius: 22,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            // إضاءة علوية خفيفة (حافة لامعة).
            BoxShadow(
              color: Colors.white.withOpacity(dark ? 0.05 : 0.7),
              blurRadius: 2,
              spreadRadius: -1,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            onLongPress: () => _showActions(context, s, provider, v),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _alarmBadge(scheme, dim, expired, dark),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              timeStr,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: dim ? scheme.outline : scheme.onSurface,
                                decoration: expired
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                                color: dim
                                    ? scheme.outline
                                    : scheme.onSurface.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: on,
                        onChanged: (val) => provider.setActive(v, val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _chip(scheme, accent,
                          expired ? Icons.history_toggle_off : Icons.repeat,
                          expired ? s.t('nc_expired') : repeatInfo),
                      const Spacer(),
                      if (r.location.trim().isNotEmpty)
                        _miniAction(
                          icon: Icons.place_outlined,
                          color: accent,
                          tooltip: 'فتح الموقع',
                          onPressed: () async {
                            final u = Uri.tryParse(r.location.trim());
                            if (u == null) return;
                            try {
                              await launchUrl(u,
                                  mode: LaunchMode.externalApplication);
                            } catch (_) {/* لا تطبيق يفتح الرابط */}
                          },
                        ),
                      if (r.attachmentPath.trim().isNotEmpty)
                        _miniAction(
                          icon: r.attachmentPath.toLowerCase().endsWith('.pdf')
                              ? Icons.picture_as_pdf_outlined
                              : Icons.image_outlined,
                          color: accent,
                          tooltip: 'الدعوة',
                          onPressed: () =>
                              EditorAttachments.openFile(r.attachmentPath),
                        ),
                      _miniAction(
                        icon: Icons.delete_outline,
                        color: scheme.error,
                        tooltip: 'حذف',
                        onPressed: () async {
                          if (await confirmDelete(context,
                              title: 'حذف التنبيه؟',
                              message:
                                  'سيُحذف هذا التنبيه ولن يُذكّرك بعد الآن.')) {
                            await provider.removeReminder(r);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
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

  /// شارة منبّه دائرية بارزة (ثلاثية الأبعاد) بتدرّج وظلّ ملوّن.
  Widget _alarmBadge(
      ColorScheme scheme, bool dim, bool expired, bool dark) {
    final c1 = dim ? scheme.outline : scheme.primary;
    final c2 = dim ? scheme.outlineVariant : scheme.tertiary;
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
        boxShadow: [
          BoxShadow(
            color: c2.withOpacity(dim ? 0.25 : 0.5),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(dark ? 0.10 : 0.45),
            blurRadius: 2,
            spreadRadius: -2,
            offset: const Offset(-2, -2),
          ),
        ],
      ),
      child: Icon(
        expired
            ? Icons.alarm_off_rounded
            : (dim ? Icons.notifications_off_rounded : Icons.alarm_on_rounded),
        color: Colors.white,
        size: 27,
      ),
    );
  }

  /// شريحة معلومات صغيرة (التكرار/الحالة).
  Widget _chip(ColorScheme scheme, Color accent, IconData icon, String text) =>
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: accent),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _miniAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) =>
      IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        tooltip: tooltip,
        icon: Icon(icon, color: color, size: 21),
        onPressed: onPressed,
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
