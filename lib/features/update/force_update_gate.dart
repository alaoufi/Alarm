import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/update_service.dart';

/// بوّابة «التحديث الإلزاميّ»: عند وجود إنترنت وتوفّر إصدار أحدث، تُوقف التطبيق
/// وتطلب التحديث للمتابعة — **مع الاحتفاظ بكل البيانات**. إن تعذّر الفحص (لا
/// إنترنت) لا تحجب التطبيق فيعمل عاديًّا.
class ForceUpdateGate extends StatefulWidget {
  final Widget child;
  const ForceUpdateGate({super.key, required this.child});

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate>
    with WidgetsBindingObserver {
  UpdateInfo? _required; // إصدار أحدث متوفّر ⇒ يُحجب التطبيق حتى التحديث.
  double? _progress; // تقدّم التنزيل (null = لم يبدأ).
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // أعِد الفحص عند العودة للواجهة (قد يكون اتصل بالنت أو صدر تحديث).
    if (state == AppLifecycleState.resumed && _required == null) _check();
  }

  Future<void> _check() async {
    try {
      final info = await UpdateService.instance.check();
      if (mounted && info != null) setState(() => _required = info);
    } catch (_) {
      // تعذّر الفحص (غالبًا دون إنترنت) ⇒ لا نحجب التطبيق.
    }
  }

  Future<void> _update() async {
    final info = _required;
    if (info == null || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
      _progress = 0;
    });
    final err = await UpdateService.instance.downloadAndInstall(
      info.url,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = err != null;
    });
  }

  Future<void> _browser() async {
    try {
      await launchUrl(Uri.parse(UpdateService.downloadUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_required == null) return widget.child;
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final pct = _progress == null ? null : (_progress! * 100).clamp(0, 100).toInt();

    return PopScope(
      canPop: false, // إلزاميّ — لا خروج دون تحديث.
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [
                        scheme.primary,
                        Color.alphaBlend(
                            Colors.black.withOpacity(0.2), scheme.primary),
                      ]),
                      boxShadow: [
                        BoxShadow(
                            color: scheme.primary.withOpacity(0.4),
                            blurRadius: 22,
                            offset: const Offset(0, 10)),
                      ],
                    ),
                    child: const Icon(Icons.system_update,
                        color: Colors.white, size: 46),
                  ),
                  const SizedBox(height: 22),
                  Text(s.t('fu_title'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text(s.t('fu_body'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: scheme.onSurface.withOpacity(0.75))),
                  const SizedBox(height: 10),
                  Text('${s.t('fu_new_version')}: ${_required!.version}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: scheme.primary)),
                  const SizedBox(height: 26),
                  if (_busy && _progress != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                          value: _progress, minHeight: 10),
                    ),
                    const SizedBox(height: 8),
                    Text('${s.t('fu_downloading')} ${pct ?? 0}%',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurface.withOpacity(0.6))),
                  ] else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          textStyle: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      onPressed: _update,
                      icon: const Icon(Icons.download),
                      label: Text(s.t('fu_now')),
                    ),
                  if (_failed) ...[
                    const SizedBox(height: 10),
                    Text(s.t('fu_failed'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _browser,
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: Text(s.t('fu_browser')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
