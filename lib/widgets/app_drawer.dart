import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/l10n/app_strings.dart';
import '../features/backup/backup_screen.dart';
import '../features/categories/manage_categories_screen.dart';
import '../features/cleanup/cleanup_screen.dart';
import '../features/help/help_guide_screen.dart';
import '../features/security/note_unlock.dart';
import '../features/security/secret_notes_screen.dart';
import '../features/security/security_settings_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/trash/archive_screen.dart';
import '../features/trash/trash_screen.dart';

/// القائمة الجانبية الرئيسية (مستوحاة من تطبيقات المذكرات الاحترافية).
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;

    void go(Widget page) {
      Navigator.pop(context); // أغلق القائمة
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    Future<void> goSecret() async {
      Navigator.pop(context);
      final ok = await ensureUnlocked(context);
      if (ok && context.mounted) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SecretNotesScreen()));
      }
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: scheme.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // الشعار + زرّ رجوع/إغلاق واضح للقائمة الجانبية (نفس الصفّ).
                  Row(
                    children: [
                      Icon(Icons.sticky_note_2,
                          color: scheme.onPrimary, size: 40),
                      const Spacer(),
                      IconButton(
                        tooltip: 'رجوع',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.arrow_back, color: scheme.onPrimary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.t('app_name'),
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    s.t('about_desc'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: scheme.onPrimary.withOpacity(0.8), fontSize: 11),
                  ),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) {
                      final info = snap.data;
                      if (info == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'v${info.version} • #${info.buildNumber}',
                          style: TextStyle(
                              color: scheme.onPrimary.withOpacity(0.7),
                              fontSize: 11),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // دليل الاستخدام بارز أعلى القائمة (يفتح حسب اللغة المختارة).
            ListTile(
              leading: Icon(Icons.auto_stories, color: scheme.primary),
              title: Text(s.t('user_guide'),
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: scheme.primary)),
              onTap: () => go(const HelpGuideScreen()),
            ),
            const Divider(height: 1),
            // القائمة الجانبية مخصّصة للإعدادات والتحكّم والإدارة.
            // (التنبيهات/التقويم/البحث في الهيدر، والخدمات السريعة في قائمة ⋮.)
            // 1) الإدارة والتنظيم.
            _group(context, Icons.tune, s.t('group_manage'),
                initiallyExpanded: true, children: [
              _tile(context, Icons.category_outlined, s.t('manage_categories'),
                  () => go(const ManageCategoriesScreen())),
            ]),
            // 2) الأمان.
            _group(context, Icons.shield_outlined, s.t('security'),
                children: [
              _tile(context, Icons.lock, s.t('secret_notes'), goSecret),
              _tile(context, Icons.security, s.t('security_lock'),
                  () => go(const SecuritySettingsScreen())),
            ]),
            // 3) النسخ والصيانة.
            _group(context, Icons.backup_outlined, s.t('group_backup'),
                children: [
              _tile(context, Icons.backup_outlined, s.t('backup'),
                  () => go(const BackupScreen())),
              _tile(context, Icons.archive_outlined, s.t('archived'),
                  () => go(const ArchiveScreen())),
              _tile(context, Icons.delete_outline, s.t('trash'),
                  () => go(const TrashScreen())),
              _tile(context, Icons.cleaning_services_outlined, s.t('cleanup'),
                  () => go(const CleanupScreen())),
            ]),
            const Divider(),
            _tile(context, Icons.settings_outlined, s.t('settings'),
                () => go(const SettingsScreen())),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String label,
      VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      onTap: onTap,
    );
  }

  /// مجموعة قابلة للطيّ (تمدّد/انكماش) تضمّ عناصر متشابهة.
  Widget _group(BuildContext context, IconData icon, String title,
      {required List<Widget> children, bool initiallyExpanded = false}) {
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      initiallyExpanded: initiallyExpanded,
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsetsDirectional.only(start: 12),
      children: children,
    );
  }
}
