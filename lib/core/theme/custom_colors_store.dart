import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مكتبة ألوان مخصّصة يحفظها المستخدم (المكوّنة بالأرقام/المنتقي) — دائمة، كي لا
/// يُعيد تكوين نفس اللون في كل مرّة. تُعرض في منتقي ألوان الخلفية.
class CustomColorsStore {
  CustomColorsStore._();
  static final CustomColorsStore instance = CustomColorsStore._();

  static const _key = 'custom_note_colors';
  static const _max = 30;

  /// قيم ألوان (int) — الأحدث أولًا. يُحدَّث فتُعاد بناء الواجهة المستمعة.
  final ValueNotifier<List<int>> colors = ValueNotifier<List<int>>(<int>[]);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getStringList(_key) ?? const [];
      colors.value = raw
          .map((e) => int.tryParse(e))
          .whereType<int>()
          .toList();
    } catch (_) {/* تجاهل — نبدأ بقائمة فارغة */}
    _loaded = true;
  }

  Future<void> add(int value) async {
    final list = List<int>.of(colors.value)
      ..remove(value) // تفادي التكرار
      ..insert(0, value); // الأحدث أولًا
    if (list.length > _max) list.removeRange(_max, list.length);
    colors.value = list;
    await _persist(list);
  }

  Future<void> remove(int value) async {
    final list = List<int>.of(colors.value)..remove(value);
    colors.value = list;
    await _persist(list);
  }

  Future<void> _persist(List<int> list) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, list.map((e) => e.toString()).toList());
    } catch (_) {/* تجاهل فشل الكتابة */}
  }
}
