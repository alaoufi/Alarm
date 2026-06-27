import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/license_service.dart';

/// بوابة تفعيل التطبيق (مربوط بالجهاز). تظهر قبل المحتوى إن لم يُفعّل أو انتهت
/// مدّته. تُعيد الفحص عند عودة التطبيق للواجهة كي يُطبَّق الانتهاء مباشرة.
class ActivationGate extends StatefulWidget {
  final Widget child;
  const ActivationGate({super.key, required this.child});

  @override
  State<ActivationGate> createState() => _ActivationGateState();
}

class _ActivationGateState extends State<ActivationGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  LicenseState _state = LicenseState.none;
  int _daysLeft = 0;
  bool _permanent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // أعد فحص الصلاحية عند العودة للواجهة (لتطبيق الانتهاء فورًا).
    if (state == AppLifecycleState.resumed && !_checking) _check();
  }

  Future<void> _check() async {
    final info = await LicenseService.instance.info();
    if (mounted) {
      setState(() {
        _state = info.state;
        _daysLeft = info.daysLeft;
        _permanent = info.permanent;
        _checking = false;
      });
    }
  }

  bool get _open =>
      _state == LicenseState.active || _state == LicenseState.disabled;

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_open) return widget.child;
    return _ActivationScreen(
      expired: _state == LicenseState.expired,
      onActivated: _check,
    );
  }
}

class _ActivationScreen extends StatefulWidget {
  final bool expired;
  final VoidCallback onActivated;
  const _ActivationScreen({required this.expired, required this.onActivated});

  @override
  State<_ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<_ActivationScreen> {
  final _codeCtrl = TextEditingController();
  String _deviceId = '...';
  bool _error = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    LicenseService.instance
        .deviceIdPretty()
        .then((v) => mounted ? setState(() => _deviceId = v) : null);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = false;
    });
    final ok = await LicenseService.instance.tryActivate(_codeCtrl.text);
    if (!mounted) return;
    if (ok) {
      widget.onActivated();
    } else {
      setState(() {
        _busy = false;
        _error = true;
      });
    }
  }

  /// استرجاع المالك: إدخال المفتاح الخاصّ (Seed) لفكّ القفل دائمًا — ضمانة ألّا
  /// يُحبَس المالك عن بياناته. متاح فقط لمن يملك المفتاح الخاصّ.
  Future<void> _ownerRecovery() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استرجاع المالك'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'للمالك فقط: ألصق المفتاح الخاصّ (Seed) لفكّ القفل دائمًا على هذا الجهاز.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'المفتاح الخاصّ (64 خانة)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('فكّ القفل')),
        ],
      ),
    );
    if (ok != true) return;
    final done = await LicenseService.instance.recoverWithOwnerSeed(ctrl.text);
    if (!mounted) return;
    if (done) {
      widget.onActivated();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المفتاح الخاصّ غير صحيح')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    widget.expired
                        ? Icons.lock_clock_outlined
                        : Icons.verified_user_outlined,
                    size: 64,
                    color: scheme.primary),
                const SizedBox(height: 16),
                Text(widget.expired ? 'انتهت صلاحية التفعيل' : 'تفعيل التطبيق',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  widget.expired
                      ? 'انتهت مدّة الترخيص لهذا الجهاز. أرسل «رقم الجهاز» أدناه '
                          'للحصول على رمز تفعيل جديد.'
                      : 'هذه النسخة مرخّصة لجهاز واحد. أرسل «رقم الجهاز» أدناه '
                          'للحصول على رمز التفعيل.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text('رقم الجهاز',
                          style: TextStyle(color: scheme.primary, fontSize: 12)),
                      const SizedBox(height: 6),
                      SelectableText(
                        _deviceId,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _deviceId));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ رقم الجهاز')));
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('نسخ رقم الجهاز'),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeCtrl,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: 'رمز التفعيل',
                    hintText: 'ألصق الرمز هنا',
                    errorText: _error ? 'رمز غير صحيح لهذا الجهاز' : null,
                    prefixIcon: const Icon(Icons.vpn_key),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _activate,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.lock_open),
                    label: const Text('تفعيل'),
                  ),
                ),
                const SizedBox(height: 8),
                // استرجاع المالك (مخفيّ بضغطة مطوّلة على الأيقونة).
                GestureDetector(
                  onLongPress: _ownerRecovery,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('© مذكراتي',
                        style: TextStyle(
                            color: scheme.outline, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
