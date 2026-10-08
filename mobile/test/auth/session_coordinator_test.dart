import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/auth/auth_models.dart';
import 'package:hamtdaa/auth/auth_repository.dart';
import 'package:hamtdaa/auth/session_coordinator.dart';

class _FakeAuth implements AuthRepository {
  final _events = StreamController<AuthSession>.broadcast();
  AuthSession _current = const AuthSession.signedOut();

  @override
  AuthSession get current => _current;

  @override
  Stream<AuthSession> get sessions => _events.stream;

  void emit(AuthSession value) {
    _current = value;
    _events.add(value);
  }

  @override
  Future<void> requestEmailCode(String email) async {}

  @override
  Future<AuthSession> verifyEmailCode(String email, String code) async =>
      _current;

  @override
  Future<void> signOut() async => emit(const AuthSession.signedOut());

  Future<void> dispose() => _events.close();
}

void main() {
  test('signout and same-user login never revive an old account scope', () async {
    final auth = _FakeAuth();
    final coordinator = SessionCoordinator(auth);
    const login = AuthSession.signedIn(userId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', email: 'a@example.com', epoch: 1);
    auth.emit(login);
    await Future<void>.delayed(Duration.zero);
    final original = coordinator.current.scope;
    await coordinator.signOut();
    await Future<void>.delayed(Duration.zero);
    auth.emit(login);
    await Future<void>.delayed(Duration.zero);
    final reopened = coordinator.current.scope;
    expect(coordinator.accepts(original), isFalse);
    expect(coordinator.accepts(reopened), isTrue);
    auth.emit(login);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.current.scope, reopened);
    await coordinator.dispose();
    await auth.dispose();
  });

  test('identity change always invalidates the previous account scope', () async {
    final auth = _FakeAuth();
    final coordinator = SessionCoordinator(auth);
    auth.emit(
      const AuthSession.signedIn(
        userId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        email: 'a@example.com',
        epoch: 1,
      ),
    );
    final a = coordinator.current.scope;
    expect(coordinator.accepts(a), isTrue);

    auth.emit(
      const AuthSession.signedIn(
        userId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        email: 'b@example.com',
        epoch: 1,
      ),
    );
    expect(coordinator.accepts(a), isFalse);
    expect(coordinator.current.scope.userId, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
    expect(coordinator.current.epoch, 2);

    await coordinator.dispose();
    await auth.dispose();
  });

  test('signed-out state rejects a late callback scope', () async {
    final auth = _FakeAuth();
    final coordinator = SessionCoordinator(auth);
    auth.emit(
      const AuthSession.signedIn(
        userId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        email: 'a@example.com',
        epoch: 4,
      ),
    );
    final scope = coordinator.current.scope;
    await coordinator.signOut();
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.accepts(scope), isFalse);
    await coordinator.dispose();
    await auth.dispose();
  });
}
