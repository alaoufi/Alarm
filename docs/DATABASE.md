# قاعدة البيانات — مذكراتي

قاعدة **SQLite مشفّرة بالكامل عبر SQLCipher** (حزمة `sqflite_sqlcipher`)، تُفتح بمفتاح
من `lib/data/database/db_key.dart`. كل الجداول داخل الملفّ المشفّر على الجهاز فقط.

- **إصدار المخطّط الحاليّ:** `18` (الثابت `_dbVersion` في `app_database.dart`).
- **الترقية:** عبر `_onUpgrade` (سلسلة `ALTER TABLE`/جداول جديدة لكل إصدار) — لا تُفقد بيانات.
- **الإنشاء الأوّل:** `_onCreate` ينشئ الجداول والفهارس ويزرع التصنيفات الافتراضية.

تُولَّد النماذج (`lib/data/models/`) من/إلى صفوف هذه الجداول عبر `toMap()`/`fromMap()`،
والوصول كلّه عبر المستودعات (`lib/data/repositories/`).

---

## الجداول

### `categories` — التصنيفات
| العمود | النوع | ملاحظات |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| name | TEXT NOT NULL | اسم التصنيف |
| color | INTEGER NOT NULL | لون ARGB |
| icon_code | INTEGER NOT NULL | فهرس الأيقونة |
| position | INTEGER NOT NULL = 0 | ترتيب العرض |

افتراضيًّا تُزرع: شخصي، عمل، مهم، مواعيد، أفكار.

### `notes` — الملاحظات
| العمود | النوع | ملاحظات |
|---|---|---|
| id | INTEGER PK | |
| uuid | TEXT | معرّف عالميّ للمزامنة |
| title | TEXT = '' | العنوان |
| content | TEXT = '' | **Delta JSON** للنصّ الغنيّ (flutter_quill) |
| type | TEXT = 'text' | text/checklist/image/audio/pdf/drawing/password |
| color | INTEGER | لون خلفية (nullable) |
| is_pinned / is_favorite / is_archived / is_locked / is_deleted | INTEGER = 0 | أعلام |
| deleted_at | INTEGER | وقت الحذف (سلة المحذوفات) |
| category_id | INTEGER FK→categories | ON DELETE SET NULL |
| image_path / audio_path / pdf_path / drawing_path | TEXT | مسارات المرفقات |
| bg_style | INTEGER = 0 | نمط صفحة الملاحظة 0..7 |
| gradient | TEXT | تدرّج مُرمَّز `dir:c1,c2[,c3]` |
| rule_on_line / rule_thickness / rule_opacity / rule_line_height | INT/REAL | إعدادات التسطير (nullable) |
| created_at / updated_at | INTEGER NOT NULL | ملّي ثانية |

فهارس: `idx_notes_uuid`, `idx_notes_category`, `idx_notes_flags(is_deleted,is_archived)`.

### `checklist_items` — عناصر قوائم المهام
| العمود | النوع | ملاحظات |
|---|---|---|
| id | INTEGER PK | |
| note_id | INTEGER FK→notes | ON DELETE CASCADE |
| text | TEXT = '' | |
| is_done | INTEGER = 0 | |
| position | INTEGER = 0 | |
| is_task | INTEGER = 1 | عنصر مهمّة أم سطر نصّ |

### `tags` / `note_tags` — الوسوم (علاقة متعدّد‑لمتعدّد)
- `tags(id PK, name TEXT UNIQUE, color INTEGER = 0)`
- `note_tags(note_id, tag_id, PRIMARY KEY(note_id,tag_id))` — FKs CASCADE.

### `reminders` — التذكيرات (مرتبطة بملاحظة أو مستقلّة)
| العمود | النوع | ملاحظات |
|---|---|---|
| id | INTEGER PK | |
| note_id | INTEGER FK→notes | NULL = تنبيه مستقلّ، CASCADE |
| title | TEXT | عنوان التنبيه المستقلّ (الأدوية: `💊 الاسم \| الجرعة`) |
| time | INTEGER NOT NULL | ملّي ثانية |
| repeat | TEXT = 'once' | once/daily/weekly/monthly/yearly/hijriYearly |
| is_active | INTEGER = 1 | |
| notification_id | INTEGER NOT NULL | معرّف إشعار النظام |
| importance | TEXT = 'high' | low/medium/high/critical |
| pre_alerts | TEXT = '' | تنبيهات مسبقة (دقائق، مفصولة) |
| location | TEXT = '' | |
| attachment | TEXT = '' | |
| interval_days | INTEGER = 0 | كورس دواء: الفاصل بالأيام (= أيام الراحة + ١) |
| dose_count | INTEGER = 0 | عدد جرعات الكورس (0 = مستمرّ) |

فهرس: `idx_reminders_note`.

### `med_doses` — سجلّ جرعات الدواء الفعليّ
`id PK, name TEXT, dose TEXT, status TEXT = 'taken' (taken/missed), at INTEGER`.

### `reminder_log` — سجلّ التنبيهات المنفّذة
`id PK, reminder_id INTEGER, title TEXT, at INTEGER`.

### `info_entries` — قاعدة المعلومات الداخليّة
`id PK, main_specialty, sub_specialty, topic, brief, detail, notes, source, created_at`.
فهرس: `idx_info_specialty(main_specialty, sub_specialty)`.

---

## ملاحظات مهمّة للمطوّر
- **عند تغيير المخطّط:** ارفع `_dbVersion` وأضِف خطوة في `_onUpgrade` (لا تعدّل `_onCreate`
  وحده — المستخدمون الحاليّون لا يمرّون عليه). استخدم `ALTER TABLE … ADD COLUMN` أو إنشاء
  جدول جديد ونسخ البيانات (انظر مثال ترقية جدول `reminders` في الكود).
- **محتوى الملاحظة** مخزَّن Delta JSON؛ لاستخراج نصّ عاديّ استخدم `richToPlainText()`.
- **التشفير:** المفتاح في `db_key.dart`؛ لا تُسجِّله ولا تُصدِّره. النسخ الاحتياطيّة
  تُشفَّر مستقلًّا (AES‑256) عبر `encryption_service.dart`.
- **اتجاه السطر/البحث العربيّ:** أدوات في `lib/core/text/`.
