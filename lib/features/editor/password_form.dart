import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../data/models/password_entry.dart';

/// نموذج إدخال ملاحظة كلمات المرور: حقول منظمة + نسخ لكل حقل + مولّد + مؤشّر قوة.
class PasswordForm extends StatefulWidget {
  final PasswordEntry initial;
  final ValueChanged<PasswordEntry> onChanged;

  const PasswordForm({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<PasswordForm> {
  late final TextEditingController _site;
  late final TextEditingController _app;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _notes;
  bool _obscure = true;
  Timer? _clearTimer;

  @override
  void initState() {
    super.initState();
    _site = TextEditingController(text: widget.initial.site);
    _app = TextEditingController(text: widget.initial.app);
    _username = TextEditingController(text: widget.initial.username);
    _password = TextEditingController(text: widget.initial.password);
    _notes = TextEditingController(text: widget.initial.notes);
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    _site.dispose();
    _app.dispose();
    _username.dispose();
    _password.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(PasswordEntry(
      site: _site.text,
      app: _app.text,
      username: _username.text,
      password: _password.text,
      notes: _notes.text,
    ));
  }

  /// نسخ عادي.
  Future<void> _copy(String value) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    _toast(S.of(context).t('pw_copied'));
  }

  /// نسخ آمن: يُمسح من الحافظة تلقائيًا بعد 30 ثانية.
  Future<void> _copySecure(String value) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    _toast('${S.of(context).t('pw_copied')} — ${S.of(context).t('pw_clear_30')}');
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(seconds: 30), () async {
      final data = await Clipboard.getData('text/plain');
      if (data?.text == value) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _generate() {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghijkmnpqrstuvwxyz';
    const digits = '23456789';
    const symbols = '!@#\$%&*?-_=+';
    const all = upper + lower + digits + symbols;
    final rnd = Random.secure();
    const len = 16;
    // نضمن وجود صنف واحد على الأقل من كل نوع.
    final chars = <String>[
      upper[rnd.nextInt(upper.length)],
      lower[rnd.nextInt(lower.length)],
      digits[rnd.nextInt(digits.length)],
      symbols[rnd.nextInt(symbols.length)],
    ];
    for (var i = chars.length; i < len; i++) {
      chars.add(all[rnd.nextInt(all.length)]);
    }
    chars.shuffle(rnd);
    setState(() {
      _password.text = chars.join();
      _obscure = false;
    });
    _emit();
  }

  // 0..4
  int _strength(String p) {
    if (p.isEmpty) return 0;
    var score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'\d').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    return score.clamp(0, 4);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(s.t('pw_site'), _site, Icons.language),
        _field(s.t('pw_app'), _app, Icons.apps),
        _field(s.t('pw_username'), _username, Icons.person_outline),
        _passwordField(s),
        _strengthBar(s),
        _field(s.t('pw_notes'), _notes, Icons.notes, maxLines: 3),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.lock, size: 14, color: Theme.of(context).hintColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(s.t('pw_encrypted_hint'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, IconData icon,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        onChanged: (_) => _emit(),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: IconButton(
            tooltip: S.of(context).t('copy'),
            icon: const Icon(Icons.copy),
            onPressed: () => _copy(ctrl.text),
          ),
        ),
      ),
    );
  }

  Widget _passwordField(S s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _password,
        obscureText: _obscure,
        onChanged: (_) {
          setState(() {});
          _emit();
        },
        decoration: InputDecoration(
          labelText: s.t('pw_password'),
          prefixIcon: const Icon(Icons.vpn_key),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: s.t('pw_generate'),
                icon: const Icon(Icons.casino_outlined),
                onPressed: _generate,
              ),
              IconButton(
                tooltip: _obscure ? s.t('pw_show') : s.t('pw_hide'),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              IconButton(
                tooltip: s.t('copy'),
                icon: const Icon(Icons.copy),
                onPressed: () => _copySecure(_password.text),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _strengthBar(S s) {
    if (_password.text.isEmpty) return const SizedBox(height: 4);
    final score = _strength(_password.text);
    const labels = ['ضعيفة جدًا', 'ضعيفة', 'متوسطة', 'جيدة', 'قوية'];
    const colors = [
      Color(0xFFE53935),
      Color(0xFFFB8C00),
      Color(0xFFFDD835),
      Color(0xFF7CB342),
      Color(0xFF2E7D32),
    ];
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 6, top: 2),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (score + 1) / 5,
                minHeight: 6,
                backgroundColor: Theme.of(context).dividerColor,
                color: colors[score],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(labels[score],
              style: TextStyle(fontSize: 12, color: colors[score])),
        ],
      ),
    );
  }
}
