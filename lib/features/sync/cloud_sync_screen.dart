import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/sync/sync_service.dart';
import '../../widgets/ui_kit.dart';
import '../home/notes_provider.dart';

/// شاشة المزامنة السحابية: WebDAV (متاح) و Google Drive (قريبًا).
///
/// مزامنة حقيقية ثنائية الاتجاه بدمج «آخر تعديل يفوز» لكل ملاحظة، وكل ما يُرفع
/// **مشفّر طرفيًّا** بعبارة مرور يحدّدها المستخدم.
class CloudSyncScreen extends StatefulWidget {
  /// [embedded] = يُعرض داخل تبويب (بلا Scaffold/شريط علوي خاص).
  final bool embedded;
  const CloudSyncScreen({super.key, this.embedded = false});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _phrase = TextEditingController();

  SyncProvider _provider = SyncProvider.webdav;
  bool _auto = false;
  SyncFrequency _freq = SyncFrequency.daily; // تردّد المزامنة التلقائية
  bool _silent = false; // مزامنة صامتة في الخلفية
  bool _busy = false;
  DateTime? _last;
  bool _loaded = false;
  String? _googleEmail; // بريد حساب Google المتّصل (إن وُجد)

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = SyncService.instance;
    final prov = await s.provider();
    final cfg = await s.webdavConfig();
    final auto = await s.autoSync();
    final freq = await s.syncFrequency();
    final silent = await s.silentSync();
    final last = await s.lastSync();
    setState(() {
      _provider = prov == SyncProvider.none ? SyncProvider.webdav : prov;
      _url.text = cfg.url;
      _user.text = cfg.user;
      _auto = auto;
      _freq = freq;
      _silent = silent;
      _last = last;
      _loaded = true;
    });
    // حدّث حالة اتصال Google في الخلفية (دخول صامت).
    final email = await SyncService.instance.googleEmail();
    if (mounted) setState(() => _googleEmail = email);
  }

  Future<void> _googleConnect() async {
    setState(() => _busy = true);
    try {
      final email = await SyncService.instance.googleConnect();
      if (mounted) {
        setState(() {
          _googleEmail = email;
          if (email != null) _provider = SyncProvider.googleDrive;
        });
      }
      final loc = S.of(context);
      _snack(email != null
          ? '${loc.t('sync_connected')}: $email'
          : loc.t('sync_login_fail_google'));
    } catch (e) {
      _snack('${S.of(context).t('sync_login_fail')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleDisconnect() async {
    await SyncService.instance.googleDisconnect();
    if (mounted) setState(() => _googleEmail = null);
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _phrase.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// وقت نسبيّ ودّي لآخر مزامنة (الآن/قبل دقائق/ساعات/أيام).
  String _freqLabel(SyncFrequency f) => switch (f) {
        SyncFrequency.everyOpen => 'كلّ فتح',
        SyncFrequency.onClose => 'عند الإغلاق',
        SyncFrequency.daily => 'مرّة باليوم',
      };

  String _relative(DateTime d) {
    final loc = S.of(context);
    String fmt(String key, int n) => loc.t(key).replaceAll('{n}', '$n');
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return loc.t('just_now');
    if (diff.inMinutes < 60) return fmt('mins_ago', diff.inMinutes);
    if (diff.inHours < 24) return fmt('hours_ago', diff.inHours);
    if (diff.inDays < 30) return fmt('days_ago', diff.inDays);
    return fmt('months_ago', diff.inDays ~/ 30);
  }

  Future<bool> _saveSettings() async {
    final s = SyncService.instance;
    final loc = S.of(context);
    if (_phrase.text.trim().isEmpty && !await s.hasPassphrase()) {
      _snack(loc.t('sync_enter_passphrase'));
      return false;
    }
    if (_provider == SyncProvider.webdav) {
      if (_url.text.trim().isEmpty || _user.text.trim().isEmpty) {
        _snack(loc.t('sync_enter_webdav'));
        return false;
      }
      await s.setProvider(SyncProvider.webdav);
      await s.setWebdavConfig(
        url: _url.text,
        user: _user.text,
        password: _pass.text,
      );
    } else if (_provider == SyncProvider.googleDrive) {
      if (_googleEmail == null) {
        _snack(loc.t('sync_login_google_first'));
        return false;
      }
      await s.setProvider(SyncProvider.googleDrive);
    }
    if (_phrase.text.trim().isNotEmpty) {
      await s.setPassphrase(_phrase.text.trim());
    }
    await s.setAutoSync(_auto);
    await s.setSyncFrequency(_freq);
    await s.setSilentSync(_silent);
    return true;
  }

  Future<void> _test() async {
    if (!await _saveSettings()) return;
    setState(() => _busy = true);
    final r = await SyncService.instance.testConnection();
    setState(() => _busy = false);
    _snack(r.message);
  }

  Future<void> _syncNow() async {
    if (!await _saveSettings()) return;
    setState(() => _busy = true);
    final r = await SyncService.instance.syncNow();
    if (r.ok && mounted) {
      // أعِد تحميل الملاحظات والتصنيفات بعد الدمج.
      final notes = context.read<NotesProvider>();
      await notes.loadCategories();
      await notes.refresh();
      _last = await SyncService.instance.lastSync();
    }
    setState(() => _busy = false);
    _snack(r.message);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = !_loaded
        ? const Center(child: CircularProgressIndicator())
        : _content(context, scheme);
    if (widget.embedded) return body;
    return Scaffold(
      appBar: gradientAppBar(context, S.of(context).t('cloud_sync')),
      body: body,
    );
  }

  Widget _content(BuildContext context, ColorScheme scheme) {
    final loc = S.of(context);
    return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // اختيار المزوّد.
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.cloud_sync, color: scheme.primary),
                        const SizedBox(width: 10),
                        Text(loc.t('sync_provider'),
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ]),
                      const SizedBox(height: 10),
                      SegmentedButton<SyncProvider>(
                        segments: const [
                          ButtonSegment(
                              value: SyncProvider.webdav,
                              icon: Icon(Icons.dns_outlined),
                              label: Text('WebDAV')),
                          ButtonSegment(
                              value: SyncProvider.googleDrive,
                              icon: Icon(Icons.add_to_drive_outlined),
                              label: Text('Google Drive')),
                        ],
                        selected: {_provider},
                        onSelectionChanged: (sel) =>
                            setState(() => _provider = sel.first),
                      ),
                    ],
                  ),
                ),

                // إعداد WebDAV.
                if (_provider == SyncProvider.webdav)
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(loc.t('sync_webdav_data'),
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                            loc.t('sync_webdav_example'),
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _url,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: loc.t('sync_folder_url'),
                            prefixIcon: Icon(Icons.link),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _user,
                          decoration: InputDecoration(
                            labelText: loc.t('username'),
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _pass,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: loc.t('password_app'),
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                      ],
                    ),
                  ),

                // إعداد Google Drive.
                if (_provider == SyncProvider.googleDrive)
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(loc.t('google_account'),
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                            loc.t('sync_google_hidden'),
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        if (_googleEmail != null)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.account_circle,
                                color: Colors.green),
                            title: Text(_googleEmail!),
                            subtitle: Text(loc.t('connected')),
                            trailing: TextButton.icon(
                              onPressed: _busy ? null : _googleDisconnect,
                              icon: const Icon(Icons.logout),
                              label: Text(loc.t('logout')),
                            ),
                          )
                        else
                          FilledButton.tonalIcon(
                            onPressed: _busy ? null : _googleConnect,
                            icon: const Icon(Icons.login),
                            label: Text(loc.t('sync_login_google')),
                          ),
                      ],
                    ),
                  ),

                // عبارة مرور التشفير الطرفي.
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.shield_outlined, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(loc.t('e2e_passphrase'),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                          loc.t('e2e_desc'),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phrase,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: loc.t('passphrase_hint'),
                          prefixIcon: Icon(Icons.key),
                        ),
                      ),
                    ],
                  ),
                ),

                // المزامنة التلقائية + آخر مزامنة.
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _auto,
                        onChanged: (v) => setState(() => _auto = v),
                        secondary: const Icon(Icons.sync),
                        title: Text(loc.t('auto_sync_open'),
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      // خيارات التردّد + الوضع الصامت — تظهر فقط عند تفعيل التلقائي.
                      if (_auto) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text('متى تتمّ المزامنة؟',
                                style: Theme.of(context).textTheme.bodySmall),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              for (final f in SyncFrequency.values)
                                ChoiceChip(
                                  label: Text(_freqLabel(f)),
                                  selected: _freq == f,
                                  onSelected: (_) =>
                                      setState(() => _freq = f),
                                ),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          value: _silent,
                          onChanged: (v) => setState(() => _silent = v),
                          secondary: const Icon(Icons.notifications_off_outlined),
                          title: const Text('مزامنة صامتة في الخلفية'),
                          subtitle: const Text(
                              'بلا شريط علويّ — لا تؤثّر على سرعة التعامل'),
                        ),
                      ],
                      ListTile(
                        leading: Icon(
                            _last != null ? Icons.cloud_done : Icons.cloud_off,
                            color: _last != null
                                ? Colors.green
                                : Theme.of(context).hintColor),
                        title: Text(loc.t('last_sync')),
                        subtitle: Text(_last == null
                            ? loc.t('not_yet')
                            : '${_relative(_last!)} • ${DateFormat('yyyy/MM/dd – HH:mm').format(_last!)}'),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _test,
                          icon: const Icon(Icons.wifi_tethering),
                          label: Text(loc.t('test_connection')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _syncNow,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.cloud_sync),
                          label: Text(loc.t('sync_now')),
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    loc.t('sync_note'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
  }
}
