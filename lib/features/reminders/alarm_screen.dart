import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/alarm_volume.dart';
import '../../services/notification_service.dart';
import '../settings/settings_provider.dart';

/// شاشة المنبّه داخل التطبيق — تظهر عند الضغط على تذكير حرج: عنوان/وصف/وقت
/// مع زرّ «تم الإنجاز» وزرّ «تأجيل» (خيارات 5/10/15/30/60 دقيقة).
///
/// عند ظهورها ترفع صوت المنبّه تلقائيًّا (إن فُعِّل) ليُسمَع حتى مع الصامت/المنخفض،
/// بالتدرّج إن طُلب، وتستعيد المستوى الأصليّ عند إغلاقها.
class AlarmScreen extends StatefulWidget {
  final Map<String, String> info;
  const AlarmScreen({super.key, required this.info});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  bool _raised = false;
  Timer? _escalateTimer; // تصعيد متعدّد المراحل إن لم يتفاعل المستخدم.
  int _stage = 0;
  // مشغّل داخليّ يكرّر صوت المنبّه ما دامت الشاشة ظاهرة — ضمانٌ أن الصوت
  // يستمرّ حتى إكمال التحدّي/التأجيل، حتى لو أوقف النظام صوت الإشعار.
  final AudioPlayer _player = AudioPlayer();

  int get _base => int.tryParse(widget.info['base'] ?? '') ?? 0;
  int? get _noteId {
    final n = int.tryParse(widget.info['note'] ?? '');
    return (n == null || n < 0) ? null : n;
  }

