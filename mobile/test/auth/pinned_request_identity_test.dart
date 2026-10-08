import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/content/content_repository.dart';
import 'package:hamtdaa/content/supabase_content_repository.dart';
import 'package:hamtdaa/pair/pair_models.dart';
import 'package:hamtdaa/pair/supabase_pair_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _accountA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _accountB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _sessionA = '11111111-1111-1111-1111-111111111111';

Session _session(String userId, String sessionId, {String version = 'first'}) {
  String encode(Map<String, Object?> value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token = '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode({'sub': userId, 'session_id': sessionId, 'fixture': version, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.'
      'fixture-signature';
  return Session(
    accessToken: token,
    tokenType: 'bearer',
    user: User(
      id: userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '',
      email: '$userId@example.invalid',
    ),
  );
}

class _Auth extends GoTrueClient {
  _Auth() : super(autoRefreshToken: false);
  final events = StreamController<AuthState>.broadcast(sync: true);
  @override
  Session? currentSession;
  @override
  User? get currentUser => currentSession?.user;
  @override
  Stream<AuthState> get onAuthStateChange => events.stream;
  Future<Session?> Function()? resolveSession;
  @override
  Future<Session?> getSession() async =>
      resolveSession == null ? currentSession : await resolveSession!();

  void switchTo(Session next) {
    currentSession = next;
    events.add(AuthState(AuthChangeEvent.signedIn, next));
  }

  @override
  Future<void> dispose() async {
    await events.close();
    super.dispose();
  }
}

/// Keep real PostgREST, FunctionsClient and AuthHttpClient transport code. The
/// controllable token lookup recreates an account switch during the SDK await.
class _Client extends SupabaseClient {
  _Client(String url, this.fixtureAuth, Future<String?> Function() tokenLookup)
    : super(url, 'sb_publishable_test_fixture', accessToken: tokenLookup);

  final _Auth fixtureAuth;
  @override
  GoTrueClient get auth => fixtureAuth;
}

class _Request {
  const _Request(this.path, this.authorization, this.body);
  final String path;
  final String? authorization;
  final List<int> body;
}

class _Harness {
  final auth = _Auth();
  final requests = <_Request>[];
  late HttpServer server;
  late _Client client;
  late Future<String?> Function() tokenLookup;

  Future<void> start() async {
    auth.currentSession = _session(_accountA, _sessionA);
    tokenLookup = () async => auth.currentSession?.accessToken;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final bytes = await request.fold<List<int>>([], (all, next) => all..addAll(next));
      requests.add(_Request(request.uri.path, request.headers.value('Authorization'), bytes));
      if (request.uri.path.endsWith('hamtdaa-media') && request.method == 'GET') {
        request.response.headers.contentType = ContentType('application', 'octet-stream');
        request.response.add([1, 2, 3]);
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true, 'items': [], 'item': {}, 'key': 'fixture/photo.png'}));
      }
      await request.response.close();
    });
    client = _Client('http://127.0.0.1:${server.port}', auth, () => tokenLookup());
  }

  void switchInSdkLookup() {
    tokenLookup = () async {
      final next = _session(_accountB, '22222222-2222-2222-2222-222222222222');
      auth.switchTo(next);
      return next.accessToken;
    };
  }

  Future<void> dispose() async {
    await client.dispose();
    await auth.dispose();
    await server.close(force: true);
  }
}

