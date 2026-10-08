import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'billing_models.dart';
import 'billing_repository.dart';
import 'store_gateway.dart';

/// Own once per authenticated account, above routes. Native transactions stay
/// unfinished until this account's server validates them. Nothing grants Plus
/// locally, even when a native payment sheet reports success.
class SubscriptionController extends ChangeNotifier {
  SubscriptionController({required this.repository, required this.store, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _invalidations = repository.invalidations.listen((_) => _invalidate());
    // Subscribe before availability/product requests; this also receives native
    // transactions left pending by an earlier launch.
    _purchases = store.purchases.listen(_enqueue, onError: (Object _) {
      if (_current) { failure = const BillingFailure('store_unavailable', retryable: true); _notify(); }
    });
  }

  final BillingRepository repository;
  final StoreGateway store;
  final DateTime Function() _now;
  late final StreamSubscription<void> _invalidations;
  late final StreamSubscription<List<StorePurchase>> _purchases;
  Future<void> _queue = Future.value();
  final _retry = <String, StorePurchase>{};
  final _verified = <String>{};
  final _completed = <String>{};
  final _pending = <String>{};
  Timer? _expiry;
  bool _disposed = false;
  bool _invalid = false;
  bool _initializing = false;
  bool _restoring = false;
  bool _awaitingStore = false;
  int _processing = 0;
  int _snapshotVersion = 0;
  BillingSnapshot? _snapshot;
  BillingCatalog? _catalog;
  bool _statusReady = false;
  bool _storeAvailable = false;

  List<StoreProduct> products = const [];
  BillingFailure? failure;
  String? notice;
  bool get _current => !_disposed && !_invalid && repository.isCurrent;
  bool get isCurrent => _current;
  bool get loading => _initializing;
  bool get busy => _initializing || _restoring || _awaitingStore || _processing > 0 || _pending.isNotEmpty;
  bool get hasPendingVerification => _retry.isNotEmpty;
  bool get purchasePending => _pending.isNotEmpty || _awaitingStore;
  BillingProvider? get provider => store.provider;
  BillingEntitlement get entitlement => _current
      ? _snapshot?.entitlement ?? const BillingEntitlement.free()
      : const BillingEntitlement.free();
  bool get premiumCards => _current && entitlement.activeAt(_now());
  bool get storeReady => _current && _storeAvailable && provider != null &&
      _catalog?.enabled.contains(provider) == true && _statusReady &&
      _snapshot?.storeAccounts[provider] != null;
  bool get canRestore => storeReady && !busy;
  bool canBuy(StoreProduct product) => storeReady && !busy &&
      !premiumCards && !hasPendingVerification && products.contains(product);

  void _notify() { if (!_disposed) notifyListeners(); }

  void _invalidate() {
    if (_disposed || _invalid) return;
    _invalid = true;
    _snapshot = null;
    _catalog = null;
    products = const [];
    _retry.clear();
    _verified.clear();
    _completed.clear();
    _pending.clear();
    _expiry?.cancel();
    failure = const BillingFailure('unauthenticated');
    notice = null;
    _notify();
  }

  void _install(BillingSnapshot snapshot) {
    if (!_current) return;
    _snapshot = snapshot;
    _snapshotVersion++;
    _statusReady = true;
    _expiry?.cancel();
    final expiry = snapshot.entitlement.expiresAt;
    if (expiry != null && expiry.isAfter(_now())) {
      _expiry = Timer(expiry.difference(_now()), () {
        if (_current) { _notify(); unawaited(refresh()); }
      });
    }
  }

  Future<void> initialize() async {
    if (!_current || _initializing) return;
    _initializing = true;
    failure = null;
    _notify();
    final version = _snapshotVersion;
    try {
      final catalog = await repository.catalog();
      if (!_current) return;
      _catalog = catalog;
      final snapshot = await repository.status();
      if (!_current) return;
      if (version == _snapshotVersion) _install(snapshot);
      _storeAvailable = await store.isAvailable();
      if (!_current) return;
      if (_storeAvailable && provider != null && catalog.enabled.contains(provider)) {
        products = List.unmodifiable(await store.products(catalog.products[provider] ?? {}));
      } else { products = const []; }
      if (!_current) return;
      if (!storeReady || products.isEmpty) {
        notice = 'Дэлгүүрийн багцууд одоогоор бэлэн болоогүй байна. Үнэгүй боломжуудаа ашиглаарай.';
      }
    } catch (error) {
      if (_current) failure = error is BillingFailure ? error : const BillingFailure('store_unavailable', retryable: true);
    } finally {
      _initializing = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    if (!_current) return;
    final version = _snapshotVersion;
    try {
      final snapshot = await repository.status();
      if (!_current) return;
      if (version == _snapshotVersion) _install(snapshot);
      _notify();
    } catch (error) {
      if (!_current) return;
      _statusReady = false;
      failure = error is BillingFailure ? error : const BillingFailure('network_error', retryable: true);
      _notify();
    }
  }

  Future<void> buy(StoreProduct product) async {
    if (!canBuy(product)) return;
    // Re-read server status before charging; the current partner may already
    // have purchased Plus since this screen was opened.
    _awaitingStore = true;
    failure = null;
    notice = null;
    _notify();
    try {
      final snapshot = await repository.status();
      if (!_current) return;
      _install(snapshot);
      if (premiumCards) { _awaitingStore = false; return; }
      final binding = snapshot.storeAccounts[provider];
      if (binding == null) throw const BillingFailure('store_unavailable');
      final launched = await store.buy(product, accountBinding: binding);
      if (!_current) return;
      if (!launched) {
        _awaitingStore = false;
        notice = 'Худалдан авалт эхлээгүй байна. Дахин оролдоорой.';
      }
    } catch (error) {
      if (!_current) return;
      _awaitingStore = false;
      failure = error is BillingFailure ? error : const BillingFailure('store_unavailable', retryable: true);
    } finally { _notify(); }
  }

  Future<void> restore() async {
    if (!canRestore) return;
    _restoring = true;
    failure = null;
    notice = null;
    _notify();
    try {
      await store.restore(accountBinding: _snapshot!.storeAccounts[provider]!);
      if (!_current) return;
      await _queue;
      if (!_current) return;
      await refresh();
      if (_current && failure == null) {
        notice = premiumCards ? 'Plus эрхийг сэргээлээ.' : 'Худалдан авалтыг шалгалаа. Энэ бүртгэлд идэвхтэй Plus эрх олдсонгүй.';
      }
    } catch (error) {
      if (_current) failure = error is BillingFailure ? error : const BillingFailure('store_unavailable', retryable: true);
    } finally { _restoring = false; _notify(); }
  }

  String _key(StorePurchase purchase) => '${purchase.provider.name}:${purchase.productId}:'
      '${sha256.convert(utf8.encode('${purchase.transactionId ?? ''}:${purchase.purchaseToken ?? ''}'))}';

  void _enqueue(List<StorePurchase> batch) {
    for (final purchase in batch) {
      _queue = _queue.then((_) => _process(purchase));
    }
  }

  Future<void> _process(StorePurchase purchase) async {
    if (!_current || purchase.provider != provider ||
        !PlusPeriod.values.any((p) => p.productId == purchase.productId)) return;
    if (purchase.state == StorePurchaseState.pending) {
      _pending.add(purchase.productId);
      _awaitingStore = false;
      notice = 'Төлбөрийн зөвшөөрлийг хүлээж байна. Баталгаажмагц Plus идэвхжинэ.';
      _notify();
      return;
    }
    _pending.remove(purchase.productId);
    _awaitingStore = false;
    if (purchase.state == StorePurchaseState.canceled || purchase.state == StorePurchaseState.error) {
      notice = purchase.state == StorePurchaseState.canceled ? 'Худалдан авалтыг цуцаллаа.' : null;
      failure = purchase.state == StorePurchaseState.error ? const BillingFailure('store_unavailable', retryable: true) : null;
      _notify();
      return;
    }
    final key = _key(purchase);
    if (_completed.contains(key)) return;
    _retry[key] = purchase;
    _processing++;
    _notify();
    try {
      if (!_verified.contains(key)) {
        final snapshot = await repository.verify(purchase);
        if (!_current) return;
        _install(snapshot);
        _verified.add(key);
      }
      if (!_current) return;
      if (purchase.needsCompletion) {
        try { await store.complete(purchase); }
        catch (_) { throw const BillingFailure('complete_failed', retryable: true); }
      }
      if (!_current) return;
      _completed.add(key);
      _retry.remove(key);
      failure = null;
      notice = premiumCards ? 'Plus эрх идэвхжлээ. Хосын картаа бүтээгээрэй ♡' : 'Худалдан авалтыг шалгалаа. Идэвхтэй эрх байхгүй байна.';
    } catch (error) {
      if (_current) {
        failure = error is BillingFailure ? error : const BillingFailure('network_error', retryable: true);
        notice = null;
      }
    } finally { _processing--; _notify(); }
  }

  Future<void> retryPending() async {
    if (!_current || _processing > 0) return;
    for (final purchase in _retry.values.toList()) {
      _queue = _queue.then((_) => _process(purchase));
    }
    await _queue;
  }

  /// Completion is deliberately not attempted during disposal/account switch.
  /// The native queue redelivers the transaction on a later authorized launch.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _expiry?.cancel();
    _retry.clear();
    _snapshot = null;
    unawaited(_purchases.cancel());
    unawaited(_invalidations.cancel());
    unawaited(store.dispose());
    unawaited(repository.dispose());
    super.dispose();
  }
}
