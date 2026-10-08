import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'pair_models.dart';
import 'pair_repository.dart';

typedef PairRpcTransport = Future<dynamic> Function(
  String name,
  Map<String, dynamic> parameters,
);

class SupabasePairRepository implements PairRepository {
  SupabasePairRepository(SupabaseClient client)
    : _rpc = ((name, parameters) => client.rpc(name, params: parameters)),
      _sessionCurrent = (() => client.auth.currentSession != null),
      _accountId = client.auth.currentUser?.id {
    final identity = _accountId;
    _sessionCurrent = () =>
        identity != null &&
        client.auth.currentSession != null &&
        client.auth.currentUser?.id == identity;
    _subscription = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut ||
            state.session?.user.id != identity) {
          _invalidate();
        }
      },
      onError: (Object _, StackTrace _) => _invalidate(),
    );
  }

  SupabasePairRepository.withTransport({
    required PairRpcTransport rpc,
    required bool Function() sessionCurrent,
    required String accountId,
  }) : _rpc = rpc,
       _sessionCurrent = sessionCurrent,
       _accountId = accountId;

  final PairRpcTransport _rpc;
  bool Function() _sessionCurrent;
  final String? _accountId;
  final _invalidations = StreamController<void>.broadcast(sync: true);
  StreamSubscription<AuthState>? _subscription;
  bool _valid = true;
  bool _disposed = false;

  @override
  Stream<void> get invalidations => _invalidations.stream;

  void _invalidate() {
    if (!_valid || _disposed) return;
    _valid = false;
    _invalidations.add(null);
  }

  void _checkSession() {
    if (_disposed || !_valid || !_sessionCurrent()) {
      _invalidate();
      throw const PairFailure('unauthenticated');
    }
  }

  Future<Map<String, dynamic>> _call(
    String rpc,
    Map<String, dynamic> parameters, {
    bool expectsOk = true,
  }) async {
    _checkSession();
    try {
      final raw = await _rpc(rpc, parameters).timeout(const Duration(seconds: 15));
      _checkSession();
      final result = Map<String, dynamic>.from(raw as Map);
      if (expectsOk && result['ok'] != true) {
        final failure = PairFailure(
          result['code'] is String ? result['code'] as String : 'invalid_response',
          retryable: result['retryable'] == true,
        );
        if (failure.code == 'unauthenticated') _invalidate();
        throw failure;
      }
      return result;
    } on PairFailure {
      rethrow;
    } on PostgrestException catch (error) {
      final code = switch (error.code) {
        '42501' || 'PGRST301' || 'PGRST302' || 'PGRST303' => 'unauthenticated',
        '22023' => 'validation',
        _ => error.message == 'version_conflict' ? 'conflict' : 'network_error',
      };
      if (code == 'unauthenticated') _invalidate();
      throw PairFailure(code, retryable: code == 'network_error');
    } on AuthException {
      _invalidate();
      throw const PairFailure('unauthenticated');
    } catch (_) {
      // Transport/SQL details and token-bearing payloads are never surfaced.
      throw const PairFailure('network_error', retryable: true);
    }
  }

  @override
  Future<PairSnapshot> status() async {
    final result = await _call('hamtdaa_pair_status', const {});
    try {
      final snapshot = PairSnapshot.fromJson(result);
      if (snapshot.profile.userId != _accountId) {
        _invalidate();
        throw const PairFailure('unauthenticated');
      }
      return snapshot;
    } on PairFailure {
      rethrow;
    } catch (_) {
      throw const PairFailure('invalid_response', retryable: true);
    }
  }

  @override
  Future<PairInvitation> preview(String token) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const PairFailure('not_found');
    }
    final result = await _call('hamtdaa_preview_pair_invite', {'p_token': token});
    try {
      return PairInvitation.fromJson(result['invitation'] as Map<String, dynamic>);
    } catch (_) {
      throw const PairFailure('invalid_response', retryable: true);
    }
  }

  @override
  Future<Map<String, dynamic>> execute(PairCommand command) => _call(
    command.rpc,
    command.parameters,
    expectsOk: command.kind != PairCommandKind.updateName,
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _valid = false;
    unawaited(_subscription?.cancel());
    unawaited(_invalidations.close());
  }
}
