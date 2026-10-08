enum BillingProvider {
  apple,
  google;

  String get label => this == apple ? 'App Store' : 'Google Play';
}

enum PlusPeriod {
  month,
  year;

  String get label => this == month ? 'Сар бүр' : 'Жил бүр';
  String get suffix => this == month ? 'сар' : 'жил';
  String get productId => this == month
      ? 'mn.moch.hamtdaa.plus.monthly'
      : 'mn.moch.hamtdaa.plus.yearly';
}

class BillingFailure implements Exception {
  const BillingFailure(this.code, {this.retryable = false});
  final String code;
  final bool retryable;

  String get message => switch (code) {
    'unauthenticated' || 'session_changed' =>
      'Нэвтрэлт өөрчлөгдсөн байна. Дахин нэвтэрнэ үү.',
    'store_unavailable' || 'billing_unavailable' || 'provider_unavailable' ||
    'store_not_configured' =>
      'Дэлгүүрийн худалдан авалт одоогоор бэлэн болоогүй байна. Үнэгүй боломжуудаа ашиглаарай.',
    'product_unavailable' =>
      'Энэ багц дэлгүүрт хараахан бэлэн болоогүй байна.',
    'account_mismatch' || 'purchase_account_mismatch' || 'purchase_owned' =>
      'Энэ худалдан авалт өөр бүртгэлд хамаарч байна. Анх худалдан авсан бүртгэлээрээ нэвтэрнэ үү.',
    'invalid_purchase' || 'invalid_product' || 'invalid_proof' =>
      'Дэлгүүрийн худалдан авалтыг баталгаажуулж чадсангүй.',
    'purchase_pending' => 'Төлбөрийн зөвшөөрлийг хүлээж байна.',
    'complete_failed' =>
      'Эрх баталгаажсан. Дэлгүүрийн баталгаажуулалтыг дуусгахын тулд дахин оролдоно уу.',
    'legal_unavailable' =>
      'Үйлчилгээний нөхцөл бэлэн болмогц худалдан авалт нээгдэнэ.',
    'rate_limited' => 'Түр хүлээгээд дахин оролдоорой.',
    _ => 'Худалдан авалтын төлөвийг шалгаж чадсангүй. Дахин оролдоорой.',
  };

  @override
  String toString() => 'BillingFailure($code)';
}

class BillingEntitlement {
  const BillingEntitlement({
    required this.tier,
    required this.premiumCards,
    this.source,
    this.expiresAt,
    this.provider,
  });
  const BillingEntitlement.free()
    : tier = 'free', premiumCards = false, source = null,
      expiresAt = null, provider = null;

  final String tier;
  final bool premiumCards;
  final String? source;
  final DateTime? expiresAt;
  final String? provider;

  bool activeAt(DateTime now) => tier == 'plus' && premiumCards &&
      expiresAt != null && expiresAt!.isAfter(now);

  factory BillingEntitlement.fromJson(Map<String, dynamic> json) {
    final tier = json['tier'];
    final source = json['source'];
    final provider = json['provider'];
    final expires = json['expires_at'];
    if (!['free', 'plus'].contains(tier) ||
        json['premium_cards'] is! bool ||
        ![null, 'self', 'partner'].contains(source) ||
        ![null, 'apple', 'google', 'qpay'].contains(provider)) {
      throw const FormatException('Invalid entitlement');
    }
    final expiry = expires == null ? null : DateTime.parse(expires as String);
    if (tier == 'plus' && (source == null || expiry == null)) {
      throw const FormatException('Missing entitlement owner or expiry');
    }
    return BillingEntitlement(
      tier: tier as String,
      premiumCards: json['premium_cards'] as bool,
      source: source as String?,
      expiresAt: expiry,
      provider: provider as String?,
    );
  }
}

class BillingSnapshot {
  const BillingSnapshot({required this.entitlement, required this.storeAccounts});
  final BillingEntitlement entitlement;
  final Map<BillingProvider, String> storeAccounts;

  factory BillingSnapshot.fromJson(Map<String, dynamic> json) {
    final values = json['store_account'] as Map<String, dynamic>;
    final apple = values['apple'];
    final google = values['google'];
    if (apple is! String ||
        !RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$').hasMatch(apple) ||
        google is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(google)) {
      throw const FormatException('Invalid store account binding');
    }
    return BillingSnapshot(
      entitlement: BillingEntitlement.fromJson(json['entitlement'] as Map<String, dynamic>),
      storeAccounts: Map.unmodifiable({BillingProvider.apple: apple, BillingProvider.google: google}),
    );
  }
}

class BillingCatalog {
  const BillingCatalog({required this.enabled, required this.products});
  final Set<BillingProvider> enabled;
  final Map<BillingProvider, Set<String>> products;

  factory BillingCatalog.fromJson(Map<String, dynamic> json) {
    final native = json['native_enabled'] as Map<String, dynamic>;
    final enabled = BillingProvider.values.where((p) => native[p.name] == true).toSet();
    final products = <BillingProvider, Set<String>>{};
    for (final raw in json['products'] as List) {
      final item = raw as Map<String, dynamic>;
      final provider = BillingProvider.values.where((p) => p.name == item['provider']).firstOrNull;
      final period = PlusPeriod.values.where((p) => p.name == item['period']).firstOrNull;
      if (provider != null && period != null && item['id'] == period.productId) {
        products.putIfAbsent(provider, () => {}).add(period.productId);
      }
    }
    return BillingCatalog(enabled: Set.unmodifiable(enabled), products: Map.unmodifiable(products));
  }
}

enum StorePurchaseState { pending, purchased, restored, canceled, error }

class StoreProduct {
  const StoreProduct({required this.id, required this.price, required this.period});
  final String id;
  /// Localized, current price returned by the native store. Never a fallback.
  final String price;
  final PlusPeriod period;
}

class StorePurchase {
  const StorePurchase({
    required this.provider,
    required this.productId,
    required this.state,
    this.transactionId,
    this.purchaseToken,
    this.needsCompletion = false,
    this.nativeHandle,
  });
  final BillingProvider provider;
  final String productId;
  final StorePurchaseState state;
  final String? transactionId;
  final String? purchaseToken;
  final bool needsCompletion;
  final Object? nativeHandle;

  Map<String, dynamic> verificationBody() => {
    'provider': provider.name,
    'product_id': productId,
    if (provider == BillingProvider.apple) 'transaction_id': transactionId,
    if (provider == BillingProvider.google) 'purchase_token': purchaseToken,
  };
}
