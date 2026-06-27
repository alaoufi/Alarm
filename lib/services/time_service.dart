import 'dart:io';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// خدمة الوقت والمنطقة الزمنية:
/// - تطبّق المنطقة الزمنية (تلقائيًّا من الجهاز أو يدويًّا من الإعدادات).
/// - تفحص دقّة ساعة الجهاز مقابل وقت الإنترنت (المنبّه يعتمد على ساعة الجهاز).
class TimeService {
  TimeService._();
  static final TimeService instance = TimeService._();

  static const _kZone = 'timezone_id'; // فارغ/غير موجود = تلقائي (منطقة الجهاز)
  bool _initialized = false;

  /// يهيّئ قاعدة المناطق ويطبّق المنطقة المحفوظة (أو منطقة الجهاز تلقائيًّا).
  Future<void> applyZone() async {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      _initialized = true;
    }
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kZone) ?? '';
    if (id.isEmpty) {
      try {
        id = (await FlutterTimezone.getLocalTimezone()).identifier;
      } catch (_) {
        id = 'UTC';
      }
    }
    try {
      tz.setLocalLocation(tz.getLocation(id));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('UTC'));
      } catch (_) {}
    }
  }

  /// اسم المنطقة الزمنية المطبّقة حاليًّا (مثل Asia/Riyadh).
  String currentZoneName() {
    try {
      return tz.local.name;
    } catch (_) {
      return 'UTC';
    }
  }

  /// كل أسماء المناطق الزمنية المتاحة (مرتّبة) — لمنتقي الإعدادات.
  List<String> allZones() {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      _initialized = true;
    }
    final list = tz.timeZoneDatabase.locations.keys.toList()..sort();
    return list;
  }

  /// المنطقة الزمنية المحفوظة ('' = تلقائي).
  Future<String> savedZone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kZone) ?? '';
  }

  /// يحفظ المنطقة الزمنية ('' = تلقائي) ويطبّقها فورًا.
  Future<void> setZone(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kZone, id);
    await applyZone();
  }

  /// الفرق بين وقت الإنترنت وساعة الجهاز (إنترنت − جهاز). موجب = الجهاز متأخّر،
  /// سالب = الجهاز متقدّم. يعيد null عند تعذّر الوصول للإنترنت.
  Future<Duration?> networkOffset() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      // مورد خفيف يعيد ترويسة Date بتوقيت UTC.
      final req = await client
          .headUrl(Uri.parse('https://www.google.com/generate_204'));
      final res = await req.close();
      final dateStr = res.headers.value(HttpHeaders.dateHeader);
      if (dateStr == null) return null;
      final net = HttpDate.parse(dateStr); // UTC
      return net.difference(DateTime.now().toUtc());
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}
