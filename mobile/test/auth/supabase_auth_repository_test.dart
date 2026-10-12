import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/auth/auth_models.dart';
import 'package:hamtdaa/auth/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _SdkAuth extends GoTrueClient {
  _SdkAuth(this.currentSession) : super(autoRefreshToken: false);

  final events = StreamController<AuthState>.broadcast();
  @override
  Session? currentSession;
  @override
  Stream<AuthState> get onAuthStateChange => events.stream;

  void emit(AuthChangeEvent event, [Session? session]) {
    currentSession = session;
    events.add(AuthState(event, session));
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    throw StateError('internal transport fixture');
  }

  @override
  Future<void> dispose() async {
    await events.close();
    super.dispose();
  }
}

Session _signedInSession() => Session(
  accessToken: 'test-token',
  tokenType: 'bearer',
  user: const User(
    id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '',
    email: 'a@example.com',
  ),
);

void main() {
  test('SDK refresh callbacks do not create extra account lifetimes', () async {
    final sdk = _SdkAuth(null);
    final repository = SupabaseAuthRepository.withAuthClient(sdk);
    final events = <AuthSession>[];
    final subscription = repository.sessions.listen(events.add);
    final session = Session(
      accessToken: 'test-token',
      tokenType: 'bearer',
      user: const User(
        id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '',
        email: 'a@example.com',
      ),
    );
    sdk.emit(AuthChangeEvent.signedIn, session);
    await Future<void>.delayed(Duration.zero);
    final original = repository.current.scope;
    sdk.emit(AuthChangeEvent.tokenRefreshed, session);
    sdk.emit(AuthChangeEvent.signedIn, session);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(repository.current.scope, original);
    sdk.emit(AuthChangeEvent.signedOut);
    await Future<void>.delayed(Duration.zero);
    sdk.emit(AuthChangeEvent.signedIn, session);
    await Future<void>.delayed(Duration.zero);
    expect(repository.current.scope, isNot(original));
    expect(events, hasLength(3));
    await subscription.cancel();
    await repository.dispose();
    await sdk.dispose();
  });

  test('SDK refresh errors retain the current account lifetime', () async {
    final sdk = _SdkAuth(_signedInSession());
    final repository = SupabaseAuthRepository.withAuthClient(sdk);
    final original = repository.current.scope;
    sdk.events.addError(StateError('internal transport fixture'));
    await Future<void>.delayed(Duration.zero);
    expect(repository.current.isSignedIn, isTrue);
    expect(repository.current.scope, original);
    expect(repository.current.message, isNotNull);
    expect(repository.current.message, isNot(contains('internal transport')));
    await repository.dispose();
    await sdk.dispose();
  });

  test('signout transport failure exposes a retryable safe error', () async {
    final sdk = _SdkAuth(_signedInSession());
    final repository = SupabaseAuthRepository.withAuthClient(sdk);
    final original = repository.current.scope;
    await expectLater(
      repository.signOut(),
      throwsA(
        isA<AuthFailure>()
            .having((error) => error.code, 'code', 'sign_out_error')
            .having((error) => error.retryable, 'retryable', isTrue)
            .having(
              (error) => error.message,
              'message',
              isNot(contains('internal transport')),
            ),
      ),
    );
    expect(repository.current.scope, original);
    await repository.dispose();
    await sdk.dispose();
  });
}
