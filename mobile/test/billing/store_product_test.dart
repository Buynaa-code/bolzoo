import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/billing/billing_models.dart';
import 'package:hamtdaa/billing/store_gateway.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

GooglePlayProductDetails google({String? offerId, String period = 'P1M', RecurrenceMode mode = RecurrenceMode.infiniteRecurring, bool trial = false}) {
  final regular = PricingPhaseWrapper(billingCycleCount: 0, billingPeriod: period, formattedPrice: '₮9,900', priceAmountMicros: 9900000000, priceCurrencyCode: 'MNT', recurrenceMode: mode);
  return GooglePlayProductDetails.fromProductDetails(ProductDetailsWrapper(description: 'Plus', name: 'Plus', productId: PlusPeriod.month.productId, productType: ProductType.subs, title: 'Plus', subscriptionOfferDetails: [SubscriptionOfferDetailsWrapper(basePlanId: 'monthly', offerId: offerId, offerTags: [], offerIdToken: 'opaque-offer-token', pricingPhases: [
    if (trial) const PricingPhaseWrapper(billingCycleCount: 1, billingPeriod: 'P1W', formattedPrice: 'Free', priceAmountMicros: 0, priceCurrencyCode: 'MNT', recurrenceMode: RecurrenceMode.finiteRecurring),
    regular,
  ])])).single;
}

AppStoreProduct2Details apple({bool trial = false, SK2ProductType type = SK2ProductType.autoRenewable, SK2SubscriptionPeriodUnit unit = SK2SubscriptionPeriodUnit.month}) => AppStoreProduct2Details.fromSK2Product(SK2Product(
  id: PlusPeriod.month.productId, displayName: 'Plus', displayPrice: '₮9,900', description: 'Plus', price: 9900, type: type, priceLocale: SK2PriceLocale(currencyCode: 'MNT', currencySymbol: '₮'),
  subscription: SK2SubscriptionInfo(subscriptionGroupID: 'hamtdaa-plus', subscriptionPeriod: SK2SubscriptionPeriod(value: 1, unit: unit), promotionalOffers: [
    if (trial) SK2SubscriptionOffer(price: 0, type: SK2SubscriptionOfferType.introductory, period: const SK2SubscriptionPeriod(value: 1, unit: SK2SubscriptionPeriodUnit.week), periodCount: 1, paymentMode: SK2SubscriptionOfferPaymentMode.freeTrial),
  ]),
));

void main() {
  test('Google only sells regular recurring plan matching displayed period', () {
    expect(InAppPurchaseGateway.isRegularPlan(google(), PlusPeriod.month), isTrue);
    expect(InAppPurchaseGateway.isRegularPlan(google(offerId: 'intro'), PlusPeriod.month), isFalse);
    expect(InAppPurchaseGateway.isRegularPlan(google(trial: true), PlusPeriod.month), isFalse);
    expect(InAppPurchaseGateway.isRegularPlan(google(mode: RecurrenceMode.nonRecurring), PlusPeriod.month), isFalse);
    expect(InAppPurchaseGateway.isRegularPlan(google(period: 'P1Y'), PlusPeriod.month), isFalse);
  });
  test('Apple validates renewable duration and excludes configured free trial', () {
    expect(InAppPurchaseGateway.isRegularPlan(apple(), PlusPeriod.month), isTrue);
    expect(InAppPurchaseGateway.isRegularPlan(apple(trial: true), PlusPeriod.month), isFalse);
    expect(InAppPurchaseGateway.isRegularPlan(apple(type: SK2ProductType.nonConsumable), PlusPeriod.month), isFalse);
    expect(InAppPurchaseGateway.isRegularPlan(apple(unit: SK2SubscriptionPeriodUnit.year), PlusPeriod.month), isFalse);
  });
}
