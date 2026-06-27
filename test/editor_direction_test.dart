import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mudhakkarati/features/editor/rich_text_field.dart';
import 'package:mudhakkarati/features/settings/settings_provider.dart';
import 'package:provider/provider.dart';

/// اختبارات سلوك المحرّر: **كل سطر باتجاه لغته** مع **وراثة** الاتجاه للأسطر
/// الفارغة (والافتراضي يمين). تغطّي ما أبلغ عنه المستخدم وتمنع رجوعه:
///
///  - العربي يمينًا (الشرطة يمين السطر)، والإنجليزي يسارًا (الشرطة يسار السطر).
///  - الملاحظة الجديدة تبدأ يمينًا؛ والسطر الجديد يرث لغة ما قبله ⇒ لا قفز.
///  - الحفظ لا يُخزّن سمة اتجاه (تُحسب عند العرض)، والغامق يبقى محفوظًا.
///  - المحرّر والعارض بمحيط LTR كي يُحاذى كل سطر باتجاهه الصحيح.

/// علامات الاتجاه لكل سطر: true = معلّم rtl (يمين)، false = بلا سمة (يسار).
/// السطر = ما ينتهي بـ`\n`.
List<bool> _lineRtlFlags(QuillController q) {
  final text = q.document.toPlainText();
  final flags = <bool>[];
  for (var i = 0; i < text.length; i++) {
    if (text[i] != '\n') continue;
    var rtl = false;
    try {
      rtl = q.document.collectStyle(i, 1).attributes['direction']?.value ==
          'rtl';
    } catch (_) {}
    flags.add(rtl);
  }
  return flags;
}

/// يحاكي كتابة [text] في محرّر فارغ ثم يطبّق ضبط الاتجاه (كما يجري بعد الإطار).
QuillController _typed(String text) {
  final c = RichTextController('', (_) {});
  c.quill.replaceText(
      0, 0, text, TextSelection.collapsed(offset: text.length));
  applyLineDirections(c.quill);
  return c.quill;
}

Widget _wrap(Widget child) {
  return ChangeNotifierProvider<SettingsProvider>(
    create: (_) => SettingsProvider(),
    child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  );
}

TextDirection _ambientDirOf(WidgetTester tester) {
  final dir = tester.widget<Directionality>(
    find
        .ancestor(
          of: find.byType(QuillEditor),
          matching: find.byType(Directionality),
        )
        .first,
  );
  return dir.textDirection;
}