  @override
  void initState() {
    super.initState();
    // رفع صوت المنبّه إن فُعِّل (يقرأ تفضيلات المستخدم).
    final settings = context.read<SettingsProvider>();
    if (settings.autoRaiseVolume) {
      _raised = true;
      AlarmVolume.raise(
        targetPercent: 100,
        rampSeconds: settings.gradualVolume ? 15 : 0,
      );
    }
    _startLoopingSound(settings);
    // تصعيد متعدّد المراحل: كل 12 ثانية بلا تفاعل يزيد الإلحاح (صوت أقصى +
    // اهتزاز متصاعد) — للمنبّهات الحرجة التي يجب ألّا تُفوَّت.
    _escalateTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted) return;
      setState(() => _stage++);
      if (_raised) AlarmVolume.raise(targetPercent: 100);
      final pulses = _stage.clamp(1, 4);
      for (var i = 0; i < pulses; i++) {
        Future.delayed(Duration(milliseconds: i * 200),
            () => HapticFeedback.heavyImpact());
      }
    });
  }

  /// يبدأ تكرار نغمة المنبّه المختارة بأقصى صوت داخل التطبيق.
  Future<void> _startLoopingSound(SettingsProvider settings) async {
    try {
      final tone = settings.alarmTone;
      // النغمة المخصّصة (URI الجهاز) لا تُشغَّل كأصل؛ نستخدم نغمة إنذار مضمونة.
      final asset = (tone == 'custom' || tone.isEmpty) ? 'alarm' : tone;
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('sounds/$asset.wav'), volume: 1.0);
    } catch (_) {
      // عند أيّ خطأ يبقى صوت الإشعار هو الاحتياط.
    }
  }

  Future<void> _stopSound() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _escalateTimer?.cancel();
    _player.dispose(); // إيقاف الصوت الداخليّ عند إغلاق الشاشة بأيّ طريقة.
    // نستعيد مستوى الصوت الأصليّ مهما كانت طريقة الإغلاق (إنجاز/تأجيل/رجوع).
    if (_raised) AlarmVolume.restore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final info = widget.info;
    final now = TimeOfDay.now();
    final date = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    // وضع «لا يُفوَّت»: لا خروج إلا بإكمال التحدّي أو التأجيل (لا رجوع).
    final cantMiss = context.watch<SettingsProvider>().dismissChallenge != 0;

    return PopScope(
      canPop: !cantMiss,
      child: Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A237E), Color(0xFFB71C1C)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // مع «لا يُفوَّت»: لا زرّ رجوع — الخروج فقط بإكمال التحدّي أو
                // التأجيل. بدونه: سهم رجوع يُغلق الشاشة (يبقى التذكير).
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: cantMiss
                      ? Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_clock,
                                  color: Colors.white70, size: 18),
                              const SizedBox(width: 6),
                              Text(s.t('cant_miss_locked'),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12.5)),
                            ],
                          ),
                        )
                      : BackButton(
                          color: Colors.white,
                          onPressed: () => Navigator.maybePop(context),
                        ),
                ),
                Icon(Icons.crisis_alert,
                    color: Colors.white, size: 56.0 + _stage * 4),
                if (_stage > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('🔴 التنبيه يتصاعد',
                        style: TextStyle(
                            color: Colors.amberAccent.shade100,
                            fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                // الوقت الكبير.
                Text('${two(now.hour)}:${two(now.minute)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 64,
                        fontWeight: FontWeight.bold)),
                Text('${date.year}/${two(date.month)}/${two(date.day)}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 16)),
                const SizedBox(height: 28),
                // العنوان والوصف.
                Text(info['title'] ?? '⏰',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700)),
                if ((info['body'] ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(info['body']!,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.9), fontSize: 16)),
                ],
                const Spacer(),
                // تأجيل/غفوة — يُخفى في وضع «لا يُفوَّت»: الحلّ الوحيد إكمال التحدّي.
                if (!cantMiss) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => _snooze(context, s),
                    icon: const Icon(Icons.snooze),
                    label: Text(s.t('alarm_snooze')),
                  ),
                  const SizedBox(height: 12),
                ],
                // تم الإنجاز.
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFB71C1C),
                    minimumSize: const Size.fromHeight(58),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    if (!await _confirmDismiss()) return;
                    await _stopSound();
                    await NotificationService.instance.acknowledgeAlarm(_base);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check_circle),
                  label: Text(s.t('alarm_done')),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  /// كلمات بسيطة لتحدّي «اكتب الكلمة» — بلغة التطبيق المختارة (تُنسَخ كما هي).
  static const Map<String, List<String>> _dismissWords = {
    'ar': ['صحيت', 'قمت', 'واعي', 'ابشر', 'خلاص', 'فهمت', 'هالحين'],
    'en': ['alert', 'awake', 'ready', 'done', 'morning', 'wake'],
    'es': ['alerta', 'listo', 'hecho', 'aviso', 'hora', 'dia'],
    'de': ['wecker', 'wach', 'bereit', 'fertig', 'morgen', 'alarm'],
    'fr': ['alerte', 'reveil', 'pret', 'fait', 'matin', 'jour'],
    'id': ['alarm', 'bangun', 'siap', 'selesai', 'pagi', 'ingat'],
    'it': ['sveglia', 'sveglio', 'pronto', 'fatto', 'mattino', 'allarme'],
    'ms': ['jaga', 'siap', 'selesai', 'pagi', 'ingat', 'amaran'],
    'fil': ['gising', 'handa', 'tapos', 'umaga', 'alala', 'alerto'],
    'hi': ['सतर्क', 'जागो', 'तैयार', 'हुआ', 'सुबह', 'याद'],
    'bn': ['সতর্ক', 'জাগো', 'প্রস্তুত', 'সকাল', 'মনে', 'প্রস্তুতি'],
    'fa': ['هشدار', 'بیدار', 'آماده', 'انجام', 'صبح', 'یادآور'],
    'ru': ['будильник', 'проснись', 'готов', 'сделано', 'утро', 'сигнал'],
    'tr': ['alarm', 'uyan', 'hazır', 'tamam', 'sabah', 'anımsat'],
  };

  /// «لا يُفوَّت»: حسب الإعداد إمّا حلّ مسألة أرقام أو كتابة كلمة قبل الإيقاف.
  Future<bool> _confirmDismiss() async {
    final s = S.of(context);
    final settings = context.read<SettingsProvider>();
    final mode = settings.dismissChallenge; // 0 معطّل · 1 أرقام · 2 كلمة
    if (mode == 0) return true;
    final rnd = Random();
    final ctrl = TextEditingController();

    // نُجهّز السؤال والمطابقة حسب النوع، والكلمة بلغة التطبيق.
    final bool isWord = mode == 2;
    final int a = rnd.nextInt(8) + 2;
    final int b = rnd.nextInt(8) + 2;
    final words = _dismissWords[s.locale.languageCode] ?? _dismissWords['en']!;
    final String word = words[rnd.nextInt(words.length)];

    bool matches() {
      final t = ctrl.text.trim();
      return isWord ? t == word : int.tryParse(t) == a + b;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isWord ? s.t('dismiss_word') : s.t('dismiss_calc')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isWord ? word : '$a + $b = ؟',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType:
                    isWord ? TextInputType.text : TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.t('cancel'))),
            FilledButton(
              onPressed: matches() ? () => Navigator.pop(ctx, true) : null,
              child: Text(s.t('confirm')),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _snooze(BuildContext context, S s) async {
    final mins = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in const [5, 10, 15, 30, 60])
              ListTile(
                leading: const Icon(Icons.snooze),
                title: Text('$m ${s.t('minutes')}'),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (mins == null) return;
    await NotificationService.instance.snoozeAlarm(
      _base,
      widget.info['title'] ?? '⏰',
      widget.info['body'] ?? '',
      mins,
      _noteId,
    );
    if (context.mounted) Navigator.pop(context);
  }
}
