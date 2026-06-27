import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';

/// لوحة إدخال رقم سري (4 خانات) مع لوحة أرقام وزر بصمة اختياري.
class PinEntry extends StatefulWidget {
  final String title;
  final bool showBiometric;

  /// يُعيد true إذا كان الرقم صحيحًا.
  final Future<bool> Function(String pin) onSubmit;
  final Future<bool> Function()? onBiometric;

  const PinEntry({
    super.key,
    required this.title,
    required this.onSubmit,
    this.showBiometric = false,
    this.onBiometric,
  });

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry> {
  String _pin = '';
  bool _error = false;

  Future<void> _add(String digit) async {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _error = false;
    });
    if (_pin.length == 4) {
      final ok = await widget.onSubmit(_pin);
      if (!ok && mounted) {
        setState(() {
          _error = true;
          _pin = '';
        });
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_rounded, size: 56, color: scheme.primary),
          const SizedBox(height: 16),
          Text(widget.title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          // نقاط التقدّم تُثبَّت على LTR كي تمتلئ من اليسار (أوّل رقم = النقطة
          // اليسرى) متّسقةً مع لوحة الأرقام، لا أن تنعكس بسبب اتجاه الواجهة RTL.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? scheme.primary : Colors.transparent,
                    border: Border.all(
                      color: _error ? scheme.error : scheme.primary,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
          ),
          if (_error)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(s.t('wrong_pin'),
                  style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 28),
          _NumPad(
            onDigit: _add,
            onBackspace: _backspace,
            onBiometric:
                widget.showBiometric ? widget.onBiometric : null,
          ),
        ],
      ),
    );
  }
}

class _NumPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Future<bool> Function()? onBiometric;

  const _NumPad({
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, Widget? child}) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          width: 62,
          height: 62,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap ?? () => onDigit(label),
              child: Center(
                child: child ??
                    Text(label,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      );
    }

    // لوحة الأرقام تُثبَّت على LTR كي تظهر 1‑2‑3 من اليسار كأي هاتف/آلة حاسبة،
    // ولا تنعكس إلى 3‑2‑1 بسبب اتجاه الواجهة العربيّ (RTL).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            key('1'),
            key('2'),
            key('3'),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            key('4'),
            key('5'),
            key('6'),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            key('7'),
            key('8'),
            key('9'),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            onBiometric != null
                ? key('', onTap: () => onBiometric!.call(), child: const Icon(Icons.fingerprint, size: 30))
                : const SizedBox(width: 74),
            key('0'),
            key('', onTap: onBackspace, child: const Icon(Icons.backspace_outlined)),
          ]),
        ],
      ),
    );
  }
}
