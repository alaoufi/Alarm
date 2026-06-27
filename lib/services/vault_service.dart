import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'encryption_service.dart';

/// يدير مفتاح التشفير الرئيسي لحقول كلمات المرور.
///
/// المفتاح (32 بايت عشوائي) يُخزَّن في تخزين الجهاز الآمن (Android Keystore عبر
/// flutter_secure_storage) ولا يغادر الجهاز أبدًا. يُستخدم لتشفير/فك تشفير
/// كلمات المرور المخزّنة داخل قاعدة البيانات المحلية.
class VaultService {
  VaultService._();
  static final VaultService instance = VaultService._();

  static const _kMasterKey = 'vault_master_key';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Uint8List? _key;

  /// يضمن تحميل (أو إنشاء) المفتاح الرئيسي في الذاكرة.
  Future<void> ensureKey() async {
    if (_key != null) return;
    final existing = await _storage.read(key: _kMasterKey);
    if (existing != null) {
      _key = base64Decode(existing);
    } else {
      final fresh = enc.Key.fromSecureRandom(32).bytes;
      await _storage.write(key: _kMasterKey, value: base64Encode(fresh));
      _key = fresh;
    }
  }

  /// يشفّر نصًّا (يجب استدعاء [ensureKey] أولًا).
  String encrypt(String plain) {
    if (_key == null || plain.isEmpty) return '';
    return EncryptionService.instance.encryptWithKey(plain, _key!);
  }

  /// يفكّ تشفير نص (يجب استدعاء [ensureKey] أولًا).
  String decrypt(String packed) {
    if (_key == null) return '';
    return EncryptionService.instance.decryptWithKey(packed, _key!);
  }
}
