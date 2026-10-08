import 'dart:async';

import '../pair/pair_models.dart';
import '../pair/pair_repository.dart';
import 'cloudflare_auth_repository.dart';

/// An instance belongs to one exact login, including repeat logins by the same
/// user. Every request pins its bearer before awaiting network work.
class CloudflarePairRepository implements PairRepository {
  CloudflarePairRepository(this._auth) : _credential = _auth.credential {
    _subscription = _auth.sessions.listen((_) {
      if (!_current) _invalidate();
    });
  }

  final CloudflareAuthRepository _auth;
  final CloudflareCredential? _credential;
  final _invalidations = StreamController<void>.broadcast(sync: true);
  late final StreamSubscription<dynamic> _subscription;
  bool _valid = true;
  bool _disposed = false;

  bool get _current => !_disposed && _valid && _credential != null && _auth.accepts(_credential);

  @override
  Stream<void> get invalidations => _invalidations.stream;

  void _invalidate() {
    if (_disposed || !_valid) return;
    _valid = false;
    _invalidations.add(null);
  }

  void _check() {
    if (!_current) {
      _invalidate();
      throw const PairFailure('unauthenticated');
    }
  }

  Future<Map<String, dynamic>> _call(String method, String path, {
    Map<String, dynamic>? body,
    bool expectsOk = true,
  }) async {
    _check();
    try {
      final response = await _auth.transport.send(method, path, token: _credential!.token, body: body);
      _check();
      if (response.status == 401) {
        _invalidate();
        await _auth.reject(_credential);
        throw const PairFailure('unauthenticated');
      }
      final result = response.body;
      if (response.status < 200 || response.status >= 300 || result['ok'] == false || (expectsOk && result['ok'] != true)) {
        final code = result['code'] is String ? result['code'] as String : 'invalid_response';
        throw PairFailure(code, retryable: result['retryable'] == true || response.status >= 500);
      }
      return result;
    } on PairFailure {
      rethrow;
    } catch (_) {
      // Do not leak HTTP bodies, bearer keys, invite tokens or server details.
      throw const PairFailure('network_error', retryable: true);
    }
  }

  @override
  Future<PairSnapshot> status() async {
    final result = await _call('GET', '/v1/pair/status');
    try {
      final snapshot = PairSnapshot.fromJson(result);
      if (snapshot.profile.userId != _credential!.scope.userId) {
        _invalidate();
        throw const PairFailure('unauthenticated');
      }
      return snapshot;
    } on PairFailure { rethrow; } catch (_) {
      throw const PairFailure('invalid_response', retryable: true);
    }
  }

  @override
  Future<PairInvitation> preview(String token) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) throw const PairFailure('not_found');
    final result = await _call('POST', '/v1/pair/preview', body: {'token': token});
    try {
      return PairInvitation.fromJson(result['invitation'] as Map<String, dynamic>);
    } catch (_) { throw const PairFailure('invalid_response', retryable: true); }
  }

  @override
  Future<Map<String, dynamic>> execute(PairCommand command) {
    final name = switch (command.kind) {
      PairCommandKind.create => 'create',
      PairCommandKind.request => 'request',
      PairCommandKind.confirm => 'confirm',
      PairCommandKind.close => 'close',
      PairCommandKind.unlink => 'unlink',
      PairCommandKind.updateName => 'update-name',
    };
    return _call('POST', '/v1/pair/commands/$name', body: {
      for (final entry in command.parameters.entries)
        entry.key.replaceFirst(RegExp(r'^p_'), ''): entry.value,
    }, expectsOk: command.kind != PairCommandKind.updateName);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _valid = false;
    unawaited(_subscription.cancel());
    unawaited(_invalidations.close());
  }
}
