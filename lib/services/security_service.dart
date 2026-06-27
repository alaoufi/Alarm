import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'encryption_service.dart';

/// قفل التطبيق برقم سري + دعم البصمة. كل شيء محلي.
class SecurityService {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  static const _kPinHash = 'pin_hash';
  static const _kPinSalt = 'pin_salt';
  static const _kLockEnabled = 'lock_enabled';
  static const _kBiometric = 'biometric_enabled';
  static const _kLockedCats = 'locked_categories'; // معرّفات مفصولة بفواصل
  static const _kInfoLocked = 'info_page_locked';
  static const _kInfoPinHash = 'info_pin_hash';
  static const _kInfoPinSalt = 'info_pin_salt';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _auth = LocalAuthentication();

  Future<bool> isLockEnabled() async =>
      (await _storage.read(key: _kLockEnabled)) == 'true';

  Future<bool> isBiometricEnabled() async =>
      (await _storage.read(key: _kBiometric)) == 'true';

  Future<bool> hasPin() async => (await _storage.read(key: _kPinHash)) != null;

  Future<void> setPin(String pin) async {
    const salt = 'mudhakkarati_pin';
    final hash = EncryptionService.instance.hashSecret(pin, salt);
    await _storage.write(key: _kPinSalt, value: salt);
    await _storage.write(key: _kPinHash, value: hash);
    await _storage.write(key: _kLockEnabled, value: 'true');
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _kPinSalt) ?? 'mudhakkarati_pin';
    final stored = await _storage.read(key: _kPinHash);
    if (stored == null) return false;
    return EncryptionService.instance.hashSecret(pin, salt) == stored;
  }

  Future<void> disableLock() async {
    await _storage.write(key: _kLockEnabled, value: 'false');
    await _storage.write(key: _kBiometric, value: 'false');
    await _storage.delete(key: _kPinHash);
    await _storage.delete(key: _kPinSalt);
  }

  Future<void> setBiometric(bool enabled) async {
    await _storage.write(key: _kBiometric, value: enabled ? 'true' : 'false');
  }

  Future<bool> canUseBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  // ---- قفل التصنيفات ----

  /// معرّفات التصنيفات المقفلة.
  Future<Set<int>> lockedCategories() async {
    final raw = await _storage.read(key: _kLockedCats) ?? '';
    return raw
        .split(',')
        .where((e) => e.trim().isNotEmpty)
        .map(int.parse)
        .toSet();
  }

  Future<bool> isCategoryLocked(int id) async =>
      (await lockedCategories()).contains(id);

  Future<void> setCategoryLocked(int id, bool locked) async {
    final set = await lockedCategories();
    if (locked) {
      set.add(id);
    } else {
      set.remove(id);
    }
    await _storage.write(key: _kLockedCats, value: set.join(','));
  }

  // ---- قفل صفحة المعلومات (رمز مستقل خاص بها) ----
  // القفل مُفعّل طالما يوجد رمز مستقل محفوظ (لا نعتمد على علامة منفصلة قد
  // تبقى «مفعّلة» دون رمز فتُتجاوَز الحماية).

  Future<bool> hasInfoPin() async =>
      (await _storage.read(key: _kInfoPinHash)) != null;

  Future<bool> isInfoLocked() async => hasInfoPin();

  /// ضبط رمز مستقل لصفحة المعلومات وتفعيل قفلها.
  Future<void> setInfoPin(String pin) async {
    const salt = 'mudhakkarati_info';
    final hash = EncryptionService.instance.hashSecret(pin, salt);
    await _storage.write(key: _kInfoPinSalt, value: salt);
    await _storage.write(key: _kInfoPinHash, value: hash);
    await _storage.write(key: _kInfoLocked, value: 'true');
  }

  Future<bool> verifyInfoPin(String pin) async {
    final salt = await _storage.read(key: _kInfoPinSalt) ?? 'mudhakkarati_info';
    final stored = await _storage.read(key: _kInfoPinHash);
    if (stored == null) return false;
    return EncryptionService.instance.hashSecret(pin, salt) == stored;
  }

  /// إلغاء قفل صفحة المعلومات وحذف رمزها المستقل.
  Future<void> clearInfoLock() async {
    await _storage.write(key: _kInfoLocked, value: 'false');
    await _storage.delete(key: _kInfoPinHash);
    await _storage.delete(key: _kInfoPinSalt);
  }

  Future<bool> authenticateBiometric(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
