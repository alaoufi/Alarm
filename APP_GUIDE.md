# Alarm (تنبيهات) — دليل التطبيق للجلسة المخصّصة

ابدأ من هنا عند فتح جلسة تطوير جديدة لهذا التطبيق.

## الهويّة
- **الاسم:** Alarm (تنبيهات)
- **applicationId:** `com.alaoufi.alarm` (يتعايش مع التطبيقات الأخرى على الجهاز)
- **اسم حزمة Dart الداخليّ:** `mudhakkarati` (بقي كما هو عمدًا؛ أعِد تسميته لاحقًا إن رغبت)
- **النسخة:** `1.0.0+1`
- **مصدر التحديث الذاتيّ:** `apk-dist-alarm` / إصدار `alarm-latest` (مستقلّ — يحتاج إعداد CI لاحقًا)

## الأصل ونقطة التراجع
منبثق عن التطبيق الموحّد **Alaoufi Notes** (`mudhakkarati/`). نقطة التراجع للأصل:
وسم `v1.8.9-combined` / بصمة `d28bb1e`.

## الوضع الحاليّ (المرحلة ١)
نسخة **كاملة تعمل** من مذكراتي (كل الميزات)، تحلّل بلا أخطاء (`flutter analyze`).
البنية والوثائق نفسها: `docs/DEVELOPER_GUIDE.md` و`docs/DATABASE.md` و`docs/schema.sql`.

## المطلوب في هذا التطبيق (المرحلة ٢ — التخصيص)
اجعله متخصّصًا في **التذكيرات والمنبّهات** فقط:
- **أبقِ:** التذكيرات (`features/reminders`)، الأدوية (`features/meds`)، التقويم
  (`features/calendar`)، شاشة المنبّه + الموثوقيّة، مكتبة النغمات (`features/sounds`)،
  مركز الإشعارات، خدمة الإشعارات (`services/notification_service`)، الإعدادات، الأمان،
  النسخ الاحتياطي/المزامنة.
- **أزِل/قلّص:** المحرّر الغنيّ (`features/editor`)، أنواع الملاحظات (صورة/صوت/PDF/رسم)،
  التصنيفات/الوسوم كمنظومة ملاحظات، القوالب — وما يتبعها في التنقّل.
- **الترابط:** التذكير قد يُربَط بملاحظة — للتطبيق المتخصّص اجعل التذكيرات **مستقلّة**
  (عنوان + وقت + تكرار/أهميّة) + كورسات الأدوية، واستغنِ عن ربط الملاحظة الكامل.

> تحذير: حذف ميزة يكسر كل `import`/`switch`/عنصر تنقّل يشير إليها — اعتمد على
> `flutter analyze` (المُصرِّف يدلّك)، وشغّل `flutter test` قبل أي دفع. لاحظ أنّ
> `ReminderRepeat` enum تستعمله عدّة `switch` شاملة.

## التشغيل والبناء
```bash
cd alarm
flutter pub get
flutter test                 # بوّابة الجودة
flutter run
flutter build apk --release --split-per-abi
```

## أين تبدأ
- نقطة الإقلاع: `lib/main.dart` → `lib/app.dart`.
- جوهر التطبيق: `lib/services/notification_service.dart` + `lib/features/reminders/`
  + `lib/features/meds/`.
- القائمة الجانبية/التنقّل: `lib/widgets/app_drawer.dart`.
- نصوص الواجهة: `lib/core/l10n/app_strings.dart`.
