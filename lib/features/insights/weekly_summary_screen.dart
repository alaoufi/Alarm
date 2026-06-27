import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/ui_kit.dart';
import '../home/notes_provider.dart';

/// ملخّص أسبوعي: إحصاءات سريعة عن الملاحظات لمساعدة المستخدم على المتابعة.
class WeeklySummaryScreen extends StatefulWidget {
  const WeeklySummaryScreen({super.key});

  @override
  State<WeeklySummaryScreen> createState() => _WeeklySummaryScreenState();
}

class _WeeklySummaryScreenState extends State<WeeklySummaryScreen> {
  bool _loading = true;
  int _total = 0, _newThisWeek = 0, _uncategorized = 0, _untagged = 0,
      _needReview = 0, _locked = 0;
  String _topCategory = '—';
  int _topCategoryCount = 0;
  List<MapEntry<String, int>> _topTags = [];

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    final provider = context.read<NotesProvider>();
    final all = (await provider.notes.getEverything())
        .where((n) => !n.isDeleted && !n.isArchived)
        .toList();
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final monthAgo = now.subtract(const Duration(days: 30));

    final catCount = <int, int>{};
    final tagCount = <String, int>{};
    var uncategorized = 0, untagged = 0, newThisWeek = 0, needReview = 0,
        locked = 0;
    for (final n in all) {
      if (n.createdAt.isAfter(weekAgo)) newThisWeek++;
      if (n.updatedAt.isBefore(monthAgo)) needReview++;
      if (n.isLocked) locked++;
      if (n.categoryId == null) {
        uncategorized++;
      } else {
        catCount[n.categoryId!] = (catCount[n.categoryId!] ?? 0) + 1;
      }
      if (n.tags.isEmpty) untagged++;
      for (final t in n.tags) {
        tagCount[t] = (tagCount[t] ?? 0) + 1;
      }
    }

    var topCat = '—', topCount = 0;
    catCount.forEach((id, c) {
      if (c > topCount) {
        topCount = c;
        topCat = provider.categoryById(id)?.name ?? '—';
      }
    });
    final topTags = tagCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (!mounted) return;
    setState(() {
      _total = all.length;
      _newThisWeek = newThisWeek;
      _uncategorized = uncategorized;
      _untagged = untagged;
      _needReview = needReview;
      _locked = locked;
      _topCategory = topCat;
      _topCategoryCount = topCount;
      _topTags = topTags.take(8).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, 'الملخّص الأسبوعي'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    _stat('جديدة هذا الأسبوع', '$_newThisWeek', Icons.fiber_new,
                        Colors.green),
                    const SizedBox(width: 12),
                    _stat('إجمالي الملاحظات', '$_total',
                        Icons.sticky_note_2_outlined, Colors.blue),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _stat('بلا تصنيف', '$_uncategorized', Icons.folder_off,
                        Colors.orange),
                    const SizedBox(width: 12),
                    _stat('بلا وسوم', '$_untagged', Icons.label_off,
                        Colors.purple),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _stat('تحتاج مراجعة', '$_needReview', Icons.history,
                        Colors.red, hint: 'لم تُعدّل منذ ٣٠ يومًا'),
                    const SizedBox(width: 12),
                    _stat('مقفلة', '$_locked', Icons.lock, Colors.teal),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: const Text('أكثر تصنيف استخدامًا'),
                    subtitle: Text('$_topCategory ($_topCategoryCount)'),
                  ),
                ),
                const SizedBox(height: 8),
                if (_topTags.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
                    child: Text('أكثر الوسوم استخدامًا',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in _topTags)
                        Chip(label: Text('#${e.key} (${e.value})')),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color,
      {String? hint}) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(value,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              if (hint != null)
                Text(hint,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Theme.of(context).hintColor)),
            ],
          ),
        ),
      ),
    );
  }
}
