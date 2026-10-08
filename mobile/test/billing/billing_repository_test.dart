import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/billing/billing_models.dart';
import 'package:hamtdaa/billing/billing_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_session_storage.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';

import 'billing_fakes.dart';

class _Storage implements CloudflareSessionStorage {
  String? value;
  @override Future<String?> read() async => value;
  @override Future<void> write(String value) async => this.value = value;
  @override Future<void> clear() async => value = null;
}

Map<String, dynamic> _status({bool plus = false}) => {
  'ok': true,
  'entitlement': {'tier': plus ? 'plus' : 'free', 'premium_cards': plus,
    'source': plus ? 'self' : null, 'provider': plus ? 'apple' : null,
    'expires_at': plus ? DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String() : null},
  'store_account': {'apple': appleAccount, 'google': googleAccount},
};

class _Transport implements CloudflareTransport {
  final requests = <({String method, String path, String? token, Map<String, dynamic>? body})>[];
  Future<CloudflareResponse> Function()? onBilling;
  @override
  Future<CloudflareResponse> send(String method, String path, {String? token, Map<String, dynamic>? body}) async {
    requests.add((method: method, path: path, token: token, body: body));
    if (path == '/v1/auth/verify-code') {
      final actor = (body!['email'] as String).split('@').first;
      return CloudflareResponse(200, {'ok': true, 'token': 'token-$actor', 'user': {'id': actor, 'email': body['email']}, 'expires_at': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String()});
    }
    if (path == '/v1/auth/sign-out') return const CloudflareResponse(200, {'ok': true});
    return onBilling == null ? CloudflareResponse(200, _status()) : await onBilling!();
  }
  @override void close() {}
}

void main() {
  late _Transport transport;
  late CloudflareAuthRepository auth;
  late CloudflareBillingRepository repository;
  setUp(() async {
    transport = _Transport();
    auth = CloudflareAuthRepository(transport: transport, storage: _Storage());
    await auth.verifyEmailCode('a@example.com', '123456');
    repository = CloudflareBillingRepository(auth);
  });
  tearDown(() async { await repository.dispose(); await auth.dispose(); });

  test('verify sends provider-specific evidence with pinned bearer, no client grant', () async {
    await repository.verify(purchase());
    final request = transport.requests.last;
    expect(request.token, 'token-a');
    expect(request.path, '/v1/billing/store/verify');
    expect(request.body, {'provider': 'apple', 'product_id': PlusPeriod.month.productId, 'transaction_id': '10001'});
    await repository.verify(purchase(provider: BillingProvider.google));
    expect(transport.requests.last.body, {'provider': 'google', 'product_id': PlusPeriod.month.productId, 'purchase_token': 'opaque-token'});
  });

  test('late verification is discarded after switching to another account', () async {
    final response = Completer<CloudflareResponse>();
    transport.onBilling = () => response.future;
    final future = repository.verify(purchase());
    final expected = expectLater(future, throwsA(isA<BillingFailure>().having((e) => e.code, 'code', 'unauthenticated')));
    await auth.verifyEmailCode('b@example.com', '123456');
    response.complete(CloudflareResponse(200, _status(plus: true)));
    await expected;
    expect(repository.isCurrent, isFalse);
    expect(auth.current.userId, 'b');
    expect(transport.requests.where((r) => r.path.contains('/billing/')).single.token, 'token-a');
  });

  test('401 invalidates the exact auth session but 503 leaves it retryable', () async {
    transport.onBilling = () async => const CloudflareResponse(503, {'ok': false, 'code': 'temporarily_unavailable'});
    await expectLater(repository.status(), throwsA(isA<BillingFailure>().having((e) => e.retryable, 'retryable', true)));
    expect(auth.current.isSignedIn, isTrue);
    transport.onBilling = () async => const CloudflareResponse(401, {'ok': false});
    await expectLater(repository.status(), throwsA(isA<BillingFailure>().having((e) => e.code, 'code', 'unauthenticated')));
    expect(auth.current.isSignedIn, isFalse);
  });

  test('malformed or incomplete Plus response is never accepted', () async {
    final malformed = _status(plus: true);
    (malformed['entitlement'] as Map)['expires_at'] = null;
    transport.onBilling = () async => CloudflareResponse(200, malformed);
    await expectLater(repository.status(), throwsA(isA<BillingFailure>().having((e) => e.code, 'code', 'invalid_response')));
  });
}
