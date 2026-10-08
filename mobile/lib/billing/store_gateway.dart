import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'billing_models.dart';

abstract interface class StoreGateway {
  BillingProvider? get provider;
  Stream<List<StorePurchase>> get purchases;
  Future<bool> isAvailable();
  Future<List<StoreProduct>> products(Set<String> ids);
  Future<bool> buy(StoreProduct product, {required String accountBinding});
  Future<void> restore({required String accountBinding});
  Future<void> complete(StorePurchase purchase);
  Future<void> dispose();
}

/// Official App Store / Play Billing integration. No external native checkout.
class InAppPurchaseGateway implements StoreGateway {
  InAppPurchaseGateway({TargetPlatform? platform})
    : provider = kIsWeb ? null : switch (platform ?? defaultTargetPlatform) {
        TargetPlatform.iOS => BillingProvider.apple,
        TargetPlatform.android => BillingProvider.google,
        _ => null,
      };

  @override
  final BillingProvider? provider;
  final _details = <String, ProductDetails>{};
  InAppPurchase get _store => InAppPurchase.instance;

  @override
  Stream<List<StorePurchase>> get purchases => provider == null
      ? const Stream.empty()
      : _store.purchaseStream.map((batch) => batch.map((purchase) => StorePurchase(
          provider: provider!,
          productId: purchase.productID,
          state: switch (purchase.status) {
            PurchaseStatus.pending => StorePurchaseState.pending,
            PurchaseStatus.purchased => StorePurchaseState.purchased,
            PurchaseStatus.restored => StorePurchaseState.restored,
            PurchaseStatus.canceled => StorePurchaseState.canceled,
            PurchaseStatus.error => StorePurchaseState.error,
          },
          transactionId: purchase.purchaseID,
          purchaseToken: provider == BillingProvider.google
              ? purchase.verificationData.serverVerificationData : null,
          needsCompletion: purchase.pendingCompletePurchase,
          nativeHandle: purchase,
        )).toList(growable: false));

  @override
  Future<bool> isAvailable() async => provider != null && await _store.isAvailable();

  /// Only the regular recurring base price is offered. Promotional/trial and
  /// prepaid plans must not silently change the price or renewal description.
  static bool isRegularPlan(ProductDetails product, PlusPeriod period) {
    if (product.price.trim().isEmpty || product.rawPrice <= 0) return false;
    if (product is GooglePlayProductDetails) {
      final index = product.subscriptionIndex;
      final offers = product.productDetails.subscriptionOfferDetails;
      if (index == null || offers == null || index >= offers.length) return false;
      final offer = offers[index];
      if (offer.offerId != null || offer.pricingPhases.length != 1) return false;
      final price = offer.pricingPhases.single;
      return price.recurrenceMode == RecurrenceMode.infiniteRecurring &&
          price.priceAmountMicros > 0 &&
          price.billingPeriod == (period == PlusPeriod.month ? 'P1M' : 'P1Y');
    }
    if (product is AppStoreProduct2Details) {
      final subscription = product.sk2Product.subscription;
      if (product.sk2Product.type != SK2ProductType.autoRenewable || subscription == null) return false;
      // Introductory offers auto-apply to eligible users on StoreKit. Keep this
      // no-trial release unavailable if an introductory offer is configured.
      if (subscription.promotionalOffers.any((offer) => offer.type == SK2SubscriptionOfferType.introductory)) return false;
      return subscription.subscriptionPeriod.value == 1 &&
          subscription.subscriptionPeriod.unit == (period == PlusPeriod.month
              ? SK2SubscriptionPeriodUnit.month : SK2SubscriptionPeriodUnit.year);
    }
    // StoreKit 2 is the supported Apple path; do not sell an unknown product.
    return false;
  }

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async {
    if (provider == null) return [];
    final response = await _store.queryProductDetails(ids);
    if (response.error != null) throw const BillingFailure('store_unavailable', retryable: true);
    _details.clear();
    for (final period in PlusPeriod.values) {
      if (!ids.contains(period.productId)) continue;
      final matches = response.productDetails.where((p) =>
          p.id == period.productId && isRegularPlan(p, period)).toList();
      // Ambiguous base plans must be corrected in Play Console first.
      if (matches.length == 1) _details[period.productId] = matches.single;
    }
    return [for (final period in PlusPeriod.values)
      if (_details[period.productId] case final detail?)
        StoreProduct(id: detail.id, price: detail.price, period: period),
    ];
  }

  @override
  Future<bool> buy(StoreProduct product, {required String accountBinding}) async {
    final detail = _details[product.id];
    if (provider == null || detail == null) throw const BillingFailure('product_unavailable');
    return _store.buyNonConsumable(purchaseParam: PurchaseParam(
      productDetails: detail,
      // StoreKit 2: appAccountToken. Play: obfuscatedExternalAccountId.
      applicationUserName: accountBinding,
    ));
  }

  @override
  Future<void> restore({required String accountBinding}) async {
    if (provider == null) throw const BillingFailure('store_unavailable');
    await _store.restorePurchases(applicationUserName: accountBinding);
  }

  @override
  Future<void> complete(StorePurchase purchase) async {
    final detail = purchase.nativeHandle;
    if (detail is! PurchaseDetails || !detail.pendingCompletePurchase) return;
    await _store.completePurchase(detail);
  }

  @override
  Future<void> dispose() async { _details.clear(); }
}
