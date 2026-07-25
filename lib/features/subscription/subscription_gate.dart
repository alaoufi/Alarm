import 'package:flutter/material.dart';

import '../../services/subscription_service.dart';
import 'paywall_screen.dart';

/// بوّابة الاشتراك: تعرض التطبيق ما دام الوصول مسموحًا (تجربة سارية أو اشتراك
/// فعّال)، وتعرض شاشة الاشتراك الحاجبة عند انتهاء التجربة دون اشتراك — **دون
/// المساس بأي بيانات**. تُعيد التحقّق من الاشتراك عند عودة التطبيق للواجهة.
class SubscriptionGate extends StatefulWidget {
  final Widget child;
  const SubscriptionGate({super.key, required this.child});

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عند العودة للواجهة أعِد التحقّق (قد يكون اشترك أو انتهى اشتراكه من بلاي).
    if (state == AppLifecycleState.resumed) {
      SubscriptionService.instance.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AccessState>(
      valueListenable: SubscriptionService.instance.access,
      builder: (context, state, child) {
        if (state == AccessState.expired) {
          return const PaywallScreen(blocking: true);
        }
        return widget.child;
      },
    );
  }
}
