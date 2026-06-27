import 'package:flutter_test/flutter_test.dart';
import 'package:mudhakkarati/services/update_service.dart';

/// يضمن أن فحص التحديث يقارن بـ**اسم النسخة** لا برقم البناء — فقد كان رقم البناء
/// المثبَّت (مع split-per-abi) أكبر من المنشور فيقول دائمًا «أنت على الأحدث».
void main() {
  group('UpdateService.isNewerVersion', () {
    test('نسخة أحدث تُكتشف (الحالة التي فشلت سابقًا)', () {
      expect(UpdateService.isNewerVersion('1.7.4', '1.7.1'), isTrue);
      expect(UpdateService.isNewerVersion('1.8.0', '1.7.9'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('نفس النسخة أو أقدم لا تُكتشف', () {
      expect(UpdateService.isNewerVersion('1.7.1', '1.7.1'), isFalse);
      expect(UpdateService.isNewerVersion('1.7.0', '1.7.1'), isFalse);
      expect(UpdateService.isNewerVersion('1.6.9', '1.7.0'), isFalse);
    });

    test('تتجاهل لاحقة البناء والرموز', () {
      expect(UpdateService.isNewerVersion('1.7.4+73', '1.7.1+70'), isTrue);
      expect(UpdateService.isNewerVersion('1.7.1+99', '1.7.1+70'), isFalse);
    });

    test('اختلاف طول المقاطع', () {
      expect(UpdateService.isNewerVersion('1.7.1.1', '1.7.1'), isTrue);
      expect(UpdateService.isNewerVersion('1.7', '1.7.1'), isFalse);
    });
  });
}
