import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/l10n/app_strings.dart';
import '../../data/models/note.dart';
import '../../widgets/ui_kit.dart';
import '../editor/note_editor_screen.dart';
import '../editor/rich_text_field.dart';
import '../home/notes_provider.dart';
import '../reminders/reminders_provider.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  bool _hijri = false;

  List<Note> _all = [];
  bool _loading = true;

  static const _kHijriPref = 'calendar_hijri'; // تذكّر اختيار التقويم

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _loadHijriPref();
  }

  Future<void> _loadHijriPref() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _hijri = p.getBool(_kHijriPref) ?? false);
  }

  Future<void> _setHijri(bool v) async {
    setState(() => _hijri = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHijriPref, v);
  }

  /// نقل الشهر **الهجريّ** المعروض بمقدار [delta] (±1) مع ضبط السنة.
  void _shiftHijriMonth(int delta) {
    final hf = HijriCalendar.fromDate(_focused);
    var y = hf.hYear;
    var m = hf.hMonth + delta;
    while (m > 12) {
      m -= 12;
      y++;
    }
    while (m < 1) {
      m += 12;
      y--;
    }
    setState(() => _focused = HijriCalendar().hijriToGregorian(y, m, 1));
  }

  Future<void> _loadNotes() async {
    final provider = context.read<NotesProvider>();
    final notes = await provider.notes.getNotes();
    if (mounted) {
      setState(() {
        _all = notes;
        _loading = false;
      });
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Note> _notesFor(DateTime day) =>
      _all.where((n) => _sameDay(n.createdAt, day)).toList();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // أسماء الشهور/الأيام الهجريّة حسب لغة الواجهة.
    HijriCalendar.setLocal(s.isArabic ? 'ar' : 'en');
    final reminders = context.watch<RemindersProvider>();
    // ملاحظات اليوم مرتّبة بوقت الإنشاء (الأقدم أولًا)، والتذكيرات بوقتها.
    final dayNotes = _notesFor(_selected)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final dayReminders = reminders.items
        .where((v) => _sameDay(v.reminder.time, _selected))
        .toList()
      ..sort((a, b) => a.reminder.time.compareTo(b.reminder.time));

    return Scaffold(
      appBar: gradientAppBar(context, s.t('calendar'), actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(s.t('gregorian'))),
                ButtonSegment(value: true, label: Text(s.t('hijri'))),
              ],
              selected: {_hijri},
              onSelectionChanged: (v) => _setHijri(v.first),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadNotes,
              child: ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  // بطاقة التقويم: هجريّ (شبكة مخصّصة) أو ميلاديّ (TableCalendar).
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _hijri
                        ? _hijriCalendar(context, s)
                        : TableCalendar<Note>(
                            locale: s.isArabic ? 'ar' : 'en',
                            firstDay: DateTime(2015),
                            lastDay: DateTime(2100),
                            focusedDay: _focused,
                            selectedDayPredicate: (d) => _sameDay(d, _selected),
                            eventLoader: _notesFor,
                            startingDayOfWeek: StartingDayOfWeek.saturday,
                            calendarFormat: CalendarFormat.month,
                            availableCalendarFormats: const {
                              CalendarFormat.month: ''
                            },
                            onDaySelected: (selected, focused) {
                              setState(() {
                                _selected = selected;
                                _focused = focused;
                              });
                            },
                            calendarStyle: CalendarStyle(
                              markerDecoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              todayDecoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              selectedDecoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            // تلوين خفيف لأيام بها ملاحظات (غير اليوم/المحدَّد).
                            calendarBuilders: CalendarBuilders<Note>(
                              defaultBuilder: (ctx, day, _) {
                                if (_notesFor(day).isEmpty) return null;
                                final scheme = Theme.of(ctx).colorScheme;
                                return Container(
                                  margin: const EdgeInsets.all(6),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer
                                        .withOpacity(0.45),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text('${day.day}'),
                                );
                              },
                            ),
                          ),
                  ),
                  // بطاقة تفاصيل اليوم: التاريخ + تذكيرات + ملاحظات (مرتّبة، بخلفية).
                  _dayCard(context, s, dayReminders, dayNotes),
                ],
              ),
            ),
    );
  }

  /// شبكة تقويم **هجريّة كاملة**: رأس باسم الشهر الهجريّ + تنقّل بالشهور الهجريّة،
  /// وخلايا بأرقام الأيام الهجريّة (مع علامة الملاحظات وتمييز اليوم/المحدَّد).
  /// كل خليّة مرتبطة بتاريخها الميلاديّ المقابل كي تعمل الملاحظات والاختيار كالعادة.
  Widget _hijriCalendar(BuildContext context, S s) {
    final scheme = Theme.of(context).colorScheme;
    final hf = HijriCalendar.fromDate(_focused);
    final y = hf.hYear;
    final m = hf.hMonth;
    final firstGreg = HijriCalendar().hijriToGregorian(y, m, 1);
    final daysInMonth = HijriCalendar().getDaysInMonth(y, m);
    // أعمدة تبدأ السبت: السبت=0 … الجمعة=6 (weekday: الاثنين=1 … الأحد=7).
    final lead = (firstGreg.weekday + 1) % 7;
    final now = DateTime.now();

    final weekdays = s.isArabic
        ? const ['سبت', 'أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة']
        : const ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final greg = DateTime(firstGreg.year, firstGreg.month, firstGreg.day)
          .add(Duration(days: d - 1));
      final isToday = _sameDay(greg, now);
      final isSel = _sameDay(greg, _selected);
      final hasNotes = _notesFor(greg).isNotEmpty;
      cells.add(GestureDetector(
        onTap: () => setState(() {
          _selected = greg;
          _focused = greg;
        }),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSel
                ? scheme.primary
                : isToday
                    ? scheme.primaryContainer
                    : hasNotes
                        ? scheme.primaryContainer.withOpacity(0.45)
                        : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$d',
                  style: TextStyle(
                      color: isSel ? scheme.onPrimary : null,
                      fontWeight: isToday || isSel ? FontWeight.bold : null)),
              if (hasNotes)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSel ? scheme.onPrimary : scheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shiftHijriMonth(-1),
              ),
              Text('${hf.longMonthName} $y هـ',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shiftHijriMonth(1),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: weekdays.asMap().entries.map((e) {
              final isFriday = e.key == 6; // عطلة نهاية الأسبوع
              return Expanded(
                child: Center(
                  child: Text(e.value,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isFriday ? scheme.error : scheme.primary,
                          )),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: cells,
        ),
      ],
    );
  }

  /// عنوان عرض الملاحظة: العنوان إن وُجد، وإلا **أوّل ثلاث كلمات** من نصّها العاديّ
  /// (نفكّ Delta JSON فلا تظهر رموز التنسيق)، وإلا «بدون عنوان».
  String _noteLabel(Note n) {
    final t = n.title.trim();
    if (t.isNotEmpty) return t;
    final plain = richToPlainText(n.content).trim();
    if (plain.isEmpty) return 'بدون عنوان';
    return plain.split(RegExp(r'\s+')).take(3).join(' ');
  }

  Widget _dot(BuildContext context, Color color, {double size = 14}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      );

  Widget _sectionLabel(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text(text,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.primary, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// بطاقة تفاصيل اليوم المحدَّد: رأس التاريخ (هجريّ/ميلاديّ) + التذكيرات +
  /// الملاحظات — مرتّبة بخلفيّة بطاقة، وكل عنصر بعنوانه الواضح ونقطة لونه.
  Widget _dayCard(BuildContext context, S s, List<ReminderView> dayReminders,
      List<Note> dayNotes) {
    final scheme = Theme.of(context).colorScheme;
    final greg = DateFormat('EEEE، d MMMM yyyy', s.isArabic ? 'ar' : 'en')
        .format(_selected);
    final h = HijriCalendar.fromDate(_selected);
    final hijriStr = '${h.hDay} ${h.longMonthName} ${h.hYear} هـ';

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // رأس التاريخ بشارة يوم بارزة.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.primaryContainer,
                  child: Text('${_hijri ? h.hDay : _selected.day}',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_hijri ? hijriStr : greg,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(_hijri ? greg : hijriStr,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // التذكيرات.
          if (dayReminders.isNotEmpty) ...[
            _sectionLabel(context, Icons.alarm, s.t('reminders')),
            ...dayReminders.map((v) => ListTile(
                  dense: true,
                  leading: _dot(context, scheme.tertiary),
                  title: Text(
                    v.note != null ? _noteLabel(v.note!) : 'تذكير',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(DateFormat('HH:mm').format(v.reminder.time),
                      style: Theme.of(context).textTheme.bodySmall),
                  onTap: v.note != null
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  NoteEditorScreen(noteId: v.note!.id),
                            ),
                          )
                      : null,
                )),
            const Divider(height: 1),
          ],

          // الملاحظات.
          _sectionLabel(context, Icons.sticky_note_2_outlined, s.t('nav_notes')),
          if (dayNotes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(s.t('no_notes_day'),
                    style: TextStyle(color: scheme.outline)),
              ),
            )
          else
            ...dayNotes.map((n) => ListTile(
                  dense: true,
                  leading: _dot(context,
                      n.color != null ? Color(n.color!) : scheme.primary),
                  title: Text(
                    _noteLabel(n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NoteEditorScreen(noteId: n.id),
                    ),
                  ),
                )),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
