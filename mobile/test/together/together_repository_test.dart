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
    auth = CloudflareAuthRepository(
      transport: transport,
      storage: TogetherStorage(),
    );
    await auth.verifyEmailCode('a@example.com', '123456');
    repository = CloudflareTogetherRepository(auth);
  });
  tearDown(() async {
    await repository.dispose();
    await auth.dispose();
  });

  test(
    'all requests POST with pinned bearer and exact pair-bound command',
    () async {
      await repository.state('2026-10');
      final command = TogetherCommand('calendar/respond', pairId, {
        'id': 'event-1',
        'expected_version': 1,
        'response': 'accepted',
      });
      await repository.mutate(command);
      expect(transport.calls.map((e) => e.method), everyElement('POST'));
      expect(transport.calls.map((e) => e.token), everyElement('token-a'));
      expect(transport.calls.first.body, {'month': '2026-10'});
      expect(transport.calls.last.path, '/v1/together/calendar/respond');
      expect(transport.calls.last.body, command.body);
    },
  );

  test(
    'late response rejected after another login and never uses new bearer',
    () async {
      final response = Completer<CloudflareResponse>();
      transport.onCall = (_, _) => response.future;
      final request = repository.state('2026-10');
      final assertion = expectLater(
        request,
        throwsA(
          isA<TogetherFailure>().having(
            (e) => e.code,
            'code',
            'unauthenticated',
          ),
        ),
      );
      await auth.verifyEmailCode('b@example.com', '123456');
      response.complete(CloudflareResponse(200, stateJson()));
      await assertion;
      expect(auth.current.userId, 'b');
      expect(transport.calls.single.token, 'token-a');
      expect(repository.isCurrent, isFalse);
    },
  );

  test(
    '401 closes current account while 503 leaves retryable login intact',
    () async {
      transport.onCall = (_, _) async => const CloudflareResponse(503, {
        'ok': false,
        'code': 'temporarily_unavailable',
      });
      await expectLater(
        repository.state('2026-10'),
        throwsA(
          isA<TogetherFailure>().having(
            (e) => e.retryable,
            'retryable',
            isTrue,
          ),
        ),
      );
      expect(auth.current.isSignedIn, isTrue);
      transport.onCall = (_, _) async => const CloudflareResponse(401, {
        'ok': false,
        'code': 'unauthenticated',
      });
      await expectLater(
        repository.state('2026-10'),
        throwsA(isA<TogetherFailure>()),
      );
      expect(auth.current.isSignedIn, isFalse);
    },
  );

  test(
    'malformed state is safely rejected and unpaired ignores private fields',
    () async {
      transport.onCall = (_, _) async => CloudflareResponse(200, {
        ...stateJson(),
        'events': [eventJson(version: 0)],
      });
      await expectLater(
        repository.state('2026-10'),
        throwsA(
          isA<TogetherFailure>().having(
            (e) => e.code,
            'code',
            'invalid_response',
          ),
        ),
      );
      transport.onCall = (_, _) async => CloudflareResponse(200, {
        ...stateJson(events: [eventJson()]),
        'paired': false,
      });
      final state = await repository.state('2026-10');
      expect(state.paired, isFalse);
      expect(state.events, isEmpty);
      expect(state.daily, isNull);
    },
  );

  test('calendar loads all pages with the pinned month and bearer', () async {
    transport.onCall = (_, body) async => CloudflareResponse(200, {
      ...stateJson(
        events: [
          {...eventJson(), 'id': body?['cursor'] == null ? 'first' : 'second'},
        ],
      ),
      'next_cursor': body?['cursor'] == null ? 'page-two' : null,
    });
    final state = await repository.state('2026-10');
    expect(state.events.map((event) => event.id), ['first', 'second']);
    expect(transport.calls.last.body, {
      'month': '2026-10',
      'cursor': 'page-two',
    });
    expect(transport.calls.map((call) => call.token), everyElement('token-a'));
  });

  test('concurrent calendar edit restarts the entire snapshot once', () async {
    var calls = 0;
    transport.onCall = (_, body) async {
      calls++;
      if (calls == 2) {
        return const CloudflareResponse(409, {
          'ok': false,
          'code': 'calendar_changed',
        });
      }
      return CloudflareResponse(200, {
        ...stateJson(
          events: [
            {...eventJson(), 'id': calls == 1 ? 'obsolete' : 'fresh'},
          ],
        ),
        'next_cursor': calls == 1 ? 'page-two' : null,
      });
    };
    final state = await repository.state('2026-10');
    expect(state.events.map((event) => event.id), ['fresh']);
    expect(transport.calls.last.body, {'month': '2026-10'});
  });

  test(
    'a second concurrent edit returns failure instead of a partial calendar',
    () async {
      transport.onCall = (_, body) async => body?['cursor'] != null
          ? const CloudflareResponse(409, {
              'ok': false,
              'code': 'calendar_changed',
            })
          : CloudflareResponse(200, {
              ...stateJson(events: [eventJson()]),
              'next_cursor': 'next',
            });
      await expectLater(
        repository.state('2026-10'),
        throwsA(
          isA<TogetherFailure>().having(
            (error) => error.code,
            'code',
            'calendar_changed',
          ),
        ),
      );
      expect(transport.calls, hasLength(4));
    },
  );

  test('different pair on a later page cannot mix partner content', () async {
    transport.onCall = (_, body) async => CloudflareResponse(200, {
      ...stateJson(
        pair: body?['cursor'] == null ? pairId : otherPairId,
        events: [
          {...eventJson(), 'id': body?['cursor'] == null ? 'old' : 'new'},
        ],
      ),
      'next_cursor': body?['cursor'] == null ? 'page-two' : null,
    });
    await expectLater(
      repository.state('2026-10'),
      throwsA(
        isA<TogetherFailure>().having(
          (error) => error.code,
          'code',
          'pair_changed',
        ),
      ),
    );
  });

  test('repeated cursor and duplicate event pages fail closed', () async {
    transport.onCall = (_, body) async => CloudflareResponse(200, {
      ...stateJson(events: [eventJson()]),
      'next_cursor': 'same',
    });
    await expectLater(
      repository.state('2026-10'),
      throwsA(
        isA<TogetherFailure>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
    expect(transport.calls, hasLength(2));
  });
}
