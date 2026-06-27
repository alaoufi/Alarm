import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/text/line_direction.dart';
import '../../data/database/app_database.dart';
import '../../data/models/enums.dart';
import '../../data/models/med_dose.dart';
import '../../data/models/reminder.dart';
import '../../data/repositories/med_repository.dart';
import '../../data/repositories/reminder_repository.dart';
import '../../services/med_dose_logger.dart';
import '../../services/med_occurrences.dart';
import '../reminders/reminders_provider.dart';
import '../../widgets/confirm_dialog.dart';

/// طريقة عرض سجلّ الجرعات: مجمّع حسب الدواء، أو السجل الكامل مسطّحًا.
enum _MedView { byMed, all }

/// وضع الدواء/العلاج:
/// - **كورسات الدواء**: لكل دواء عدد جرعات وفاصل وأوّل جرعة — يُحسب المتبقّي
///   زمنيًّا (ينقص مع مرور الوقت حتى لو لم يرنّ التنبيه)، ويعرض الجرعات السابقة
///   واللاحقة. دقيق لأنه علاج.
/// - **سجلّ الجرعات**: تسجيل فعليّ (أُخذت/فاتت) مع نسبة الالتزام.
class MedicationScreen extends StatefulWidget {
  const MedicationScreen({super.key});

  @override
  State<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends State<MedicationScreen> {
  final _repo = MedRepository(AppDatabase.instance);
  List<MedDose> _doses = [];
  List<Reminder> _courses = [];
  bool _loading = true;
  _MedView _view = _MedView.byMed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // سجّل أولًا أي جرعات فائتة لمنبّهات الدواء 💊 منذ آخر فتح، ثم اعرض.
    await MedDoseLogger.instance.run();
    final list = await _repo.getAll();
    final reminders = await ReminderRepository(AppDatabase.instance).getAll();
    final courses = reminders
        .where((r) =>
            r.isActive && (r.title ?? '').contains('💊') && r.doseCount > 0)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    if (mounted) {
      setState(() {
        _doses = list;
        _courses = courses;
        _loading = false;
      });
    }
  }

  // ===================== كورسات الدواء =====================

