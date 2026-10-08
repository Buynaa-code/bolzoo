import 'dart:async';

import '../cloudflare/cloudflare_auth_repository.dart';
import 'billing_models.dart';

abstract interface class BillingRepository {
  bool get isCurrent;
  Stream<void> get invalidations;
  Future<BillingCatalog> catalog();
  Future<BillingSnapshot> status();
  Future<BillingSnapshot> verify(StorePurchase purchase);
  Future<void> dispose();
}

/// Bound to one exact authenticated session, never to whichever user logs in next.
class CloudflareBillingRepository implements BillingRepository {
  CloudflareBillingRepository(this._auth) : _credential = _auth.credential {
    _sessionChanges = _auth.sessions.listen((_) {
      if (!isCurrent) _invalidate();
    });
  }
  final CloudflareAuthRepository _auth;
  final CloudflareCredential? _credential;
  late final StreamSubscription<dynamic> _sessionChanges;
  final _invalidations = StreamController<void>.broadcast(sync: true);
  bool _valid = true;
  bool _disposed = false;

  @override
  bool get isCurrent => !_disposed && _valid && _credential != null && _auth.accepts(_credential);
  @override
  Stream<void> get invalidations => _invalidations.stream;

  void _invalidate() {
    if (!_valid || _disposed) return;
    _valid = false;
    _invalidations.add(null);
  }

  void _check() {
    if (!isCurrent) {
      _invalidate();
      throw const BillingFailure('unauthenticated');
    }
  }

  Future<Map<String, dynamic>> _call(String method, String path, {Map<String, dynamic>? body}) async {
    _check();
    try {
      final response = await _auth.transport.send(method, path, token: _credential!.token, body: body);
      _check();
      if (response.status == 401) {
        _invalidate();
        try { await _auth.reject(_credential); } catch (_) { /* Access is already closed. */ }
        throw const BillingFailure('unauthenticated');
      }
      if (response.status < 200 || response.status >= 300 || response.body['ok'] != true) {
        throw BillingFailure(
          response.body['code'] is String ? response.body['code'] as String : 'invalid_response',
          retryable: response.body['retryable'] == true || response.status >= 500,
        );
      }
      return response.body;
    } on BillingFailure {
      rethrow;
    } catch (_) {
      _check();
      throw const BillingFailure('network_error', retryable: true);
    }
  }

  @override
  Future<BillingCatalog> catalog() async {
    final result = await _call('GET', '/v1/billing/catalog');
    try { return BillingCatalog.fromJson(result); }
    catch (_) { throw const BillingFailure('invalid_response', retryable: true); }
  }

  Future<BillingSnapshot> _snapshot(String method, String path, {Map<String, dynamic>? body}) async {
    final result = await _call(method, path, body: body);
    try { return BillingSnapshot.fromJson(result); }
    catch (_) { throw const BillingFailure('invalid_response', retryable: true); }
  }

  @override
  Future<BillingSnapshot> status() => _snapshot('GET', '/v1/billing/status');

  @override
  Future<BillingSnapshot> verify(StorePurchase purchase) => _snapshot(
    'POST', '/v1/billing/store/verify', body: purchase.verificationBody(),
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _valid = false;
    await _sessionChanges.cancel();
    await _invalidations.close();
  }
}
