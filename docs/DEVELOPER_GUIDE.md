# دليل المطوّر — مذكراتي (Mudhakkarati / Alaoufi Notes)

تطبيق ملاحظات Flutter لأندرويد، **يعمل دون إنترنت بالكامل**، البيانات محليّة في SQLite
مشفّر (SQLCipher). هذا الدليل يجعلك تبني المشروع وتطوّره بسرعة. للوصف الموسّع راجع
`README.md`، ولقاعدة البيانات راجع `docs/DATABASE.md`.

---

## 1) المتطلّبات
- **Flutter** `>= 3.22` (Dart `>= 3.4`). يُنصح بالقناة `stable`.
- **Android SDK** + JDK 17. الحدّ الأدنى للجهاز: Android 8.0 (API 26).
- لا حاجة لأي خادم أو مفاتيح سحابيّة لتشغيل التطبيق.

## 2) التشغيل السريع
```bash
flutter pub get          # جلب الحزم
flutter test             # بوّابة الجودة (يجب أن تنجح كلّها قبل أي دفع/نشر)
flutter run              # تشغيل على جهاز/محاكي موصول
```

## 3) بناء APK / App Bundle
```bash
# APK لكل معماريّة (موصى به للتوزيع المباشر)
flutter build apk --release --split-per-abi
# الناتج: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# حزمة Google Play
flutter build appbundle --release
```
> ⚠️ مع `--split-per-abi` يضيف Flutter إزاحة معماريّة إلى `versionCode`، فلا تقارن
> التحديثات برقم البناء بل **باسم النسخة** (انظر `update_service.dart`).

## 4) بنية المشروع (`lib/`)
```
main.dart            تهيئة آمنة (runZonedGuarded) + حقن المزوّدات (MultiProvider)
app.dart             MaterialApp + الثيم + التوطين + البوّابات (Activation→AppLock)
core/                l10n (التوطين S)، theme، text (اتجاه السطر)، constants
data/
  models/            نماذج غير قابلة للتغيير (toMap/fromMap)
  database/          AppDatabase (SQLCipher) + db_key
  repositories/      وصول CRUD لكل كيان
features/<اسم>/      شاشات كل ميزة + مزوّداتها الخاصة
services/            خدمات مفردة (إشعارات، مزامنة، تشفير، تحديث، نسخ احتياطي…)
widgets/             عناصر واجهة مشتركة
```
**إدارة الحالة:** `provider`. ثلاثة مزوّدات عامّة: `SettingsProvider`، `NotesProvider`،
`RemindersProvider` (تُحقَن في `main.dart`).

## 5) قواعد ذهبيّة عند التطوير
- **اختبارات أولًا:** أي تغيير سلوك → حدّث/أضف اختبارًا في `test/`. CI يمنع النشر عند الفشل.
- **رقم الإصدار:** ارفع `version:` في `pubspec.yaml` مع كل تغيير يُراد نشره
  (الصيغة `X.Y.Z+BUILD`). يظهر في التحديث الذاتيّ.
- **enum التذكير:** إضافة قيمة لـ`ReminderRepeat` تكسر كل `switch` الشاملة — المُصرِّف
  يدلّك عليها؛ شغّل `flutter analyze` قبل الدفع.
- **التعليقات بالعربيّة** وتشرح «لماذا» لا «ماذا» — حافظ على الأسلوب.
- **التشفير والمفاتيح:** لا تُسجّل ولا تُصدّر مفاتيح القاعدة/المخزن.
- **نصّ الملاحظة** Delta JSON؛ استخدم `richToPlainText()` لأي معاينة نصّية.

## 6) قاعدة البيانات (مختصر)
- ملف SQLite مشفّر، إصداره `_dbVersion` في `lib/data/database/app_database.dart`.
- **لتغيير المخطّط:** ارفع `_dbVersion` + أضِف خطوة في `_onUpgrade` (لا تعتمد على
  `_onCreate` وحده). التفاصيل الكاملة وكل الجداول في `docs/DATABASE.md`.

## 7) الإشعارات والتذكيرات
- `services/notification_service.dart`: الجدولة عبر `flutter_local_notifications` +
  `timezone`. التكرار الأصليّ ميلاديّ؛ **الهجريّ** والكورسات تُجدوَل يدويًّا وتُعاد عند كل
  فتح عبر `RemindersProvider.ensureScheduled()`.
- مستويات الأهميّة تحدّد القناة والسلوك (`critical` = منبّه شاشة كاملة).
- ملاحظات مثبّتة في شريط الإشعارات + موجز صباحيّ: في نفس الخدمة (`showPinnedNote`،
  `updateMorningBriefing`).

## 8) المزامنة والنسخ الاحتياطيّ (اختياريّة، E2E)
- `services/sync/`: `sync_service` + خلفيّات WebDAV و Google Drive. الملف مشفّر بعبارة سرّ
  المستخدم. تردّد المزامنة ووضعها الصامت في الإعدادات.
- `services/backup_service.dart`: نسخة محليّة مشفّرة (AES‑256) + نسخة يوميّة تلقائيّة.

## 9) التوزيع والتحديث الذاتيّ
- يُبنى عبر GitHub Actions (`.github/workflows/build-apk.yml`): اختبارات → بناء →
  نشر `version.json` + APK على فرع `apk-dist` و GitHub Releases (وسم `latest`).
- `services/update_service.dart` يقارن **اسم النسخة** بالمنشور، وينزّل APK ويشغّل مثبّت
  النظام (قناة `installer` الأصليّة + FileProvider).

## 10) الترخيص (تفعيل مربوط بالجهاز، دون إنترنت)
- معرّف جهاز ثابت + توقيع **Ed25519** على (معرّف الجهاز + المدّة) يولّده المالك بمفتاحه
  الخاصّ. التطبيق يتحقّق بالمفتاح العامّ. التفاصيل في `LICENSING.md` و
  `services/license_service.dart` و `features/security/activation_gate.dart`.

---

## أين أبدأ لمهامّ شائعة؟
| المهمّة | ابدأ من |
|---|---|
| إضافة حقل لملاحظة | `data/models/note.dart` + ترقية مخطّط في `app_database.dart` |
| تعديل المحرّر الغنيّ | `features/editor/rich_text_field.dart` |
| منطق التذكيرات/الجدولة | `services/notification_service.dart` + `features/reminders/` |
| كورسات الدواء | `features/meds/medication_screen.dart` + `services/med_occurrences.dart` |
| نصوص الواجهة (عربي/إنجليزي) | `core/l10n/app_strings.dart` (أضِف للمفتاح في `_ar` و`_en`) |
| الثيم والألوان | `core/theme/` |