void main() {
  late _Harness harness;
  setUp(() async {
    harness = _Harness();
    await harness.start();
  });
  tearDown(() => harness.dispose());

  final unauthenticatedContent = isA<ContentException>().having((e) => e.code, 'code', 'unauthenticated');
  final unauthenticatedPair = isA<PairFailure>().having((e) => e.code, 'code', 'unauthenticated');

  test('content write keeps original Authorization when SDK resolves a new account', () async {
    final token = harness.auth.currentSession!.accessToken;
    final repository = SupabaseContentRepository(harness.client);
    harness.switchInSdkLookup();
    await expectLater(
      repository.save(commandId: 'command-a', id: 'memory-a', kind: 'memory', payload: {'title': 'Private A'}, shared: false),
      throwsA(unauthenticatedContent),
    );
    expect(harness.requests.single.authorization, 'Bearer $token');
    expect(harness.requests.single.path, '/rest/v1/rpc/hamtdaa_content_save');
    expect((jsonDecode(utf8.decode(harness.requests.single.body)) as Map)['p_payload'], {'title': 'Private A'});
    await expectLater(repository.snapshot(), throwsA(unauthenticatedContent));
    expect(harness.requests, hasLength(1));
  });

  test('media upload keeps original Authorization across the SDK account switch', () async {
    final token = harness.auth.currentSession!.accessToken;
    final repository = SupabaseContentRepository(harness.client);
    harness.switchInSdkLookup();
    await expectLater(repository.uploadPhoto('memory-a', Uint8List.fromList([8, 9]), 'png'), throwsA(unauthenticatedContent));
    expect(harness.requests.single.authorization, 'Bearer $token');
    expect(harness.requests.single.body, [8, 9]);
  });

  test('media download keeps original Authorization across the SDK account switch', () async {
    final token = harness.auth.currentSession!.accessToken;
    final repository = SupabaseContentRepository(harness.client);
    harness.switchInSdkLookup();
    await expectLater(repository.downloadPhoto('fixture/photo.png'), throwsA(unauthenticatedContent));
    expect(harness.requests.single.authorization, 'Bearer $token');
  });

  test('pair command keeps original Authorization across the SDK account switch', () async {
    final token = harness.auth.currentSession!.accessToken;
    final repository = SupabasePairRepository(harness.client);
    addTearDown(repository.dispose);
    harness.switchInSdkLookup();
    await expectLater(repository.execute(PairCommand.updateName('Private A', 1)), throwsA(unauthenticatedPair));
    expect(harness.requests.single.authorization, 'Bearer $token');
    expect(harness.requests.single.path, '/rest/v1/rpc/hamtdaa_update_profile');
    await expectLater(repository.execute(PairCommand.create()), throwsA(unauthenticatedPair));
    expect(harness.requests, hasLength(1));
  });

  test('same account new login invalidates old pair adapter without an auth event', () async {
    final repository = SupabasePairRepository(harness.client);
    addTearDown(repository.dispose);
    harness.auth.currentSession = _session(_accountA, '33333333-3333-3333-3333-333333333333');
    await expectLater(repository.execute(PairCommand.create()), throwsA(unauthenticatedPair));
    expect(harness.requests, isEmpty);
  });

  test('session switch while refreshing aborts content before any network write', () async {
    final repository = SupabaseContentRepository(harness.client);
    harness.auth.resolveSession = () async {
      final next = _session(_accountB, '22222222-2222-2222-2222-222222222222');
      harness.auth.switchTo(next);
      return next;
    };
    await expectLater(repository.save(commandId: 'command-a', id: 'memory-a', kind: 'memory', payload: {'title': 'Private A'}, shared: false), throwsA(unauthenticatedContent));
    expect(harness.requests, isEmpty);
  });

  test('refreshed token in the same login remains usable for content and pair', () async {
    final content = SupabaseContentRepository(harness.client);
    final pair = SupabasePairRepository(harness.client);
    addTearDown(pair.dispose);
    final refreshed = _session(_accountA, _sessionA, version: 'refreshed');
    harness.auth.resolveSession = () async {
      harness.auth.currentSession = refreshed;
      return refreshed;
    };
    expect(await content.snapshot(), isEmpty);
    await pair.execute(PairCommand.updateName('Ану', 1));
    expect(harness.requests, hasLength(2));
    expect(harness.requests.every((r) => r.authorization == 'Bearer ${refreshed.accessToken}'), isTrue);
  });
}
