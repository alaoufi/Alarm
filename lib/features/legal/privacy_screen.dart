import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';

/// شاشة «الخصوصية وإخلاء المسؤولية» — محتوى ثابت مترجَم (عربيّ/إنجليزيّ)
/// بتصميم بطاقات بارزة. يوضّح أن التطبيق يعمل محليًّا دون جمع بيانات، وحدود
/// الاعتماد على التنبيهات.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ar = s.locale.languageCode == 'ar';
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sections = ar ? _ar : _en;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            pinned: true,
            title: Text(s.t('privacy_disclaimer'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            flexibleSpace: FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      scheme.primaryContainer.withOpacity(0.7),
                      scheme.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
            sliver: SliverList.list(
              children: [
                for (final sec in sections)
                  _LegalCard(
                      icon: sec.$1,
                      color: sec.$2,
                      title: sec.$3,
                      body: sec.$4,
                      dark: dark),
                const SizedBox(height: 8),
                Center(
                  child: Text(ar ? 'تطبيق Alerts' : 'Alerts app',
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

class _LegalCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final bool dark;
  const _LegalCard(
      {required this.icon,
      required this.color,
      required this.title,
      required this.body,
      required this.dark});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = dark ? const Color(0xFF1E2230) : Colors.white;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [surface, Color.alphaBlend(color.withOpacity(0.06), surface)],
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.4 : 0.10),
              offset: const Offset(0, 8),
              blurRadius: 20,
              spreadRadius: -6),
        ],
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(Colors.white.withOpacity(0.25), color),
                    color,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                      color: color.withOpacity(0.45),
                      blurRadius: 7,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: scheme.onSurface)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(body,
              style: TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  color: scheme.onSurface.withOpacity(0.8))),
        ],
      ),
    );
  }
}

const _cLock = Color(0xFF2E7D6B);
const _cCloud = Color(0xFF3F6FB5);
const _cKey = Color(0xFF7E57C2);
const _cWarn = Color(0xFFE53935);
const _cMail = Color(0xFF6D4C41);

// (icon, color, title, body)
const List<(IconData, Color, String, String)> _ar = [
  (
    Icons.lock_outline,
    _cLock,
    'خصوصيتك أولًا',
    '«تنبيهات» يعمل دون إنترنت. كل بياناتك — التنبيهات والمرفقات والإعدادات — '
        'تُخزَّن محليًّا على جهازك فقط. لا نجمع أيّ بيانات شخصية، ولا توجد '
        'إعلانات أو تتبّع أو حسابات إجبارية.'
  ),
  (
    Icons.cloud_outlined,
    _cCloud,
    'المزامنة السحابية (اختيارية)',
    'إن فعّلت المزامنة عبر Google Drive بنفسك، تُشفَّر بياناتك على جهازك قبل '
        'رفعها بعبارة تشفير تعرفها أنت وحدك؛ فلا يستطيع أحد — ولا الخدمة — '
        'قراءتها. لا تُرفع أيّ بيانات دون تفعيلك للمزامنة.'
  ),
  (
    Icons.vpn_key_outlined,
    _cKey,
    'الأذونات ولماذا',
    '• الإشعارات: لإطلاق التنبيهات في وقتها.\n'
        '• الميكروفون: للإملاء الصوتي عند استخدامه فقط.\n'
        '• التخزين: لحفظ النسخ الاحتياطية والمرفقات.\n'
        '• الموقع/الكاميرا: اختيارية لمرفقات المواعيد فقط.'
  ),
  (
    Icons.warning_amber_outlined,
    _cWarn,
    'إخلاء المسؤولية',
    '«تنبيهات» أداة مساعِدة للتذكير. قد لا يُطلَق التنبيه على بعض الأجهزة بسبب '
        'قيود الشركة المصنّعة أو وضع توفير الطاقة أو إغلاق النظام للتطبيق.\n\n'
        'لا تعتمد عليه وحده في الأمور الحرجة (مواعيد الأدوية، المواعيد الطبية، '
        'الطوارئ) دون وسيلة احتياطية. يُقدَّم التطبيق «كما هو» دون أيّ ضمان، '
        'والمطوّر غير مسؤول عن أيّ ضرر أو خسارة ناتجة عن فوات تنبيه أو خطأ.'
  ),
  (
    Icons.mail_outline,
    _cMail,
    'التواصل',
    'لأيّ استفسار حول الخصوصية أو ملاحظة، يمكنك التواصل مع المطوّر عبر صفحة '
        'التطبيق. باستخدامك التطبيق فأنت توافق على ما ورد أعلاه.'
  ),
];

const List<(IconData, Color, String, String)> _en = [
  (
    Icons.lock_outline,
    _cLock,
    'Your privacy first',
    'Alerts works offline. All your data — reminders, attachments and '
        'settings — is stored locally on your device only. We collect no '
        'personal data, and there are no ads, tracking or mandatory accounts.'
  ),
  (
    Icons.cloud_outlined,
    _cCloud,
    'Cloud sync (optional)',
    'If you enable Google Drive sync yourself, your data is encrypted on your '
        'device before upload with a passphrase only you know — no one, not '
        'even the service, can read it. Nothing is uploaded unless you turn '
        'sync on.'
  ),
  (
    Icons.vpn_key_outlined,
    _cKey,
    'Permissions and why',
    '• Notifications: to fire reminders on time.\n'
        '• Microphone: only while you use voice dictation.\n'
        '• Storage: to save backups and attachments.\n'
        '• Location/Camera: optional, for appointment attachments only.'
  ),
  (
    Icons.warning_amber_outlined,
    _cWarn,
    'Disclaimer',
    'Alerts is an aid for reminders. An alert may fail to fire on some devices '
        'due to manufacturer restrictions, battery saving, or the system '
        'killing the app.\n\n'
        'Do not rely on it alone for critical matters (medication times, '
        'medical appointments, emergencies) without a backup. The app is '
        'provided as is, without warranty, and the developer is not liable for '
        'any damage or loss from a missed alert or error.'
  ),
  (
    Icons.mail_outline,
    _cMail,
    'Contact',
    'For any privacy question or feedback, you can reach the developer via the '
        'app page. By using the app you agree to the above.'
  ),
];
