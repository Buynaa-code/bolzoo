import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/billing/billing_models.dart';
import 'package:hamtdaa/billing/subscription_controller.dart';

import 'billing_fakes.dart';

void main() {
  late FakeBillingRepository repository;
  late FakeStoreGateway store;
  late SubscriptionController controller;
  setUp(() {
    repository = FakeBillingRepository();
    store = FakeStoreGateway();
    controller = SubscriptionController(repository: repository, store: store, now: () => testNow);
  });
  tearDown(() => controller.dispose());

  test('subscribes before querying, sends server binding and never grants locally', () async {
    await controller.initialize();
    expect(store.listenerBeforeQuery, isTrue);
    final verified = Completer<BillingSnapshot>();
    repository.onVerify = (_) => verified.future;
    await controller.buy(controller.products.first);
    expect(store.buys.single.account, appleAccount);
    expect(controller.premiumCards, isFalse);
    store.emit(purchase());
    await settleBilling();
    expect(repository.verifyCalls, 1);
    expect(store.completes, isEmpty);
    expect(controller.premiumCards, isFalse);
    verified.complete(snapshot(plus: true));
    await settleBilling();
    expect(controller.premiumCards, isTrue);
    expect(store.completes, hasLength(1));
  });

  test('pending disables duplicate buy; cancellation and error do not verify', () async {
    await controller.initialize();
    final product = controller.products.first;
    await controller.buy(product);
    await controller.buy(product);
    expect(store.buys, hasLength(1));
    store.emit(purchase(state: StorePurchaseState.pending));
    await settleBilling();
    expect(controller.purchasePending, isTrue);
    expect(controller.canBuy(product), isFalse);
    store.emit(purchase(state: StorePurchaseState.canceled));
    await settleBilling();
    expect(controller.busy, isFalse);
    expect(controller.notice, contains('цуцаллаа'));
    store.emit(purchase(state: StorePurchaseState.error));
    await settleBilling();
    expect(repository.verifyCalls, 0);
    expect(store.completes, isEmpty);
    expect(controller.premiumCards, isFalse);
  });

  test('duplicate native delivery verifies and completes once', () async {
    await controller.initialize();
    store.emit(purchase());
    store.emit(purchase());
    store.emit(purchase(state: StorePurchaseState.restored));
    await settleBilling();
    expect(repository.verifyCalls, 1);
    expect(store.completes, hasLength(1));
  });

  test('network rejection leaves native transaction pending until retry', () async {
    await controller.initialize();
    repository.onVerify = (_) async => throw const BillingFailure('network_error', retryable: true);
    store.emit(purchase());
    await settleBilling();
    expect(controller.premiumCards, isFalse);
    expect(controller.hasPendingVerification, isTrue);
    expect(controller.canBuy(controller.products.first), isFalse);
    expect(store.completes, isEmpty);
    repository.onVerify = (_) async => snapshot(plus: true);
    await controller.retryPending();
    expect(controller.premiumCards, isTrue);
    expect(store.completes, hasLength(1));
    expect(controller.hasPendingVerification, isFalse);
  });

  test('account switch during verification cannot grant or acknowledge', () async {
    await controller.initialize();
    final result = Completer<BillingSnapshot>();
    repository.onVerify = (_) => result.future;
    store.emit(purchase());
    await settleBilling();
    repository.invalidate();
    result.complete(snapshot(plus: true));
    await settleBilling();
    expect(controller.premiumCards, isFalse);
    expect(controller.products, isEmpty);
    expect(store.completes, isEmpty);
  });

  test('disposal during verification never acknowledges later success', () async {
    await controller.initialize();
    final result = Completer<BillingSnapshot>();
    repository.onVerify = (_) => result.future;
    store.emit(purchase());
    await settleBilling();
    controller.dispose();
    result.complete(snapshot(plus: true));
    await settleBilling();
    expect(store.completes, isEmpty);
    expect(controller.premiumCards, isFalse);
  });

  test('failed acknowledgement retries completion without recharging or reverifying', () async {
    await controller.initialize();
    store.completionFails = true;
    store.emit(purchase());
    await settleBilling();
    expect(controller.premiumCards, isTrue);
    expect(controller.failure?.code, 'complete_failed');
    store.completionFails = false;
    await controller.retryPending();
    expect(repository.verifyCalls, 1);
    expect(store.completes, hasLength(2));
    expect(store.buys, isEmpty);
    expect(controller.hasPendingVerification, isFalse);
  });

  test('restore validates receipts before entitlement and acknowledgement', () async {
    await controller.initialize();
    store.onRestore = () async { store.emit(purchase(state: StorePurchaseState.restored)); };
    await controller.restore();
    await settleBilling();
    expect(store.restores.last, appleAccount);
    expect(repository.verifyCalls, 1);
    expect(controller.premiumCards, isTrue);
    expect(store.completes, hasLength(1));
  });

  test('unready provider and missing products never offer fallback purchase', () async {
    repository.enabled = false;
    await controller.initialize();
    expect(controller.storeReady, isFalse);
    expect(controller.products, isEmpty);
    expect(store.buys, isEmpty);
    repository.enabled = true;
    store.offered = [];
    await controller.initialize();
    expect(controller.products, isEmpty);
    expect(controller.notice, contains('бэлэн болоогүй'));
  });

  test('expired server entitlement cannot unlock premium cards', () async {
    repository.value = snapshot(plus: true, expires: testNow.subtract(const Duration(seconds: 1)));
    await controller.initialize();
    expect(controller.premiumCards, isFalse);
  });

  test('stale initial status cannot overwrite newly verified purchase', () async {
    final status = Completer<BillingSnapshot>();
    repository.onStatus = () => status.future;
    final initializing = controller.initialize();
    await settleBilling();
    store.emit(purchase());
    await settleBilling();
    expect(controller.premiumCards, isTrue);
    status.complete(snapshot());
    await initializing;
    expect(controller.premiumCards, isTrue);
  });

  test('partner entitlement arriving before buy avoids unnecessary charge', () async {
    await controller.initialize();
    repository.value = snapshot(plus: true, source: 'partner');
    await controller.buy(controller.products.first);
    expect(store.buys, isEmpty);
    expect(controller.premiumCards, isTrue);
    expect(controller.entitlement.source, 'partner');
  });

  test('wrong account restore is denied and never completed', () async {
    await controller.initialize();
    repository.onVerify = (_) async => throw const BillingFailure('account_mismatch');
    store.emit(purchase(state: StorePurchaseState.restored));
    await settleBilling();
    expect(controller.premiumCards, isFalse);
    expect(store.completes, isEmpty);
    expect(controller.failure?.message, contains('өөр бүртгэлд'));
  });
}
