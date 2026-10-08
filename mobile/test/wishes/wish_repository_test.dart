import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/wishes/wish_models.dart';
import 'package:hamtdaa/wishes/wish_repository.dart';
import 'package:http/http.dart' as http;

import '../together/together_fakes.dart'
    show TogetherStorage, TogetherTransport;
import 'wish_fakes.dart';

Map<String, dynamic> _list({
  String pair = wishPair,
  List<Map<String, dynamic>>? wishes,
}) => {
  'ok': true,
  'pair_id': pair,
  'wishes': wishes ?? [wishJson()],
};
http.StreamedResponse _json(Map<String, dynamic> data, {int status = 200}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(data))),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
Matcher _failure(String code) =>
    throwsA(isA<WishFailure>().having((error) => error.code, 'code', code));

class _Client extends http.BaseClient {
  final calls = <http.BaseRequest>[];
  Future<http.StreamedResponse> Function(http.BaseRequest)? onSend;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request);
    return onSend == null ? _json(_list()) : onSend!(request);
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  late CloudflareAuthRepository auth;
  late CloudflareWishRepository repository;
  late _Client client;
  setUp(() async {
    auth = CloudflareAuthRepository(
      transport: TogetherTransport(),
      storage: TogetherStorage(),
    );
    await auth.verifyEmailCode('a@example.com', '123456');
    client = _Client();
    repository = CloudflareWishRepository(
      auth,
      baseUri: Uri.parse('https://wishes.example'),
      client: client,
    );
  });
  tearDown(() async {
    await repository.dispose();
    await auth.dispose();
  });

  test('pins bearer and pair on credentialed POST without redirects', () async {
    await repository.list(wishPair);
    final request = client.calls.single as http.Request;
    expect(request.url, Uri.parse('https://wishes.example/v1/wishes/list'));
    expect(request.method, 'POST');
    expect(request.followRedirects, isFalse);
    expect(request.headers['Authorization'], 'Bearer token-a');
    expect(jsonDecode(request.body), {'expected_pair_id': wishPair});
    client.onSend = (_) async => _json({'ok': true, 'wish': wishJson()});
    await repository.create(wishPair, wishCommand, wishDraft);
    final creation = client.calls.last as http.Request;
    expect(jsonDecode(creation.body), {
      'expected_pair_id': wishPair,
      'command_id': wishCommand,
      ...wishDraft.toJson(),
    });
  });

  test(
    'missing collection routes report feature unavailable without an uncertain retry',
    () async {
      client.onSend = (_) async =>
          _json({'ok': false, 'code': 'not_found'}, status: 404);
      final unavailable = throwsA(
        isA<WishFailure>()
            .having((error) => error.code, 'code', 'feature_unavailable')
            .having((error) => error.needsRetry, 'needsRetry', isFalse)
            .having((error) => error.outcomeUnknown, 'outcomeUnknown', isFalse)
            .having(
              (error) => error.message,
              'message',
              'Хүслийн самбарын үйлчилгээ хараахан нээгдээгүй байна. Түр хүлээгээд дахин шалгаарай.',
            ),
      );
      await expectLater(repository.list(wishPair), unavailable);
      await expectLater(
        repository.create(wishPair, wishCommand, wishDraft),
        unavailable,
      );
      await expectLater(repository.exportData(wishPair), unavailable);
      expect(auth.current.isSignedIn, isTrue);
    },
  );

  test(
    'missing individual wish remains not found for every record operation',
    () async {
      client.onSend = (_) async =>
          _json({'ok': false, 'code': 'not_found'}, status: 404);
      await expectLater(
        repository.like(wish(), wishCommand, false),
        _failure('not_found'),
      );
      await expectLater(
        repository.plan(
          wish(partnerLiked: true),
          wishCommand,
          DateTime.utc(2027),
        ),
        _failure('not_found'),
      );
      await expectLater(
        repository.complete(wish(status: 'planned'), wishCommand),
        _failure('not_found'),
      );
      await expectLater(
        repository.delete(wish(), wishCommand),
        _failure('not_found'),
      );
      expect(auth.current.isSignedIn, isTrue);
    },
  );

  for (final status in [200, 401]) {
    test(
      'late $status response cannot expose old data or reject a newer login',
      () async {
        final reply = Completer<http.StreamedResponse>();
        client.onSend = (_) => reply.future;
        final response = repository.list(wishPair);
        final assertion = expectLater(response, _failure('unauthenticated'));
        await auth.verifyEmailCode('b@example.com', '123456');
        reply.complete(
          _json(
            status == 200 ? _list() : {'ok': false, 'code': 'unauthenticated'},
            status: status,
          ),
        );
        await assertion;
        expect(auth.current.userId, 'b');
        expect(auth.current.isSignedIn, isTrue);
        expect(repository.isCurrent, isFalse);
        expect(client.calls.single.headers['Authorization'], 'Bearer token-a');
      },
    );
  }

  test(
    'same-account fresh login invalidates old repository and aborts its requests',
    () async {
      final aborted = Completer<void>();
      client.onSend = (request) async {
        await (request as http.AbortableRequest).abortTrigger;
        aborted.complete();
        throw http.ClientException('aborted');
      };
      final response = repository.list(wishPair);
      final assertion = expectLater(response, _failure('unauthenticated'));
      await auth.verifyEmailCode('a@example.com', '123456');
      await aborted.future;
      await assertion;
      await expectLater(repository.list(wishPair), _failure('unauthenticated'));
      expect(client.calls, hasLength(1));
    },
  );

  test(
    'current 401 invalidates session but service failure preserves it',
    () async {
      client.onSend = (_) async =>
          _json({'ok': false, 'code': 'temporarily_unavailable'}, status: 503);
      await expectLater(
        repository.list(wishPair),
        _failure('temporarily_unavailable'),
      );
      expect(auth.current.isSignedIn, isTrue);
      var invalidations = 0;
      final subscription = repository.invalidations.listen(
        (_) => invalidations++,
      );
      addTearDown(subscription.cancel);
      client.onSend = (_) async =>
          _json({'ok': false, 'code': 'unauthenticated'}, status: 401);
      await expectLater(repository.list(wishPair), _failure('unauthenticated'));
      expect(auth.current.isSignedIn, isFalse);
      expect(invalidations, 1);
    },
  );

  test(
    'rejects foreign pair envelopes, duplicate IDs, bad rows and excessive counts',
    () async {
      for (final reply in [
        _list(pair: wishOtherPair),
        _list(wishes: [wishJson(pair: wishOtherPair)]),
        _list(wishes: [wishJson(), wishJson()]),
        _list(
          wishes: [
            {...wishJson(), 'my_liked': 1},
          ],
        ),
        _list(wishes: List.generate(501, (i) => wishJson(id: 'wish-$i'))),
      ]) {
        client.onSend = (_) async => _json(reply);
        await expectLater(
          repository.list(wishPair),
          _failure('invalid_response'),
        );
      }
    },
  );

  test(
    'accepts maximal valid Unicode payload but caps arbitrary JSON at four MiB',
    () async {
      final rows = List.generate(
        500,
        (i) => {
          ...wishJson(id: 'wish-$i'),
          'title': 'Ө' * 80,
          'note': 'Ө' * 500,
          'location': 'Ө' * 120,
        },
      );
      client.onSend = (_) async => _json(_list(wishes: rows));
      expect(await repository.list(wishPair), hasLength(500));
      client.onSend = (_) async =>
          _json({..._list(wishes: []), 'padding': 'x' * (4 * 1024 * 1024)});
      await expectLater(
        repository.list(wishPair),
        _failure('invalid_response'),
      );
    },
  );

  test('rejects redirect, HTML and malformed JSON response', () async {
    for (final response in [
      http.StreamedResponse(
        Stream.value([]),
        302,
        headers: {'location': 'https://other.example/'},
      ),
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(_list()))),
        200,
        headers: {'content-type': 'text/html'},
      ),
      http.StreamedResponse(
        Stream.value(utf8.encode('{')),
        200,
        headers: {'content-type': 'application/json'},
      ),
    ]) {
      client.onSend = (_) async => response;
      await expectLater(
        repository.list(wishPair),
        _failure('invalid_response'),
      );
    }
    expect(client.calls.every((request) => !request.followRedirects), isTrue);
  });

  test(
    'create rejects wrong creator and treats malformed mutation replies as uncertain',
    () async {
      for (final row in [wishJson(actor: 'b'), wishJson(pair: wishOtherPair)]) {
        client.onSend = (_) async => _json({'ok': true, 'wish': row});
        await expectLater(
          repository.create(wishPair, wishCommand, wishDraft),
          throwsA(
            isA<WishFailure>().having(
              (error) => error.outcomeUnknown,
              'unknown outcome',
              isTrue,
            ),
          ),
        );
      }
      final before = client.calls.length;
      await expectLater(
        repository.create(wishPair, wishCommand, const WishDraft(title: ' ')),
        _failure('invalid_input'),
      );
      expect(client.calls, hasLength(before));
    },
  );

  test('mutations pin version, like value and exact UTC plan times', () async {
    final value = wish(partnerLiked: true);
    client.onSend = (_) async =>
        _json({'ok': true, 'wish': wishJson(partnerLiked: true, version: 2)});
    await repository.like(value, wishCommand, false);
    expect(jsonDecode((client.calls.last as http.Request).body), {
      'expected_pair_id': wishPair,
      'command_id': wishCommand,
      'id': wishId,
      'expected_version': 1,
      'liked': false,
    });
    final start = DateTime(2027, 1, 1, 14), end = DateTime(2027, 1, 1, 16);
    client.onSend = (_) async => _json({
      'ok': true,
      'wish': wishJson(status: 'planned', partnerLiked: true, version: 2),
      'event_id': 'event-1',
    });
    await repository.plan(value, wishCommand, start, endsAt: end);
    final body = jsonDecode((client.calls.last as http.Request).body) as Map;
    expect(body['starts_at'], start.toUtc().toIso8601String());
    expect(body['ends_at'], end.toUtc().toIso8601String());
    expect(body['expected_version'], 1);
    await repository.plan(
      value,
      wishCommand,
      DateTime.utc(2027, 1, 1, 14, 0, 0, 123, 456),
    );
    expect(
      (jsonDecode((client.calls.last as http.Request).body)
          as Map)['starts_at'],
      '2027-01-01T14:00:00.123Z',
    );
    await expectLater(
      repository.plan(value, wishCommand, start, endsAt: start),
      _failure('invalid_dates'),
    );
    await expectLater(
      repository.plan(value, wishCommand, DateTime.utc(2100)),
      _failure('invalid_dates'),
    );
    await expectLater(
      repository.plan(
        value,
        wishCommand,
        start,
        endsAt: start.add(const Duration(days: 32)),
      ),
      _failure('invalid_dates'),
    );
    client.onSend = (_) async => _json({
      'ok': true,
      'wish': wishJson(status: 'planned', partnerLiked: true),
      'event_id': 'wrong-event',
    });
    await expectLater(
      repository.plan(value, wishCommand, start),
      _failure('invalid_response'),
    );
  });

  test(
    'delete requires authored wish and an explicit deleted confirmation',
    () async {
      await expectLater(
        repository.delete(wish(actor: 'b'), wishCommand),
        _failure('creator_only'),
      );
      expect(client.calls, isEmpty);
      client.onSend = (_) async => _json({'ok': true});
      await expectLater(
        repository.delete(wish(), wishCommand),
        _failure('invalid_response'),
      );
      client.onSend = (_) async => _json({'ok': true, 'deleted': true});
      await repository.delete(wish(), wishCommand);
      expect(jsonDecode((client.calls.last as http.Request).body), {
        'expected_pair_id': wishPair,
        'command_id': wishCommand,
        'id': wishId,
        'expected_version': 1,
      });
    },
  );

  test(
    'account export validates own rows and keeps partner liked state out',
    () async {
      final own = wishJson()..remove('partner_liked');
      client.onSend = (_) async => _json({
        'ok': true,
        'pair_id': wishPair,
        'wishes': [own],
        'likes': [
          {'wish_id': wishId, 'liked': true},
        ],
      });
      final data = await repository.exportData(wishPair);
      expect(client.calls.last.url.path, '/v1/wishes/export');
      expect(data.toJson()['wishes'], [own]);
      expect(data.wishes.single.containsKey('partner_liked'), isFalse);
      client.onSend = (_) async => _json({
        'ok': true,
        'wishes': [own],
        'likes': [],
      });
      await expectLater(
        repository.exportData(wishPair),
        _failure('invalid_response'),
      );
    },
  );

  test(
    'timeout aborts transport and retains unknown mutation outcome',
    () async {
      final slowClient = _Client();
      final aborted = Completer<void>();
      slowClient.onSend = (request) async {
        await (request as http.AbortableRequest).abortTrigger;
        aborted.complete();
        throw http.ClientException('aborted');
      };
      final slow = CloudflareWishRepository(
        auth,
        baseUri: Uri.parse('https://wishes.example'),
        client: slowClient,
        requestTimeout: const Duration(milliseconds: 5),
      );
      addTearDown(slow.dispose);
      await expectLater(
        slow.create(wishPair, wishCommand, wishDraft),
        throwsA(
          isA<WishFailure>().having(
            (error) => error.outcomeUnknown,
            'unknown outcome',
            isTrue,
          ),
        ),
      );
      await aborted.future;
      expect(auth.current.isSignedIn, isTrue);
    },
  );

  test('dispose aborts in-flight request and refuses late data', () async {
    client.onSend = (request) async {
      await (request as http.AbortableRequest).abortTrigger;
      throw http.ClientException('aborted');
    };
    final response = repository.list(wishPair);
    final assertion = expectLater(response, _failure('unauthenticated'));
    await repository.dispose();
    await assertion;
    expect(client.closed, isTrue);
  });

  test(
    'two accounts send distinct credentials, contextual likes and stale version conflict',
    () async {
      final partnerAuth = CloudflareAuthRepository(
        transport: TogetherTransport(),
        storage: TogetherStorage(),
      );
      await partnerAuth.verifyEmailCode('b@example.com', '123456');
      final partnerClient = _Client();
      final partner = CloudflareWishRepository(
        partnerAuth,
        baseUri: Uri.parse('https://wishes.example'),
        client: partnerClient,
      );
      addTearDown(() async {
        await partner.dispose();
        await partnerAuth.dispose();
      });
      partnerClient.onSend = (_) async =>
          _json(_list(wishes: [wishJson(myLiked: false, partnerLiked: true)]));
      final aWish = (await repository.list(wishPair)).single;
      final bWish = (await partner.list(wishPair)).single;
      expect(aWish.myLiked, isTrue);
      expect(bWish.myLiked, isFalse);
      expect(bWish.partnerLiked, isTrue);
      partnerClient.onSend = (_) async => _json({
        'ok': true,
        'wish': wishJson(myLiked: true, partnerLiked: true, version: 2),
      });
      final mutual = await partner.like(bWish, wishCommand, true);
      expect(mutual.canPlan, isTrue);
      expect(
        partnerClient.calls.last.headers['Authorization'],
        'Bearer token-b',
      );
      client.onSend = (_) async =>
          _json({'ok': false, 'code': 'conflict'}, status: 409);
      await expectLater(
        repository.like(aWish, wishCommand, false),
        _failure('conflict'),
      );
      expect(client.calls.last.headers['Authorization'], 'Bearer token-a');
      expect(
        (jsonDecode((client.calls.last as http.Request).body)
            as Map)['expected_version'],
        1,
      );
      expect(auth.current.isSignedIn, isTrue);
      expect(partnerAuth.current.isSignedIn, isTrue);
    },
  );
}
