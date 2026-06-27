import 'package:flutter/widgets.dart';

/// اتجاه السطر حسب **أول حرف قويّ** فيه، أو `null` إن لم يوجد حرف قويّ
/// (سطر فارغ/رموز/أرقام فقط). يتجاهل الأرقام والرموز والمسافات في البداية.
///
/// نستخدمه لضبط اتجاه السطر **فقط** عند وجود حرف لغوي فعلي — فلا نضع اتجاهًا
/// على السطور الفارغة (كان ذلك يسبّب تبادل يمين/يسار عند إنشاء أسطر جديدة).
TextDirection? strongLineDirection(String text) {
  for (final r in text.runes) {
    // العربية/العبرية وأشكال العربية التقديمية.
    if ((r >= 0x0590 && r <= 0x08FF) ||
        (r >= 0xFB1D && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF)) {
      return TextDirection.rtl;
    }
    // اللاتينية الأساسية والممتدة.
    if ((r >= 0x41 && r <= 0x5A) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x24F)) {
      return TextDirection.ltr;
    }
    // غير ذلك (أرقام/رموز/مسافات) ⇒ تجاهل وتابع للحرف التالي.
  }
  return null;
}

/// اتجاه السطر حسب **اللغة الغالبة** فيه (عدد الحروف العربية مقابل اللاتينية)،
/// أو `null` إن لم يوجد حرف قويّ (فارغ/رموز/أرقام فقط).
///
/// نفضّله على «أول حرف» للأسطر المختلطة (عربي + إنجليزي): فالسطر يأخذ اتجاه لغته
/// **الأكثر** بدل أن يتقلّب يمينًا/يسارًا حسب أول رمز أو كلمة ⇒ استقرار أعلى
/// وسلوك متوقَّع (سطر وصفه عربيّ يبقى يمينًا ولو فيه اسم دواء إنجليزيّ، والعكس).
TextDirection? dominantLineDirection(String text) {
  var ar = 0, lat = 0;
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) ||
        (r >= 0xFB1D && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF)) {
      ar++;
    } else if ((r >= 0x41 && r <= 0x5A) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x24F)) {
      lat++;
    }
  }
  if (ar == 0 && lat == 0) return null;
  return ar >= lat ? TextDirection.rtl : TextDirection.ltr;
}

/// تحديد اتجاه السطر حسب **اللغة الغالبة** فيه (عربي/لاتيني)، مع تجاهل الأرقام
/// والرموز والمسافات. إن لم يوجد حرف قويّ (فارغ/رموز/أرقام فقط) ⇒ [fallback]
/// (افتراضيًّا RTL).
///
/// يُستخدم لتحديد اتجاه الكتابة والعرض لكل سطر بشكل مستقلّ دون تغيير النص المخزَّن.
TextDirection lineDirection(String text,
        {TextDirection fallback = TextDirection.rtl}) =>
    dominantLineDirection(text) ?? fallback;

/// اتجاه النصّ **الغالب** حسب أكثر الحروف (عربي مقابل لاتيني). يُستخدم لاتجاه
/// الملاحظة ككلّ في المحرّر/العارض — فيستقرّ على سياق اللغة بلا تشويش يمين/يسار.
/// النصّ بلا حروف قويّة (فارغ/رموز) ⇒ [fallback] (افتراضيًّا RTL — لغة عربية).
TextDirection dominantDirection(String text,
    {TextDirection fallback = TextDirection.rtl}) {
  var ar = 0, lat = 0;
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) ||
        (r >= 0xFB1D && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF)) {
      ar++;
    } else if ((r >= 0x41 && r <= 0x5A) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x24F)) {
      lat++;
    }
  }
  if (ar == 0 && lat == 0) return fallback;
  return ar >= lat ? TextDirection.rtl : TextDirection.ltr;
}

/// عنصر نصّ يعرض كل سطر باتجاهه المستقلّ (للعرض للقراءة فقط: البطاقات/المعاينات).
/// يحافظ على ترتيب الرموز/الشرطة/الترقيم في بداية كل سطر دون عكسها.
class AutoDirText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  const AutoDirText(this.text, {super.key, this.style, this.maxLines, this.overflow});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    // سطر واحد: عنصر نصّ واحد باتجاهه (أبسط وأخفّ).
    if (lines.length <= 1) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textDirection: lineDirection(text),
      );
    }
    // أسطر متعددة: كل سطر باتجاهه المستقلّ.
    final shown = (maxLines != null && maxLines! < lines.length)
        ? lines.sublist(0, maxLines!)
        : lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in shown)
          Text(
            line,
            style: style,
            maxLines: 1,
            overflow: overflow ?? TextOverflow.ellipsis,
            textDirection: lineDirection(line),
          ),
      ],
    );
  }
}
