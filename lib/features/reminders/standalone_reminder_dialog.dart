import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../widgets/confirm_dialog.dart';
import '../../data/models/enums.dart';
import '../editor/editor_attachments.dart';
import 'alarm_permissions.dart';
import '../../data/models/reminder.dart';
import '../../services/ringtone_picker.dart';
import '../../services/tone_preview.dart';
import '../../widgets/time_wheel.dart';
import '../settings/settings_provider.dart';
import '../sounds/sound_catalog.dart';
import 'reminder_helpers.dart';
import 'reminders_provider.dart';

/// نوع المنبّه — يُغيّر الحقول الظاهرة والإعدادات الافتراضية.
enum ReminderKind { general, medication, appointment, occasion, bills, travel, car }

extension ReminderKindX on ReminderKind {
  /// مفتاح ترجمة (يُحلّ عبر s.t)؛ الأنواع الجديدة بنصّ عربيّ مباشر (s.t يُرجعه كما هو).
  String get label => switch (this) {
        ReminderKind.general => 'rk_general',
        ReminderKind.medication => 'rk_med',
        ReminderKind.appointment => 'rk_appt',
        ReminderKind.occasion => 'rk_occasion',
        ReminderKind.bills => 'فواتير',
        ReminderKind.travel => 'سفر',
        ReminderKind.car => 'سيارة',
      };

  IconData get icon => switch (this) {
        ReminderKind.general => Icons.notifications_active_outlined,
        ReminderKind.medication => Icons.medication_outlined,
        ReminderKind.appointment => Icons.event_outlined,
        ReminderKind.occasion => Icons.celebration_outlined,
        ReminderKind.bills => Icons.receipt_long_outlined,
        ReminderKind.travel => Icons.flight_takeoff_outlined,
        ReminderKind.car => Icons.directions_car_outlined,
      };

  String get emoji => switch (this) {
        ReminderKind.general => '',
        ReminderKind.medication => '💊 ',
        ReminderKind.appointment => '📅 ',
        ReminderKind.occasion => '🎉 ',
        ReminderKind.bills => '🧾 ',
        ReminderKind.travel => '✈️ ',
        ReminderKind.car => '🚗 ',
      };

  String get titleLabel => switch (this) {
        ReminderKind.general => 'rd_title_reminder',
        ReminderKind.medication => 'med_name',
        ReminderKind.appointment => 'rd_title_appt',
        ReminderKind.occasion => 'rd_title_occasion',
        ReminderKind.bills => 'اسم الفاتورة',
        ReminderKind.travel => 'الوجهة',
        ReminderKind.car => 'الخدمة/السيارة',
      };
}

/// وصف ودّي مختصر لفاصل الجرعات (جرعة ثمّ راحة).
String _intervalHint(S s) => s.t('rd_interval_hint');

/// أسماء الأشهر الهجريّة (1..12).
const List<String> _hijriMonths = [
  'محرّم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة',
  'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة',
];

/// التاريخ الهجريّ المقابل لتاريخ ميلاديّ، بصيغة «١٥ رمضان ١٤٤٧ هـ».
String _hijriStr(DateTime d) {
  try {
    final h = HijriCalendar.fromDate(d);
    final m = (h.hMonth >= 1 && h.hMonth <= 12) ? _hijriMonths[h.hMonth - 1] : '';
    return '${h.hDay} $m ${h.hYear} هـ';
  } catch (_) {
    return '';
  }
}

/// رابط بحث خرائط جوجل لنصّ المكان (لاختيار الموقع ونسخ رابطه).
Uri _mapsSearchUri(String query) {
  final q = Uri.encodeComponent(query.trim().isEmpty ? 'موقع' : query.trim());
  return Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
}

/// يفتح رابطًا في تطبيق خارجي (الخرائط/المتصفّح) بأمان.
Future<void> _openExternal(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {/* لا يوجد تطبيق يفتح الرابط */}
}

