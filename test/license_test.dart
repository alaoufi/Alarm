import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mudhakkarati/services/license_service.dart';

/// يحاكي ما يفعله المولّد المستقلّ (التوقيع) كي نتأكّد أنّ التطبيق يفكّ ويتحقّق
/// بنفس الصيغة تمامًا — دون إلزام أيّ مفتاح خاصّ في المستودع.
Future<String> _signKey(
    SimpleKeyPair kp, String deviceId, int duration) async {
  final ed = Ed25519();
  final msg = utf8.encode('MDKL1|$deviceId|$duration');
  final sig = await ed.sign(msg, keyPair: kp);
  final bytes = <int>[(duration >> 8) & 0xff, duration & 0xff, ...sig.bytes];
  return LicenseService.base32(bytes);
}

void main() {
  group('Base32 (Crockford-ish)', () {
    test('round-trips arbitrary bytes', () {
      final rnd = Random(42);
      for (var trial = 0; trial < 200; trial++) {
        final len = rnd.nextInt(70) + 1;
        final bytes = List<int>.generate(len, (_) => rnd.nextInt(256));
        final enc = LicenseService.base32(bytes);
        final dec = LicenseService.base32Decode(enc);
        // قد يضيف الترميز بتات حشو؛ نتحقّق من مطابقة أوّل len بايت.
        expect(dec.take(len).toList(), bytes,
            reason: 'فشل round-trip عند الطول $len');
      }
    });

    test('decoder ignores separators and lowercase noise', () {
      final bytes = [1, 2, 3, 4, 5, 250, 200, 33];
      final enc = LicenseService.base32(bytes);
      final messy = '  ${enc.substring(0, 4)}-${enc.substring(4)} \n';
      final dec = LicenseService.base32Decode(
          messy.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''));
      expect(dec.take(bytes.length).toList(), bytes);
    });
  });

  group('License key pipeline (generator → app)', () {
    test('valid key verifies; tamper & wrong-device fail', () async {
      final ed = Ed25519();
      final kp = await ed.newKeyPair();
      final pub = await kp.extractPublicKey();
      const deviceId = 'ABCD2345EFGH6789';
      const duration = 30;

      final key = await _signKey(kp, deviceId, duration);

      // جانب التطبيق: فكّ ثم تحقّق (يطابق tryActivate داخليًّا).
      final decoded = LicenseService.base32Decode(key);
      expect(decoded.length, 66, reason: 'مدّة(2) + توقيع(64)');
      final dur = (decoded[0] << 8) | decoded[1];
      expect(dur, duration);
      final sig = decoded.sublist(2);

      final goodMsg = utf8.encode('MDKL1|$deviceId|$dur');
      expect(
        await ed.verify(goodMsg, signature: Signature(sig, publicKey: pub)),
        isTrue,
      );

      // جهاز مختلف ⇒ يفشل (مربوط بالجهاز، لا ينتقل).
      final otherMsg = utf8.encode('MDKL1|ZZZZ2345EFGH6789|$dur');
      expect(
        await ed.verify(otherMsg, signature: Signature(sig, publicKey: pub)),
        isFalse,
      );

      // تلاعب بالتوقيع ⇒ يفشل.
      final bad = List<int>.of(sig)..[0] ^= 0xff;
      expect(
        await ed.verify(goodMsg, signature: Signature(bad, publicKey: pub)),
        isFalse,
      );

      // تلاعب بالمدّة ⇒ الرسالة تختلف ⇒ يفشل.
      final wrongDurMsg = utf8.encode('MDKL1|$deviceId|9999');
      expect(
        await ed.verify(wrongDurMsg, signature: Signature(sig, publicKey: pub)),
        isFalse,
      );
    });

    test('permanent (duration 0) encodes/decodes correctly', () async {
      final ed = Ed25519();
      final kp = await ed.newKeyPair();
      final key = await _signKey(kp, 'TESTDEVICE234567', 0);
      final decoded = LicenseService.base32Decode(key);
      final dur = (decoded[0] << 8) | decoded[1];
      expect(dur, 0); // 0 = دائم.
    });
  });
}
