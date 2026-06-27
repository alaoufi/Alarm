import 'dart:convert';

import '../../services/vault_service.dart';

/// بيانات ملاحظة كلمات المرور (حقول منظمة).
///
/// تُخزَّن داخل حقل `content` للملاحظة كـ JSON، مع تشفير كلمة المرور فقط
/// بمفتاح الخزنة (VaultService). باقي الحقول تبقى نصًّا ليعمل البحث.
class PasswordEntry {
  final String site; // الموقع
  final String app; // التطبيق
  final String username; // اسم المستخدم
  final String password; // كلمة المرور (نص صريح في الذاكرة فقط)
  final String notes; // ملاحظات

  const PasswordEntry({
    this.site = '',
    this.app = '',
    this.username = '',
    this.password = '',
    this.notes = '',
  });

  PasswordEntry copyWith({
    String? site,
    String? app,
    String? username,
    String? password,
    String? notes,
  }) {
    return PasswordEntry(
      site: site ?? this.site,
      app: app ?? this.app,
      username: username ?? this.username,
      password: password ?? this.password,
      notes: notes ?? this.notes,
    );
  }

  /// يحوّل إلى JSON قابل للتخزين مع تشفير كلمة المرور.
  /// يجب استدعاء VaultService.instance.ensureKey() مسبقًا.
  String toStoredJson() {
    return jsonEncode({
      'site': site,
      'app': app,
      'username': username,
      'password_enc': password.isEmpty
          ? ''
          : VaultService.instance.encrypt(password),
      'notes': notes,
    });
  }

  /// يقرأ من JSON المخزَّن ويفك تشفير كلمة المرور.
  factory PasswordEntry.fromStoredJson(String raw) {
    if (raw.trim().isEmpty) return const PasswordEntry();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final enc = (map['password_enc'] as String?) ?? '';
      return PasswordEntry(
        site: (map['site'] as String?) ?? '',
        app: (map['app'] as String?) ?? '',
        username: (map['username'] as String?) ?? '',
        password: enc.isEmpty ? '' : VaultService.instance.decrypt(enc),
        notes: (map['notes'] as String?) ?? '',
      );
    } catch (_) {
      return const PasswordEntry();
    }
  }

  /// نص مختصر يُعرض في البطاقة (بدون كلمة المرور).
  String get displayTitle {
    if (site.trim().isNotEmpty) return site;
    if (app.trim().isNotEmpty) return app;
    if (username.trim().isNotEmpty) return username;
    return 'كلمة مرور';
  }
}
