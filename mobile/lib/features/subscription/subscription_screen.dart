import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../billing/billing_models.dart';
import '../../billing/billing_repository.dart';
import '../../billing/store_gateway.dart';
import '../../billing/subscription_controller.dart';
import '../../cloudflare/cloudflare_auth_repository.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';

class SubscriptionLegalLinks {
  const SubscriptionLegalLinks({required this.terms, required this.privacy});
  final Uri terms;
  final Uri privacy;
  bool get ready => [terms, privacy].every((uri) => uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty);
}

/// Convenient route entry. An account-level controller is preferred when the
/// app hosts subscriptions so purchase updates are observed across all routes.
class SubscriptionEntry extends StatefulWidget {
  const SubscriptionEntry({super.key, required this.auth, required this.legalLinks, this.onOpenCards});
  final CloudflareAuthRepository auth;
  final SubscriptionLegalLinks legalLinks;
  final VoidCallback? onOpenCards;
  @override
  State<SubscriptionEntry> createState() => _SubscriptionEntryState();
}

class _SubscriptionEntryState extends State<SubscriptionEntry> {
  late final SubscriptionController _controller;
  @override
  void initState() {
    super.initState();
    _controller = SubscriptionController(repository: CloudflareBillingRepository(widget.auth), store: InAppPurchaseGateway());
    unawaited(_controller.initialize());
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SubscriptionScreen(controller: _controller, legalLinks: widget.legalLinks, onOpenCards: widget.onOpenCards);
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    required this.controller,
    required this.legalLinks,
    this.onOpenCards,
    this.openLink,
  });
  final SubscriptionController controller;
  final SubscriptionLegalLinks legalLinks;
  final VoidCallback? onOpenCards;
  final Future<bool> Function(Uri)? openLink;
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> with WidgetsBindingObserver {
  PlusPeriod _selected = PlusPeriod.year;
  SubscriptionController get _controller => widget.controller;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refresh());
      unawaited(_controller.retryPending());
    }
  }

  Future<void> _open(Uri uri) async {
    var opened = false;
    try { opened = await (widget.openLink?.call(uri) ?? launchUrl(uri, mode: LaunchMode.externalApplication)); }
    catch (_) { /* Display an actionable, non-sensitive error. */ }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Хуудсыг нээж чадсангүй. Дахин оролдоорой.')));
    }
  }

  Uri? get _manageUri => switch (_controller.entitlement.provider) {
    'apple' => Uri.parse('https://apps.apple.com/account/subscriptions'),
    'google' => Uri.https('play.google.com', '/store/account/subscriptions', {'package': 'mn.moch.hamtdaa'}),
    _ => null,
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final product = _controller.products.where((p) => p.period == _selected).firstOrNull;
      final active = _controller.premiumCards;
      final entitlement = _controller.entitlement;
      final canBuy = product != null && _controller.canBuy(product) && widget.legalLinks.ready;
      return Scaffold(
        appBar: AppBar(title: const Text('Хамтдаа Plus')),
        body: SafeArea(
          child: ListView(
            key: const Key('subscriptionList'),
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
            children: [
              const Center(child: HamtdaaMark(size: 52)),
              const SizedBox(height: 16),
              Text(active ? 'Хоёуланд тань Plus ♡' : 'Бидний түүхийг\nкартад үлдээе',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900, height: 1.2)),
              const SizedBox(height: 12),
              const Text('Нэг нь авна. Одоо холбогдсон хос нь хамт ашиглана.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
              const SizedBox(height: 26),
              if (active) ...[
                SoftCard(color: AppColors.blush, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [const Icon(Icons.verified_rounded, color: AppColors.pink), const SizedBox(width: 10),
                    Expanded(child: Text(entitlement.source == 'partner' ? 'Хосын тань Plus эрх' : 'Таны Plus эрх идэвхтэй',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))]),
                  const SizedBox(height: 10),
                  if (entitlement.expiresAt case final date?)
                    Text('Баталгаажсан хугацаа: ${date.toLocal().year}.${date.toLocal().month.toString().padLeft(2, '0')}.${date.toLocal().day.toString().padLeft(2, '0')}', style: const TextStyle(color: AppColors.muted)),
                  if (entitlement.source == 'partner') ...[
                    const SizedBox(height: 8),
                    const Text('Холболт болон төлбөр төлөгчийн эрх хүчинтэй үед хамт ашиглана.', style: TextStyle(height: 1.5)),
                  ],
                ])),
                const SizedBox(height: 18),
              ],
              const SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Үнэгүй хэвээр', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                SizedBox(height: 12),
                _Feature('Бүртгэл, хоёр талын зөвшөөрөлтэй хосын холболт'),
                _Feature('Үндсэн хуанли, дурсамж'),
                _Feature('Хүслийн жагсаалт, өдрийн асуулт'),
              ])),
              const SizedBox(height: 12),
              const SoftCard(color: AppColors.blush, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Plus · Хосын карт', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.pink)),
                SizedBox(height: 12),
                _Feature('Хоёрын нэр, хамтдаа өнгөрүүлсэн өдөртэй карт'),
                _Feature('Тусгай загвараа сонгож зураг болгон хадгалах'),
                _Feature('Одоо холбогдсон хоёр хүнд нэг Plus эрх'),
              ])),
              const SizedBox(height: 24),
              if (!active) ...[
                for (final period in PlusPeriod.values) ...[
                  _PlanTile(
                    period: period,
                    product: _controller.products.where((p) => p.period == period).firstOrNull,
                    selected: _selected == period,
                    enabled: !_controller.busy,
                    onSelect: () => setState(() => _selected = period),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              if (_controller.loading) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator(minHeight: 2)),
              if (_controller.failure case final failure?)
                Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(failure.message, key: const Key('subscriptionError'), style: TextStyle(color: Theme.of(context).colorScheme.error, height: 1.5))),
              if (_controller.notice case final notice?)
                Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(notice, key: const Key('subscriptionNotice'), style: const TextStyle(color: AppColors.muted, height: 1.5))),
              if (_controller.hasPendingVerification)
                OutlinedButton.icon(key: const Key('subscriptionRetryVerification'),
                  onPressed: _controller.busy ? null : _controller.retryPending,
                  icon: const Icon(Icons.refresh_rounded), label: const Text('Төлбөрөө дахин баталгаажуулах')),
              if (active && widget.onOpenCards != null)
                FilledButton.icon(key: const Key('subscriptionOpenCards'), onPressed: widget.onOpenCards,
                  icon: const Icon(Icons.favorite_outline_rounded), label: const Text('Хосын картаа бүтээх')),
              if (!active) ...[
                FilledButton(
                  key: const Key('subscriptionBuy'),
                  onPressed: canBuy ? () => _controller.buy(product) : null,
                  child: Text(_controller.purchasePending ? 'Зөвшөөрлийг хүлээж байна…'
                    : product == null ? 'Багц хараахан бэлэн болоогүй'
                    : 'Plus авах · ${product.price} / ${product.period.suffix}', textAlign: TextAlign.center),
                ),
                const SizedBox(height: 12),
                Text(product == null ? 'Үнэ, төлбөрийг App Store эсвэл Google Play баталгаажуулна.'
                  : '${product.price} / ${product.period.suffix}. Үнэгүй туршилтгүй. Төлбөр дэлгүүрийн баталгаажуулалтын дараа суутгагдана.',
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
                if (!widget.legalLinks.ready) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Үйлчилгээний нөхцөл бэлэн болмогц худалдан авалт нээгдэнэ.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted))),
              ],
              const SizedBox(height: 16),
              const Text('Захиалга цуцлах хүртэл сонгосон хугацаагаар автоматаар сунгагдана. Дараагийн сунгалтаас өмнө дэлгүүрийн захиалгын тохиргоонд цуцалж болно. Апп устгах эсвэл хосын холболт салгах нь захиалгыг цуцлахгүй.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.6)),
              const SizedBox(height: 14),
              OutlinedButton.icon(key: const Key('subscriptionRestore'),
                onPressed: _controller.canRestore ? _controller.restore : null,
                icon: const Icon(Icons.restore_rounded), label: const Text('Худалдан авалтаа сэргээх')),
              if (entitlement.source == 'self' && _manageUri != null) ...[
                const SizedBox(height: 10),
                OutlinedButton(key: const Key('subscriptionManage'), onPressed: () => _open(_manageUri!), child: const Text('Дэлгүүрт захиалгаа удирдах')),
              ],
              if (!_controller.busy)
                TextButton(key: const Key('subscriptionRefresh'), onPressed: _controller.initialize, child: const Text('Төлөв дахин шалгах')),
              Wrap(alignment: WrapAlignment.center, children: [
                TextButton(key: const Key('subscriptionTerms'), onPressed: widget.legalLinks.ready ? () => _open(widget.legalLinks.terms) : null, child: const Text('Үйлчилгээний нөхцөл')),
                TextButton(key: const Key('subscriptionPrivacy'), onPressed: widget.legalLinks.ready ? () => _open(widget.legalLinks.privacy) : null, child: const Text('Нууцлал')),
              ]),
            ],
          ),
        ),
      );
    },
  );
}

class _Feature extends StatelessWidget {
  const _Feature(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Icon(Icons.check_rounded, size: 18, color: AppColors.pink), const SizedBox(width: 10),
    Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
  ]));
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.period, required this.product, required this.selected, required this.enabled, required this.onSelect});
  final PlusPeriod period;
  final StoreProduct? product;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(color: selected ? AppColors.blush : Colors.white, borderRadius: BorderRadius.circular(22),
      child: InkWell(key: Key('subscriptionPlan${period.name}'), borderRadius: BorderRadius.circular(22), onTap: enabled ? onSelect : null,
        child: Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: selected ? AppColors.pink : AppColors.line, width: selected ? 1.5 : 1)),
          child: Row(children: [Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.pink : AppColors.muted), const SizedBox(width: 12),
            Expanded(child: Text(period.label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
            Flexible(child: Text(product?.price ?? 'Бэлэн болоогүй', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, color: product == null ? AppColors.muted : AppColors.ink))),
          ]),
        ),
      ),
    ),
  );
}