  Future<void> _startCourse() async {
    final names = await _repo.distinctNames();
    if (!mounted) return;
    final draft = await showModalBottomSheet<_CourseDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewCourseSheet(suggestions: names),
    );
    if (draft == null || !mounted) return;
    final title = '💊 ${draft.name}'
        '${(draft.dose != null && draft.dose!.isNotEmpty) ? ' — ${draft.dose}' : ''}';
    // فاصل ≥2 يوم ⇒ يُجدوَل ككورس بالأيام؛ ويوميّ (=1) عبر التكرار اليوميّ.
    final intervalDays = draft.every >= 2 ? draft.every : 0;
    await context.read<RemindersProvider>().setStandalone(
          draft.first,
          ReminderRepeat.daily,
          title,
          intervalDays: intervalDays,
          doseCount: draft.total,
        );
    await _load();
  }

  Future<void> _stopCourse(Reminder r, S s) async {
    if (!await confirmDelete(context,
        title: s.t('med_stop'),
        message: s.t('med_stop_confirm'),
        icon: Icons.medication_outlined)) {
      return;
    }
    await context.read<RemindersProvider>().removeReminder(r);
    await _load();
  }

  Widget _courseCard(Reminder r, S s) {
    final scheme = Theme.of(context).colorScheme;
    final parsed = MedDoseLogger.parseMedTitle(r.title ?? '');
    final name = parsed.$1;
    final dose = parsed.$2;
    final total = r.doseCount;
    final now = DateTime.now();
    final doses = [for (var i = 0; i < total; i++) medOccurrenceAt(r, i)];
    final duePassed = doses.where((d) => !d.isAfter(now)).length;
    final remaining = total - duePassed;
    final complete = remaining <= 0;
    final progress = total == 0 ? 0.0 : duePassed / total;
    final dateFmt = DateFormat('yyyy/MM/dd');
    final dtFmt = DateFormat('yyyy/MM/dd – HH:mm');
    final accent = complete ? Colors.green : scheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: accent.withOpacity(0.15),
            child: complete
                ? Icon(Icons.check, color: accent)
                : Text('$remaining',
                    style: TextStyle(
                        color: accent, fontWeight: FontWeight.bold)),
          ),
          title: Text(
            (dose != null && dose.isNotEmpty) ? '$name — $dose' : name,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                complete
                    ? s.t('med_complete')
                    : '${s.t('med_remaining')}: $remaining / $total',
                style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text('${s.t('med_first')}: ${dateFmt.format(doses.first)}',
                  style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: accent,
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
          children: [
            for (var i = 0; i < doses.length; i++)
              _doseRow(i, doses[i], duePassed, dtFmt, s, scheme),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _stopCourse(r, s),
                  icon: Icon(Icons.stop_circle_outlined,
                      size: 18, color: scheme.error),
                  label: Text(s.t('med_stop'),
                      style: TextStyle(color: scheme.error)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// صفّ جرعة واحدة ضمن الكورس بخلفيّة ملوّنة شفّافة تميّز حالتها:
  /// **أُخذت (مضت)** خضراء خفيفة، **التالية الآن** بإطار مميّز، و**متبقّية (لم
  /// تُؤخذ بعد)** حمراء خفيفة — فيُفهَم المأخوذ والمتبقّي بنظرة.
  Widget _doseRow(int i, DateTime when, int duePassed, DateFormat fmt, S s,
      ColorScheme scheme) {
    final isPast = i < duePassed;
    final isNext = i == duePassed;
    final IconData icon;
    final Color color; // لون الأيقونة/التسمية
    final Color bg; // خلفيّة الصفّ الشفّافة
    final String label;
    if (isPast) {
      icon = Icons.check_circle;
      color = Colors.green.shade700;
      bg = Colors.green.withOpacity(0.13); // أُخذت
      label = s.t('med_past_label');
    } else if (isNext) {
      icon = Icons.notifications_active;
      color = scheme.primary;
      bg = scheme.primary.withOpacity(0.14); // التالية الآن
      label = s.t('med_next_label');
    } else {
      icon = Icons.schedule;
      color = Colors.red.shade400;
      bg = Colors.red.withOpacity(0.08); // متبقّية (لم تُؤخذ)
      label = s.t('med_upcoming_label');
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: isNext
            ? Border.all(color: scheme.primary.withOpacity(0.5), width: 1.2)
            : null,
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        leading: Icon(icon, color: color, size: 20),
        title: Text('${s.t('med_dose_word')} ${i + 1}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: isNext ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text(fmt.format(when), style: const TextStyle(fontSize: 12)),
        trailing: Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ===================== سجلّ الجرعات (الفعليّ) =====================

  Future<void> _logDose() async {
    final names = await _repo.distinctNames();
    if (!mounted) return;
    final result = await showModalBottomSheet<MedDose>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LogSheet(suggestions: names),
    );
    if (result != null) {
      await _repo.insert(result);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final taken = _doses.where((d) => d.taken).length;
    final missed = _doses.length - taken;
    final adherence = _doses.isEmpty ? 1.0 : taken / _doses.length;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('med_mode')),
        actions: [
          IconButton(
            tooltip: s.t('med_log_dose'),
            icon: const Icon(Icons.add_task),
            onPressed: _logDose,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startCourse,
        icon: const Icon(Icons.medication),
        label: Text(s.t('med_new')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
              children: [
                // كورسات الدواء الجارية.
                if (_courses.isNotEmpty) ...[
                  _sectionTitle(Icons.medication_liquid, s.t('med_courses'),
                      scheme),
                  for (final r in _courses) _courseCard(r, s),
                  const SizedBox(height: 8),
                ],

                // سجلّ الجرعات الفعليّ + الالتزام.
                _sectionTitle(Icons.fact_check_outlined, s.t('med_history'),
                    scheme),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.health_and_safety,
                              color: scheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(s.t('adherence'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          const Spacer(),
                          Text('${(adherence * 100).round()}%',
                              style: TextStyle(
                                  color: adherence > 0.7
                                      ? Colors.green
                                      : (adherence > 0.4
                                          ? Colors.orange
                                          : Colors.red),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18)),
                        ]),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: adherence,
                            minHeight: 8,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: adherence > 0.7
                                ? Colors.green
                                : (adherence > 0.4
                                    ? Colors.orange
                                    : Colors.red),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _metric('$taken', s.t('med_taken'), Colors.green),
                            _metric('$missed', s.t('med_missed'), Colors.red),
                            _metric('${_doses.length}', s.t('nc_total'),
                                scheme.onSurface),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_doses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Center(child: Text(s.t('no_med_log'))),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SegmentedButton<_MedView>(
                      segments: [
                        ButtonSegment(
                            value: _MedView.byMed,
                            icon: const Icon(Icons.medication_liquid),
                            label: Text(s.t('med_by_drug'))),
                        ButtonSegment(
                            value: _MedView.all,
                            icon: const Icon(Icons.list_alt),
                            label: Text(s.t('med_full_log'))),
                      ],
                      selected: {_view},
                      onSelectionChanged: (v) =>
                          setState(() => _view = v.first),
                    ),
                  ),
                  if (_view == _MedView.all)
                    for (final d in _doses) _doseTile(d, s)
                  else
                    for (final entry in _groupedByName().entries)
                      _medGroupCard(entry.key, entry.value, s),
                ],
              ],
            ),
    );
  }

  Widget _sectionTitle(IconData icon, String text, ColorScheme scheme) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Row(children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: scheme.primary)),
        ]),
      );

  Map<String, List<MedDose>> _groupedByName() {
    final map = <String, List<MedDose>>{};
    for (final d in _doses) {
      (map[d.name] ??= []).add(d);
    }
    return map;
  }

  Widget _medGroupCard(String name, List<MedDose> list, S s) {
    final taken = list.where((d) => d.taken).length;
    final missed = list.length - taken;
    final scheme = Theme.of(context).colorScheme;
    String two(int n) => n.toString().padLeft(2, '0');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            child: Text('$taken',
                style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold)),
          ),
          title: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            '${s.t('med_taken')}: $taken'
            '${missed > 0 ? '  •  ${s.t('med_missed')}: $missed' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
          children: [
            for (final d in list)
              ListTile(
                dense: true,
                leading: Icon(d.taken ? Icons.check_circle : Icons.cancel,
                    color: d.taken ? Colors.green : Colors.red, size: 20),
                title: Text(
                    '${d.at.year}/${two(d.at.month)}/${two(d.at.day)}  '
                    '${two(d.at.hour)}:${two(d.at.minute)}',
                    style: const TextStyle(fontSize: 13)),
                subtitle: (d.dose ?? '').isEmpty ? null : Text(d.dose!),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _deleteDose(d),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDose(MedDose d) async {
    final s = S.of(context);
    if (!await confirmDelete(context,
        title: s.t('med_delete_dose'), message: s.t('med_delete_dose_msg'))) {
      return;
    }
    await _repo.delete(d.id!);
    await _load();
  }

  Widget _metric(String v, String label, Color color) => Column(
        children: [
          Text(v,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );

  Widget _doseTile(MedDose d, S s) {
    String two(int n) => n.toString().padLeft(2, '0');
    final when = '${d.at.year}/${two(d.at.month)}/${two(d.at.day)}  '
        '${two(d.at.hour)}:${two(d.at.minute)}';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: Icon(d.taken ? Icons.check_circle : Icons.cancel,
            color: d.taken ? Colors.green : Colors.red),
        title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            [if ((d.dose ?? '').isNotEmpty) d.dose!, when].join('  •  '),
            style: const TextStyle(fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteDose(d),
        ),
      ),
    );
  }
}

/// مسوّدة كورس دواء جديد (تُعاد من ورقة الإنشاء).
class _CourseDraft {
  final String name;
  final String? dose;
  final int total;
  final int every; // الفاصل بالأيام (7 = أسبوعيًّا)
  final DateTime first;
  const _CourseDraft({
    required this.name,
    required this.dose,
    required this.total,
    required this.every,
    required this.first,
  });
}

/// ورقة «بدء دواء»: الاسم + الجرعة + عدد الجرعات + الفاصل + أوّل موعد.
class _NewCourseSheet extends StatefulWidget {
  final List<String> suggestions;
  const _NewCourseSheet({required this.suggestions});

  @override
  State<_NewCourseSheet> createState() => _NewCourseSheetState();
}

class _NewCourseSheetState extends State<_NewCourseSheet> {
  final _name = TextEditingController();
  final _dose = TextEditingController();
  int _total = 8;
  int _every = 1; // يوميًّا افتراضيًّا (راحة ٠) — الأشيع للأدوية
  late DateTime _date;
  late TimeOfDay _time;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _time = TimeOfDay(hour: now.hour, minute: now.minute);
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Widget _stepper(String label, int value, String suffix, VoidCallback dec,
      VoidCallback inc) {
    return Row(children: [
      Expanded(
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w600))),
      IconButton(
          icon: const Icon(Icons.remove_circle_outline), onPressed: dec),
      Text('$value $suffix',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: inc),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final dateFmt = DateFormat('yyyy/MM/dd');
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('med_new'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textDirection: lineDirection(_name.text),
              decoration: InputDecoration(
                labelText: s.t('med_name'),
                prefixIcon: const Icon(Icons.medication_outlined),
              ),
            ),
            if (widget.suggestions.isNotEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (final n in widget.suggestions.take(8))
                    ActionChip(
                        label: Text(n),
                        onPressed: () => setState(() => _name.text = n)),
                ],
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _dose,
              decoration: InputDecoration(
                labelText: s.t('med_dose'),
                prefixIcon: const Icon(Icons.science_outlined),
              ),
            ),
            const SizedBox(height: 12),
            _stepper(
                s.t('med_total'),
                _total,
                s.t('med_dose_unit'),
                () => setState(() => _total = (_total - 1).clamp(1, 365)),
                () => setState(() => _total = (_total + 1).clamp(1, 365))),
            // الفاصل = «عدد أيام الراحة بين الجرعتين» (نموذج بسيط واضح):
            //   ٠ = يوميًّا، ١ = يوم بعد يوم، ٢ = جرعة ثمّ راحة يومين…
            // داخليًّا: الفاصل بالأيام (_every) = أيام الراحة + ١.
            Text('أيام الراحة بين الجرعتين',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(children: [
              IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 30),
                  onPressed: () =>
                      setState(() => _every = (_every - 1).clamp(1, 90))),
              SizedBox(
                width: 44,
                child: Text('${_every - 1}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 22)),
              ),
              IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 30),
                  onPressed: () =>
                      setState(() => _every = (_every + 1).clamp(1, 90))),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _every == 1
                      ? 'يوميًّا'
                      : _every == 2
                          ? 'يوم بعد يوم'
                          : 'راحة ${_every - 1} أيام',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ),
            ]),
            // توضيح صريح للمعنى.
            Text(
              _every == 1
                  ? 'جرعة كلّ يوم (بلا راحة)'
                  : _every == 2
                      ? 'جرعة، ثمّ راحة يوم واحد، ثمّ الجرعة التالية'
                      : 'جرعة، ثمّ راحة ${_every - 1} أيام، ثمّ الجرعة التالية',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 8),
            // أوّل جرعة: تاريخ + وقت.
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(dateFmt.format(_date)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time, size: 18),
                  label: Text(_time.format(context)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('${s.t('med_first')}: ${dateFmt.format(_date)}',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
            const SizedBox(height: 16),
            Row(children: [
              const Spacer(),
              FilledButton.icon(
                onPressed: _name.text.trim().isEmpty
                    ? null
                    : () {
                        final first = DateTime(_date.year, _date.month,
                            _date.day, _time.hour, _time.minute);
                        Navigator.pop(
                          context,
                          _CourseDraft(
                            name: _name.text.trim(),
                            dose: _dose.text.trim().isEmpty
                                ? null
                                : _dose.text.trim(),
                            total: _total,
                            every: _every,
                            first: first,
                          ),
                        );
                      },
                icon: const Icon(Icons.check),
                label: Text(s.t('save')),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// ورقة تسجيل جرعة فعليّة: اسم + جرعة + الحالة (أُخذت/فاتت).
class _LogSheet extends StatefulWidget {
  final List<String> suggestions;
  const _LogSheet({required this.suggestions});

  @override
  State<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<_LogSheet> {
  final _name = TextEditingController();
  final _dose = TextEditingController();
  bool _taken = true;

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('med_log_dose'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            textDirection: lineDirection(_name.text),
            decoration: InputDecoration(
              labelText: s.t('med_name'),
              prefixIcon: const Icon(Icons.medication_outlined),
            ),
          ),
          if (widget.suggestions.isNotEmpty)
            Wrap(
              spacing: 6,
              children: [
                for (final n in widget.suggestions.take(8))
                  ActionChip(
                      label: Text(n),
                      onPressed: () => setState(() => _name.text = n)),
              ],
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _dose,
            decoration: InputDecoration(
              labelText: s.t('med_dose'),
              prefixIcon: const Icon(Icons.science_outlined),
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.check_circle),
                  label: Text(s.t('med_taken'))),
              ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.cancel),
                  label: Text(s.t('med_missed'))),
            ],
            selected: {_taken},
            onSelectionChanged: (v) => setState(() => _taken = v.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              FilledButton(
                onPressed: _name.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        MedDose(
                          name: _name.text.trim(),
                          dose: _dose.text.trim().isEmpty
                              ? null
                              : _dose.text.trim(),
                          taken: _taken,
                          at: DateTime.now(),
                        )),
                child: Text(s.t('save')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
