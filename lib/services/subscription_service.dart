import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// حالة الوصول إلى التطبيق (تُستخدم للبوّابة وشاشة الاشتراك).
enum AccessState {
  /// ضمن فترة التجربة المجانية (10 أيام من أول تشغيل).
  trial,

  /// اشتراك فعّال مدفوع من قوقل بلاي.
  subscribed,

  /// انتهت التجربة ولا اشتراك فعّال ⇒ يُطلَب الاشتراك (تبقى البيانات محفوظة).
  expired,
}

/// إدارة الوصول عبر **اشتراكات قوقل بلاي** مع **تجربة مجانية 10 أيام**.
///
/// النموذج:
/// - عند أول تشغيل تبدأ تجربة مجانية 10 أيام (محليًّا) — التطبيق مفتوح بالكامل.
/// - بعد انتهائها يلزم اشتراك فعّال (شهري/نصف سنوي/سنوي) من قوقل بلاي.
/// - التفعيل آليّ: بمجرّد إتمام الدفع يصل التحديث عبر تيّار المشتريات فيُفتح فورًا.
/// - عند انتهاء الاشتراك يتوقّف الوصول **مع الاحتفاظ بكل البيانات** ويُطلَب التجديد.
///
/// التحقّق من الاشتراك يتمّ على جهاز المستخدم عبر قناة الفوترة (restorePurchases
/// تُعيد بثّ الاشتراكات المملوكة الفعّالة). تُخزَّن آخر حالة معروفة محليًّا كي
/// يعمل التطبيق دون إنترنت بين عمليات التحقّق.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  // مدّة التجربة المجانية.
  static const int trialDays = 10;

  // معرّفات منتجات الاشتراك في قوقل بلاي (يجب أن تطابق ما يُنشأ في Play Console).
  static const String monthlyId = 'alerts_sub_monthly';
  static const String semiAnnualId = 'alerts_sub_semiannual';
  static const String yearlyId = 'alerts_sub_yearly';
  static const Set<String> _productIds = {monthlyId, semiAnnualId, yearlyId};

  static const _kFirstLaunch = 'sub_first_launch_ms';
  static const _kSubActive = 'sub_active_cached';
  static const _kLastCheck = 'sub_last_check_ms';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  Timer? _restoreFinalize;

  /// تُعلِم المستمعين (البوّابة) بأي تغيّر في حالة الوصول.
  final ValueNotifier<AccessState> access =
      ValueNotifier<AccessState>(AccessState.trial);

  /// منتجات الاشتراك المتاحة للعرض في شاشة الاشتراك (بأسعارها المحليّة من بلاي).
  final ValueNotifier<List<ProductDetails>> products =
      ValueNotifier<List<ProductDetails>>(const []);

  /// هل قناة الفوترة متاحة على هذا الجهاز؟ (Play Services موجودة).
  bool storeAvailable = false;

  int _firstLaunchMs = 0;
  bool _subActiveCached = false;
  bool _sawActiveSub = false; // رُصد اشتراك فعّال خلال آخر استرجاع؟

  /// أيام التجربة المتبقّية (0 إن انتهت).
  int get trialDaysLeft {
    if (_firstLaunchMs == 0) return trialDays;
    final end = _firstLaunchMs + trialDays * 86400000;
    final left = ((end - DateTime.now().millisecondsSinceEpoch) / 86400000).ceil();
    return left < 0 ? 0 : left;
  }

  bool get _trialActive {
    if (_firstLaunchMs == 0) return true;
    final end = _firstLaunchMs + trialDays * 86400000;
    return DateTime.now().millisecondsSinceEpoch < end;
  }

  /// هل الوصول مسموح الآن؟ (تجربة سارية أو اشتراك فعّال).
  bool get hasAccess => _subActiveCached || _trialActive;

  AccessState _compute() {
    if (_subActiveCached) return AccessState.subscribed;
    if (_trialActive) return AccessState.trial;
    return AccessState.expired;
  }

  void _publish() => access.value = _compute();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _firstLaunchMs = prefs.getInt(_kFirstLaunch) ?? 0;
    if (_firstLaunchMs == 0) {
      _firstLaunchMs = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_kFirstLaunch, _firstLaunchMs);
    }
    _subActiveCached = prefs.getBool(_kSubActive) ?? false;
    _publish();

    // قناة الفوترة (قد تكون غير متاحة على أجهزة بلا خدمات قوقل).
    try {
      storeAvailable = await _iap.isAvailable();
    } catch (_) {
      storeAvailable = false;
    }
    if (!storeAvailable) return;

    _purchaseSub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (_) {/* لا تُعطّل التطبيق */},
    );

    await _loadProducts();
    // استرجاع الاشتراكات الفعّالة عند الإقلاع ⇒ تفعيل آليّ إن كان مشتركًا.
    await refresh();
  }

  Future<void> _loadProducts() async {
    try {
      final resp = await _iap.queryProductDetails(_productIds);
      if (resp.productDetails.isNotEmpty) {
        products.value = resp.productDetails;
      }
    } catch (_) {/* نتجاهل — تبقى القائمة كما هي */}
  }

  /// يُعيد التحقّق من حالة الاشتراك عبر قناة الفوترة (يُستدعى عند الإقلاع والعودة
  /// للواجهة). يضبط حارسًا: إن لم يُرصد اشتراك فعّال خلال مهلة قصيرة اعتُبر
  /// المستخدم غير مشترك (انتهى) — مع بقاء آخر حالة محفوظة عند تعذّر الاتصال.
  Future<void> refresh() async {
    if (!storeAvailable) return;
    _sawActiveSub = false;
    try {
      await _iap.restorePurchases();
    } catch (_) {
      return; // تعذّر الاسترجاع (غالبًا دون إنترنت) ⇒ أبقِ الحالة المخزّنة.
    }
    _restoreFinalize?.cancel();
    _restoreFinalize = Timer(const Duration(seconds: 8), () {
      // اكتمل الاسترجاع ولم يظهر اشتراك فعّال ⇒ انتهى الاشتراك.
      if (!_sawActiveSub && _subActiveCached) {
        _setSubActive(false);
      }
    });
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (_productIds.contains(p.productID)) {
            _sawActiveSub = true;
            _setSubActive(true);
          }
          break;
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          break;
        case PurchaseStatus.pending:
          break;
      }
      // يجب إتمام كل عملية معلّقة وإلّا يستردّها قوقل تلقائيًّا.
      if (p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p);
        } catch (_) {}
      }
    }
  }

  Future<void> _setSubActive(bool active) async {
    _subActiveCached = active;
    _publish();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSubActive, active);
    await prefs.setInt(_kLastCheck, DateTime.now().millisecondsSinceEpoch);
  }

  /// يبدأ عملية شراء اشتراك. التفعيل يصل آليًّا عبر [_onPurchases] بعد الدفع.
  Future<bool> subscribe(ProductDetails product) async {
    if (!storeAvailable) return false;
    try {
      final param = PurchaseParam(productDetails: product);
      // الاشتراكات تُشترى عبر buyNonConsumable في in_app_purchase.
      return await _iap.buyNonConsumable(purchaseParam: param);
    } catch (_) {
      return false;
    }
  }

  /// استعادة اشتراك سابق يدويًّا (زر «استعادة المشتريات»).
  Future<void> restore() => refresh();

  void dispose() {
    _restoreFinalize?.cancel();
    _purchaseSub?.cancel();
  }
}
