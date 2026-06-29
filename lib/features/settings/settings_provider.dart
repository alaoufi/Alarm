import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/enums.dart';
import '../../services/notification_service.dart';

/// مكان زرّ صفحة «معلومات عامة».
enum InfoPlacement { tab, menu, drawer }

/// إعدادات المظهر واللغة والعرض. تُحفظ محليًا في SharedPreferences.
class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = AppColors.defaultSeed;
  double _fontScale = 1.0;
  String _fontFamily = 'Cairo';
  bool _hideSelectionMenu = false;
  bool _dynamicColor = false; // ألوان النظام (Dynamic Color) على أندرويد 12+
  bool _compactCards = false; // عرض مدمج لبطاقات الملاحظات
  InfoPlacement _infoPlacement = InfoPlacement.tab;
  NoteLayout _layout = NoteLayout.grid;
  Locale _locale = const Locale('ar'); // عربي افتراضيًّا (تطبيق عربيّ ⇒ اتجاه RTL)
  String _alarmTone = 'ocean'; // Calm Tide افتراضيًّا
  int _snoozeMinutes = 10; // مدّة الغفوة بالدقائق (0 = بلا غفوة)
  bool _morningBriefing = false; // موجز صباحيّ يوميّ بعدد التذكيرات
  int _briefingHour = 8; // ساعة الموجز الصباحيّ
  int _briefingMinute = 0; // دقيقة الموجز الصباحيّ
  bool _autoRaiseVolume = true; // رفع صوت المنبّه تلقائيًّا عند الصامت/المنخفض
  bool _gradualVolume = false; // رفع صوت المنبّه بالتدرّج
  // «لا يُفوَّت» قبل إيقاف المنبّه: 0 = معطّل · 1 = أرقام (مسألة حساب) · 2 = كتابة كلمة.
  int _dismissChallenge = 0;
  int _defaultPreAlert = 0; // تنبيه قبل الوقت الافتراضي بالدقائق (0 = بلا)
  String? _customToneUri; // رابط نغمة مخصّصة من الجهاز (عند alarmTone=custom)
  String? _customToneTitle; // اسم النغمة المخصّصة للعرض
  int _customToneSeq = 0; // معرّف متزايد لقناة النغمة المخصّصة
  Set<String> _favoriteTones = {}; // النغمات المفضّلة

  // ---- الافتراضي للملاحظات الجديدة ----
  int? _defaultNoteColor; // null = اللون الافتراضي للسمة
  String? _defaultGradient; // تدرّج لوني افتراضي (مُرمَّز) أو null
  int _defaultBgStyle = 0; // 0..7 (نمط صفحة الملاحظة)
  String _noteFontFamily = 'Cairo'; // خط متن الملاحظة
  double _noteFontSize = 16; // حجم خط المتن
  double _noteLineHeight = 1.6; // تباعد الأسطر (مضاعف ارتفاع السطر)
  // أزرار شريط التنسيق المخفية (بمعرّفاتها) — تخصيص الشريط لتقصيره.
  Set<String> _hiddenTools = {};
  // ترتيب أزرار شريط التنسيق (بمعرّفاتها) — يحدّده المستخدم بالسحب والإفلات.
  List<String> _toolOrder = toolbarTools.keys.toList();
  // ---- تنسيق تسطير الصفحة ----
  double _ruleThickness = 1.0; // سماكة الأسطر
  double _ruleOpacity = 0.12; // شفافية الأسطر (0..1)
  bool _ruleOnLine = true; // الكتابة على السطر (true) أو بين السطرين (false)
  bool _privacyMode = false; // إخفاء معاينات الملاحظات بسرعة

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  double get fontScale => _fontScale;
  String get fontFamily => _fontFamily;
  bool get hideSelectionMenu => _hideSelectionMenu;
  bool get dynamicColor => _dynamicColor;
  bool get compactCards => _compactCards;
  InfoPlacement get infoPlacement => _infoPlacement;
  NoteLayout get layout => _layout;
  Locale get locale => _locale;
  String get alarmTone => _alarmTone;
  int get snoozeMinutes => _snoozeMinutes;
  bool get morningBriefing => _morningBriefing;
  int get briefingHour => _briefingHour;
  int get briefingMinute => _briefingMinute;
  bool get autoRaiseVolume => _autoRaiseVolume;
  /// 0 = معطّل · 1 = أرقام · 2 = كتابة كلمة.
  int get dismissChallenge => _dismissChallenge;
  bool get mathToDismiss => _dismissChallenge != 0; // توافق خلفيّ.
  bool get gradualVolume => _gradualVolume;
  int get defaultPreAlert => _defaultPreAlert;
  String? get customToneUri => _customToneUri;
  String? get customToneTitle => _customToneTitle;
  Set<String> get favoriteTones => _favoriteTones;
  bool isFavoriteTone(String id) => _favoriteTones.contains(id);

  Future<void> toggleFavoriteTone(String id) async {
    if (!_favoriteTones.add(id)) _favoriteTones.remove(id);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_tones', _favoriteTones.toList());
  }

  int? get defaultNoteColor => _defaultNoteColor;
  String? get defaultGradient => _defaultGradient;
  int get defaultBgStyle => _defaultBgStyle;
  String get noteFontFamily => _noteFontFamily;
  double get noteFontSize => _noteFontSize;
  double get noteLineHeight => _noteLineHeight;

  /// هل زرّ شريط التنسيق [id] ظاهر؟ (الافتراضي: كل الأزرار ظاهرة).
  bool isToolVisible(String id) => !_hiddenTools.contains(id);

  /// ترتيب أزرار شريط التنسيق كما حدّده المستخدم (كلّها، ظاهرها ومخفيّها).
  List<String> get toolOrder => List.unmodifiable(_toolOrder);

  /// ينقل الأداة [id] خطوة لأعلى (مبكّرًا) أو لأسفل (متأخّرًا) في الترتيب.
  Future<void> moveTool(String id, {required bool up}) async {
    final i = _toolOrder.indexOf(id);
    if (i < 0) return;
    final j = up ? i - 1 : i + 1;
    if (j < 0 || j >= _toolOrder.length) return;
    final item = _toolOrder.removeAt(i);
    _toolOrder.insert(j, item);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kToolOrder, _toolOrder);
  }

  /// أزرار شريط التنسيق القابلة للإظهار/الإخفاء: المعرّف ← الاسم المعروض.
  /// (الترتيب هو ترتيب ظهورها في شاشة الإعدادات.)
  static const toolbarTools = <String, String>{
    'undo': 'تراجع',
    'redo': 'إعادة',
    'voice': 'إملاء صوتي',
    'font': 'نوع الخط',
    'size': 'حجم الخط',
    'bold': 'غامق',
    'italic': 'مائل',
    'underline': 'تسطير',
    'strike': 'شطب',
    'color': 'لون الخط',
    'highlight': 'تظليل الخط',
    'header': 'العناوين',
    'ul': 'قائمة نقطية',
    'ol': 'قائمة رقمية',
    'quote': 'اقتباس',
    'align': 'المحاذاة',
    'lineSpacing': 'تباعد الأسطر',
    'clearFormat': 'مسح التنسيق',
    'pasteMenu': 'زرّ قائمة النسخ/اللصق',
    'export': 'تصدير (PDF/Word)',
  };
  double get ruleThickness => _ruleThickness;
  double get ruleOpacity => _ruleOpacity;
  bool get ruleOnLine => _ruleOnLine;
  bool get privacyMode => _privacyMode;

  /// الخطوط مرتّبة حسب العائلة (نسخ، كوفي، نستعليق/فارسي، عصري، زخرفي) مع اسم
  /// عربيّ لكل خط — تُستخدم في قوائم اختيار الخط (الواجهة والمتن).
  static const List<(String, List<String>)> fontGroups = [
    ('نسخ', [
      'Noto Naskh Arabic',
      'Amiri',
      'Amiri Quran',
      'Scheherazade New',
      'Lateef',
      'Harmattan',
      'Markazi Text',
      'Alkalami',
    ]),
    ('كوفي', [
      'Reem Kufi',
      'Kufam',
      'Noto Kufi Arabic',
      'Qahiri',
    ]),
    ('نستعليق وفارسي', [
      'Noto Nastaliq Urdu',
      'Gulzar',
      'Mirza',
      'Vazirmatn',
    ]),
    ('عصري', [
      'Cairo',
      'Tajawal',
      'Almarai',
      'IBM Plex Sans Arabic',
      'Readex Pro',
      'Mada',
      'Changa',
      'El Messiri',
      'Noto Sans Arabic',
      'Rubik',
    ]),
    ('زخرفي وعناوين', [
      'Aref Ruqaa',
      'Aref Ruqaa Ink',
      'Lalezar',
      'Rakkas',
      'Jomhuria',
      'Lemonada',
      'Marhey',
      'Baloo Bhaijaan 2',
      'Katibeh',
    ]),
  ];

  /// اسم العرض العربيّ لكل خط (نفس الأسماء الظاهرة في شريط تنسيق المحرّر).
  static const Map<String, String> fontLabels = {
    'Noto Naskh Arabic': 'نسخ',
    'Amiri': 'أميري',
    'Amiri Quran': 'نسخ قرآني',
    'Scheherazade New': 'شهرزاد',
    'Lateef': 'لطيف',
    'Harmattan': 'هرمتان',
    'Markazi Text': 'مركزي',
    'Alkalami': 'القلمي',
    'Reem Kufi': 'كوفي',
    'Kufam': 'كُفام',
    'Noto Kufi Arabic': 'نوتو كوفي',
    'Qahiri': 'قاهري',
    'Noto Nastaliq Urdu': 'نستعليق',
    'Gulzar': 'كلزار',
    'Mirza': 'ميرزا',
    'Vazirmatn': 'فزيرمتن',
    'Cairo': 'القاهرة',
    'Tajawal': 'تجوال',
    'Almarai': 'المراعي',
    'IBM Plex Sans Arabic': 'IBM Plex',
    'Readex Pro': 'ريدكس',
    'Mada': 'مدى',
    'Changa': 'شنقا',
    'El Messiri': 'المصري',
    'Noto Sans Arabic': 'نوتو سانس',
    'Rubik': 'روبيك',
    'Aref Ruqaa': 'رقعة',
    'Aref Ruqaa Ink': 'رقعة حبر',
    'Lalezar': 'لاله‌زار',
    'Rakkas': 'ركّاس',
    'Jomhuria': 'جمهورية',
    'Lemonada': 'ليمونادة',
    'Marhey': 'مرحى',
    'Baloo Bhaijaan 2': 'بالو',
    'Katibeh': 'كتيبة',
  };

  /// قائمة مسطّحة بكل الخطوط (بترتيب العائلات).
  static final List<String> fontFamilies = [
    for (final g in fontGroups) ...g.$2,
  ];

  /// الاسم العربيّ للخط (أو اسمه الأصليّ إن لم يوجد).
  static String fontLabel(String family) => fontLabels[family] ?? family;

  static const _kMode = 'theme_mode';
  static const _kSeed = 'seed_color';
  static const _kFont = 'font_scale';
  static const _kFontFamily = 'font_family';
  static const _kHideSelMenu = 'hide_selection_menu';
  static const _kDynamicColor = 'dynamic_color';
  static const _kCompactCards = 'compact_cards';
  static const _kInfoPlacement = 'info_placement';
  static const _kLayout = 'note_layout';
  static const _kLocale = 'locale';
  static const _kTone = 'alarm_tone';
  static const _kCustomToneUri = 'custom_tone_uri';
  static const _kCustomToneTitle = 'custom_tone_title';
  static const _kCustomToneSeq = 'custom_tone_seq';
  static const _kDefColor = 'def_note_color';
  static const _kDefGradient = 'def_gradient';
  static const _kDefBgStyle = 'def_bg_style';
  static const _kNoteFont = 'note_font_family';
  static const _kNoteFontSize = 'note_font_size';
  static const _kNoteLineHeight = 'note_line_height';
  static const _kHiddenTools = 'hidden_toolbar_tools';
  static const _kToolOrder = 'toolbar_order';
  static const _kRuleThickness = 'rule_thickness';
  static const _kRuleOpacity = 'rule_opacity';
  static const _kRuleOnLine = 'rule_on_line';
  static const _kPrivacyMode = 'privacy_mode';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_kMode);
    _themeMode = switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final seed = prefs.getInt(_kSeed);
    if (seed != null) _seedColor = Color(seed);
    _fontScale = prefs.getDouble(_kFont) ?? 1.0;
    final fam = prefs.getString(_kFontFamily);
    if (fam != null && fontFamilies.contains(fam)) _fontFamily = fam;
    _hideSelectionMenu = prefs.getBool(_kHideSelMenu) ?? false;
    _dynamicColor = prefs.getBool(_kDynamicColor) ?? false;
    _compactCards = prefs.getBool(_kCompactCards) ?? false;
    final ip = prefs.getString(_kInfoPlacement);
    _infoPlacement = InfoPlacement.values
        .firstWhere((e) => e.name == ip, orElse: () => InfoPlacement.tab);
    _layout = prefs.getString(_kLayout) == 'list' ? NoteLayout.list : NoteLayout.grid;
    _locale = Locale(prefs.getString(_kLocale) ?? 'ar'); // افتراضي عربي (RTL)
    _alarmTone = prefs.getString(_kTone) ?? 'ocean';
    _favoriteTones = (prefs.getStringList('favorite_tones') ?? const []).toSet();
    _snoozeMinutes = prefs.getInt('snooze_minutes') ?? 10;
    _morningBriefing = prefs.getBool('morning_briefing') ?? false;
    _briefingHour = prefs.getInt('briefing_hour') ?? 8;
    _briefingMinute = prefs.getInt('briefing_minute') ?? 0;
    _autoRaiseVolume = prefs.getBool('auto_raise_volume') ?? true;
    _gradualVolume = prefs.getBool('gradual_volume') ?? false;
    // ترقية: الإعداد القديم (مفتاح منطقيّ) ⇒ أرقام، وإلّا القيمة الجديدة.
    _dismissChallenge = prefs.getInt('dismiss_challenge') ??
        ((prefs.getBool('math_to_dismiss') ?? false) ? 1 : 0);
    _defaultPreAlert = prefs.getInt('default_pre_alert') ?? 0;
    NotificationService.instance.snoozeMinutes = _snoozeMinutes;
    _customToneUri = prefs.getString(_kCustomToneUri);
    _customToneTitle = prefs.getString(_kCustomToneTitle);
    _customToneSeq = prefs.getInt(_kCustomToneSeq) ?? 0;
    NotificationService.instance.tone = _alarmTone;
    if (_alarmTone == 'custom' && _customToneUri != null) {
      await NotificationService.instance
          .setCustomTone(_customToneUri, seq: _customToneSeq);
    }

    // اللون الافتراضي الأوّلي للملاحظات الجديدة = أصفر دافئ (#FCE49E)، ويبقى
    // قابلًا للتغيير من الإعدادات (وعند الضبط يُحفظ مفتاحه).
    _defaultNoteColor = prefs.containsKey(_kDefColor)
        ? prefs.getInt(_kDefColor)
        : 0xFFFCE49E;
    // الخلفية الافتراضية لأي تثبيت جديد = تدرّج أصفر دافئ من الأعلى
    // (FCE49E → EFE6C0 → E8E49E). المفتاح غائب ⇒ تثبيت جديد ⇒ التدرّج؛ قيمة
    // فارغة ⇒ ألغى المستخدم التدرّج صراحةً ⇒ بلا تدرّج؛ وإلا ⇒ تدرّجه المحفوظ.
    if (prefs.containsKey(_kDefGradient)) {
      final g = prefs.getString(_kDefGradient);
      _defaultGradient = (g == null || g.isEmpty) ? null : g;
    } else {
      _defaultGradient = '0:${0xFFFCE49E},${0xFFEFE6C0},${0xFFE8E49E}';
    }
    _defaultBgStyle = prefs.getInt(_kDefBgStyle) ?? 0;
    final nf = prefs.getString(_kNoteFont);
    if (nf != null && fontFamilies.contains(nf)) _noteFontFamily = nf;
    _noteFontSize = prefs.getDouble(_kNoteFontSize) ?? 16;
    _noteLineHeight = prefs.getDouble(_kNoteLineHeight) ?? 1.6;
    _hiddenTools = (prefs.getStringList(_kHiddenTools) ?? const []).toSet();
    // الترتيب المحفوظ مع مواءمته لأي أدوات أُضيفت/أُزيلت في التحديثات: نُبقي
    // المعروفة بترتيب المستخدم ثم نُلحق أيّ أداة جديدة لم تكن محفوظة.
    final valid = toolbarTools.keys.toList();
    final saved = prefs.getStringList(_kToolOrder);
    if (saved == null) {
      _toolOrder = valid;
    } else {
      final order = saved.where(valid.contains).toList();
      for (final k in valid) {
        if (!order.contains(k)) order.add(k);
      }
      _toolOrder = order;
    }
    _ruleThickness = prefs.getDouble(_kRuleThickness) ?? 1.0;
    _ruleOpacity = prefs.getDouble(_kRuleOpacity) ?? 0.12;
    _ruleOnLine = prefs.getBool(_kRuleOnLine) ?? true;
    _privacyMode = prefs.getBool(_kPrivacyMode) ?? false;

    notifyListeners();
  }

  Future<void> setPrivacyMode(bool v) async {
    _privacyMode = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrivacyMode, v);
  }

  Future<void> setDefaultNoteColor(int? color) async {
    _defaultNoteColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_kDefColor);
    } else {
      await prefs.setInt(_kDefColor, color);
    }
  }

  Future<void> setDefaultGradient(String? gradient) async {
    _defaultGradient = gradient;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // فارغ = «بلا تدرّج» صراحةً (نميّزه عن «لم يُضبط» كي لا يعود التدرّج الافتراضي).
    await prefs.setString(_kDefGradient, gradient ?? '');
  }

  Future<void> setDefaultBgStyle(int style) async {
    _defaultBgStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDefBgStyle, style);
  }

  Future<void> setNoteFontFamily(String family) async {
    _noteFontFamily = family;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNoteFont, family);
  }

  Future<void> setNoteFontSize(double size) async {
    _noteFontSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kNoteFontSize, size);
  }

  Future<void> setNoteLineHeight(double h) async {
    _noteLineHeight = h;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kNoteLineHeight, h);
  }

  /// إظهار/إخفاء زرّ شريط التنسيق [id].
  Future<void> setToolVisible(String id, bool visible) async {
    if (visible) {
      _hiddenTools.remove(id);
    } else {
      _hiddenTools.add(id);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kHiddenTools, _hiddenTools.toList());
  }

  Future<void> setRuleThickness(double t) async {
    _ruleThickness = t;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kRuleThickness, t);
  }

  Future<void> setRuleOpacity(double o) async {
    _ruleOpacity = o;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kRuleOpacity, o);
  }

  Future<void> setRuleOnLine(bool v) async {
    _ruleOnLine = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRuleOnLine, v);
  }

  Future<void> setAlarmTone(String tone) async {
    _alarmTone = tone;
    NotificationService.instance.tone = tone;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTone, tone);
  }

  /// مدّة الغفوة بالدقائق (0 = بلا غفوة).
  Future<void> setSnoozeMinutes(int minutes) async {
    _snoozeMinutes = minutes;
    NotificationService.instance.snoozeMinutes = minutes;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('snooze_minutes', minutes);
  }

  /// رفع صوت المنبّه تلقائيًّا عند ظهوره (يتجاوز الصامت/الصوت المنخفض).
  Future<void> setAutoRaiseVolume(bool v) async {
    _autoRaiseVolume = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_raise_volume', v);
  }

  /// تعيين نوع تحدّي الإيقاف (0 معطّل · 1 أرقام · 2 كلمة).
  Future<void> setDismissChallenge(int v) async {
    _dismissChallenge = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dismiss_challenge', v);
    await prefs.setBool('math_to_dismiss', v != 0); // توافق خلفيّ.
  }

  /// توافق خلفيّ: تفعيل/إيقاف سريع (يفترض الأرقام عند التفعيل).
  Future<void> setMathToDismiss(bool v) async =>
      setDismissChallenge(v ? 1 : 0);

  Future<void> setMorningBriefing(bool v) async {
    _morningBriefing = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('morning_briefing', v);
  }

  Future<void> setBriefingTime(int hour, int minute) async {
    _briefingHour = hour;
    _briefingMinute = minute;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('briefing_hour', hour);
    await prefs.setInt('briefing_minute', minute);
  }

  /// رفع صوت المنبّه بالتدرّج (يبدأ منخفضًا ويعلو تدريجيًّا).
  Future<void> setGradualVolume(bool v) async {
    _gradualVolume = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gradual_volume', v);
  }

  /// تنبيه قبل الوقت الافتراضي (بالدقائق، 0 = بلا) — يُستخدم كقيمة أولية للتنبيه الجديد.
  Future<void> setDefaultPreAlert(int minutes) async {
    _defaultPreAlert = minutes;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('default_pre_alert', minutes);
  }

  /// يضبط نغمة مخصّصة مختارة من نغمات الجهاز ([uri] رابطها، [title] اسمها).
  Future<void> setCustomTone(String uri, String? title) async {
    _customToneSeq++; // معرّف قناة جديد عند كل تغيير (قنوات أندرويد ثابتة الصوت)
    _customToneUri = uri;
    _customToneTitle = title;
    _alarmTone = 'custom';
    await NotificationService.instance.setCustomTone(uri, seq: _customToneSeq);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTone, 'custom');
    await prefs.setString(_kCustomToneUri, uri);
    await prefs.setInt(_kCustomToneSeq, _customToneSeq);
    if (title != null) {
      await prefs.setString(_kCustomToneTitle, title);
    } else {
      await prefs.remove(_kCustomToneTitle);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, mode.name);
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeed, color.value);
  }

  Future<void> setFontScale(double scale) async {
    _fontScale = scale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFont, scale);
  }

  Future<void> setFontFamily(String family) async {
    _fontFamily = family;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFontFamily, family);
  }

  Future<void> setHideSelectionMenu(bool hide) async {
    _hideSelectionMenu = hide;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideSelMenu, hide);
  }

  Future<void> setDynamicColor(bool on) async {
    _dynamicColor = on;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDynamicColor, on);
  }

  Future<void> setCompactCards(bool on) async {
    _compactCards = on;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCompactCards, on);
  }

  Future<void> setInfoPlacement(InfoPlacement placement) async {
    _infoPlacement = placement;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInfoPlacement, placement.name);
  }

  Future<void> setLayout(NoteLayout layout) async {
    _layout = layout;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLayout, layout.name);
  }

  void toggleLayout() {
    setLayout(_layout == NoteLayout.grid ? NoteLayout.list : NoteLayout.grid);
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocale, locale.languageCode);
  }
}
