import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/text/line_direction.dart';
import '../../services/system_dictation.dart';

/// يفتح **خدمة الإملاء الأصلية في النظام** (نافذة `RecognizerIntent`) ويعيد
/// النصّ المتعرَّف عليه لإدراجه في الملاحظة، أو null عند الإلغاء/التعذّر.
///
/// الخطوات: فحص توفّر الخدمة → فتح نافذة النظام باللغة المناسبة → قراءة أول
/// نتيجة غير فارغة → عرضها في مربّع قابل للتحرير مع زرّ «إدراج».
Future<String?> showVoiceDictation(BuildContext context) async {
  final s = S.of(context);

  // (6,7) فحص توفّر الخدمة قبل التشغيل؛ إن لم توجد لا نحاول ونعرض رسالة واضحة.
  final available = await SystemDictation.isAvailable();
  if (!context.mounted) return null;
  if (!available) {
    await _info(context, s.t('stt_system_missing'));
    return null;
  }

  // (4) اللغة: ar-SA افتراضيًّا، وإلا وسم لغة التطبيق.
  final locale = _localeTag(s.locale.languageCode);

  // (3) فتح نافذة الإملاء الأصلية.
  String? raw;
  try {
    raw = await SystemDictation.recognize(locale);
  } on PlatformException catch (e) {
    if (!context.mounted) return null;
    if (e.code == 'busy') return null;
    await _info(
        context,
        e.code == 'unavailable'
            ? s.t('stt_system_missing')
            : '${s.t('error')}: ${e.message ?? e.code}');
    return null;
  } catch (e) {
    if (context.mounted) await _info(context, '${s.t('error')}: $e');
    return null;
  }

  if (!context.mounted) return null;
  if (raw == null) return null; // (8) أُلغيت العملية
  if (raw.trim().isEmpty) {
    await _info(context, s.t('stt_no_speech')); // (8) لم يُلتقط كلام
    return null;
  }

  // (5,9) مربّع التفريغ: عرض النصّ قابلًا للتحرير + زرّ «إدراج».
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ConfirmSheet(initial: raw!, locale: locale),
  );
}

/// وسم اللغة (BCP-47) لخدمة النظام؛ ar-SA افتراضيًّا للعربية.
String _localeTag(String lang) {
  const map = {
    'ar': 'ar-SA',
    'en': 'en-US',
    'fr': 'fr-FR',
    'es': 'es-ES',
    'de': 'de-DE',
    'it': 'it-IT',
    'ru': 'ru-RU',
    'id': 'id-ID',
    'ms': 'ms-MY',
    'hi': 'hi-IN',
    'bn': 'bn-BD',
    'fa': 'fa-IR',
    'fil': 'fil-PH',
  };
  return map[lang] ?? lang;
}

Future<void> _info(BuildContext context, String msg) {
  final s = S.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.mic_none),
      title: Text(s.t('voice_typing')),
      content: Text(msg),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(s.t('ok')),
        ),
      ],
    ),
  );
}

/// مربّع تأكيد النصّ المتعرَّف عليه: قابل للتحرير، مع إعادة التسجيل والإدراج.
class _ConfirmSheet extends StatefulWidget {
  final String initial;
  final String locale;
  const _ConfirmSheet({required this.initial, required this.locale});

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  /// يفتح نافذة الإملاء ويُضيف الكلام الجديد للنصّ الموجود.
  /// [newLine] = true ⇒ يُضاف في **سطر جديد**؛ وإلا يُكمل على نفس السطر بمسافة.
  Future<void> _again({bool newLine = false}) async {
    try {
      final t = await SystemDictation.recognize(widget.locale);
      if (t != null && t.trim().isNotEmpty && mounted) {
        // متابعة الكلام: نُضيف للنصّ الموجود بدل استبداله.
        final cur = _c.text.trimRight();
        final piece = t.trim();
        final merged = cur.isEmpty
            ? piece
            : (newLine ? '$cur\n$piece' : '$cur $piece');
        setState(() {
          _c.text = merged;
          _c.selection = TextSelection.collapsed(offset: merged.length);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.keyboard_voice, color: scheme.primary),
                const SizedBox(width: 8),
                Text(s.t('voice_typing'),
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 14),
            // مربّع التفريغ (قابل للتحرير، باتجاه السطر الصحيح).
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _c,
              builder: (_, v, __) => TextField(
                controller: _c,
                maxLines: null,
                minLines: 2,
                textDirection: lineDirection(v.text),
                style: const TextStyle(fontSize: 16, height: 1.4),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withOpacity(0.4),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // صفّ الإملاء: متابعة على نفس السطر / متابعة في سطر جديد.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _again,
                    icon: const Icon(Icons.mic, size: 18),
                    label: Text(s.t('stt_continue')),
                  ),
                ),
                const SizedBox(width: 10),
                // سطر جديد: يُكمل الإملاء لكن في سطر جديد.
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _again(newLine: true),
                    icon: const Icon(Icons.subdirectory_arrow_left, size: 18),
                    label: const Text('سطر جديد'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // صفّ الإجراءات: إلغاء / إدراج.
            Row(
              children: [
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(s.t('cancel')),
                ),
                const SizedBox(width: 10),
                // (9) زرّ الإدراج مفعّل فقط إذا النصّ غير فارغ.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _c,
                  builder: (_, v, __) => FilledButton.icon(
                    onPressed: v.text.trim().isEmpty
                        ? null
                        : () => Navigator.pop(context, _c.text.trim()),
                    icon: const Icon(Icons.check),
                    label: Text(s.t('stt_insert')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
