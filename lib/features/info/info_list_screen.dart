import 'package:flutter/material.dart';
import '../../core/l10n/app_strings.dart';

import '../../data/models/info_entry.dart';
import '../../data/repositories/info_repository.dart';
import '../../widgets/ui_kit.dart';
import 'info_detail_screen.dart';
import 'info_edit_screen.dart';

/// صفحة «معلومات عامة» — قاعدة بيانات داخلية مع بحث وعرض احترافي.
///
/// عند تمرير [filterMain]/[filterSub] تعرض فقط المواضيع تحت ذلك التخصص.
class InfoListScreen extends StatefulWidget {
  final String? filterMain;
  final String? filterSub;
  const InfoListScreen({super.key, this.filterMain, this.filterSub});

  @override
  State<InfoListScreen> createState() => _InfoListScreenState();
}

class _InfoListScreenState extends State<InfoListScreen> {
  final _repo = InfoRepository();
  final _searchCtrl = TextEditingController();
  List<InfoEntry> _items = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _filtered =>
      widget.filterMain != null || widget.filterSub != null;

  Future<void> _load() async {
    setState(() => _loading = true);
    List<InfoEntry> items;
    if (_filtered) {
      items = await _repo.filter(
          main: widget.filterMain, sub: widget.filterSub);
      final q = _query.trim().toLowerCase();
      if (q.isNotEmpty) {
        items = items.where((e) => _matches(e, q)).toList();
      }
    } else {
      items = _query.trim().isEmpty
          ? await _repo.getAll()
          : await _repo.search(_query);
    }
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  bool _matches(InfoEntry e, String q) =>
      [e.mainSpecialty, e.subSpecialty, e.topic, e.brief, e.detail, e.notes,
              e.source]
          .any((f) => f.toLowerCase().contains(q));

  Future<void> _add() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InfoEditScreen(
            initialMain: widget.filterMain, initialSub: widget.filterSub),
      ),
    );
    if (added == true) _load();
  }

  Future<void> _open(InfoEntry e) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => InfoDetailScreen(entry: e)),
    );
    // أعد التحميل دائمًا عند الرجوع (قد يكون عُدّل أو حُذف).
    _load();
  }

  String get _title =>
      widget.filterSub ?? widget.filterMain ?? S.of(context).t('info');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: gradientAppBar(context, _title,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                _query = v;
                _load();
              },
              decoration: InputDecoration(
                hintText: S.of(context).t('inf_search_hint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _query = '';
                          _load();
                        },
                      ),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(S.of(context).t('add')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _empty(theme)
              : (_query.trim().isNotEmpty
                  // نتائج البحث: قائمة مسطّحة بسطر تعريفي.
                  ? RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: theme.dividerColor.withValues(alpha: 0.4)),
                        itemBuilder: (context, i) =>
                            _row(_items[i], theme, scheme),
                      ),
                    )
                  // العرض المنظّم: مجموعات حسب التخصص (رئيسي › فرعي) + بطاقات.
                  : _grouped(theme, scheme)),
    );
  }

  /// عرض منظّم احترافيًّا: التخصص الرئيسي عنوانًا بارزًا، تحته التخصصات الفرعية،
  /// ثم بطاقات المواضيع — كقاعدة معرفة منسّقة.
  Widget _grouped(ThemeData theme, ColorScheme scheme) {
    final mains = <String, Map<String, List<InfoEntry>>>{};
    for (final e in _items) {
      final m = e.mainSpecialty.trim();
      final sub = e.subSpecialty.trim();
      mains
          .putIfAbsent(m, () => <String, List<InfoEntry>>{})
          .putIfAbsent(sub, () => [])
          .add(e);
    }
    final mainKeys = mains.keys.toList()..sort();
    // نوسّع تلقائيًّا عندما تكون التخصصات قليلة؛ وإلا نطويها لعرضٍ نظيف.
    final expandAll = mainKeys.length <= 2;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
        children: [
          _overviewBar(mainKeys.length, _items.length, theme, scheme),
          for (final m in mainKeys)
            _mainSection(m, mains[m]!, expandAll, theme, scheme),
        ],
      ),
    );
  }

  /// شريط نظرة عامّة: عدد التخصّصات والمواضيع.
  Widget _overviewBar(
      int mainsCount, int total, ThemeData theme, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Row(children: [
        Icon(Icons.menu_book_outlined, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Text('$mainsCount ${S.of(context).t('inf_specialty_unit')} • $total ${S.of(context).t('inf_topic_unit')}',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  /// قسم تخصّص رئيسيّ قابل للطيّ (بطاقة) مع عدّاد، يضمّ التخصصات الفرعية ومواضيعها.
  Widget _mainSection(String m, Map<String, List<InfoEntry>> subs, bool expand,
      ThemeData theme, ColorScheme scheme) {
    final count = subs.values.fold<int>(0, (a, b) => a + b.length);
    final subKeys = subs.keys.toList()..sort();
    final children = <Widget>[];
    for (final sName in subKeys) {
      if (sName.isNotEmpty) children.add(_subHeader(sName, theme, scheme));
      for (final e in subs[sName]!) {
        children.add(_card(e, theme, scheme));
      }
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // نُخفي خطوط ExpansionTile الفاصلة لمظهر أنظف.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expand,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.account_tree_outlined,
                size: 18, color: scheme.onPrimaryContainer),
          ),
          title: Text(m.isEmpty ? S.of(context).t('inf_general') : m,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold, color: scheme.primary)),
          subtitle: Text('$count ${S.of(context).t('inf_topic_unit')}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          children: children,
        ),
      ),
    );
  }

  Widget _subHeader(String name, ThemeData theme, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 2, 4),
      child: Row(children: [
        Icon(Icons.subdirectory_arrow_left, size: 16, color: theme.hintColor),
        const SizedBox(width: 6),
        Text(name,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  /// بطاقة موضوع أنيقة (عنوان + لمحة من الملخّص).
  Widget _card(InfoEntry e, ThemeData theme, ColorScheme scheme) {
    final title = e.topic.isNotEmpty ? e.topic : e.brief;
    final preview = e.brief.trim();
    return AppCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      onTap: () => _open(e),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(children: [
        Container(
          width: 6,
          height: 38,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              if (preview.isNotEmpty && e.topic.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ],
            ],
          ),
        ),
        Icon(Icons.chevron_left, size: 18, color: theme.hintColor),
      ]),
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 64, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(
              _query.isEmpty ? S.of(context).t('inf_empty') : S.of(context).t('inf_no_results'),
              style: theme.textTheme.titleMedium,
            ),
            if (_query.isEmpty) ...[
              const SizedBox(height: 6),
              Text(S.of(context).t('inf_empty_hint'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor)),
            ],
          ],
        ),
      );

  /// صفّ مختصر: الاسم فقط (لعرض أكبر عدد). عند البحث يظهر سطر تعريفي
  /// (التخصص + لمحة من المختصر) لتمييز النتائج.
  Widget _row(InfoEntry e, ThemeData theme, ColorScheme scheme) {
    final title = e.topic.isNotEmpty ? e.topic : e.brief;
    final searching = _query.trim().isNotEmpty;
    String? sub;
    if (searching) {
      final parts = <String>[];
      final sp = [e.mainSpecialty, e.subSpecialty]
          .where((x) => x.isNotEmpty)
          .join(' › ');
      if (sp.isNotEmpty) parts.add(sp);
      if (e.topic.isNotEmpty && e.brief.isNotEmpty) parts.add(e.brief);
      sub = parts.join('  •  ');
    }
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      leading: Icon(Icons.article_outlined, size: 20, color: scheme.primary),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: (sub == null || sub.isEmpty)
          ? null
          : Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
      trailing: Icon(Icons.chevron_left, size: 18, color: theme.hintColor),
      onTap: () => _open(e),
    );
  }
}
