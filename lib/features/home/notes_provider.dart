// نخفي Category الخاصة بـ Flutter (تعليق توضيحي) لتفادي التعارض مع نموذجنا.
import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../../data/models/enums.dart';

import '../../data/models/category.dart';
import '../../data/models/checklist_item.dart';
import '../../data/models/note.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/note_repository.dart';
import '../../services/file_service.dart';
import '../../services/widget_service.dart';

/// الحالة المركزية للملاحظات والتصنيفات.
class NotesProvider extends ChangeNotifier {
  final NoteRepository notes;
  final CategoryRepository categoriesRepo;

  NotesProvider(this.notes, this.categoriesRepo);

  List<Note> _items = [];
  List<Category> _categories = [];
  bool _loading = true;
  bool _dbError = false; // تعذّر فتح القاعدة (لا تُعرض كفارغة)

  int? _filterCategoryId; // null = الكل
  String? _filterTag;
  String _search = '';
  NoteSort _sort = NoteSort.updatedDesc;
  int? _inboxId; // تصنيف «الوارد» الافتراضي للإضافة السريعة

  int? get inboxId => _inboxId;

  // فلاتر البحث المتقدّم.
  NoteType? fType;
  bool fPinned = false,
      fLocked = false,
      fImage = false,
      fAudio = false,
      fPdf = false,
      fFav = false;
  DateTime? fFrom, fTo;

  bool get hasAdvancedFilter =>
      fType != null ||
      fPinned ||
      fLocked ||
      fImage ||
      fAudio ||
      fPdf ||
      fFav ||
      fFrom != null ||
      fTo != null;

  Future<void> applyAdvancedFilter() async => refresh();

  void clearAdvancedFilter() {
    fType = null;
    fPinned = fLocked = fImage = fAudio = fPdf = fFav = false;
    fFrom = fTo = null;
    refresh();
  }

  List<Note> get items => _items;
  List<Category> get categories => _categories;
  bool get loading => _loading;
  bool get dbError => _dbError;
  int? get filterCategoryId => _filterCategoryId;
  String? get filterTag => _filterTag;
  String get search => _search;
  NoteSort get sort => _sort;

  List<Note> get pinned => _items.where((n) => n.isPinned).toList();
  List<Note> get unpinned => _items.where((n) => !n.isPinned).toList();

  Future<void> init() async {
    await ensureInbox();
    await Future.wait([loadCategories(), refresh(), _loadTagColors()]);
    await notes.purgeOldTrash();
  }

  /// ألوان الوسوم التي اختارها المستخدم (الاسم ⇒ لون). الوسوم بلا لون مختار
  /// (0) تُحسب تلقائيًّا من اسمها، فلا نخزّنها هنا.
  Map<String, int> _tagColors = {};
  Map<String, int> get tagColors => _tagColors;

  Set<int> _reminderNoteIds = {};
  bool noteHasReminder(int? id) => id != null && _reminderNoteIds.contains(id);

  Map<int, int> _categoryCounts = {};
  int _allCount = 0;
  int get allCount => _allCount;
  int categoryCount(int? id) => id == null ? 0 : (_categoryCounts[id] ?? 0);

  Future<void> _loadTagColors() async {
    final list = await notes.getAllTagsWithColors();
    _tagColors = {
      for (final t in list)
        if (t.color != 0) t.name: t.color,
    };
    notifyListeners();
  }

  /// يضمن وجود تصنيف «الوارد» (يظهر أولًا) ويحفظ معرّفه.
  Future<void> ensureInbox() async {
    _inboxId = await categoriesRepo.ensureByName('الوارد',
        color: 0xFF42A5F5, iconCode: 12, position: -1);
  }