void main() {
  group('اتجاه كل سطر حسب لغته (مع وراثة)', () {
    test('١) ملاحظة جديدة: المؤشّر عند البداية والسطر يمين (الافتراضي)', () {
      final c = RichTextController('', (_) {});
      expect(c.quill.selection.baseOffset, 0);
      expect(_lineRtlFlags(c.quill), [true],
          reason: 'الملاحظة الجديدة تبدأ يمينًا');
      c.dispose();
    });

    test('٢) سطر عربي ⇒ يمين، سطر إنجليزي ⇒ يسار', () {
      expect(_lineRtlFlags(_typed('تابل')), [true]);
      expect(_lineRtlFlags(_typed('gfghj')), [false]);
    });

    test('٣) قائمة بشرطة: "- تابل" يمين، و"- gfghj" يسار (إصلاح الصورة)', () {
      // النقطة الجوهرية: الشرطة أوّل السطر لا تقلب الاتجاه — يُحدَّد باللغة الغالبة.
      expect(_lineRtlFlags(_typed('- تابل')), [true],
          reason: 'سطر عربي بشرطة ⇒ يمين (الشرطة يمين)');
      expect(_lineRtlFlags(_typed('- gfghj')), [false],
          reason: 'سطر إنجليزي بشرطة ⇒ يسار (الشرطة يسار)');
    });

    test('٤) قائمة متعددة الأسطر مختلطة', () {
      // كما في الصورة: أسطر عربية ثم أسطر إنجليزية.
      final q = _typed('تلبتتةا\n- تابل\n- تاللا\nDfhhj\n- gfghj\n- fhjjjjjh');
      expect(_lineRtlFlags(q), [true, true, true, false, false, false]);
    });

    test('٥) وراثة: سطر جديد فارغ يرث لغة ما قبله (لا قفز)', () {
      // بعد سطر عربي ⇒ السطر الفارغ التالي يمين.
      expect(_lineRtlFlags(_typed('تابل\n')), [true, true],
          reason: 'سطر فارغ بعد عربي ⇒ يمين (وراثة)');
      // بعد سطر إنجليزي ⇒ السطر الفارغ التالي يسار.
      expect(_lineRtlFlags(_typed('gfghj\n')), [false, false],
          reason: 'سطر فارغ بعد إنجليزي ⇒ يسار (وراثة)');
    });

    test('٦) سطر يبدأ برموز/أرقام فقط يرث (الأول ⇒ يمين الافتراضي)', () {
      expect(_lineRtlFlags(_typed('12345')), [true]);
      expect(_lineRtlFlags(_typed('- ')), [true]);
      expect(_lineRtlFlags(_typed('!!!')), [true]);
    });

    test('٧) مختلط داخل السطر ⇒ يُحدَّد باللغة الغالبة (لا أوّل حرف)', () {
      // غالبه إنجليزيّ (11 حرفًا مقابل 4) ⇒ يسار — ولو بدأ بالعربية.
      expect(_lineRtlFlags(_typed('عربي then english')), [false]);
      // غالبه إنجليزيّ (7 مقابل 6) ⇒ يسار.
      expect(_lineRtlFlags(_typed('english ثم عربي')), [false]);
      // غالبه عربيّ (وصف عربيّ + اسم دواء إنجليزيّ) ⇒ يمين، ويثبت بعد الفتح.
      expect(_lineRtlFlags(_typed('حبة واحدة باليوم Augmentin')), [true]);
    });

    test('٨) كتابة العربية على سطر موروث يمين لا تُغيّر شيئًا (لا قفز)', () {
      // سطر ثانٍ ورث «يمين»؛ ثم نكتب فيه عربيًّا — يبقى يمينًا (لا تبديل).
      final c = RichTextController('', (_) {});
      c.quill.replaceText(0, 0, 'تابل\n',
          const TextSelection.collapsed(offset: 5));
      applyLineDirections(c.quill);
      final before = _lineRtlFlags(c.quill); // [true, true]
      c.quill.replaceText(5, 0, 'مرحبا',
          const TextSelection.collapsed(offset: 10));
      applyLineDirections(c.quill);
      expect(_lineRtlFlags(c.quill), before,
          reason: 'الكتابة بنفس اللغة لا تغيّر الاتجاه ⇒ لا قفز');
      c.dispose();
    });
  });

  group('الحفظ والاستقرار', () {
    test('٩) الحفظ لا يُخزّن سمة اتجاه، ويُنظّف القديمة', () async {
      final legacy = jsonEncode([
        {'insert': 'سطر قديم'},
        {
          'insert': '\n',
          'attributes': {'direction': 'rtl', 'align': 'right'}
        },
      ]);
      String? saved;
      final c = RichTextController(legacy, (json) => saved = json);
      c.quill.replaceText(0, 0, 'ا', const TextSelection.collapsed(offset: 1));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(saved, isNotNull);
      expect(saved, isNot(contains('"direction"')),
          reason: 'الاتجاه يُحسب عند العرض ولا يُخزَّن');
      expect(saved, contains('align'), reason: 'بقية السمات تبقى');
      c.dispose();
    });

    test('١٠) الحفظ يُنتج JSON صالحًا يُعاد تحميله بنفس النص', () async {
      String? saved;
      final c = RichTextController('', (json) => saved = json);
      const text = 'نص\nسطر ثانٍ';
      c.quill.replaceText(
          0, 0, text, TextSelection.collapsed(offset: text.length));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(saved, isNotNull);
      final reloaded = Document.fromJson(jsonDecode(saved!) as List);
      expect(reloaded.toPlainText().trim(), 'نص\nسطر ثانٍ');
      c.dispose();
    });

    test('١١) الغامق يبقى محفوظًا عبر الحفظ (يُزال الاتجاه فقط)', () async {
      String? saved;
      final c = RichTextController('', (json) => saved = json);
      const text = 'غامق عادي';
      c.quill.replaceText(
          0, 0, text, TextSelection.collapsed(offset: text.length));
      c.quill.formatText(0, 4, Attribute.bold);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(saved, isNotNull);
      expect(saved, contains('bold'));
      expect(saved, isNot(contains('"direction"')));
      c.dispose();
    });

    test('١٢) اللمس/تحريك المؤشّر دون تغيّر نصّ لا يستدعي الحفظ', () async {
      var calls = 0;
      final c = RichTextController('نص', (_) => calls++);
      c.quill.updateSelection(
        const TextSelection.collapsed(offset: 1),
        ChangeSource.local,
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(calls, 0);
      c.dispose();
    });
  });

  group('اتجاه المحيط LTR (كي يُحاذى كل سطر باتجاهه)', () {
    testWidgets('١٣) محرّر التحرير بمحيط LTR', (tester) async {
      final c = RichTextController('', (_) {});
      await tester.pumpWidget(_wrap(RichTextEditorBody(controller: c)));
      await tester.pump();
      expect(_ambientDirOf(tester), TextDirection.ltr);
      c.dispose();
    });

    testWidgets('١٤) العارض (القراءة) بمحيط LTR', (tester) async {
      await tester.pumpWidget(_wrap(const RichTextViewer(content: 'مرحبا')));
      await tester.pump();
      expect(_ambientDirOf(tester), TextDirection.ltr);
    });
  });

  group('فاعلية أدوات التنسيق (إصلاح: الغامق يُحفظ)', () {
    test('١٥) الغامق يُحفظ ولو طُبّق بعد توقّف الكتابة (تنسيق بلا تغيّر نصّ)', () async {
      String? saved;
      final c = RichTextController('', (json) => saved = json);
      const text = 'كلمة أخرى';
      c.quill.replaceText(
          0, 0, text, TextSelection.collapsed(offset: text.length));
      // ننتظر اكتمال الحفظ الأول (بلا غامق) — تمامًا كحالة المستخدم الواقعية.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(saved, isNot(contains('bold')),
          reason: 'قبل تطبيق الغامق لا يوجد غامق محفوظ');
      // الآن نطبّق الغامق دون أيّ تغيير في النصّ:
      c.quill.formatText(0, 4, Attribute.bold);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(saved, contains('bold'),
          reason: 'تغيّر التنسيق وحده يجب أن يُجدوِل الحفظ');
      c.dispose();
    });

    test('١٦) تحريك المؤشّر وحده (بلا تغيّر تنسيق) لا يستدعي الحفظ', () async {
      var calls = 0;
      final c = RichTextController('نص للاختبار', (_) => calls++);
      c.quill.updateSelection(
        const TextSelection.collapsed(offset: 3),
        ChangeSource.local,
      );
      c.quill.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 2),
        ChangeSource.local,
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(calls, 0, reason: 'البصمة لم تتغيّر ⇒ لا حفظ عند مجرّد التحديد');
      c.dispose();
    });
  });

  group('توسيع الكلمة عند المؤشّر (تنسيق بلا تحديد)', () {
    // مرحبا(0..5) مسافة(5) بالعالم(6..13)
    const t = 'مرحبا بالعالم';
    test('١٧) المؤشّر داخل كلمة ⇒ نطاق الكلمة كاملة', () {
      expect(wordRangeAt(t, 2), [0, 5]);
      expect(wordRangeAt(t, 9), [6, 13]);
    });
    test('١٨) المؤشّر ملاصق لنهاية كلمة (بعد الكتابة) ⇒ الكلمة قبله', () {
      expect(wordRangeAt(t, 5), [0, 5]);
      expect(wordRangeAt(t, 13), [6, 13]);
    });
    test('١٩) المؤشّر على مسافة/فراغ بلا كلمة ملاصقة ⇒ null', () {
      expect(wordRangeAt('ا  ب', 2), isNull);
      expect(wordRangeAt('', 0), isNull);
    });
  });
}
