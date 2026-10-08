import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';
import 'package:hamtdaa/together/together_models.dart';
import 'package:hamtdaa/together/together_repository.dart';
import 'together_fakes.dart';

void main() {
  late TogetherTransport transport;
  late CloudflareAuthRepository auth;
  late CloudflareTogetherRepository repository;
  setUp(() async {
    transport = TogetherTransport();
    auth = CloudflareAuthRepository(transport: transport, storage: TogetherStorage());
    await auth.verifyEmailCode('a@example.com', '123456');
    repository = CloudflareTogetherRepository(auth);
  });
  tearDown(() async { await repository.dispose(); await auth.dispose(); });

  test('all requests POST with pinned bearer and exact pair-bound command', () async {
    await repository.state('2026-10');
    final command = TogetherCommand('calendar/respond', pairId, {'id': 'event-1', 'expected_version': 1, 'response': 'accepted'});
    await repository.mutate(command);
    expect(transport.calls.map((e) => e.method), everyElement('POST'));
    expect(transport.calls.map((e) => e.token), everyElement('token-a'));
    expect(transport.calls.first.body, {'month': '2026-10'});
    expect(transport.calls.last.path, '/v1/together/calendar/respond');
    expect(transport.calls.last.body, command.body);
  });

  test('late response rejected after another login and never uses new bearer', () async {
    final response = Completer<CloudflareResponse>();
    transport.onCall = (_, _) => response.future;
    final request = repository.state('2026-10');
    final assertion = expectLater(request, throwsA(isA<TogetherFailure>().having((e) => e.code, 'code', 'unauthenticated')));
    await auth.verifyEmailCode('b@example.com', '123456');
    response.complete(CloudflareResponse(200, stateJson()));
    await assertion;
    expect(auth.current.userId, 'b');
    expect(transport.calls.single.token, 'token-a');
    expect(repository.isCurrent, isFalse);
  });

  test('401 closes current account while 503 leaves retryable login intact', () async {
    transport.onCall = (_, _) async => const CloudflareResponse(503, {'ok': false, 'code': 'temporarily_unavailable'});
    await expectLater(repository.state('2026-10'), throwsA(isA<TogetherFailure>().having((e) => e.retryable, 'retryable', isTrue)));
    expect(auth.current.isSignedIn, isTrue);
    transport.onCall = (_, _) async => const CloudflareResponse(401, {'ok': false, 'code': 'unauthenticated'});
    await expectLater(repository.state('2026-10'), throwsA(isA<TogetherFailure>()));
    expect(auth.current.isSignedIn, isFalse);
  });

  test('malformed state is safely rejected and unpaired ignores private fields', () async {
    transport.onCall = (_, _) async => CloudflareResponse(200, {...stateJson(), 'events': [eventJson(version: 0)]});
    await expectLater(repository.state('2026-10'), throwsA(isA<TogetherFailure>().having((e) => e.code, 'code', 'invalid_response')));
    transport.onCall = (_, _) async => CloudflareResponse(200, {...stateJson(events: [eventJson()]), 'paired': false});
    final state = await repository.state('2026-10');
    expect(state.paired, isFalse);
    expect(state.events, isEmpty);
    expect(state.daily, isNull);
  });
}