  /// يفتح ملاحظة اليوم (يُنشئها بقالب إن لم تكن موجودة) ويعيد معرّفها.
  Future<int> openOrCreateDaily() async {
    final title = dailyTitle(DateTime.now());
    final existing = await notes.findByTitle(title);
    if (existing != null) return existing.id!;
    const body = '• أهم شيء اليوم:\n\n'
        '• مهام اليوم:\n- \n\n'
        '• ملاحظات سريعة:\n\n'
        '• أشياء لا أنساها:\n\n'
        '• ملخص اليوم:\n';
    final note = Note.create(type: NoteType.text, categoryId: _inboxId)
        .copyWith(title: title, content: body);
    final id = await notes.upsertNote(note);
    await refresh();
    return id;
  }

  static const _arDays = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس',
    'الجمعة', 'السبت', 'الأحد',
  ];
  static const _arMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  /// عنوان ملاحظة اليوم: «الاثنين 8 يونيو 2026».
  static String dailyTitle(DateTime d) {
    final day = _arDays[(d.weekday - 1) % 7];
    return '$day ${d.day} ${_arMonths[d.month - 1]} ${d.year}';
  }

  Future<void> loadCategories() async {
    try {
      _categories = await categoriesRepo.getAll();
    } catch (_) {/* تعذّر فتح القاعدة مؤقّتًا — لا نمسح القائمة القديمة */}
    notifyListeners();
  }

  /// يعيد تحميل قائمة الملاحظات.
  ///
  /// [silent]: عند `true` لا نُظهر مؤشّر التحميل (نُبقي القائمة الحالية ظاهرة
  /// ونحدّثها في مكانها عند الانتهاء) — يُستخدم عند الرجوع من المحرّر كي يكون
  /// الانتقال سلسًا بلا وميض شاشة تحميل.
  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    try {
      _items = await notes.getNotes(
        categoryId: _filterCategoryId,
        tag: _filterTag,
        search: _search,
        sort: _sort,
        onlyFavorites: fFav,
        type: fType,
        onlyPinned: fPinned,
        onlyLocked: fLocked,
        hasImage: fImage,
        hasAudio: fAudio,
        hasPdf: fPdf,
        from: fFrom,
        to: fTo,
      );
      _dbError = false;
      _reminderNoteIds = await notes.noteIdsWithReminders();
      final hc = await notes.homeCounts();
      _categoryCounts = hc.byCategory;
      _allCount = hc.total;
    } catch (_) {
      // **حماية:** تعذّر فتح القاعدة (غالبًا مؤقّت — مفتاح/تخزين). لا نعرضها
      // كـ«فارغة» (يُربك ويخاطر بقرار حذف/استعادة خاطئ)، ولا نمسح القائمة القديمة.
      _dbError = true;
    }
    _loading = false;
    notifyListeners();
    // تحديث الويدجت بآخر/أهم ملاحظة (فقط عند نجاح القراءة).
    if (!_dbError) WidgetService.instance.update(_items);
  }

  Future<void> setCategoryFilter(int? categoryId) async {
    _filterCategoryId = categoryId;
    _filterTag = null;
    await refresh();
  }

  Future<void> setTagFilter(String? tag) async {
    _filterTag = tag;
    _filterCategoryId = null;
    await refresh();
  }

  Timer? _searchDebounce;

  /// بحث مؤجَّل (debounce) لتفادي إعادة الاستعلام مع كل حرف — أسرع وأسلس.
  void setSearch(String query) {
    _search = query;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), refresh);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> setSort(NoteSort sort) async {
    _sort = sort;
    await refresh();
  }

  Category? categoryById(int? id) {
    if (id == null) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ---- إجراءات الملاحظات ----

  /// يحفظ الملاحظة (والقائمة إن وُجدت) ويعيد المعرّف.
  ///
  /// [reload]: عند `false` لا يُعاد تحميل كامل قائمة الملاحظات — يُستخدم أثناء
  /// التحرير المتكرّر (حفظ مؤجَّل لكل سطر/تعديل) لتفادي البطء مع مئات الملاحظات.
  /// الشاشة الفاتحة للمحرّر تتولّى تحديث القائمة مرّة واحدة عند الرجوع.
  Future<int> saveNote(Note note,
      {List<ChecklistItem>? checklist, bool reload = true}) async {
    final id = await notes.upsertNote(note);
    if (checklist != null) {
      await notes.saveChecklist(id, checklist);
    }
    if (reload) await refresh();
    return id;
  }

  Future<void> togglePin(Note note) async {
    await notes.togglePin(note);
    await refresh();
  }

  Future<void> toggleFavorite(Note note) async {
    await notes.toggleFavorite(note);
    await refresh();
  }

  Future<List<Note>> getFavorites() => notes.getNotes(onlyFavorites: true);
  Future<List<Note>> getLocked() => notes.getLocked();

  Future<void> setArchived(Note note, bool archived) async {
    await notes.setArchived(note.id!, archived);
    await refresh();
  }

  Future<void> setColor(Note note, int? color) async {
    await notes.setColor(note.id!, color);
    await refresh();
  }

  Future<void> setLocked(Note note, bool locked) async {
    await notes.setLocked(note.id!, locked);
    await refresh();
  }

  // ===== عمليات جماعية (التحديد المتعدّد) — تحديث واحد في النهاية =====
  Future<void> bulkArchive(Iterable<int> ids) async {
    for (final id in ids) {
      await notes.setArchived(id, true);
    }
    await refresh();
  }

  Future<void> bulkTrash(Iterable<int> ids) async {
    for (final id in ids) {
      await notes.moveToTrash(id);
    }
    await refresh();
  }

  Future<void> bulkPin(Iterable<int> ids, bool pinned) async {
    for (final id in ids) {
      await notes.setPinned(id, pinned);
    }
    await refresh();
  }

  Future<void> bulkSetCategory(Iterable<int> ids, int? categoryId) async {
    for (final id in ids) {
      await notes.setCategory(id, categoryId);
    }
    await refresh();
  }

  Future<void> moveToTrash(Note note) async {
    await notes.moveToTrash(note.id!);
    await refresh();
  }

  Future<void> duplicate(Note note) async {
    await notes.duplicate(note.id!);
    await refresh();
  }

  // ---- التصنيفات ----

  Future<void> addCategory(Category category) async {
    await categoriesRepo.insert(category);
    await loadCategories();
  }

  Future<void> updateCategory(Category category) async {
    await categoriesRepo.update(category);
    await loadCategories();
    await refresh();
  }

  Future<void> deleteCategory(int id) async {
    if (_filterCategoryId == id) _filterCategoryId = null;
    await categoriesRepo.delete(id);
    await loadCategories();
    await refresh();
  }

  Future<void> reorderCategories(List<Category> ordered) async {
    await categoriesRepo.reorder(ordered);
    await loadCategories();
  }

  Future<int> countByCategory(int categoryId) => notes.countByCategory(categoryId);

  // ---- سلة المحذوفات ----

  Future<List<Note>> getTrash() => notes.getTrash();
  Future<List<Note>> getArchived() => notes.getArchived();

  Future<void> restore(int id) async {
    await notes.restoreFromTrash(id);
    await refresh();
  }

  Future<void> deleteForever(Note note) async {
    // حذف المرفقات المرتبطة فعليًا من القرص.
    await FileService.instance.deleteIfExists(note.imagePath);
    await FileService.instance.deleteIfExists(note.audioPath);
    await FileService.instance.deleteIfExists(note.pdfPath);
    await FileService.instance.deleteIfExists(note.drawingPath);
    await notes.deletePermanently(note.id!);
    await refresh();
  }

  Future<void> emptyTrash() async {
    final trash = await notes.getTrash();
    for (final n in trash) {
      await FileService.instance.deleteIfExists(n.imagePath);
      await FileService.instance.deleteIfExists(n.audioPath);
      await FileService.instance.deleteIfExists(n.pdfPath);
      await FileService.instance.deleteIfExists(n.drawingPath);
    }
    await notes.emptyTrash();
    await refresh();
  }

  Future<List<String>> allTags() => notes.getAllTags();

  Future<List<({String name, int color})>> allTagsWithColors() =>
      notes.getAllTagsWithColors();

  Future<void> setTagColor(String name, int color) async {
    await notes.setTagColor(name, color);
    await _loadTagColors();
    await refresh();
  }
}
