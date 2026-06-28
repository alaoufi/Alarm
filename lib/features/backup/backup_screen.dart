import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/backup_service.dart';
import '../../widgets/ui_kit.dart';
import '../home/notes_provider.dart';
import '../reminders/reminders_provider.dart';
import '../sync/cloud_sync_screen.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  // حالة النسخ الاحتياطي التلقائي.
  bool _autoEnabled = false;
  int _autoInterval = 1; // 1 = يومي، 7 = أسبوعي
  bool _autoHasPassword = false;
  int _autoCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAuto();
  }

  Future<void> _loadAuto() async {
    final bs = BackupService.instance;
    final enabled = await bs.autoBackupEnabled();
    final interval = await bs.autoBackupIntervalDays();
    final hasPwd = await bs.hasAutoBackupPassword();
    final count = (await bs.listAutoBackups()).length;
    if (!mounted) return;
    setState(() {
      _autoEnabled = enabled;
      _autoInterval = interval;
      _autoHasPassword = hasPwd;
      _autoCount = count;
    });
  }

  Future<String?> _askPassword(String title) async {
    final ctrl = TextEditingController();
    final s = S.of(context);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: s.t('backup_password'),
            helperText: s.t('backup_password_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text(s.t('ok')),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// بطاقة تعرض تاريخ ووقت آخر العمليات (محلي/مشاركة/Drive/استعادة).
  /// لافتة «حالة الحماية»: تحسب أحدث نسخة (محلي/سحابي/تلقائي) وتُظهر مؤشّرًا
  /// ملوّنًا واضحًا — أهمّ ما يفيد المستخدم: هل بياناته محميّة؟
  Widget _protectionBanner(BuildContext context, List<DateTime?> dates) {
    final s = S.of(context);
    final live = dates.whereType<DateTime>().toList();
    final fresh = live.isEmpty
        ? null
        : live.reduce((a, b) => a.isAfter(b) ? a : b);
    final ageDays =
        fresh == null ? null : DateTime.now().difference(fresh).inDays;
    late final Color c;
    late final IconData ic;
    late final String msg;
    if (fresh == null) {
      c = Colors.red;
      ic = Icons.gpp_bad_outlined;
      msg = s.t('not_protected');
    } else if (ageDays! < 7) {
      c = Colors.green;
      ic = Icons.verified_user_outlined;
      msg = s.t('protected');
    } else if (ageDays < 30) {
      c = Colors.orange;
      ic = Icons.gpp_maybe_outlined;
      msg = s.t('backup_recommended');
    } else {
      c = Colors.red;
      ic = Icons.gpp_bad_outlined;
      msg = s.t('backup_recommended');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(ic, color: c, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg,
                    style:
                        TextStyle(fontWeight: FontWeight.bold, color: c)),
                if (fresh != null)
                  Text(
                    '${s.t('last_backup')}: ${DateFormat('yyyy/MM/dd HH:mm').format(fresh)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final bs = BackupService.instance;
    String fmt(DateTime? d) =>
        d == null ? '—' : DateFormat('yyyy/MM/dd  HH:mm').format(d);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 20),
                const SizedBox(width: 8),
                Text(S.of(context).t('bk_recent'),
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<DateTime?>>(
              future: Future.wait([
                bs.lastLocalBackup(),
                bs.lastShareBackup(),
                bs.lastRestore(),
                bs.lastAutoBackup(),
              ]),
              builder: (context, snap) {
                final d = snap.data ?? const [null, null, null, null];
                Widget row(IconData i, String label, DateTime? t) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(i, size: 16, color: Theme.of(context).hintColor),
                          const SizedBox(width: 8),
                          Expanded(child: Text(label)),
                          Text(fmt(t),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    );
                return Column(
                  children: [
                    _protectionBanner(context, [d[0], d[1], d[3]]),
                    const SizedBox(height: 8),
                    row(Icons.save_alt, S.of(context).t('bk_local'), d[0]),
                    row(Icons.ios_share, S.of(context).t('bk_cloud'), d[1]),
                    row(Icons.autorenew, S.of(context).t('bk_auto'), d[3]),
                    row(Icons.restore, S.of(context).t('bk_last_restore'), d[2]),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// بطاقة إعدادات النسخ الاحتياطي التلقائي.
  Widget _autoBackupCard(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.autorenew),
              title: Text(S.of(context).t('bk_auto_title')),
              subtitle: Text(_autoEnabled
                  ? '${S.of(context).t('bk_auto_when')} '
                      '${_autoInterval == 1 ? S.of(context).t('bk_daily') : S.of(context).t('bk_weekly')}'
                      ' ($_autoCount)'
                  : S.of(context).t('bk_auto_desc')),
              value: _autoEnabled,
              onChanged: _busy ? null : _toggleAuto,
            ),
            if (_autoEnabled) ...[
              const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(S.of(context).t('bk_frequency')),
                    const SizedBox(width: 12),
                    SegmentedButton<int>(
                      segments: [
                        ButtonSegment(value: 1, label: Text(S.of(context).t('bk_daily'))),
                        ButtonSegment(value: 7, label: Text(S.of(context).t('bk_weekly'))),
                      ],
                      selected: {_autoInterval},
                      onSelectionChanged: _busy
                          ? null
                          : (sel) => _setAutoInterval(sel.first),
                    ),
                  ],
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.play_circle_outline),
                title: Text(S.of(context).t('bk_create_now')),
                onTap: _busy ? null : _runAutoNow,
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.settings_backup_restore),
                title: Text(S.of(context).t('bk_restore_auto')),
                subtitle: Text('${S.of(context).t('bk_saved_count')}: $_autoCount'),
                onTap: _busy ? null : _restoreFromAuto,
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.password),
                title: Text(_autoHasPassword
                    ? S.of(context).t('bk_change_pwd')
                    : S.of(context).t('bk_set_pwd')),
                onTap: _busy ? null : _changeAutoPassword,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  S.of(context).t('bk_auto_note'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    final s = S.of(context);
    final pwd = await _askPassword(s.t('export_backup'));
    if (pwd == null || pwd.isEmpty) return;
    setState(() => _busy = true);
    final result = await BackupService.instance.exportBackup(pwd);
    setState(() => _busy = false);
    _toast(result.message);
  }

  /// بعد أي استعادة ناجحة: إشعار يتيح **التراجع** فورًا (يرجع لقطة ما-قبل-الاستعادة).
  void _showRestoreUndo() {
    final s = S.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(s.t('restore_done')),
      action: SnackBarAction(
        label: s.t('undo_restore'),
        onPressed: () async {
          setState(() => _busy = true);
          final r = await BackupService.instance.undoLastRestore();
          if (!mounted) return;
          setState(() => _busy = false);
          _toast(r.message);
          if (r.success) {
            await context.read<NotesProvider>().init();
            await context.read<RemindersProvider>().refresh();
            if (mounted) {
              await context.read<RemindersProvider>().ensureScheduled();
            }
          }
        },
      ),
    ));
  }

  Future<void> _exportJson() async {
    setState(() => _busy = true);
    final result = await BackupService.instance.exportNotesJson();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(result.message);
  }

  Future<void> _importJson() async {
    setState(() => _busy = true);
    final result = await BackupService.instance.importNotesJson();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(result.message);
    if (result.success) {
      await context.read<NotesProvider>().init();
      // جدولة أي تنبيهات مستوردة فورًا.
      if (mounted) await context.read<RemindersProvider>().refresh();
      if (mounted) await context.read<RemindersProvider>().ensureScheduled();
    }
  }

  Future<void> _verifyBackup() async {
    final pwd = await _askPassword(S.of(context).t('bk_verify'));
    if (pwd == null || pwd.isEmpty) return;
    setState(() => _busy = true);
    final r = await BackupService.instance.verifyBackupFile(pwd);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(r.message);
  }

  Future<void> _import() async {
    final s = S.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('import_backup')),
        content: Text(s.t('restore_warning')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('confirm'))),
        ],
      ),
    );
    if (confirm != true) return;

    final pwd = await _askPassword(s.t('import_backup'));
    if (pwd == null || pwd.isEmpty) return;

    setState(() => _busy = true);
    final result = await BackupService.instance.importBackup(pwd);
    setState(() => _busy = false);
    _toast(result.message);

    if (result.success && mounted) {
      await context.read<NotesProvider>().init();
      await context.read<RemindersProvider>().refresh();
      // أعد جدولة التذكيرات المستعادة فورًا كي تعمل دون انتظار إعادة التشغيل.
      if (mounted) await context.read<RemindersProvider>().ensureScheduled();
      if (mounted) _showRestoreUndo();
    }
  }

  Future<void> _shareToCloud() async {
    final pwd = await _askPassword(S.of(context).t('bk_share_cloud'));
    if (pwd == null || pwd.isEmpty) return;
    setState(() => _busy = true);
    final result = await BackupService.instance.shareBackupToCloud(pwd);
    setState(() => _busy = false);
    _toast(result.message);
  }

  // ---- النسخ الاحتياطي التلقائي ----

  Future<void> _toggleAuto(bool value) async {
    final bs = BackupService.instance;
    if (!value) {
      await bs.setAutoBackupEnabled(false);
      setState(() => _autoEnabled = false);
      _toast(S.of(context).t('bk_auto_stopped'));
      return;
    }

    // التفعيل يتطلّب كلمة مرور تُحفظ بأمان لتشفير النسخ دون تدخّل.
    if (!await bs.hasAutoBackupPassword()) {
      final pwd = await _askPassword(S.of(context).t('bk_auto_pwd'));
      if (pwd == null || pwd.isEmpty) return;
      await bs.setAutoBackupPassword(pwd);
    }
    await bs.setAutoBackupEnabled(true);
    if (!mounted) return;
    setState(() {
      _autoEnabled = true;
      _autoHasPassword = true;
    });

    // تشغيل أول نسخة فورًا حتى لا ينتظر المستخدم حلول الموعد.
    setState(() => _busy = true);
    final r = await bs.runAutoBackup();
    setState(() => _busy = false);
    await _loadAuto();
    _toast(r.message);
  }

  Future<void> _setAutoInterval(int days) async {
    await BackupService.instance.setAutoBackupIntervalDays(days);
    setState(() => _autoInterval = days);
  }

  Future<void> _runAutoNow() async {
    setState(() => _busy = true);
    final r = await BackupService.instance.runAutoBackup();
    setState(() => _busy = false);
    await _loadAuto();
    _toast(r.message);
  }

  Future<void> _changeAutoPassword() async {
    final pwd = await _askPassword(S.of(context).t('bk_auto_pwd'));
    if (pwd == null || pwd.isEmpty) return;
    await BackupService.instance.setAutoBackupPassword(pwd);
    setState(() => _autoHasPassword = true);
    _toast(S.of(context).t('bk_pwd_updated'));
  }

  Future<void> _restoreFromAuto() async {
    final bs = BackupService.instance;
    final files = await bs.listAutoBackups();
    if (!mounted) return;
    if (files.isEmpty) {
      _toast(S.of(context).t('bk_no_auto'));
      return;
    }

    final chosen = await showDialog<File>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(S.of(context).t('bk_restore_auto')),
        children: [
          for (final f in files)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, f),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_autoBackupLabel(f))),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).t('bk_confirm_restore')),
        content: Text(
            '${S.of(context).t('bk_restore_replace')}:\n${_autoBackupLabel(chosen)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.of(context).t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(S.of(context).t('bk_restore'))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    final r = await bs.restoreAutoBackup(chosen);
    setState(() => _busy = false);
    _toast(r.message);

    if (r.success && mounted) {
      await context.read<NotesProvider>().init();
      await context.read<RemindersProvider>().refresh();
      // أعد جدولة التذكيرات المستعادة فورًا كي تعمل دون انتظار إعادة التشغيل.
      if (mounted) await context.read<RemindersProvider>().ensureScheduled();
      if (mounted) _showRestoreUndo();
    }
  }

  /// عنوان مقروء لملف نسخة تلقائية (يوم الأسبوع المترجم + وقت آخر تعديل).
  String _autoBackupLabel(File f) {
    final m = f.statSync().modified;
    return DateFormat('EEEE  yyyy/MM/dd  HH:mm').format(m);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: gradientAppBar(
          context,
          s.t('backup'),
          bottom: TabBar(tabs: [
            Tab(
                icon: const Icon(Icons.save_outlined),
                text: S.of(context).t('bk_tab_backup')),
            Tab(
                icon: const Icon(Icons.cloud_sync),
                text: S.of(context).t('cloud_sync')),
          ]),
        ),
        body: TabBarView(children: [
          Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
            children: [
              _statusCard(context),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: Text(s.t('export_backup')),
                  subtitle: Text(
                      S.of(context).t('bk_export_desc')),
                  onTap: _busy ? null : _export,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: Text(S.of(context).t('bk_share_cloud')),
                  subtitle: Text(
                      S.of(context).t('bk_share_desc')),
                  onTap: _busy ? null : _shareToCloud,
                ),
              ),
              const SizedBox(height: 8),
              _autoBackupCard(context),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.download),
                  title: Text(s.t('import_backup')),
                  subtitle: Text(
                      S.of(context).t('bk_import_desc')),
                  onTap: _busy ? null : _import,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: Text(S.of(context).t('bk_verify')),
                  subtitle: Text(
                      S.of(context).t('bk_verify_desc')),
                  onTap: _busy ? null : _verifyBackup,
                ),
              ),
              const SizedBox(height: 16),
              // تصدير/استيراد JSON (نصّ مقروء قابل للنقل، غير مشفّر، بلا مرفقات).
              Text('JSON',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.data_object),
                  title: Text(s.t('export_json')),
                  subtitle: Text(s.t('export_json_desc')),
                  onTap: _busy ? null : _exportJson,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: Text(s.t('import_json')),
                  subtitle: Text(s.t('import_json_desc')),
                  onTap: _busy ? null : _importJson,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  S.of(context).t('bk_footer'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
              if (_busy)
                Container(
                  color: Colors.black26,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
          const CloudSyncScreen(embedded: true),
        ]),
      ),
    );
  }
}
