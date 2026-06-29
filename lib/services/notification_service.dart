import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/time/hijri_recurrence.dart';
import '../data/models/enums.dart';
import '../data/models/reminder.dart';
import 'med_occurrences.dart';
import 'time_service.dart';

/// مفتاح تنقّل عام لفتح الملاحظة عند الضغط على التذكير.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// يُستدعى عند الضغط على «غفوة» من الخلفية (لا بد أن يكون دالة عليا).
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  // إعادة الجدولة من الخلفية تتم عبر معالج عام بسيط.
  NotificationService.instance.handleAction(response, fromBackground: true);
}

/// خدمة الإشعارات/المنبّه المحلي (بدون إنترنت).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // قناة المنبّه (صوت إنذار متواصل + اهتزاز + أهمية قصوى).

  static const _snoozeAction = 'snooze';
  static const _dismissAction = 'dismiss';

  /// مدّة الغفوة بالدقائق (0 = بلا غفوة). تُضبط من الإعدادات.
  int snoozeMinutes = 10;

  /// «لا يُفوَّت» مفعَّل: نمنع زرّ «إيقاف» من الإشعار حتى لا يُغلَق دون تحدّي،
  /// ونوجّه النقر إلى شاشة المنبّه (حيث يُطلَب الحساب/كتابة الكلمة). تُضبط من الإعدادات.
  bool cantMiss = false;

  /// «وضع عدم النسيان» للتذكيرات الحرجة: يُعاد التنبيه تلقائيًّا حتى التأكيد.
  /// عدد مرّات الإعادة والفاصل بينها (يُضبطان لاحقًا من الإعدادات).
  int forgetRepeats = 4;
  Duration forgetInterval = const Duration(minutes: 3);
  static const int _forgetStride = 1 << 26; // فصل معرّفات الإعادات

  /// أقصى قيمة لمعرّف إشعار (يجب أن يسع في عدد صحيح 32-بت وإلا رمى النظام خطأً).
  static const int _maxNotifId = 0x7fffffff; // 2^31 - 1

  /// يُلغي تذكيرًا مع كل الإشعارات التابعة (إعادات «عدم النسيان» + التنبيهات
  /// المسبقة) ضمن كتلة معرّفاته. نتخطّى أي معرّف يتجاوز نطاق 32-بت (لا يمكن أن
  /// يكون مجدولًا أصلًا) لتفادي رمي النظام لخطأ «خارج النطاق».
  Future<void> _cancelFollowups(int baseId) async {
    for (var k = 1; k <= 15; k++) {
      final id = baseId + k * _forgetStride;
      if (id > _maxNotifId) break; // المعرّفات تتزايد ⇒ ما بعده أكبر
      await _plugin.cancel(id);
    }
  }

  /// يُستدعى عند فتح ملاحظة من التذكير (يضبطه التطبيق).
  void Function(int noteId)? onOpenNote;

  /// يُستدعى عند الضغط على تذكير **حرج** — لعرض شاشة المنبّه داخل التطبيق.
  /// info يحوي: title, body, base, note.
  void Function(Map<String, String> info)? onAlarm;

  Future<void> init() async {
    if (_initialized) return;

    // المنطقة الزمنية (تلقائي من الجهاز أو يدويًّا من الإعدادات).
    await TimeService.instance.applyZone();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (r) => handleAction(r),
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // قناة لكل نغمة (أندرويد يربط الصوت بالقناة).
    for (final tone in alarmTones) {
      await androidImpl?.createNotificationChannel(
        AndroidNotificationChannel(
          'alaoufi_alarm_$tone',
          'المنبّه ($tone)',
          description: 'تنبيهات المنبّه والتذكيرات',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(tone),
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableVibration: true,
        ),
      );
    }

    // قناة هادئة للتذكيرات منخفضة الأهمية (بلا صوت).
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'alaoufi_quiet',
        'تنبيهات هادئة',
        description: 'إشعارات بلا صوت',
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
      ),
    );

    _initialized = true;
  }

  /// النغمات المتاحة (أسماء ملفات raw). نغمات طبيعية ناعمة مولّدة أصليًّا
  /// (خالية من حقوق النشر). مرتّبة ضمن تصنيفات في «مكتبة الأصوات».
  static const alarmTones = [
    // بحر
    'ocean', 'gentle_waves', 'sea_shore', 'blue_harbour', 'water',
    // غابة
    'forest', 'rainforest', 'creek', 'birds',
    // مطر
    'rain', 'rain_window', 'soft_storm',
    // رياح
    'desert_wind', 'evening_breeze',
    // هادئة
    'aurora', 'morning_light', 'soft_bell', 'chime', 'bell',
    // منبّهات
    'alarm', 'digital_alarm', 'urgent', 'wake_bell',
  ];

  /// النغمة المختارة حاليًا (افتراضي ocean = Calm Tide) — تُضبط من الإعدادات.
  /// قد تكون 'custom' عند اختيار نغمة من ملفات/نغمات الجهاز.
  String _tone = 'ocean';
  String get tone => _tone;
  set tone(String t) {
    if (alarmTones.contains(t) || t == 'custom') _tone = t;
  }

  // ===== نغمة مخصّصة من الجهاز (رابط URI يقرأه نظام الإشعارات) =====
  String? _customUri;
  String _customChannelId = 'alaoufi_alarm_custom_0';

  /// يضبط نغمة مخصّصة من الجهاز ويُنشئ قناة جديدة لها (قنوات أندرويد لا
  /// يمكن تغيير صوتها بعد الإنشاء، لذا نُنشئ قناة بمعرّف جديد عند كل تغيير).
  Future<void> setCustomTone(String? uri, {int seq = 0}) async {
    _customUri = uri;
    if (uri == null || uri.isEmpty) return;
    _tone = 'custom';
    _customChannelId = 'alaoufi_alarm_custom_$seq';
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // حذف القنوات المخصّصة السابقة (تنظيف) قبل إنشاء الجديدة.
    for (var i = seq - 1; i >= 0 && i >= seq - 3; i--) {
      await androidImpl?.deleteNotificationChannel('alaoufi_alarm_custom_$i');
    }
    await androidImpl?.createNotificationChannel(
      AndroidNotificationChannel(
        _customChannelId,
        'المنبّه (نغمة مخصّصة)',
        description: 'تنبيهات بنغمة مختارة من الجهاز',
        importance: Importance.max,
        playSound: true,
        sound: UriAndroidNotificationSound(uri),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
      ),
    );
  }

  Future<void> requestPermissions() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
    // إذن الشاشة الكاملة (أندرويد 14+) — كي يظهر المنبّه ملء الشاشة فوق القفل.
    try {
      await androidImpl?.requestFullScreenIntentPermission();
    } catch (_) {/* قد لا يتوفّر على بعض الإصدارات */}
  }

  /// تفاصيل الإشعار حسب **مستوى الأهمية**:
  /// - low: إشعار هادئ بلا صوت/اهتزاز (قناة منفصلة).
  /// - medium: صوت فقط.
  /// - high: صوت + اهتزاز.
  /// - critical: شاشة كاملة + إصرار (تكرار الصوت) حتى تفاعل المستخدم.
  AndroidNotificationDetails _alarmDetails(ReminderImportance imp) {
    if (imp == ReminderImportance.low) {
      return const AndroidNotificationDetails(
        'alaoufi_quiet',
        'تنبيهات هادئة',
        channelDescription: 'إشعارات بلا صوت',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        playSound: false,
        enableVibration: false,
      );
    }
    final isCustom = _tone == 'custom' && _customUri != null;
    final critical = imp == ReminderImportance.critical;
    final vibrate = imp == ReminderImportance.high || critical;
    return AndroidNotificationDetails(
      isCustom ? _customChannelId : 'alaoufi_alarm_$_tone',
      isCustom ? 'المنبّه (نغمة مخصّصة)' : 'المنبّه ($_tone)',
      channelDescription: 'تنبيهات المنبّه والتذكيرات',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      // شاشة كاملة للتذكيرات الحرجة فقط.
      fullScreenIntent: critical,
      playSound: true,
      sound: isCustom
          ? UriAndroidNotificationSound(_customUri!)
          : RawResourceAndroidNotificationSound(_tone),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: vibrate,
      vibrationPattern:
          vibrate ? Int64List.fromList([0, 600, 300, 600, 300, 600]) : null,
      // FLAG_INSISTENT (تكرار الصوت حتى التفاعل) للحرجة فقط.
      additionalFlags: critical ? Int32List.fromList([4]) : null,
      actions: [
        if (snoozeMinutes > 0)
          AndroidNotificationAction(_snoozeAction, 'غفوة',
              showsUserInterface: false, cancelNotification: true),
        // مع «لا يُفوَّت» نُخفي زرّ الإيقاف المباشر: يجب فتح المنبّه وإكمال
        // التحدّي (حساب/كتابة كلمة) لإيقافه — فلا يُغلَق من الإشعار بالخطأ.
        if (!cantMiss)
          const AndroidNotificationAction(_dismissAction, 'إيقاف',
              showsUserInterface: false, cancelNotification: true),
      ],
    );
  }

  NotificationDetails _detailsFor(ReminderImportance imp) =>
      NotificationDetails(android: _alarmDetails(imp));

  /// وضع الجدولة: المنبّهات **الحرجة** تستخدم `alarmClock` (أعلى أولوية، تتجاوز
  /// وضع توفير الطاقة/Doze وتعمل حتى لو كان التطبيق مغلقًا) — وهو الأكثر موثوقية
  /// على أجهزة مثل شاومي/هواوي. غير الحرجة تستخدم `exactAllowWhileIdle`.
  AndroidScheduleMode _mode(ReminderImportance imp) =>
      imp == ReminderImportance.critical
          ? AndroidScheduleMode.alarmClock
          : AndroidScheduleMode.exactAllowWhileIdle;

  /// جدولة تذكير. يدعم التكرار يومي/أسبوعي/شهري/سنوي/مرة واحدة.
  /// يجدول إشعارًا مع تحمّل غياب إذن «المنبّهات الدقيقة»: إن رفض النظام الجدولة
  /// الدقيقة (exact_alarms_not_permitted) نُعيد المحاولة بوضع غير دقيق بدلًا من أن
  /// يرتفع استثناء يُفشل الحفظ بصمت (الزر «لا يعمل»). فالتذكير يُحفَظ ويُجدول دائمًا.
  Future<void> _zonedSchedule(
    int id,
    String title,
    String body,
    tz.TZDateTime when,
    NotificationDetails details, {
    required AndroidScheduleMode mode,
    DateTimeComponents? match,
    String? payload,
  }) async {
    try {
      await _plugin.zonedSchedule(id, title, body, when, details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: match,
          payload: payload);
    } on PlatformException catch (e) {
      if (e.code != 'exact_alarms_not_permitted') rethrow;
      await _plugin.zonedSchedule(id, title, body, when, details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: match,
          payload: payload);
    }
  }

  Future<void> schedule(Reminder reminder, String title, String body) async {
    await init();
    final scheduled = tz.TZDateTime.from(reminder.time, tz.local);

    final safeTitle = title.trim().isEmpty ? '⏰ تذكير' : '⏰ ${title.trim()}';
    final safeBody =
        body.trim().isEmpty ? 'لديك تذكير من Alaoufi Notes' : body.trim();

    // كورس دواء (فاصل أيام مخصّص أو عدد جرعات محدّد): لا يوجد تكرار «كل N يوم» أو
    // «أوقف بعد N» أصليّ في الإضافة ⇒ نجدول مجموعة من المواعيد القادمة يدويًّا،
    // وتُحدَّث عند كل فتح للتطبيق (ensureScheduled).
    if (reminder.intervalDays >= 2 || reminder.doseCount > 0) {
      await _scheduleMedCourse(reminder, safeTitle, safeBody);
      return;
    }

    // سنويّ هجريّ: لا مطابقة أصليّة في الإضافة (ميلاديّة فقط) ⇒ نجدول الموعد
    // الهجريّ القادم كموعد واحد، ويُعاد حسابه عند كل فتح عبر ensureScheduled.
    if (reminder.repeat == ReminderRepeat.hijriYearly) {
      final next = nextHijriAnniversary(reminder.time, DateTime.now());
      await _zonedSchedule(
        reminder.notificationId,
        safeTitle,
        safeBody,
        tz.TZDateTime.from(next, tz.local),
        _detailsFor(reminder.importance),
        mode: _mode(reminder.importance),
        payload: 'note:${reminder.noteId}|title:$safeTitle|body:$safeBody'
            '|imp:${reminder.importance.dbValue}|base:${reminder.notificationId}',
      );
      return;
    }

    DateTimeComponents? match;
    switch (reminder.repeat) {
      case ReminderRepeat.once:
        match = null;
        break;
      case ReminderRepeat.daily:
        match = DateTimeComponents.time;
        break;
      case ReminderRepeat.weekly:
        match = DateTimeComponents.dayOfWeekAndTime;
        break;
      case ReminderRepeat.monthly:
        match = DateTimeComponents.dayOfMonthAndTime;
        break;
      case ReminderRepeat.yearly:
        match = DateTimeComponents.dateAndTime;
        break;
      case ReminderRepeat.hijriYearly:
        match = null; // مُعالَج أعلاه بالعودة المبكّرة.
        break;
    }

    await _zonedSchedule(
      reminder.notificationId,
      safeTitle,
      safeBody,
      scheduled,
      _detailsFor(reminder.importance),
      mode: _mode(reminder.importance),
      match: match,
      payload: 'note:${reminder.noteId}|title:$safeTitle|body:$safeBody'
          '|imp:${reminder.importance.dbValue}|base:${reminder.notificationId}',
    );

    // «وضع عدم النسيان»: للتذكيرات الحرجة لمرّة واحدة، أعِد التنبيه تلقائيًّا
    // عند فواصل متتالية حتى يؤكّد المستخدم (الإلغاء يحذف كل الإعادات).
    final base = reminder.notificationId;
    if (reminder.importance == ReminderImportance.critical &&
        reminder.repeat == ReminderRepeat.once &&
        base < _forgetStride &&
        forgetRepeats > 0) {
      for (var k = 1; k <= forgetRepeats; k++) {
        final when = scheduled.add(forgetInterval * k);
        await _zonedSchedule(
          base + k * _forgetStride,
          safeTitle,
          '$safeBody ⏰',
          when,
          _detailsFor(ReminderImportance.critical),
          mode: AndroidScheduleMode.alarmClock,
          payload: 'note:${reminder.noteId}|title:$safeTitle|body:$safeBody'
              '|imp:critical|base:$base',
        );
      }
    }

    // تنبيهات مسبقة قبل الموعد (للتذكيرات لمرّة واحدة): إشعار متوسّط لكل فارق.
    if (reminder.repeat == ReminderRepeat.once &&
        reminder.preAlerts.isNotEmpty &&
        base < _forgetStride) {
      final now = tz.TZDateTime.now(tz.local);
      var i = 0;
      for (final mins in reminder.preAlerts.take(4)) {
        final when = scheduled.subtract(Duration(minutes: mins));
        if (when.isAfter(now)) {
          await _zonedSchedule(
            base + (10 + i) * _forgetStride,
            '⏳ ${_beforeLabel(mins)} • ${title.trim().isEmpty ? "تذكير" : title.trim()}',
            safeBody,
            when,
            _detailsFor(ReminderImportance.medium),
            mode: AndroidScheduleMode.exactAllowWhileIdle,
            payload: 'note:${reminder.noteId}|title:$safeTitle|body:$safeBody'
                '|imp:medium|base:$base',
          );
        }
        i++;
      }
    }
  }

  /// يجدول مجموعة من المواعيد القادمة لكورس دواء (حتى 14 موعدًا أو نهاية الكورس)
  /// كإشعارات لمرّة واحدة بمعرّفات `base + k*_forgetStride` (يُلغيها cancel معًا).
  Future<void> _scheduleMedCourse(
      Reminder reminder, String safeTitle, String safeBody) async {
    final base = reminder.notificationId;
    final now = tz.TZDateTime.now(tz.local);
    final limit = reminder.doseCount; // 0 = مستمر

    // امسح أي مواعيد سابقة لهذا الكورس (قد يكون تقلّص) قبل إعادة الجدولة.
    await _plugin.cancel(base);
    await _cancelFollowups(base);

    // نقطة بداية الفهرس (قفزة سريعة للكورس المستمر بفاصل أيام).
    var i = 0;
    if (limit == 0 && reminder.intervalDays >= 2) {
      final passed = now.difference(reminder.time).inDays;
      if (passed > 0) i = passed ~/ reminder.intervalDays;
    }

    var scheduled = 0;
    var guard = 0;
    while (scheduled < 14 && guard < 8000) {
      guard++;
      if (limit > 0 && i >= limit) break;
      final occ = tz.TZDateTime.from(medOccurrenceAt(reminder, i), tz.local);
      i++;
      if (!occ.isAfter(now)) continue; // موعد فات ⇒ تخطٍّ.
      await _zonedSchedule(
        base + scheduled * _forgetStride,
        safeTitle,
        safeBody,
        occ,
        _detailsFor(reminder.importance),
        mode: _mode(reminder.importance),
        payload: 'note:${reminder.noteId}|title:$safeTitle|body:$safeBody'
            '|imp:${reminder.importance.dbValue}|base:$base',
      );
      scheduled++;
    }
  }

  String _beforeLabel(int mins) {
    if (mins % 1440 == 0) return 'قبل ${mins ~/ 1440} يوم';
    if (mins % 60 == 0) return 'قبل ${mins ~/ 60} ساعة';
    return 'قبل $mins دقيقة';
  }

  /// يعالج الضغط على التذكير أو أزراره (إيقاف/غفوة/فتح الملاحظة).
  Future<void> handleAction(NotificationResponse r,
      {bool fromBackground = false}) async {
    final payload = r.payload ?? '';
    final noteId = _extractInt(payload, 'note:');

    // «تم الإنجاز/إيقاف» أو غفوة ⇒ أكّد الاستلام: ألغِ كل إعادات «عدم النسيان».
    final base = _extractInt(payload, 'base:') ?? r.id ?? 0;

    switch (r.actionId) {
      case _dismissAction:
        await init();
        await _plugin.cancel(base);
        await _cancelFollowups(base); // أوقف إعادة التنبيه نهائيًّا
        return;
      case _snoozeAction:
        await init();
        await _plugin.cancel(base);
        await _cancelFollowups(base); // أوقف الإعادات ثم أجِّل
        await _scheduleSnooze(base, payload);
        return;
      default:
        // ضغط على جسم الإشعار: تذكير حرج (أو وضع «لا يُفوَّت») ⇒ شاشة المنبّه،
        // وإلا افتح الملاحظة.
        final imp = _extractStr(payload, 'imp:');
        if ((imp == 'critical' || cantMiss) && onAlarm != null && !fromBackground) {
          onAlarm!({
            'title': _extractStr(payload, 'title:') ?? '⏰',
            'body': _extractStr(payload, 'body:') ?? '',
            'base': '$base',
            'note': '${noteId ?? -1}',
          });
          return;
        }
        if (noteId != null) {
          if (onOpenNote != null) {
            onOpenNote!(noteId);
          }
        }
    }
  }

  /// «تم الإنجاز»: يُلغي المنبّه وكل إعاداته نهائيًّا.
  Future<void> acknowledgeAlarm(int base) async {
    await init();
    await _plugin.cancel(base);
    await _cancelFollowups(base);
  }

  /// تأجيل المنبّه [minutes] دقيقة (يُلغي الإعادات ثم يُعيد جدولته حرجًا).
  Future<void> snoozeAlarm(
      int base, String title, String body, int minutes, int? noteId) async {
    await init();
    await _plugin.cancel(base);
    await _cancelFollowups(base);
    final when =
        tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
    await _zonedSchedule(
      base,
      title,
      body,
      when,
      _detailsFor(ReminderImportance.critical),
      mode: AndroidScheduleMode.alarmClock,
      payload: 'note:${noteId ?? -1}|title:$title|body:$body'
          '|imp:critical|base:$base',
    );
  }

  Future<void> _scheduleSnooze(int id, String payload) async {
    await init();
    final title = _extractStr(payload, 'title:') ?? '⏰ تذكير';
    final body = _extractStr(payload, 'body:') ?? 'تذكير مؤجَّل';
    final imp = ReminderImportanceX.fromDb(_extractStr(payload, 'imp:'));
    final when = tz.TZDateTime.now(tz.local)
        .add(Duration(minutes: snoozeMinutes > 0 ? snoozeMinutes : 10));
    await _zonedSchedule(
      id, // نفس المعرّف.
      title,
      body,
      when,
      _detailsFor(imp),
      mode: _mode(imp),
      payload: payload,
    );
  }

  int? _extractInt(String payload, String key) {
    final v = _extractStr(payload, key);
    return v == null ? null : int.tryParse(v);
  }

  String? _extractStr(String payload, String key) {
    for (final part in payload.split('|')) {
      if (part.startsWith(key)) return part.substring(key.length);
    }
    return null;
  }

  /// التذكير الذي فُتح به التطبيق (إن أُقلع بالضغط على إشعار).
  Future<int?> initialNoteId() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      final payload = details!.notificationResponse?.payload ?? '';
      return _extractInt(payload, 'note:');
    }
    return null;
  }

  /// إن أُقلع التطبيق **من المنبّه** (تطبيق مغلق + شاشة كاملة/نقرة): نعالج الإطلاق
  /// لإظهار شاشة المنبّه الحرج فورًا (أو فتح الملاحظة). يُستدعى بعد جهوز الواجهة.
  Future<void> handleLaunch() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return;
    final resp = details.notificationResponse;
    if (resp != null) await handleAction(resp);
  }

  Future<void> cancel(int notificationId) async {
    await init();
    await _plugin.cancel(notificationId);
    // ألغِ أي إعادات «عدم النسيان» تابعة (إن وُجدت).
    await _cancelFollowups(notificationId);
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  // ===================== ملاحظات مثبّتة في شريط الإشعارات =====================
  // إشعار «مستمرّ» (ongoing) صامت يعرض ملاحظة مهمّة تبقى أمام المستخدم. معرّفه في
  // نطاق مستقلّ (1<<30 + noteId) فلا يتعارض مع التذكيرات ([1, 2^26)) ولا إعاداتها.
  static const int _pinnedBase = 1 << 30;
  static const String _kPinnedKey = 'pinned_notification_notes';

  Future<Set<int>> pinnedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_kPinnedKey) ?? [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  Future<bool> isPinnedId(int noteId) async =>
      (await pinnedIds()).contains(noteId);

  Future<void> _savePinned(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _kPinnedKey, ids.map((e) => e.toString()).toList());
  }

  /// يعرض/يحدّث إشعار ملاحظة مثبّتة (صامت ومستمرّ)، ويحفظها في القائمة المثبّتة.
  Future<void> showPinnedNote(int noteId, String title, String body) async {
    await init();
    final t = title.trim().isEmpty ? 'ملاحظة مثبّتة' : title.trim();
    final b = body.trim();
    await _plugin.show(
      _pinnedBase + noteId,
      '📌 $t',
      b,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'alaoufi_quiet',
          'تنبيهات هادئة',
          channelDescription: 'إشعارات بلا صوت',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true, // لا يُزال بالسحب
          autoCancel: false,
          onlyAlertOnce: true,
          playSound: false,
          styleInformation: b.isEmpty ? null : BigTextStyleInformation(b),
        ),
      ),
      payload: 'note:$noteId|pinned:1',
    );
    final ids = await pinnedIds()
      ..add(noteId);
    await _savePinned(ids);
  }

  /// يزيل إشعار الملاحظة المثبّتة ويخرجها من القائمة.
  Future<void> cancelPinnedNote(int noteId) async {
    await init();
    await _plugin.cancel(_pinnedBase + noteId);
    final ids = await pinnedIds()
      ..remove(noteId);
    await _savePinned(ids);
  }

  // ===================== موجز الصباح =====================
  static const int _briefingId = (1 << 30) - 1; // معرّف ثابت مستقلّ

  /// يجدول (أو يلغي) إشعارًا يوميًّا صباحيًّا بعدد التذكيرات النشطة. يُحدَّث عند كل
  /// فتح للتطبيق فيبقى العدد محدَّثًا. هادئ (بلا صوت) وغير دقيق (لا يحتاج إذن منبّه).
  Future<void> updateMorningBriefing({
    required bool enabled,
    required int hour,
    required int minute,
    required int reminderCount,
  }) async {
    await init();
    await _plugin.cancel(_briefingId);
    if (!enabled) return;
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    final body = reminderCount > 0
        ? 'لديك $reminderCount تذكيرًا نشطًا — تفقّد مهامّك اليوم.'
        : 'يوم موفّق! لا تذكيرات نشطة حاليًّا.';
    await _zonedSchedule(
      _briefingId,
      '☀️ صباح الخير',
      body,
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'alaoufi_quiet',
          'تنبيهات هادئة',
          channelDescription: 'إشعارات بلا صوت',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      mode: AndroidScheduleMode.inexactAllowWhileIdle,
      match: DateTimeComponents.time, // يوميًّا في نفس الوقت
      payload: 'briefing:1',
    );
  }

  // ===== اختبار الموثوقية =====
  // معرّفات ثابتة للاختبار: أكبر من _forgetStride (كي لا تُطلَق إعادات «عدم
  // النسيان») وفي الوقت ذاته يبقى base + 15·stride ضمن نطاق 32-بت بأمان.
  static const int _testNowId = 200000000;
  static const int _testAlarmId = 200000001;

  /// هل الإشعارات مُفعّلة لهذا التطبيق؟ (للتشخيص في شاشة الاختبار).
  Future<bool?> areNotificationsEnabled() async {
    await init();
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return a?.areNotificationsEnabled();
  }

  /// هل يُسمح بجدولة المنبّهات الدقيقة (exact alarms)؟ مهمّ لدقّة التذكير.
  Future<bool?> canScheduleExactAlarms() async {
    await init();
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return a?.canScheduleExactNotifications();
  }

  /// إشعار اختبار **فوري** (صوت + اهتزاز) للتأكّد أن الإشعارات والنغمة تعمل.
  Future<void> showTestNotificationNow() async {
    await init();
    await _plugin.show(
      _testNowId,
      '🔔 اختبار إشعار فوري',
      'إن سمعت النغمة ورأيت هذا الإشعار فالإشعارات تعمل ✅',
      _detailsFor(ReminderImportance.high),
    );
  }

  /// يجدول **منبّهًا حرجًا تجريبيًّا** بعد [delay]: يختبر التنبيه الدقيق وشاشة
  /// المنبّه ملء الشاشة (عند الضغط على الإشعار تظهر شاشة المنبّه).
  Future<void> scheduleTestAlarm(Duration delay) async {
    await init();
    final r = Reminder(
      title: 'اختبار المنبّه',
      time: DateTime.now().add(delay),
      repeat: ReminderRepeat.once,
      importance: ReminderImportance.critical,
      notificationId: _testAlarmId,
    );
    await schedule(r, 'اختبار المنبّه', 'إن رأيت هذه الشاشة فالمنبّه يعمل ✅');
  }

  /// يُلغي إشعارات/منبّهات الاختبار (الفوري والمجدول).
  Future<void> cancelTests() async {
    await init();
    await _plugin.cancel(_testNowId);
    await _plugin.cancel(_testAlarmId);
  }
}
