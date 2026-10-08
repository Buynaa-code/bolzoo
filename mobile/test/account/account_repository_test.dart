import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/account/account_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _user = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _other = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _session = '11111111-1111-1111-1111-111111111111';

Map<String, dynamic> _export([String user = _user]) => {
  'schemaVersion': 1,
  'account': {'userId': user},
  'items': [],
  'media': [],
};

Matcher _code(String code) => isA<AccountOperationException>().having(
  (error) => error.code, 'code', code,
);

Session _login(String user, String session, [String nonce = 'initial']) => Session(
  accessToken: 'header.${base64Url.encode(utf8.encode(jsonEncode({'session_id': session, 'nonce': nonce})))}.signature',
  tokenType: 'bearer',
  user: User(id: user, appMetadata: const {}, userMetadata: const {}, aud: 'authenticated', createdAt: ''),
);

class _Auth implements GoTrueClient {
  _Auth(this.currentSession);
  @override
  Session? currentSession;
  @override
  User? get currentUser => currentSession?.user;
  @override
  Future<Session?> getSession() async => currentSession;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Functions implements FunctionsClient {
  _Functions(this.call);
  final Future<FunctionResponse> Function(Invocation) call;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.memberName == #invoke ? call(invocation) : super.noSuchMethod(invocation);
}

class _Client implements SupabaseClient {
  _Client(this.auth, this.functions);
  @override
  final GoTrueClient auth;
  @override
  final FunctionsClient functions;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('export accepts only matching account and supported envelope', () async {
    Object? response = {'ok': true, 'export': _export()};
    final repository = SupabaseAccountRepository.withTransport(
      userId: _user, sessionCurrent: () => true,
      transport: (_) async => response,
    );
    expect(await repository.exportData(), _export());
    for (final invalid in [
      {'ok': true, 'export': _export(_other)},
      {'ok': true, 'export': {..._export(), 'schemaVersion': 2}},
      {'ok': true, 'export': {..._export(), 'items': 'private invalid contents'}},
      {'ok': true, 'export': {..._export(), 'media': null}},
      {'ok': true, 'export': null},
      <String, Object?>{},
    ]) {
      response = invalid;
      await expectLater(repository.exportData(), throwsA(isA<AccountOperationException>()));
    }
  });

  test('transport errors and server details are sanitized', () async {
    final repository = SupabaseAccountRepository.withTransport(
      userId: _user, sessionCurrent: () => true,
      transport: (_) async => throw StateError('Authorization secret SQL private email'),
    );
    await expectLater(repository.exportData(), throwsA(_code('unavailable')));
    final serverFailure = SupabaseAccountRepository.withTransport(
      userId: _user, sessionCurrent: () => true,
      transport: (_) async => {'ok': false, 'code': 'private SQL details'},
    );
    await expectLater(serverFailure.deleteAccount(), throwsA(_code('unavailable')));
  });

  test('session change rejects late results and permanently invalidates adapter', () async {
    var current = true;
    var calls = 0;
    final pending = Completer<Object?>();
    final repository = SupabaseAccountRepository.withTransport(
      userId: _user, sessionCurrent: () => current,
      transport: (_) { calls++; return pending.future; },
    );
    final operation = repository.exportData();
    current = false;
    final expectation = expectLater(operation, throwsA(_code('session_changed')));
    pending.complete({'ok': true, 'export': _export()});
    await expectation;
    current = true;
    await expectLater(repository.deleteAccount(), throwsA(_code('session_changed')));
    expect(calls, 1);
  });

  test('media downloads reject foreign owners and invalid byte responses', () async {
    Object? response = Uint8List.fromList([1, 2, 3]);
    var calls = 0;
    final repository = SupabaseAccountRepository.withTransport(
      userId: _user, sessionCurrent: () => true,
      transport: (_) async { calls++; return response; },
    );
    await expectLater(repository.downloadMedia('$_other/memory/photo.png'), throwsA(_code('invalid_media')));
    expect(calls, 0);
    expect(await repository.downloadMedia('$_user/memory/photo.png'), [1, 2, 3]);
    for (final invalid in [Uint8List(0), Uint8List(10 * 1024 * 1024 + 1), 'private string']) {
      response = invalid;
      await expectLater(repository.downloadMedia('$_user/memory/photo.png'), throwsA(_code('invalid_media')));
    }
  });

  test('delete requires an affirmative result and supplies explicit confirmation', () async {
    Object? response = {'ok': true, 'deleted': false};
    Map<String, Object?>? request;
    final repository = SupabaseAccountRepository.withTransport(
      userId: _user, sessionCurrent: () => true,
      transport: (body) async { request = body; return response; },
    );
    await expectLater(repository.deleteAccount(), throwsA(_code('unavailable')));
    expect(request, {'action': 'delete', 'confirmation': 'DELETE'});
    response = {'ok': true, 'deleted': true};
    await repository.deleteAccount();
  });

  test('SDK scope allows same-session refresh but rejects another login', () async {
    final auth = _Auth(_login(_user, _session));
    final repository = SupabaseAccountRepository(_Client(auth, _Functions((_) async => FunctionResponse(data: {'ok': true, 'export': _export()}, status: 200))));
    auth.currentSession = _login(_user, _session, 'refreshed');
    expect(repository.sessionCurrent, isTrue);
    await repository.exportData();
    auth.currentSession = _login(_user, '22222222-2222-2222-2222-222222222222');
    expect(repository.sessionCurrent, isFalse);
    await expectLater(repository.exportData(), throwsA(_code('session_changed')));
  });

  test('destructive SDK invocation pins the authorized account token', () async {
    final original = _login(_user, _session);
    final auth = _Auth(original);
    Map<String, String>? authorization;
    final repository = SupabaseAccountRepository(_Client(auth, _Functions((call) async {
      authorization = call.namedArguments[#headers] as Map<String, String>?;
      // Encoding/network dispatch can yield before the SDK obtains a token.
      auth.currentSession = _login(_other, '22222222-2222-2222-2222-222222222222');
      return FunctionResponse(data: {'ok': true, 'deleted': true}, status: 200);
    })));
    await expectLater(repository.deleteAccount(), throwsA(_code('session_changed')));
    expect(authorization?['Authorization'], 'Bearer ${original.accessToken}');
  });
}
