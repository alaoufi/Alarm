import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mudhakkarati/core/text/line_direction.dart';

/// اختبارات القبول لاتجاه السطر: كل سطر يُحدَّد اتجاهه بأوّل حرف لغوي حقيقي،
/// مع تجاهل رموز/أرقام/مسافات بداية السطر (- * • 1. 2. ( ) …). نجاحها يضمن أنّ
/// محرّك Unicode Bidi سيضع رمزَ البداية في موضعه الصحيح بصريًّا عند العرض.
void main() {
  group('lineDirection — حالات القبول', () {
    const rtlCases = [
      '- اختبار',
      '* اختبار',
      '• اختبار',
      '1. اختبار',
      '2. فحص',
      '(اختبار)',
      '123 اختبار',
      'هذا نص عربي',
    ];
    const ltrCases = [
      '- Test',
      '* Test',
      '• Test',
      '1. Test',
      '2. Check',
      '(Test)',
      '123 Test',
      'This is English',
    ];

    for (final c in rtlCases) {
      test('RTL: "$c"', () {
        expect(lineDirection(c), TextDirection.rtl);
      });
    }
    for (final c in ltrCases) {
      test('LTR: "$c"', () {
        expect(lineDirection(c), TextDirection.ltr);
      });
    }

    test('سطر فارغ/رموز فقط ⇒ الافتراضي RTL', () {
      expect(lineDirection(''), TextDirection.rtl);
      expect(lineDirection('- '), TextDirection.rtl);
      expect(lineDirection('123'), TextDirection.rtl);
    });
  });
}
