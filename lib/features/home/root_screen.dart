import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backup_service.dart';
import '../../services/notification_service.dart';
import '../../services/sync/sync_service.dart';
import '../editor/rich_text_field.dart';
import '../reminders/reminders_provider.dart';
import '../reminders/reminders_screen.dart';
import '../settings/settings_provider.dart';
import 'notes_provider.dart';

/// الجذر: يهيّئ البيانات ثم يعرض الصفحة الرئيسية (التي تحوي القائمة الجانبية).
///
/// يراقب دورة حياة التطبيق ليُجري **مزامنة سحابية تلقائية** عند الإقلاع وكلّما
/// عاد التطبيق إلى الواجهة (resume)، مع إظهار «تمت المزامنة ✓».
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  bool _syncing = false;
  DateTime? _lastSyncDone;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotesProvider>().init();
      context.read<RemindersProvider>().refresh();
      // إن أُقلع التطبيق من منبّه حرج (وهو مغلق) ⇒ أظهر شاشة المنبّه فورًا.
      NotificationService.instance.handleLaunch();
      // شبكة أمان ضدّ فقدان الملاحظات: نُفعّل النسخ التلقائي اليومي افتراضيًا عند
      // أول تشغيل (مرّة واحدة)، ثم ننشئ نسخة إن حان موعدها — كلّه في الخلفية.
      BackupService.instance
          .ensureDefaultAutoBackup()
          .then((_) => BackupService.instance.maybeRunAutoBackup());
      // مزامنة أولى عند الإقلاع (تُعامَل كـ«فتح»).
      _autoSync(SyncTrigger.open);
      // أعِد عرض الملاحظات المثبّتة في الإشعارات (تختفي عند إغلاق التطبيق).
      _reassertPinnedNotes();
      // حدّث موجز الصباح بعدد التذكيرات الحاليّ.
      _refreshBriefing();
    });
  }

  /// يُحدّث جدولة موجز الصباح بعدد التذكيرات النشطة الحاليّ (يُستدعى عند كل فتح).
  Future<void> _refreshBriefing() async {
    try {
      if (!mounted) return;
      final st = context.read<SettingsProvider>();
      final count = context
          .read<RemindersProvider>()
          .items
          .where((v) => v.reminder.isActive)
          .length;
      await NotificationService.instance.updateMorningBriefing(
        enabled: st.morningBriefing,
        hour: st.briefingHour,
        minute: st.briefingMinute,
        reminderCount: count,
      );
    } catch (_) {}
  }

  /// يعيد إظهار إشعارات الملاحظات المثبّتة بعد إعادة تشغيل التطبيق، ويُنظّف
  /// المثبّتة المحذوفة/المؤرشفة.
  Future<void> _reassertPinnedNotes() async {
    try {
      final svc = NotificationService.instance;
      final ids = await svc.pinnedIds();
      if (ids.isEmpty || !mounted) return;
      final repo = context.read<NotesProvider>().notes;
      for (final id in ids) {
        final note = await repo.getNote(id);
        if (note == null || note.isDeleted || note.isArchived) {
          await svc.cancelPinnedNote(id);
          continue;
        }
        await svc.showPinnedNote(id, note.title, richToPlainText(note.content));
      }
    } catch (_) {
      // لا يجب أن تُعطّل بدء التطبيق.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // «فتح» عند العودة للواجهة، و«إغلاق» عند ذهابها للخلفية — كلّ منهما يُطابَق
    // بالتردّد المختار في الإعدادات (كل فتح / عند الإغلاق / مرّة باليوم).
    if (state == AppLifecycleState.resumed) {
      _autoSync(SyncTrigger.open);
      _refreshBriefing();
    } else if (state == AppLifecycleState.paused) {
      _autoSync(SyncTrigger.close);
    }
  }

  /// مزامنة تلقائية حسب التردّد المختار. تظهر بشريط خفيف ما لم يُفعّل وضع
  /// «المزامنة الصامتة» — وفي الحالين لا تُعطّل تفاعل المستخدم (عمل غير متزامن).
  Future<void> _autoSync(SyncTrigger trigger) async {
    if (_syncing) return;
    // تجنّب التكرار السريع عند تعدّد الأحداث خلال ثوانٍ.
    if (_lastSyncDone != null &&
        DateTime.now().difference(_lastSyncDone!) < const Duration(seconds: 8)) {
      return;
    }
    final svc = SyncService.instance;
    if (!await svc.shouldAutoSync(trigger)) return;
    final silent = await svc.silentSync();

    _syncing = true;
    if (!silent) {
      svc.status.value =
          const SyncStatus(SyncUi.syncing, 'جارٍ مزامنة ملاحظاتك…');
    }

    final r = await svc.syncNow();
    _lastSyncDone = DateTime.now();
    _syncing = false;

    // حدّث القائمة بهدوء عند النجاح.
    if (r.ok && mounted) {
      final notes = context.read<NotesProvider>();
      await notes.loadCategories();
      await notes.refresh();
    }

    if (silent) return; // الوضع الصامت: لا شريط ولا إشعار مرئيّ.

    svc.status.value = r.ok
        ? const SyncStatus(SyncUi.done, 'تمت المزامنة')
        : SyncStatus(SyncUi.error, r.message);
    // إخفاء الشريط تلقائيًا بعد لحظة.
    Future.delayed(Duration(seconds: r.ok ? 2 : 4), () {
      if (svc.status.value.state != SyncUi.syncing) {
        svc.status.value = const SyncStatus(SyncUi.idle);
      }
    });
  }

  // التطبيق مخصّص للتنبيهات فقط: الشاشة الرئيسية هي قائمة التنبيهات مباشرةً.
  @override
  Widget build(BuildContext context) => const RemindersScreen();
}
