import 'dart:async';
import 'package:hamtdaa/billing/billing_models.dart';
import 'package:hamtdaa/billing/billing_repository.dart';
import 'package:hamtdaa/billing/store_gateway.dart';

final testNow = DateTime.utc(2026, 10, 6);
const appleAccount = 'ee13e37e-9e35-4f32-9633-6f2e7efa1234';
final googleAccount = 'a' * 64;
BillingSnapshot snapshot({bool plus = false, String source = 'self', DateTime? expires}) => BillingSnapshot(
  entitlement: plus ? BillingEntitlement(tier: 'plus', premiumCards: true, source: source, expiresAt: expires ?? testNow.add(const Duration(days: 30)), provider: 'apple') : const BillingEntitlement.free(),
  storeAccounts: {BillingProvider.apple: appleAccount, BillingProvider.google: googleAccount},
);

class FakeBillingRepository implements BillingRepository {
  final changes = StreamController<void>.broadcast(sync: true);
  bool current = true;
  bool enabled = true;
  BillingSnapshot value = snapshot();
  Future<BillingSnapshot> Function()? onStatus;
  Future<BillingSnapshot> Function(StorePurchase)? onVerify;
  int verifyCalls = 0;
  final verified = <StorePurchase>[];
  @override
  bool get isCurrent => current;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<BillingCatalog> catalog() async => BillingCatalog(
    enabled: enabled ? BillingProvider.values.toSet() : {},
    products: {for (final provider in BillingProvider.values) provider: PlusPeriod.values.map((p) => p.productId).toSet()},
  );
  @override
  Future<BillingSnapshot> status() async => onStatus == null ? value : await onStatus!();
  @override
  Future<BillingSnapshot> verify(StorePurchase purchase) async {
    verifyCalls++;
    verified.add(purchase);
    value = onVerify == null ? snapshot(plus: true) : await onVerify!(purchase);
    return value;
  }
  void invalidate() { current = false; changes.add(null); }
  @override
  Future<void> dispose() async { current = false; await changes.close(); }
}

class FakeStoreGateway implements StoreGateway {
  FakeStoreGateway({this.provider = BillingProvider.apple});
  @override
  final BillingProvider? provider;
  final updates = StreamController<List<StorePurchase>>.broadcast(sync: true);
  bool available = true;
  bool launch = true;
  bool completionFails = false;
  bool listenerBeforeQuery = false;
  List<StoreProduct> offered = [for (final period in PlusPeriod.values) StoreProduct(id: period.productId, price: period == PlusPeriod.month ? '₮9,900' : '₮79,900', period: period)];
  final buys = <({StoreProduct product, String account})>[];
  final completes = <StorePurchase>[];
  final restores = <String>[];
  Future<void> Function()? onRestore;
  @override
  Stream<List<StorePurchase>> get purchases => updates.stream;
  @override
  Future<bool> isAvailable() async { listenerBeforeQuery = updates.hasListener; return available; }
  @override
  Future<List<StoreProduct>> products(Set<String> ids) async => offered.where((p) => ids.contains(p.id)).toList();
  @override
  Future<bool> buy(StoreProduct product, {required String accountBinding}) async { buys.add((product: product, account: accountBinding)); return launch; }
  @override
  Future<void> restore({required String accountBinding}) async { restores.add(accountBinding); await onRestore?.call(); }
  @override
  Future<void> complete(StorePurchase purchase) async { completes.add(purchase); if (completionFails) throw StateError('completion failed'); }
  void emit(StorePurchase purchase) => updates.add([purchase]);
  @override
  Future<void> dispose() async { await updates.close(); }
}

StorePurchase purchase({StorePurchaseState state = StorePurchaseState.purchased, String id = '10001', BillingProvider provider = BillingProvider.apple}) => StorePurchase(
  provider: provider, productId: PlusPeriod.month.productId, state: state,
  transactionId: id, purchaseToken: provider == BillingProvider.google ? 'opaque-token' : null, needsCompletion: true,
);

Future<void> settleBilling() async { for (var i = 0; i < 8; i++) { await Future<void>.delayed(Duration.zero); } }
