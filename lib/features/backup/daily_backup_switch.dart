import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/backup_service.dart';

/// مفتاح تفعيل/إيقاف النسخة الاحتياطية اليومية التلقائية + اختيار مجلّد الحفظ.
class DailyBackupSwitch extends StatefulWidget {
  const DailyBackupSwitch({super.key});

  @override
  State<DailyBackupSwitch> createState() => _DailyBackupSwitchState();
}

class _DailyBackupSwitchState extends State<DailyBackupSwitch> {
  bool _enabled = false;
  bool _loaded = false;
  bool _busy = false;
  String? _customDir;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await BackupService.instance.autoBackupEnabled();
    final dir = await BackupService.instance.autoBackupCustomDir();
    if (mounted) {
      setState(() {
        _enabled = on;
        _customDir = dir;
        _loaded = true;
      });
    }
  }

  Future<void> _toggle(bool v) async {
    setState(() => _busy = true);
    try {
      if (v) {
        await BackupService.instance.enableDailyAutoBackup();
      } else {
        await BackupService.instance.setAutoBackupEnabled(false);
      }
      if (!mounted) return;
      setState(() {
        _enabled = v;
        _busy = false;
      });
      _toast(v
          ? 'تم تفعيل النسخة اليومية التلقائية ✓ (7 نسخ دوريّة)'
          : 'أُوقفت النسخة التلقائية');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('تعذّر: $e');
    }
  }

  Future<void> _pickDir() async {
    setState(() => _busy = true);
    try {
      await Permission.storage.request(); // لبعض الأجهزة/الإصدارات
      final path = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'اختر مجلّد حفظ النسخ');
      if (path == null) {
        setState(() => _busy = false);
        return;
      }
      final ok = await BackupService.instance.setAutoBackupCustomDir(path);
      if (!mounted) return;
      if (ok) {
        setState(() => _customDir = path);
        // أنشئ نسخة فورية في المجلّد الجديد إن كانت الميزة مفعّلة.
        if (_enabled) await BackupService.instance.runAutoBackup();
        _toast('تم ضبط مجلّد الحفظ ✓');
      } else {
        _toast('هذا المجلّد غير قابل للكتابة على هذا النظام — سيُستخدم التخزين الداخلي');
      }
    } catch (e) {
      _toast('تعذّر: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetDir() async {
    await BackupService.instance.clearAutoBackupCustomDir();
    if (mounted) setState(() => _customDir = null);
    _toast('عاد الحفظ إلى التخزين الداخلي');
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
    }
  }

  String get _dirLabel {
    if (_customDir == null) return 'التخزين الداخلي (يُمسح عند حذف التطبيق)';
    return _customDir!;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.event_repeat),
          title: const Text('نسخة احتياطية يومية تلقائية'),
          subtitle: const Text('7 نسخ دوريّة — خانة لكل يوم من الأسبوع'),
          value: _enabled,
          onChanged: (_loaded && !_busy) ? _toggle : null,
        ),
        if (_enabled)
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('مجلّد الحفظ'),
            subtitle: Text(_dirLabel,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_customDir != null)
                  IconButton(
                    tooltip: 'إعادة للداخلي',
                    icon: const Icon(Icons.restore),
                    onPressed: _busy ? null : _resetDir,
                  ),
                IconButton(
                  tooltip: 'اختيار مجلّد',
                  icon: const Icon(Icons.drive_folder_upload_outlined),
                  onPressed: _busy ? null : _pickDir,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
