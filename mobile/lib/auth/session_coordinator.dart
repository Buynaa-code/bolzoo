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
  AccountScope? _sourceScope;
  int _epoch = 0;
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
    var repaired = next;
    if (next.isSignedIn) {
      if (!_session.isSignedIn || _sourceScope != next.scope) {
        // Keep this high-water mark while signed out, even if the next login
        // reuses the previous user's source epoch.
        _epoch = next.epoch > _epoch ? next.epoch : _epoch + 1;
      }
      _sourceScope = next.scope;
      repaired = AuthSession.signedIn(
        userId: next.userId!,
        email: next.email ?? '',
        epoch: _epoch,
      ).withMessage(next.message);
    } else {
      if (_session.isSignedIn) _epoch++;
      _sourceScope = null;
    }
    if (_session.status == repaired.status &&
        _session.userId == repaired.userId &&
        _session.email == repaired.email &&
        _session.epoch == repaired.epoch &&
        _session.message == repaired.message) {
      return;
    }
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
