// أداة ترخيص Alaoufi Notes (تعمل على جهازك أنت فقط).
//
// الاستخدام:
//   1) توليد زوج مفاتيح (مرة واحدة):
//        dart run tool/license.dart keygen
//      انسخ "PUBLIC KEY" إلى _publicKeyB64 في lib/services/license_service.dart،
//      واحتفظ بـ "PRIVATE KEY" سرًّا (لا تضعه في التطبيق إطلاقًا).
//
//   2) توليد رمز تفعيل لجهاز مستخدم (أرسل له الناتج):
//        dart run tool/license.dart sign <PRIVATE_KEY_B64> <DEVICE_ID>
//
// المفتاح الخاص عندك وحدك → لا أحد يستطيع تزوير رموز، والرمز يعمل على جهاز واحد.

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    return;
  }
  switch (args[0]) {
    case 'keygen':
      await _keygen();
      break;
    case 'sign':
      if (args.length < 3) {
        stderr.writeln('الاستخدام: sign <PRIVATE_KEY_B64> <DEVICE_ID>');
        exitCode = 2;
        return;
      }
      await _sign(args[1], args[2]);
      break;
    default:
      _usage();
  }
}

void _usage() {
  print('''
أداة ترخيص Alaoufi Notes:
  dart run tool/license.dart keygen
  dart run tool/license.dart sign <PRIVATE_KEY_B64> <DEVICE_ID>
''');
}

Future<void> _keygen() async {
  final algo = Ed25519();
  final kp = await algo.newKeyPair();
  final priv = await kp.extractPrivateKeyBytes();
  final pub = (await kp.extractPublicKey()).bytes;
  print('=== احتفظ بهذا سرًّا (للتوقيع فقط) ===');
  print('PRIVATE KEY: ${base64Encode(priv)}');
  print('');
  print('=== ضع هذا في lib/services/license_service.dart (_publicKeyB64) ===');
  print('PUBLIC KEY: ${base64Encode(pub)}');
}

Future<void> _sign(String privB64, String deviceIdRaw) async {
  final deviceId =
      deviceIdRaw.trim().replaceAll(RegExp(r'\s|-'), '').toUpperCase();
  final algo = Ed25519();
  final seed = base64Decode(privB64.trim());
  final kp = await algo.newKeyPairFromSeed(seed);
  final sig = await algo.sign(utf8.encode(deviceId), keyPair: kp);
  final code = base64Encode(sig.bytes).replaceAll('=', '');
  print('الجهاز: $deviceId');
  print('رمز التفعيل:');
  print(code);
}
