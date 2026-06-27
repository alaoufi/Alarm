import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mudhakkarati/services/encryption_service.dart';

void main() {
  final svc = EncryptionService.instance;
  final data = Uint8List.fromList(
      utf8.encode('ملاحظة سرّية — secret note 12345 \n سطر ثانٍ'));

  group('authenticated backup encryption', () {
    test('roundtrip preserves data and uses authenticated format', () {
      final out = svc.encryptBytes(data, 'p@ss');
      expect(utf8.decode(out.sublist(0, 4)), 'MDK2'); // مصادَق
      final back = svc.decryptBytes(out, 'p@ss');
      expect(back, data);
    });

    test('wrong password is rejected (not silent garbage)', () {
      final out = svc.encryptBytes(data, 'correct');
      expect(() => svc.decryptBytes(out, 'wrong'),
          throwsA(isA<FormatException>()));
    });

    test('tampering with the ciphertext is detected (HMAC)', () {
      final out = svc.encryptBytes(data, 'p@ss');
      final tampered = Uint8List.fromList(out);
      tampered[tampered.length - 1] ^= 0xFF; // قلب آخر بايت
      expect(() => svc.decryptBytes(tampered, 'p@ss'),
          throwsA(isA<FormatException>()));
    });
  });
}
