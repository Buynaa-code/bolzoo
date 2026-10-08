import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/account/cloudflare_account_export.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_session_storage.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _pair = '11111111-1111-4111-8111-111111111111';
const _otherPair = '22222222-2222-4222-8222-222222222222';
const _first = '00000000-0000-4000-8000-000000000001';
const _second = '00000000-0000-4000-8000-000000000002';
final _photo = Uint8List.fromList([0xff, 0xd8, 1, 2, 0xff, 0xd9]);

class _Storage implements CloudflareSessionStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> clear() async => value = null;
}

Map<String, dynamic> _profile({String? pair = _pair, String actor = 'a'}) => {
  'schema_version': 1,
  'section': 'profile',
  'account': {'id': actor},
  'pair': pair == null ? null : {'id': pair},
  'next_cursor': null,
};

class _Transport implements CloudflareTransport {
  String? pair = _pair;
  Future<CloudflareResponse> Function()? verifyExport;
  final exportTokens = <String?>[];
  @override
  Future<CloudflareResponse> send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    if (path == '/v1/auth/verify-code') {
      final actor = (body!['email'] as String).split('@').first;
      return CloudflareResponse(200, {
        'ok': true,
        'token': 'token-$actor',
        'user': {'id': actor, 'email': body['email']},
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
      });
    }
    expect(path, '/v1/account/export');
    expect(method, 'POST');
    expect(body, isEmpty);
    exportTokens.add(token);
    return verifyExport != null
        ? await verifyExport!()
        : CloudflareResponse(200, {'ok': true, 'export': _profile(pair: pair)});
  }

  @override
  void close() {}
}

Map<String, dynamic> _memory(
  String id, {
  String pair = _pair,
  String actor = 'a',
}) => {
  'id': id,
  'pair_id': pair,
  'creator_id': actor,
  'day': '2026-10-08',
  'title': 'Бидний өдөр',
  'note': 'A private diary note',
  'sticker': 'polaroid',
  'version': 1,
  'created_at': '2026-10-08T10:00:00Z',
  'photo_base64': base64Encode(_photo),
  'thumbnail_base64': base64Encode(_photo),
};

