import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/account/account_deletion.dart';
import 'package:hamtdaa/account/account_initializer.dart';
import 'package:hamtdaa/account/account_repository.dart';
import 'package:hamtdaa/auth/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _a = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _b = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

Matcher _code(String value) => isA<AccountOperationException>().having(
  (error) => error.code,
  'code',
  value,
);

class _Repository implements AccountRepository {
  _Repository(this.userId);
  @override
  final String userId;
  @override
  bool sessionCurrent = true;
  final called = Completer<void>();
  final finished = Completer<void>();
  @override
  Future<void> deleteAccount() async {
    called.complete();
    await finished.future;
  }
  @override
  Future<Map<String, dynamic>> exportData() => throw UnimplementedError();
  @override
  Future<Uint8List> downloadMedia(String key) => throw UnimplementedError();
}

class _SdkAuth extends GoTrueClient {
  _SdkAuth(this.currentSession) : super(autoRefreshToken: false);
  final events = StreamController<AuthState>.broadcast();
  final logoutStarted = Completer<void>(), logoutFinished = Completer<void>();
  @override
  Session? currentSession;
  @override
  Stream<AuthState> get onAuthStateChange => events.stream;
  void login(Session session) {
    currentSession = session;
    events.add(AuthState(AuthChangeEvent.signedIn, session));
  }
  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    currentSession = null;
    events.add(AuthState(AuthChangeEvent.signedOut, null));
    logoutStarted.complete();
    await logoutFinished.future;
  }
  @override
  Future<void> dispose() async {
    await events.close();
    super.dispose();
  }
}

Session _session(String id) => Session(
  accessToken: 'fixture-token-$id', tokenType: 'bearer',
  user: User(id: id, appMetadata: const {}, userMetadata: const {}, aud: 'authenticated', createdAt: ''),
);

void main() {
  for (final staleSession in [false, true]) {
    test('foreign deleting status never journals or purges A (stale=$staleSession)', () async {
      final response = Completer<Map<String, dynamic>>();
      final requested = Completer<void>();
      var current = true;
      final effects = <String>[];
      final operation = initializeAccountAccess(
        userId: _a, sessionCurrent: () => current,
        pending: () async => false,
        status: () { requested.complete(); return response.future; },
        markPending: () async => effects.add('mark'),
        purgeLocal: () async => effects.add('purge'),
        bootstrap: () async => effects.add('bootstrap'),
      );
      await requested.future;
      if (staleSession) current = false;
      final assertion = expectLater(operation, throwsA(_code(staleSession ? 'session_changed' : 'invalid_status')));
      response.complete({'ok': true, 'userId': _b, 'state': 'deleting'});
      await assertion;
      expect(effects, isEmpty);
    });
  }

  test('scope change during pending lookup stops before any status request', () async {
    final pending = Completer<bool>();
    var current = true;
    final effects = <String>[];
    final operation = initializeAccountAccess(
      userId: _a, sessionCurrent: () => current,
      pending: () => pending.future,
      status: () async { effects.add('status'); return {'ok': true, 'userId': _a, 'state': 'active'}; },
      markPending: () async => effects.add('mark'),
      purgeLocal: () async => effects.add('purge'),
      bootstrap: () async => effects.add('bootstrap'),
    );
    current = false;
    final assertion = expectLater(operation, throwsA(_code('session_changed')));
    pending.complete(false);
    await assertion;
    expect(effects, isEmpty);
  });

  test('own deletion journals before purge and never bootstraps', () async {
    final effects = <String>[];
    await expectLater(initializeAccountAccess(
      userId: _a, sessionCurrent: () => true,
      pending: () async => false,
      status: () async => {'ok': true, 'userId': _a, 'state': 'deleting'},
      markPending: () async => effects.add('mark'),
      purgeLocal: () async => effects.add('purge'),
      bootstrap: () async => effects.add('bootstrap'),
    ), throwsA(isA<AccountDeletionPending>()));
    expect(effects, ['mark', 'purge']);
  });

  test('a different account cannot coalesce onto a pending deletion', () async {
    final documents = await Directory.systemTemp.createTemp('hamtdaa-delete-boundary-');
    addTearDown(() => documents.delete(recursive: true));
    final coordinator = AccountDeletionCoordinator(documents);
    final a = _Repository(_a), b = _Repository(_b);
    Future<void> delete(_Repository repository) => coordinator.delete(
      repository: repository, freeze: () async {}, clearReminders: () async {}, signOut: () async {},
    );
    final first = delete(a);
    await a.called.future;
    expect(() => delete(b), throwsA(_code('session_changed')));
    expect(b.called.isCompleted, isFalse);
    expect(await coordinator.pending(_b), isFalse);
    a.finished.complete();
    await first;
    expect(await coordinator.pending(_a), isFalse);
  });

  test('scope change while freezing never clears new account reminders', () async {
    final documents = await Directory.systemTemp.createTemp('hamtdaa-delete-boundary-');
    addTearDown(() => documents.delete(recursive: true));
    final coordinator = AccountDeletionCoordinator(documents);
    final repository = _Repository(_a);
    final freezing = Completer<void>(), frozen = Completer<void>();
    final effects = <String>[];
    final operation = coordinator.delete(
      repository: repository,
      freeze: () { freezing.complete(); return frozen.future; },
      clearReminders: () async => effects.add('clear reminders'),
      signOut: () async => effects.add('sign out'),
    );
    await freezing.future;
    repository.sessionCurrent = false;
    final assertion = expectLater(operation, throwsA(_code('session_changed')));
    frozen.complete();
    await assertion;
    expect(effects, isEmpty);
    expect(repository.called.isCompleted, isFalse);
    expect(await coordinator.pending(_a), isTrue);
  });

  test('late signout completion retains a newer SDK login and epoch', () async {
    final sdk = _SdkAuth(_session(_a));
    final repository = SupabaseAuthRepository.withAuthClient(sdk);
    final logout = repository.signOut();
    await sdk.logoutStarted.future;
    sdk.login(_session(_b));
    await Future<void>.delayed(Duration.zero);
    final newScope = repository.current.scope;
    expect(repository.current.userId, _b);
    sdk.logoutFinished.complete();
    await logout;
    expect(repository.current.isSignedIn, isTrue);
    expect(repository.current.userId, _b);
    expect(repository.current.scope, newScope);
    await repository.dispose();
    await sdk.dispose();
  });
}
