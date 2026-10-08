import 'dart:async';

import 'auth_models.dart';
import 'auth_repository.dart';

/// Owns the account lifetime. Feature screens never refresh or clear sessions
/// on their own, which prevents a late response from account A reaching B.
class SessionCoordinator {
  SessionCoordinator(this._auth) {
    _subscription = _auth.sessions.listen(_onSession);
    _onSession(_auth.current);
  }

  final AuthRepository _auth;
  final _controller = StreamController<AuthSession>.broadcast();
  late final StreamSubscription<AuthSession> _subscription;
  AuthSession _session = const AuthSession.signedOut();
  bool _closed = false;

  AuthSession get current => _session;
  Stream<AuthSession> get sessions => _controller.stream;

  bool accepts(AccountScope scope) =>
      !_closed &&
      _session.isSignedIn &&
      _session.userId == scope.userId &&
      _session.epoch == scope.epoch;

  Future<void> signOut() => _auth.signOut();

  void _onSession(AuthSession next) {
    if (_closed) return;
    // Auth implementations must increment epoch for every identity change.
    // We still repair a reused epoch here so callers cannot accidentally
    // accept a response from the previous account.
    final changedIdentity = next.userId != _session.userId;
    final repaired = changedIdentity && next.epoch <= _session.epoch
        ? AuthSession.signedIn(
            userId: next.userId!,
            email: next.email!,
            epoch: _session.epoch + 1,
          )
        : next;
    _session = repaired;
    _controller.add(repaired);
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _controller.close();
  }
}
