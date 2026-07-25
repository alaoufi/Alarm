import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// مراسلة المطوّر عبر البريد لإرسال الملاحظات والاقتراحات.
class FeedbackService {
  FeedbackService._();

  /// بريد استقبال ملاحظات المستخدمين (يظهر أيضًا في بطاقة قوقل بلاي).
  static const String supportEmail = 'alaoufi@gmail.com';

  /// يفتح تطبيق البريد برسالة مُعبّأة (المُرسَل إليه + عنوان + معلومات النسخة).
  /// يعيد false إن تعذّر فتح أي تطبيق بريد (فيمكن للواجهة عرض البريد للنسخ).
  static Future<bool> sendEmail(BuildContext context,
      {String subject = 'ملاحظات تطبيق Alerts'}) async {
    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = 'v${info.version} (${info.buildNumber})';
    } catch (_) {}
    final body = '\n\n—\nAlerts $version';
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: _encodeQuery({'subject': subject, 'body': body}),
    );
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return false;
  }

  // ترميز معاملات mailto يدويًّا (Uri.encodeQueryComponent يحوّل المسافة إلى +
  // وبعض تطبيقات البريد لا تفكّها، لذا نستخدم %20).
  static String _encodeQuery(Map<String, String> params) => params.entries
      .map((e) =>
          '${e.key}=${Uri.encodeComponent(e.value).replaceAll('+', '%20')}')
      .join('&');
}