/// يختار مرفق الدعوة (صورة أو PDF) وينسخه لمجلد المرفقات. يعيد المسار أو null.
Future<String?> _pickInvitation(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.image_outlined),
          title: Text(S.of(context).t('image')),
          onTap: () => Navigator.pop(context, 'image'),
        ),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('PDF'),
          onTap: () => Navigator.pop(context, 'pdf'),
        ),
      ]),
    ),
  );
  if (choice == 'image' && context.mounted) {
    return EditorAttachments.pickImage(context);
  }
  if (choice == 'pdf') return EditorAttachments.pickPdf();
  return null;
}

/// أيام الأسبوع (تبدأ بالسبت) — القيمة بمعيار DateTime.weekday (الإثنين=1..الأحد=7).
const List<(int, String)> _weekdayDefs = [
  (6, 'wd_sat'),
  (7, 'wd_sun'),
  (1, 'wd_mon'),
  (2, 'wd_tue'),
  (3, 'wd_wed'),
  (4, 'wd_thu'),
  (5, 'wd_fri'),
];

/// حوار إنشاء/تعديل **تنبيه مستقلّ** (غير مرتبط بملاحظة): عنوان + وقت + تكرار + نغمة.
Future<void> showStandaloneReminderDialog(BuildContext context,
    {Reminder? existing}) async {
  final s = S.of(context);
  final provider = context.read<RemindersProvider>();
  final settings = context.read<SettingsProvider>();
  final titleCtrl = TextEditingController(text: existing?.title ?? '');
  DateTime date = existing?.time ?? DateTime.now().add(const Duration(hours: 1));
  TimeOfDay time = TimeOfDay.fromDateTime(date);
  ReminderRepeat repeat = existing?.repeat ?? ReminderRepeat.once;
  // التنبيه المستقلّ منبّه «حقيقيّ» ⇒ نجعله حرجًا افتراضيًّا (شاشة كاملة +
  // أعلى موثوقية + إصرار حتى التأكيد). يمكن للمستخدم خفض المستوى إن أراد.
  ReminderImportance importance =
      existing?.importance ?? ReminderImportance.critical;
  // تنبيه جديد: نبدأ بقيمة «قبل الوقت» الافتراضية من الإعدادات (إن وُجدت).
  final Set<int> preAlerts = {
    ...?existing?.preAlerts,
    if (existing == null && settings.defaultPreAlert > 0)
      settings.defaultPreAlert,
  };
  final Set<int> weekdays = {date.weekday};
  // نوع المنبّه + حقول خاصّة بكل نوع (جرعة الدواء / مكان الموعد + رابط خرائط).
  // عند تعديل تنبيه له موقع محفوظ، نبدأ بنوع «موعد» لإظهار حقول المكان.
  final bool existingIsMed = existing != null &&
      (existing.intervalDays >= 2 ||
          existing.doseCount > 0 ||
          (existing.title?.contains('💊') ?? false));
  final String _t0 = existing?.title ?? '';
  ReminderKind kind = existingIsMed
      ? ReminderKind.medication
      : _t0.contains('🧾')
          ? ReminderKind.bills
          : _t0.contains('✈️')
              ? ReminderKind.travel
              : _t0.contains('🚗')
                  ? ReminderKind.car
                  : _t0.contains('🎉')
                      ? ReminderKind.occasion
                      : ((existing?.location.isNotEmpty ?? false) ||
                              _t0.contains('📅'))
                          ? ReminderKind.appointment
                          : ReminderKind.general;
  final doseCtrl = TextEditingController();
  // دواء: فاصل الأيام بين الجرعات (≥2 ⇒ «كل N يوم») + عدد جرعات الكورس (0 = مستمر).
  int intervalDays = existing?.intervalDays ?? 0;
  int doseCount = existing?.doseCount ?? 0;
  final placeCtrl = TextEditingController();
  final mapLinkCtrl = TextEditingController(text: existing?.location ?? '');
  // مرفق الدعوة (صورة/PDF) للموعد — اختياري.
  String attachmentPath = existing?.attachmentPath ?? '';

  // عند **أول** إنشاء تنبيه جديد: اطلب فكّ كل القيود لضمان عمل المنبّه.
  if (existing == null) {
    await ensureAlarmReliabilityOnce(context);
    if (!context.mounted) return;
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final scheme = Theme.of(context).colorScheme;
          // ② لون مميّز لكل نوع منبّه (يُلوّن الرأس والمعاينة وزرّ الحفظ).
          Color kindColor(ReminderKind k) => switch (k) {
                ReminderKind.general => scheme.primary,
                ReminderKind.medication => const Color(0xFFE53935), // أحمر
                ReminderKind.appointment => const Color(0xFF1E88E5), // أزرق
                ReminderKind.occasion => const Color(0xFFF9A825), // ذهبي
                ReminderKind.bills => const Color(0xFF00897B), // أخضر مزرقّ
                ReminderKind.travel => const Color(0xFF5E35B1), // بنفسجي
                ReminderKind.car => const Color(0xFF6D4C41), // بنّي
              };
          final accent = kindColor(kind);
          String two(int n) => n.toString().padLeft(2, '0');
          DateTime combined() => DateTime(
              date.year, date.month, date.day, time.hour, time.minute);
          String repeatLabel(ReminderRepeat r) => switch (r) {
                ReminderRepeat.once => s.t('repeat_once'),
                ReminderRepeat.daily => s.t('repeat_daily'),
                ReminderRepeat.weekly => s.t('repeat_weekly'),
                ReminderRepeat.monthly => s.t('repeat_monthly'),
                ReminderRepeat.yearly => s.t('repeat_yearly'),
                ReminderRepeat.hijriYearly => s.t('repeat_hijri_yearly'),
              };

          // إعدادات افتراضية ذكية عند اختيار نوع المنبّه.
          void applyKindDefaults(ReminderKind k) {
            // فاصل الأيام/عدد الجرعات خاصّان بالدواء فقط.
            if (k != ReminderKind.medication) {
              intervalDays = 0;
              doseCount = 0;
            }
            switch (k) {
              case ReminderKind.general:
                break;
              case ReminderKind.medication:
                repeat = ReminderRepeat.daily; // الدواء يوميّ غالبًا
                importance = ReminderImportance.critical; // لا يُفوَّت
                preAlerts.clear();
                break;
              case ReminderKind.appointment:
                repeat = ReminderRepeat.once;
                importance = ReminderImportance.high;
                preAlerts
                  ..clear()
                  ..add(60); // تذكير قبل ساعة
                break;
              case ReminderKind.occasion:
                repeat = ReminderRepeat.yearly; // ذكرى سنويّة
                importance = ReminderImportance.medium;
                preAlerts.clear();
                break;
              case ReminderKind.bills:
                repeat = ReminderRepeat.monthly; // فاتورة شهريّة غالبًا
                importance = ReminderImportance.high;
                preAlerts
                  ..clear()
                  ..add(1440); // تذكير قبل يوم
                break;
              case ReminderKind.travel:
                repeat = ReminderRepeat.once;
                importance = ReminderImportance.high;
                preAlerts
                  ..clear()
                  ..add(1440);
                break;
              case ReminderKind.car:
                repeat = ReminderRepeat.once;
                importance = ReminderImportance.high;
                preAlerts.clear();
                break;
            }
          }

          // يُركّب العنوان النهائي من الاسم + الحقول الخاصّة بالنوع + رمز مميّز.
          String composeTitle() {
            var name = titleCtrl.text.trim();
            if (name.isEmpty) name = s.t(kind.label);
            switch (kind) {
              case ReminderKind.medication:
                final d = doseCtrl.text.trim();
                return '${kind.emoji}$name${d.isEmpty ? '' : ' — $d'}';
              case ReminderKind.appointment:
                final pl = placeCtrl.text.trim();
                return '${kind.emoji}$name${pl.isEmpty ? '' : ' @ $pl'}';
              case ReminderKind.occasion:
              case ReminderKind.bills:
              case ReminderKind.travel:
              case ReminderKind.car:
                return '${kind.emoji}$name';
              case ReminderKind.general:
                return name;
            }
          }

          Widget label(String t) => Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(t,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.bold)),
              );

          // بطاقة منتقي (تاريخ/وقت) ثلاثيّة الأبعاد بشارة دائريّة وتدرّج.
          Widget pickerCard(
                  IconData icon, String lbl, String value, VoidCallback onTap,
                  {String? sub}) =>
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.alphaBlend(
                            scheme.primary.withOpacity(0.10), scheme.surface),
                        Color.alphaBlend(
                            scheme.primary.withOpacity(0.03), scheme.surface),
                      ],
                    ),
                    border:
                        Border.all(color: scheme.primary.withOpacity(0.18)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.10),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Row(children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  scheme.primary,
                                  Color.alphaBlend(Colors.black.withOpacity(0.2),
                                      scheme.primary),
                                ],
                              ),
                            ),
                            child: Icon(icon, size: 19, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(lbl,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                                Text(value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                                if (sub != null && sub.isNotEmpty)
                                  Text(sub,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: scheme.onSurface
                                              .withOpacity(0.6))),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              );

          Future<void> pickDate() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => date = picked);
          }

          Future<void> pickTime() async {
            final picked = await pickTimeWheel(context, time);
            if (picked != null) setState(() => time = picked);
          }
          // التاريخ غير مهمّ عند التكرار اليومي/الأسبوعي (يتكرّر بنفسه)، لكنه مهمّ
          // لكورس الدواء (يحدّد بداية العلاج).
          final medCourse = kind == ReminderKind.medication &&
              (intervalDays >= 2 || doseCount > 0);
          final showDate = medCourse ||
              (repeat != ReminderRepeat.weekly &&
                  repeat != ReminderRepeat.daily);

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // رأس متدرّج ثلاثيّ الأبعاد بشارة بارزة (ثابت).
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent,
                          Color.alphaBlend(
                              Colors.black.withOpacity(0.18), accent),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.22),
                        ),
                        child: const Icon(Icons.add_alarm,
                            color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              existing == null ? s.t('rd_new') : s.t('rd_edit'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 19),
                            ),
                            Text(
                              '${kind.emoji}${s.t(kind.label)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                  // المحتوى (قابل للتمرير).
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ④ معاينة حيّة للتنبيه كما سيظهر في القائمة.
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color.alphaBlend(
                                      accent.withOpacity(0.16), scheme.surface),
                                  Color.alphaBlend(
                                      accent.withOpacity(0.04), scheme.surface),
                                ],
                              ),
                              border: BorderDirectional(
                                  start: BorderSide(color: accent, width: 4)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.10),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: [
                                    accent,
                                    Color.alphaBlend(
                                        Colors.black.withOpacity(0.2), accent),
                                  ]),
                                ),
                                child: Icon(kind.icon,
                                    color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(time.format(context),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18)),
                                    const SizedBox(height: 2),
                                    Text(composeTitle(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text(repeatLabel(repeat),
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: scheme.onSurface
                                                .withOpacity(0.6))),
                                  ],
                                ),
                              ),
                            ]),
                          ),
                          // نوع المنبّه (فوق العنوان) — يُكيّف الحقول والإعدادات.
                          label(s.t('rd_kind')),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: ReminderKind.values.map((k) {
                              return ChoiceChip(
                                avatar: Icon(k.icon,
                                    size: 18,
                                    color: kind == k ? scheme.primary : null),
                                label: Text(s.t(k.label)),
                                selected: kind == k,
                                onSelected: (_) => setState(() {
                                  kind = k;
                                  applyKindDefaults(k);
                                }),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: titleCtrl,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: s.t(kind.titleLabel),
                              prefixIcon: Icon(kind.icon),
                            ),
                          ),
                          // حقل خاصّ بالدواء: الجرعة.
                          if (kind == ReminderKind.medication) ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: doseCtrl,
                              decoration: InputDecoration(
                                labelText: s.t('rd_dose_opt'),
                                prefixIcon: Icon(Icons.science_outlined),
                              ),
                            ),
                          ],
                          // حقول خاصّة بالموعد: وصف المكان + رابط خرائط جوجل.
                          if (kind == ReminderKind.appointment) ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: placeCtrl,
                              decoration: InputDecoration(
                                labelText: s.t('rd_place_desc'),
                                hintText: s.t('rd_place_example'),
                                prefixIcon: Icon(Icons.place_outlined),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: mapLinkCtrl,
                              keyboardType: TextInputType.url,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: s.t('rd_loc_url'),
                                hintText: s.t('rd_loc_paste_hint'),
                                prefixIcon: const Icon(Icons.map_outlined),
                                suffixIcon: IconButton(
                                  tooltip: s.t('paste'),
                                  icon: const Icon(Icons.content_paste),
                                  onPressed: () async {
                                    final data = await Clipboard.getData(
                                        Clipboard.kTextPlain);
                                    final t = data?.text?.trim() ?? '';
                                    if (t.isNotEmpty) {
                                      setState(() => mapLinkCtrl.text = t);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _openExternal(
                                      _mapsSearchUri(placeCtrl.text)),
                                  icon: const Icon(Icons.map),
                                  label: Text(s.t('rd_pick_map')),
                                ),
                              ),
                              if (mapLinkCtrl.text.trim().isNotEmpty) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: s.t('rd_open_loc'),
                                  icon: const Icon(Icons.open_in_new),
                                  onPressed: () {
                                    final u =
                                        Uri.tryParse(mapLinkCtrl.text.trim());
                                    if (u != null) _openExternal(u);
                                  },
                                ),
                              ],
                            ]),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                s.t('rd_map_help'),
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurface.withOpacity(0.6)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // الدعوة (صورة/PDF) — اختياري.
                            if (attachmentPath.isEmpty)
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final path = await _pickInvitation(context);
                                  if (path != null) {
                                    setState(() => attachmentPath = path);
                                  }
                                },
                                icon: const Icon(Icons.attach_file),
                                label: Text(s.t('rd_attach_invite')),
                              )
                            else
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: attachmentPath
                                        .toLowerCase()
                                        .endsWith('.pdf')
                                    ? const Icon(Icons.picture_as_pdf,
                                        color: Colors.red, size: 38)
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.file(File(attachmentPath),
                                            width: 42,
                                            height: 42,
                                            fit: BoxFit.cover),
                                      ),
                                title: Text(s.t('rd_invite_attached')),
                                subtitle: Text(attachmentPath.split('/').last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: s.t('open'),
                                      icon: const Icon(Icons.open_in_new),
                                      onPressed: () => EditorAttachments
                                          .openFile(attachmentPath),
                                    ),
                                    IconButton(
                                      tooltip: s.t('remove'),
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () =>
                                          setState(() => attachmentPath = ''),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          const SizedBox(height: 12),
                          Row(children: [
                            if (showDate) ...[
                              pickerCard(
                                  Icons.calendar_today,
                                  s.t('rd_date'),
                                  '${date.year}/${two(date.month)}/${two(date.day)}',
                                  pickDate,
                                  sub: _hijriStr(date)),
                              const SizedBox(width: 10),
                            ],
                            pickerCard(Icons.access_time, s.t('rd_time'),
                                time.format(context), pickTime),
                          ]),
                          const SizedBox(height: 10),
                          // ⑥ اقتراحات وقت سريعة.
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final (lbl, at) in <(String, DateTime)>[
                                (
                                  'بعد ساعة',
                                  DateTime.now().add(const Duration(hours: 1))
                                ),
                                ('غدًا ٨ص', () {
                                  final n = DateTime.now();
                                  return DateTime(n.year, n.month, n.day + 1, 8);
                                }()),
                                ('الليلة ٩م', () {
                                  final n = DateTime.now();
                                  var d = DateTime(n.year, n.month, n.day, 21);
                                  if (!d.isAfter(n)) {
                                    d = d.add(const Duration(days: 1));
                                  }
                                  return d;
                                }()),
                              ])
                                ActionChip(
                                  avatar:
                                      Icon(Icons.bolt, size: 16, color: accent),
                                  label: Text(lbl),
                                  onPressed: () => setState(() {
                                    date = at;
                                    time = TimeOfDay.fromDateTime(at);
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // التكرار المخصّص «كل N يوم» يحجب خيارات التكرار العاديّة.
                          if (intervalDays < 2) ...[
                            label(s.t('rd_repeat')),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: ReminderRepeat.values.map((r) {
                                return ChoiceChip(
                                  label: Text(repeatLabel(r)),
                                  selected: repeat == r,
                                  onSelected: (_) => setState(() => repeat = r),
                                );
                              }).toList(),
                            ),
                            if (repeat == ReminderRepeat.weekly) ...[
                              const SizedBox(height: 14),
                              label(s.t('rd_weekdays')),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final d in _weekdayDefs)
                                    FilterChip(
                                      label: Text(s.t(d.$2)),
                                      selected: weekdays.contains(d.$1),
                                      onSelected: (sel) => setState(() {
                                        if (sel) {
                                          weekdays.add(d.$1);
                                        } else {
                                          weekdays.remove(d.$1);
                                        }
                                      }),
                                    ),
                                ],
                              ),
                            ],
                          ],
                          // تكرار مخصّص «كل N يوم» لكل الأنواع عدا الدواء (له قسمه
                          // الخاصّ أدناه بفاصل الجرعات ومدّة العلاج).
                          if (kind != ReminderKind.medication) ...[
                            const SizedBox(height: 14),
                            label(s.t('custom_repeat')),
                            Wrap(spacing: 8, runSpacing: 6, children: [
                              ChoiceChip(
                                label: Text(s.t('repeat_off')),
                                selected: intervalDays < 2,
                                onSelected: (_) =>
                                    setState(() => intervalDays = 0),
                              ),
                              ChoiceChip(
                                label: Text(s.t('repeat_every_days')),
                                selected: intervalDays >= 2,
                                onSelected: (_) => setState(() => intervalDays =
                                    intervalDays >= 2 ? intervalDays : 2),
                              ),
                            ]),
                            if (intervalDays >= 2)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(children: [
                                  Text(s.t('every')),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline),
                                    onPressed: intervalDays > 2
                                        ? () => setState(() => intervalDays--)
                                        : null,
                                  ),
                                  Text('$intervalDays ${s.t('day_unit')}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: intervalDays < 365
                                        ? () => setState(() => intervalDays++)
                                        : null,
                                  ),
                                ]),
                              ),
                          ],
                          // خيارات خاصّة بالدواء: فاصل الجرعات + مدّة العلاج.
                          if (kind == ReminderKind.medication) ...[
                            const SizedBox(height: 14),
                            label(s.t('rd_dose_interval')),
                            Wrap(spacing: 8, runSpacing: 6, children: [
                              ChoiceChip(
                                label: Text(s.t('rd_by_repeat')),
                                selected: intervalDays < 2,
                                onSelected: (_) =>
                                    setState(() => intervalDays = 0),
                              ),
                              ChoiceChip(
                                label: Text(s.t('repeat_every_days')),
                                selected: intervalDays >= 2,
                                onSelected: (_) => setState(() =>
                                    intervalDays = intervalDays >= 2
                                        ? intervalDays
                                        : 2),
                              ),
                            ]),
                            if (intervalDays >= 2)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(children: [
                                  Text(s.t('every')),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline),
                                    onPressed: intervalDays > 2
                                        ? () =>
                                            setState(() => intervalDays--)
                                        : null,
                                  ),
                                  Text('$intervalDays ${s.t('day_unit')}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: intervalDays < 30
                                        ? () =>
                                            setState(() => intervalDays++)
                                        : null,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text('(${_intervalHint(s)})',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurface
                                                .withOpacity(0.6))),
                                  ),
                                ]),
                              ),
                            const SizedBox(height: 14),
                            label(s.t('med_course_len')),
                            Wrap(spacing: 8, runSpacing: 6, children: [
                              ChoiceChip(
                                label: Text(s.t('med_continuous')),
                                selected: doseCount == 0,
                                onSelected: (_) =>
                                    setState(() => doseCount = 0),
                              ),
                              ChoiceChip(
                                label: Text(s.t('med_total')),
                                selected: doseCount > 0,
                                onSelected: (_) => setState(() =>
                                    doseCount = doseCount > 0 ? doseCount : 10),
                              ),
                            ]),
                            if (doseCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(children: [
                                  IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline),
                                    onPressed: doseCount > 1
                                        ? () => setState(() => doseCount--)
                                        : null,
                                  ),
                                  Text('$doseCount ${s.t('med_dose_unit')}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: doseCount < 365
                                        ? () => setState(() => doseCount++)
                                        : null,
                                  ),
                                ]),
                              ),
                          ],
                          const SizedBox(height: 14),
                          label(s.t('importance')),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: ReminderImportance.values.map((imp) {
                              return ChoiceChip(
                                avatar: Icon(impIcon(imp),
                                    size: 18, color: impColor(imp)),
                                label: Text(impLabel(s, imp)),
                                selected: importance == imp,
                                onSelected: (_) =>
                                    setState(() => importance = imp),
                              );
                            }).toList(),
                          ),
                          if (repeat == ReminderRepeat.once) ...[
                            const SizedBox(height: 14),
                            label(s.t('pre_alerts')),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final (mins, lbl) in const [
                                  (5, 'rd_pre5'),
                                  (15, 'rd_pre15'),
                                  (60, 'rd_pre_hour'),
                                  (1440, 'day_unit'),
                                ])
                                  FilterChip(
                                    label: Text(s.t(lbl)),
                                    selected: preAlerts.contains(mins),
                                    onSelected: (sel) => setState(() {
                                      if (sel) {
                                        preAlerts.add(mins);
                                      } else {
                                        preAlerts.remove(mins);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          label(s.t('rd_tone')),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: IconButton(
                              tooltip: s.t('rd_listen'),
                              icon: const Icon(Icons.play_circle_outline),
                              onPressed: () {
                                if (settings.alarmTone != 'custom') {
                                  TonePreview.play(settings.alarmTone);
                                }
                              },
                            ),
                            title: Text(settings.alarmTone == 'custom'
                                ? (settings.customToneTitle ?? s.t('rd_custom_tone'))
                                : toneName(settings.alarmTone)),
                            trailing: DropdownButton<String>(
                              value: soundCatalog
                                      .any((t) => t.id == settings.alarmTone)
                                  ? settings.alarmTone
                                  : 'custom',
                              isDense: true,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final t in soundCatalog)
                                  DropdownMenuItem(
                                      value: t.id, child: Text(t.name)),
                                if (settings.alarmTone == 'custom')
                                  DropdownMenuItem(
                                      value: 'custom',
                                      child: Text(
                                          settings.customToneTitle ?? '${s.t('rd_custom')} 🎵',
                                          overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(
                                    value: 'pick',
                                    child: Text('${s.t('rd_from_device')} 📱')),
                              ],
                              onChanged: (v) async {
                                if (v == null) return;
                                if (v == 'pick') {
                                  final uri = await RingtonePicker.pick(
                                      current: settings.customToneUri);
                                  if (uri != null) {
                                    final t = await RingtonePicker.title(uri);
                                    await settings.setCustomTone(uri, t);
                                  }
                                } else {
                                  await settings.setAlarmTone(v);
                                }
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          label(s.t('sound_options')),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.volume_up_outlined),
                            title: Text(s.t('auto_raise_volume')),
                            subtitle: Text(s.t('auto_raise_volume_desc'),
                                style: const TextStyle(fontSize: 11.5)),
                            value: settings.autoRaiseVolume,
                            onChanged: (v) async {
                              await settings.setAutoRaiseVolume(v);
                              setState(() {});
                            },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.trending_up),
                            title: Text(s.t('gradual_volume')),
                            subtitle: Text(s.t('gradual_volume_desc'),
                                style: const TextStyle(fontSize: 11.5)),
                            value: settings.gradualVolume,
                            onChanged: settings.autoRaiseVolume
                                ? (v) async {
                                    await settings.setGradualVolume(v);
                                    setState(() {});
                                  }
                                : null,
                          ),
                          const SizedBox(height: 10),
                          label(s.t('rd_snooze')),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.snooze),
                            title: Text(s.t('rd_snooze_dur')),
                            subtitle: Text(settings.snoozeMinutes == 0
                                ? s.t('rd_no_snooze')
                                : '${settings.snoozeMinutes} ${s.t('minute')}'),
                            trailing: DropdownButton<int>(
                              value: const [0, 5, 10, 15, 30]
                                      .contains(settings.snoozeMinutes)
                                  ? settings.snoozeMinutes
                                  : 10,
                              underline: const SizedBox.shrink(),
                              items: [
                                DropdownMenuItem(
                                    value: 0, child: Text(s.t('rd_no_snooze'))),
                                DropdownMenuItem(
                                    value: 5, child: Text('5 ${s.t('minute')}')),
                                DropdownMenuItem(
                                    value: 10, child: Text('10 ${s.t('minute')}')),
                                DropdownMenuItem(
                                    value: 15, child: Text('15 ${s.t('minute')}')),
                                DropdownMenuItem(
                                    value: 30, child: Text('30 ${s.t('minute')}')),
                              ],
                              onChanged: (v) async {
                                if (v == null) return;
                                await settings.setSnoozeMinutes(v);
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // شريط الحفظ الثابت (يبقى ظاهرًا دائمًا).
                  Material(
                    elevation: 10,
                    color: scheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Row(
                        children: [
                          if (existing != null)
                            TextButton.icon(
                              onPressed: () async {
                                if (!await confirmDelete(context,
                                    title: s.t('rd_delete_q'),
                                    message:
                                        s.t('rd_delete_msg'))) {
                                  return;
                                }
                                await provider.removeReminder(existing);
                                if (context.mounted) Navigator.pop(context);
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: Text(s.t('delete')),
                            ),
                          const Spacer(),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              minimumSize: const Size(140, 52),
                              elevation: 6,
                              shadowColor: accent.withOpacity(0.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              textStyle: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            onPressed: () async {
                              final finalTitle = composeTitle();
                              final isMed = kind == ReminderKind.medication;
                              // تكرار مخصّص «كل N يوم» متاح لكل الأنواع (لا الدواء
                              // فقط)؛ يُجدوَل عبر آليّة المواعيد المتكرّرة نفسها.
                              final hasInterval = intervalDays >= 2;
                              // كورس (فاصل مخصّص أو عدد جرعات) يمرّ دومًا عبر
                              // setStandalone لا التكرار الأسبوعيّ.
                              final isCourse =
                                  hasInterval || (isMed && doseCount > 0);
                              try {
                                if (repeat == ReminderRepeat.weekly &&
                                    weekdays.isNotEmpty &&
                                    !isCourse) {
                                  await provider.setStandaloneWeekly(
                                      finalTitle, time, weekdays,
                                      existing: existing);
                                } else {
                                  await provider.setStandalone(
                                      combined(),
                                      hasInterval
                                          ? ReminderRepeat.daily
                                          : repeat,
                                      finalTitle,
                                      importance: importance,
                                      preAlerts: preAlerts.toList()..sort(),
                                      location: mapLinkCtrl.text.trim(),
                                      attachmentPath: attachmentPath,
                                      intervalDays: hasInterval ? intervalDays : 0,
                                      doseCount: isMed ? doseCount : 0,
                                      existing: existing);
                                }
                                if (context.mounted) Navigator.pop(context);
                              } catch (e) {
                                // لا نترك الزر يبدو «لا يعمل»: نُغلق ونُبلّغ.
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            '${s.t('save')}: ${s.t('error')}')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.check),
                            label: Text(s.t('save')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
