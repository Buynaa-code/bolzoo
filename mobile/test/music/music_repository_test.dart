import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';
import 'package:hamtdaa/music/music_repository.dart';
import 'package:hamtdaa/music/music_track.dart';

import '../together/together_fakes.dart';

const trackJson = {
  'video_id': 'dQw4w9WgXcQ',
  'title': 'Our song',
  'channel_title': 'Official artist',
};

Matcher fails(String code) =>
    throwsA(isA<MusicFailure>().having((error) => error.code, 'code', code));

void main() {
  late TogetherTransport transport;
  late CloudflareAuthRepository auth;
  late CloudflareMusicRepository repository;
  setUp(() async {
    transport = TogetherTransport();
    auth = CloudflareAuthRepository(
      transport: transport,
      storage: TogetherStorage(),
    );
    await auth.verifyEmailCode('a@example.com', '123456');
    repository = CloudflareMusicRepository(auth);
  });
  tearDown(() async => auth.dispose());

  test(
    'search uses a pinned bearer, trims query and ignores provider URLs',
    () async {
      transport.onCall = (_, _) async => const CloudflareResponse(200, {
        'ok': true,
        'tracks': [
          {
            ...trackJson,
            'url': 'https://attacker.test',
            'thumbnail': 'https://attacker.test/pixel',
          },
        ],
      });
      final tracks = await repository.search('  Our song  ');
      expect(transport.calls.single.method, 'POST');
      expect(transport.calls.single.path, '/v1/music/search');
      expect(transport.calls.single.token, 'token-a');
      expect(transport.calls.single.body, {'query': 'Our song'});
      expect(
        tracks.single.watchUrl.toString(),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(tracks.single.thumbnailUrl.host, 'i.ytimg.com');
      expect(() => tracks.clear(), throwsUnsupportedError);
    },
  );

  test('late successful response cannot cross into another login', () async {
    final response = Completer<CloudflareResponse>();
    transport.onCall = (_, _) => response.future;
    final assertion = expectLater(
      repository.search('Our song'),
      fails('unauthenticated'),
    );
    await auth.verifyEmailCode('b@example.com', '123456');
    response.complete(
      const CloudflareResponse(200, {
        'ok': true,
        'tracks': [trackJson],
      }),
    );
    await assertion;
    expect(auth.current.userId, 'b');
    expect(transport.calls.single.token, 'token-a');
    expect(repository.isCurrent, isFalse);
  });

  test('late 401 cannot sign out a replacement account', () async {
    final response = Completer<CloudflareResponse>();
    transport.onCall = (_, _) => response.future;
    final assertion = expectLater(
      repository.search('Our song'),
      fails('unauthenticated'),
    );
    await auth.verifyEmailCode('b@example.com', '123456');
    response.complete(
      const CloudflareResponse(401, {'ok': false, 'code': 'unauthenticated'}),
    );
    await assertion;
    expect(auth.current.userId, 'b');
    expect(auth.current.isSignedIn, isTrue);
  });

  test(
    'current 401 clears the current login; provider failures do not',
    () async {
      for (final status in [429, 503]) {
        final code = status == 429 ? 'rate_limited' : 'music_unavailable';
        transport.onCall = (_, _) async =>
            CloudflareResponse(status, {'ok': false, 'code': code});
        await expectLater(repository.search('Our song'), fails(code));
        expect(auth.current.isSignedIn, isTrue);
      }
      transport.onCall = (_, _) async =>
          const CloudflareResponse(401, {'ok': false});
      await expectLater(
        repository.search('Our song'),
        fails('unauthenticated'),
      );
      expect(auth.current.isSignedIn, isFalse);
    },
  );

  test(
    'network failures are retryable without exposing underlying errors',
    () async {
      transport.onCall = (_, _) async =>
          throw StateError('private upstream diagnostic');
      await expectLater(repository.search('Our song'), fails('network_error'));
      expect(auth.current.isSignedIn, isTrue);
    },
  );

  test('invalid queries never reach the server', () async {
    for (final query in ['', ' x ', 'a' * 101]) {
      await expectLater(repository.search(query), fails('validation'));
    }
    expect(transport.calls, isEmpty);
  });

  test(
    'malformed results and oversized pages are rejected as one response',
    () async {
      for (final tracks in <Object?>[
        null,
        'not a list',
        List.filled(21, trackJson),
        [
          trackJson,
          {...trackJson, 'video_id': '../../private'},
        ],
        [
          {...trackJson, 'title': 'bad\nlabel'},
        ],
        [
          {...trackJson, 'channel_title': null},
        ],
        [42],
      ]) {
        transport.onCall = (_, _) async =>
            CloudflareResponse(200, {'ok': true, 'tracks': tracks});
        await expectLater(
          repository.search('Our song'),
          fails('invalid_response'),
        );
      }
    },
  );
}