http.Response _response(List<Map<String, dynamic>> memories, {String? next}) =>
    http.Response(
      jsonEncode({'ok': true, 'memories': memories, 'next_cursor': next}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _wish(
  String id, {
  String pair = _pair,
  String actor = 'a',
}) => {
  'id': id,
  'pair_id': pair,
  'creator_id': actor,
  'title': 'Хамтдаа аялъя',
  'note': 'Өөрийн хүслийн тэмдэглэл',
  'location': 'Хөвсгөл',
  'category': 'travel',
  'budget': 'medium',
  'status': 'idea',
  'event_id': null,
  'event_starts_at': null,
  'event_status': null,
  'version': 1,
  'my_liked': true,
  'created_at': '2026-10-08T10:00:00Z',
  'updated_at': '2026-10-08T10:00:00Z',
};

Map<String, dynamic> _wishExport({
  List<Map<String, dynamic>> wishes = const [],
  List<Map<String, dynamic>> likes = const [],
}) => {'ok': true, 'pair_id': _pair, 'wishes': wishes, 'likes': likes};

http.Response _wishResponse(Map<String, dynamic> value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

// Memory-focused cases explicitly return an empty valid wishlist response.
http.Client _memoryClient(
  Future<http.Response> Function(http.Request) handle,
) => MockClient(
  (request) => request.url.path == '/v1/wishes/export'
      ? Future.value(_wishResponse(_wishExport()))
      : handle(request),
);

void main() {
  late Directory temporary;
  late _Storage storage;
  late _Transport transport;
  late CloudflareAuthRepository auth;
  late CloudflareCredential credential;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('hamtdaa-export-test-');
    storage = _Storage();
    transport = _Transport();
    auth = CloudflareAuthRepository(transport: transport, storage: storage);
    await auth.verifyEmailCode('a@example.test', '123456');
    credential = auth.credential!;
  });
  tearDown(() async {
    await auth.dispose();
    await temporary.delete(recursive: true);
  });

  Future<Directory> export(
    http.Client client, {
    String? pair = _pair,
    bool Function()? isCurrent,
  }) => buildCloudflareAccountExport(
    auth: auth,
    credential: credential,
    pages: [_profile(pair: pair)],
    temporaryDirectory: temporary,
    isCurrent: isCurrent ?? () => true,
    memoryClient: client,
  );

  test(
    'unpaired export skips memory requests and still verifies its final profile',
    () async {
      transport.pair = null;
      final work = await export(
        _memoryClient(
          (_) async => throw StateError('No memory request allowed'),
        ),
        pair: null,
      );
      final zip = ZipDecoder().decodeBytes(
        await File('${work.path}/hamtdaa-data.zip').readAsBytes(),
      );
      expect(zip.files.map((f) => f.name), [
        'wishlist.json',
        'records.json',
        'README.txt',
      ]);
      final records =
          jsonDecode(utf8.decode(zip.findFile('records.json')!.content)) as Map;
      expect(records['memories'], containsPair('count', 0));
      expect(records['memories'], containsPair('pair_id', null));
      expect(records['wishlist'], containsPair('count', 0));
      final wishlist =
          jsonDecode(utf8.decode(zip.findFile('wishlist.json')!.content))
              as Map;
      expect(wishlist, {
        'scope': 'own_current_pair',
        'pair_id': null,
        'wishes': [],
        'likes': [],
      });
      expect(transport.exportTokens, ['token-a']);
    },
  );

  test(
    'wishlist archive includes own wishes and own likes with pinned scope',
    () async {
      final paths = <String>[];
      final body = _wishExport(
        wishes: [_wish(_first)],
        // A like can refer to a partner's wish without copying its contents.
        likes: [
          {'wish_id': _first, 'liked': true},
          {'wish_id': _second, 'liked': true},
        ],
      );
      final work = await export(
        MockClient((request) async {
          paths.add(request.url.path);
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], 'Bearer token-a');
          expect(request.followRedirects, isFalse);
          expect(jsonDecode(request.body), {'expected_pair_id': _pair});
          return request.url.path == '/v1/wishes/export'
              ? _wishResponse(body)
              : _response([]);
        }),
      );
      expect(paths, ['/v1/memories/export', '/v1/wishes/export']);
      final zip = ZipDecoder().decodeBytes(
        await File('${work.path}/hamtdaa-data.zip').readAsBytes(),
      );
      final wishlist =
          jsonDecode(utf8.decode(zip.findFile('wishlist.json')!.content))
              as Map;
      expect(wishlist['scope'], 'own_current_pair');
      expect(wishlist['pair_id'], _pair);
      expect((wishlist['wishes'] as List).single, _wish(_first));
      expect(wishlist['likes'], body['likes']);
      expect(jsonEncode(wishlist), isNot(contains('partner_liked')));
      final records =
          jsonDecode(utf8.decode(zip.findFile('records.json')!.content)) as Map;
      expect(records['wishlist'], {
        'scope': 'own_current_pair',
        'pair_id': _pair,
        'count': 1,
        'likes_count': 2,
        'file': 'wishlist.json',
      });
      expect(transport.exportTokens, ['token-a']);
    },
  );

  for (final invalid in [
    'scope',
    'missing_scope',
    'creator',
    'record_pair',
    'partner_like',
    'duplicate_wishes',
    'duplicate_likes',
    'too_many_wishes',
    'too_many_likes',
  ]) {
    test(
      'invalid wishlist $invalid discards previously archived memories',
      () async {
        final wish = _wish(_first);
        final body = _wishExport(wishes: [wish]);
        switch (invalid) {
          case 'scope':
            body['pair_id'] = _otherPair;
          case 'missing_scope':
            body.remove('pair_id');
          case 'creator':
            wish['creator_id'] = 'b';
          case 'record_pair':
            wish['pair_id'] = _otherPair;
          case 'partner_like':
            wish['partner_liked'] = true;
          case 'duplicate_wishes':
            body['wishes'] = [wish, wish];
          case 'duplicate_likes':
            body['likes'] = [
              {'wish_id': _first, 'liked': true},
              {'wish_id': _first, 'liked': true},
            ];
          case 'too_many_wishes':
            body['wishes'] = List.filled(501, wish);
          case 'too_many_likes':
            body['likes'] = List.filled(501, {
              'wish_id': _first,
              'liked': true,
            });
        }
        await expectLater(
          export(
            MockClient(
              (request) async => request.url.path == '/v1/wishes/export'
                  ? _wishResponse(body)
                  : _response([_memory(_first)]),
            ),
          ),
          throwsFormatException,
        );
        expect(temporary.listSync(), isEmpty);
        expect(transport.exportTokens, isEmpty);
        expect(auth.accepts(credential), isTrue);
      },
    );
  }

  test('wishlist response bound discards already written photos', () async {
    await expectLater(
      export(
        MockClient(
          (request) async => request.url.path == '/v1/wishes/export'
              ? http.Response('x' * (2 * 1024 * 1024 + 1), 200)
              : _response([_memory(_first)]),
        ),
      ),
      throwsFormatException,
    );
    expect(temporary.listSync(), isEmpty);
  });

  test('late wishlist after sign-in change cannot enter an export', () async {
    final received = Completer<void>();
    final pending = Completer<http.Response>();
    final result = export(
      MockClient((request) async {
        if (request.url.path != '/v1/wishes/export') return _response([]);
        received.complete();
        return pending.future;
      }),
    );
    final rejected = expectLater(result, throwsFormatException);
    await received.future;
    await auth.verifyEmailCode('b@example.test', '654321');
    final nextCredential = auth.credential!;
    pending.complete(_wishResponse(_wishExport(wishes: [_wish(_first)])));
    await rejected;
    expect(auth.accepts(nextCredential), isTrue);
    expect(temporary.listSync(), isEmpty);
    expect(transport.exportTokens, isEmpty);
  });

  test(
    'pages are written as separate photos with metadata and pinned bearer and pair',
    () async {
      final requests = <http.Request>[];
      final work = await export(
        _memoryClient((request) async {
          requests.add(request);
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://nandin-moch-memories-production.mendmedey.workers.dev/v1/memories/export',
          );
          expect(request.headers['Authorization'], 'Bearer token-a');
          expect(request.followRedirects, isFalse);
          expect(
            jsonDecode(request.body),
            requests.length == 1
                ? {'expected_pair_id': _pair}
                : {'expected_pair_id': _pair, 'cursor': _first},
          );
          return requests.length == 1
              ? _response([_memory(_first)], next: _first)
              : _response([_memory(_second)]);
        }),
      );
      expect(requests, hasLength(2));
      final zip = ZipDecoder().decodeBytes(
        await File('${work.path}/hamtdaa-data.zip').readAsBytes(),
      );
      expect(zip.files, hasLength(9));
      for (final number in ['0001', '0002']) {
        expect(zip.findFile('memories/$number.jpg')!.content, _photo);
        expect(zip.findFile('memories/$number-thumbnail.jpg')!.content, _photo);
        final metadata =
            jsonDecode(
                  utf8.decode(zip.findFile('memories/$number.json')!.content),
                )
                as Map;
        expect(metadata['photo'], 'memories/$number.jpg');
        expect(metadata['thumbnail'], 'memories/$number-thumbnail.jpg');
        expect(metadata['title'], 'Бидний өдөр');
        expect(metadata.containsKey('photo_base64'), isFalse);
      }
      final records =
          jsonDecode(utf8.decode(zip.findFile('records.json')!.content)) as Map;
      expect(records['memories'], containsPair('count', 2));
      expect(transport.exportTokens, ['token-a']);
    },
  );

  for (final invalid in [
    'creator',
    'pair',
    'missing_completion',
    'wrong_cursor',
    'empty_cursor',
    'too_many',
    'malformed_photo',
    'oversized_photo',
  ]) {
    test('invalid $invalid discards the entire staged archive', () async {
      final record = _memory(_first);
      final body = <String, dynamic>{
        'ok': true,
        'memories': [record],
        'next_cursor': null,
      };
      switch (invalid) {
        case 'creator':
          record['creator_id'] = 'b';
        case 'pair':
          record['pair_id'] = _otherPair;
        case 'missing_completion':
          body.remove('next_cursor');
        case 'wrong_cursor':
          body['next_cursor'] = _second;
        case 'empty_cursor':
          body['memories'] = [];
          body['next_cursor'] = _first;
        case 'too_many':
          body['memories'] = [record, record];
        case 'malformed_photo':
          record['photo_base64'] = 'not-a-jpeg';
        case 'oversized_photo':
          record['photo_base64'] = base64Encode(Uint8List(768 * 1024 + 1));
      }
      await expectLater(
        export(
          _memoryClient((_) async => http.Response(jsonEncode(body), 200)),
        ),
        throwsFormatException,
      );
      expect(temporary.listSync(), isEmpty);
      expect(transport.exportTokens, isEmpty);
      expect(auth.accepts(credential), isTrue);
    });
  }

  test('repeating memory cursor discards already written pages', () async {
    var calls = 0;
    await expectLater(
      export(
        _memoryClient((_) async {
          calls++;
          return _response([_memory(_first)], next: _first);
        }),
      ),
      throwsFormatException,
    );
    expect(calls, 2);
    expect(temporary.listSync(), isEmpty);
  });

  test('later page failure discards already written photos', () async {
    var calls = 0;
    await expectLater(
      export(
        _memoryClient((_) async {
          return ++calls == 1
              ? _response([_memory(_first)], next: _first)
              : http.Response('unavailable', 503);
        }),
      ),
      throwsFormatException,
    );
    expect(calls, 2);
    expect(temporary.listSync(), isEmpty);
  });

  test('response byte bound rejects a large page before parsing', () async {
    await expectLater(
      export(
        _memoryClient((_) async => http.Response('x' * (1200 * 1024 + 1), 200)),
      ),
      throwsFormatException,
    );
    expect(temporary.listSync(), isEmpty);
  });

  for (final actor in ['a', 'b']) {
    for (final status in [200, 401]) {
      test(
        'late $status after signing in as $actor cannot export or reject the new credential',
        () async {
          final received = Completer<void>();
          final pending = Completer<http.Response>();
          final result = export(
            _memoryClient((_) {
              received.complete();
              return pending.future;
            }),
          );
          final rejected = expectLater(result, throwsFormatException);
          await received.future;
          await auth.verifyEmailCode('$actor@example.test', '654321');
          final nextCredential = auth.credential!;
          pending.complete(
            status == 200
                ? _response([_memory(_first)])
                : http.Response('{}', 401),
          );
          await rejected;
          expect(auth.accepts(nextCredential), isTrue);
          expect(storage.value, contains('token-$actor'));
          expect(temporary.listSync(), isEmpty);
          expect(transport.exportTokens, isEmpty);
        },
      );
    }
  }

  test(
    'memory 401 rejects exactly the pinned login and removes staging',
    () async {
      await expectLater(
        export(_memoryClient((_) async => http.Response('{}', 401))),
        throwsFormatException,
      );
      expect(auth.current.isSignedIn, isFalse);
      expect(storage.value, isNull);
      expect(temporary.listSync(), isEmpty);
    },
  );

  test(
    'same login pair change during export discards the finished archive',
    () async {
      transport.pair = _otherPair;
      await expectLater(
        export(_memoryClient((_) async => _response([_memory(_first)]))),
        throwsFormatException,
      );
      expect(temporary.listSync(), isEmpty);
      expect(auth.accepts(credential), isTrue);
      expect(transport.exportTokens, ['token-a']);
    },
  );

  test(
    'disposal before final profile arrives discards the finished archive',
    () async {
      var current = true;
      final received = Completer<void>();
      final finalProfile = Completer<CloudflareResponse>();
      transport.verifyExport = () {
        received.complete();
        return finalProfile.future;
      };
      final result = export(
        _memoryClient((_) async => _response([_memory(_first)])),
        isCurrent: () => current,
      );
      final rejected = expectLater(result, throwsFormatException);
      await received.future;
      current = false;
      finalProfile.complete(
        CloudflareResponse(200, {'ok': true, 'export': _profile()}),
      );
      await rejected;
      expect(temporary.listSync(), isEmpty);
      expect(auth.accepts(credential), isTrue);
    },
  );
}
