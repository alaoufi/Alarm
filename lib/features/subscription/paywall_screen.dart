import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/subscription_service.dart';

/// شاشة الاشتراك: تُعرض عند انتهاء التجربة (بوّابة حاجبة) أو عند اختيار «اشترك
/// الآن» أثناء التجربة. تعرض الخطط الثلاث بأسعارها المحليّة من قوقل بلاي.
class PaywallScreen extends StatefulWidget {
  /// هل هي بوّابة حاجبة (انتهت التجربة) أم صفحة عاديّة يمكن إغلاقها؟
  final bool blocking;
  const PaywallScreen({super.key, this.blocking = false});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _sub = SubscriptionService.instance;
  bool _busy = false;

  /// ترتيب العرض ووصف كل خطّة.
  static const _order = [
    SubscriptionService.yearlyId,
    SubscriptionService.semiAnnualId,
    SubscriptionService.monthlyId,
  ];

  String _planLabel(S s, String id) => switch (id) {
        SubscriptionService.monthlyId => s.t('sub_monthly'),
        SubscriptionService.semiAnnualId => s.t('sub_semiannual'),
        SubscriptionService.yearlyId => s.t('sub_yearly'),
        _ => id,
      };

  Future<void> _buy(ProductDetails p) async {
    setState(() => _busy = true);
    await _sub.subscribe(p);
    // التفعيل يصل عبر تيّار المشتريات؛ البوّابة تُغلق نفسها عند تغيّر الحالة.
    if (mounted) setState(() => _busy = false);
  }

  /// حوار فتح المالك (ضغطة مطوّلة على الشارة). عند نجاح الرمز يُفتح التطبيق دائمًا.
  Future<void> _ownerUnlockDialog(BuildContext context) async {
    final s = S.of(context);
    final ctrl = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) => AlertDialog(
          title: Text(s.t('owner_unlock_title')),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              hintText: s.t('owner_unlock_hint'),
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: Text(s.t('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await _sub.ownerUnlock(ctrl.text);
                if (!dctx.mounted) return;
                if (ok) {
                  Navigator.pop(dctx); // البوّابة تُغلق نفسها عند تغيّر الحالة.
                } else {
                  setLocal(() => error = s.t('owner_unlock_bad'));
                }
              },
              child: Text(s.t('unlock')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final expired = _sub.access.value == AccessState.expired;

    return PopScope(
      canPop: !widget.blocking,
      child: Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder<List<ProductDetails>>(
            valueListenable: _sub.products,
            builder: (context, products, _) {
              final sorted = [
                for (final id in _order)
                  ...products.where((p) => p.id == id),
              ];
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                children: [
                  if (!widget.blocking)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.maybePop(context),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Center(
                    child: GestureDetector(
                      // فتح المالك: ضغطة مطوّلة على الشارة تفتح إدخال رمز المطوّر.
                      onLongPress: () => _ownerUnlockDialog(context),
                      child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [
                          scheme.primary,
                          Color.alphaBlend(
                              Colors.black.withOpacity(0.2), scheme.primary),
                        ]),
                        boxShadow: [
                          BoxShadow(
                              color: scheme.primary.withOpacity(0.4),
                              blurRadius: 22,
                              offset: const Offset(0, 10)),
                        ],
                      ),
                      child: const Icon(Icons.workspace_premium,
                          color: Colors.white, size: 44),
                    ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    expired ? s.t('sub_expired_title') : s.t('sub_title'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    expired
                        ? s.t('sub_expired_body')
                        : '${s.t('sub_trial_active')} — ${_sub.trialDaysLeft} ${s.t('sub_days_left')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: scheme.onSurface.withOpacity(0.75)),
                  ),
                  const SizedBox(height: 24),
                  Text(s.t('sub_choose_plan'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  if (!_sub.storeAvailable)
                    _notice(scheme, s.t('sub_unavailable'))
                  else if (sorted.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    for (var i = 0; i < sorted.length; i++)
                      _planCard(context, s, scheme, sorted[i],
                          best: sorted[i].id == SubscriptionService.yearlyId),

                  const SizedBox(height: 18),
                  Text(
                    s.t('sub_auto_note'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: scheme.onSurface.withOpacity(0.55)),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      onPressed: _busy ? null : () => _sub.restore(),
                      icon: const Icon(Icons.restore, size: 18),
                      label: Text(s.t('sub_restore')),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _notice(ColorScheme scheme, String text) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, color: scheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );

  Widget _planCard(BuildContext context, S s, ColorScheme scheme,
      ProductDetails p, {required bool best}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _busy ? null : () => _buy(p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                      scheme.primary.withOpacity(best ? 0.20 : 0.10),
                      scheme.surface),
                  Color.alphaBlend(
                      scheme.primary.withOpacity(0.04), scheme.surface),
                ],
              ),
              border: Border.all(
                color: best
                    ? scheme.primary
                    : scheme.primary.withOpacity(0.30),
                width: best ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(best ? Icons.star : Icons.check_circle_outline,
                    color: scheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(_planLabel(s, p.id),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                          if (best) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(s.t('sub_best_value'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(p.title.isNotEmpty ? p.title : p.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withOpacity(0.6))),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(p.price,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: scheme.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
