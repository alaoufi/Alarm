import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import 'help_guide_data.dart';

/// شاشة «دليل الاستخدام» التفاعلية ثلاثية الأبعاد — محتواها **مترجَم لكل لغة**
/// (يتبع اللغة المختارة، مع رجوع للإنجليزية عند غياب الترجمة).
class HelpGuideScreen extends StatelessWidget {
  const HelpGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final lang = S.of(context).locale.languageCode;
    final chrome = helpChrome(lang);
    final sections = helpSections(lang);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _Header(
              dark: dark,
              scheme: scheme,
              title: S.of(context).t('user_guide'),
              subtitle: chrome.subtitle),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
            sliver: SliverList.list(
              children: [
                for (final sec in sections)
                  _SectionCard(
                      section: sec, dark: dark, itemsLabel: chrome.items),
                const SizedBox(height: 8),
                Center(
                  child: Text(chrome.updated,
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withOpacity(0.4))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool dark;
  final ColorScheme scheme;
  final String title;
  final String subtitle;
  const _Header(
      {required this.dark,
      required this.scheme,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 188,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      title: Text(title),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                scheme.primary,
                Color.alphaBlend(
                    Colors.black.withOpacity(0.18), scheme.primary),
                scheme.tertiary,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                  top: -30,
                  left: -20,
                  child: _blob(scheme.onPrimary.withOpacity(0.10), 140)),
              Positioned(
                  bottom: -40,
                  right: -10,
                  child: _blob(scheme.onPrimary.withOpacity(0.08), 120)),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              scheme.onPrimary.withOpacity(0.95),
                              scheme.onPrimary.withOpacity(0.7),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.28),
                                offset: const Offset(0, 8),
                                blurRadius: 16,
                                spreadRadius: -2),
                          ],
                        ),
                        child: Icon(Icons.auto_stories,
                            color: scheme.primary, size: 34),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(subtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: scheme.onPrimary.withOpacity(0.9),
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blob(Color color, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _SectionCard extends StatelessWidget {
  final HgSection section;
  final bool dark;
  final String itemsLabel;
  const _SectionCard(
      {required this.section, required this.dark, required this.itemsLabel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = dark ? const Color(0xFF1E2230) : Colors.white;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surface,
            Color.alphaBlend(section.color.withOpacity(0.06), surface),
          ],
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.45 : 0.12),
              offset: const Offset(0, 10),
              blurRadius: 24,
              spreadRadius: -6),
          BoxShadow(
              color: Colors.white.withOpacity(dark ? 0.04 : 0.9),
              offset: const Offset(-3, -3),
              blurRadius: 8),
        ],
        border: Border.all(color: section.color.withOpacity(0.18)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: section.expanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: _Icon3D(icon: section.icon, accent: section.color, size: 46),
          title: Text(section.title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: scheme.onSurface)),
          subtitle: Text('${section.items.length} $itemsLabel',
              style: TextStyle(
                  fontSize: 11.5, color: scheme.onSurface.withOpacity(0.5))),
          children: [
            for (final it in section.items)
              _ToolRow(item: it, accent: section.color, dark: dark),
          ],
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  final HgItem item;
  final Color accent;
  final bool dark;
  const _ToolRow(
      {required this.item, required this.accent, required this.dark});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color:
            dark ? Colors.white.withOpacity(0.03) : accent.withOpacity(0.05),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Icon3D(icon: item.icon, accent: accent, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: scheme.onSurface)),
                const SizedBox(height: 2),
                Text(item.desc,
                    style: TextStyle(
                        fontSize: 12.8,
                        height: 1.4,
                        color: scheme.onSurface.withOpacity(0.72))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Icon3D extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final double size;
  const _Icon3D(
      {required this.icon, required this.accent, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(Colors.white.withOpacity(0.25), accent),
            accent,
            Color.alphaBlend(Colors.black.withOpacity(0.22), accent),
          ],
        ),
        boxShadow: [
          BoxShadow(
              color: accent.withOpacity(0.5),
              offset: const Offset(0, 5),
              blurRadius: 10,
              spreadRadius: -2),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.30), width: 1),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.5),
    );
  }
}
