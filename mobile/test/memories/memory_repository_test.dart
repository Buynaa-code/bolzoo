import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/memories/memory_models.dart';
import 'package:hamtdaa/memories/memory_repository.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../together/together_fakes.dart'
    show TogetherStorage, TogetherTransport;

const _pair = '98bd1384-1edf-4890-8d6c-d42287e71142';
const _otherPair = '1cbe789d-215f-47a3-bf83-42130c373551';
const _id = 'bcf3c123-472e-4bed-b3c7-729ba35b89f1';
const _command = 'b3291ca8-498d-48de-a8ce-2e2e8256d803';
const _month = '2026-10';

Map<String, dynamic> _memoryJson({
  String id = _id,
  String pair = _pair,
  String day = '2026-10-08',
  String actor = 'a',
  String note = 'Хамтдаа',
}) => {
  'id': id,
  'pair_id': pair,
  'creator_id': actor,
  'day': day,
  'title': 'Кофе',
  'note': note,
  'sticker': 'rounded',
  'version': 1,
  'created_at': '2026-10-08T03:00:00.000Z',
};
Map<String, dynamic> _listJson({
  List<Map<String, dynamic>>? memories,
  String pair = _pair,
}) => {
  'ok': true,
  'pair_id': pair,
  'memories': memories ?? [_memoryJson()],
};
http.StreamedResponse _json(Map<String, dynamic> body, {int status = 200}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
    );
Uint8List _jpeg() => img.encodeJpg(
  img.Image(width: 4, height: 4)..clear(img.ColorRgb8(120, 60, 80)),
);
Matcher _failure(String code) =>
    throwsA(isA<MemoryFailure>().having((e) => e.code, 'code', code));

class _Client extends http.BaseClient {
  final calls = <http.BaseRequest>[];
  Future<http.StreamedResponse> Function(http.BaseRequest)? onSend;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request);
    return onSend == null ? _json(_listJson()) : onSend!(request);
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  late CloudflareAuthRepository auth;
  late CloudflareMemoryRepository repository;
  late _Client client;
  setUp(() async {
    auth = CloudflareAuthRepository(
      transport: TogetherTransport(),
      storage: TogetherStorage(),
    );
    await auth.verifyEmailCode('a@example.com', '123456');
    client = _Client();
    repository = CloudflareMemoryRepository(
      auth,
      baseUri: Uri.parse('https://memories.example'),
      client: client,
    );
  });
  tearDown(() async {
    await repository.dispose();
    await auth.dispose();
  });

  test(
    'request pins bearer, pair and command and never follows redirects',
    () async {
      await repository.list(_pair, _month);
      final listing = client.calls.single as http.Request;
      expect(
        listing.url,
        Uri.parse('https://memories.example/v1/memories/list'),
      );
      expect(listing.method, 'POST');
      expect(listing.headers['Authorization'], 'Bearer token-a');
      expect(listing.followRedirects, isFalse);
      expect(jsonDecode(listing.body), {
        'expected_pair_id': _pair,
        'month': _month,
      });
      final photo = _jpeg();
      client.onSend = (_) async => _json({'ok': true, 'memory': _memoryJson()});
      await repository.create(
        _pair,
        _command,
        MemoryDraft(
          day: '2026-10-08',
          title: 'Кофе',
          note: 'Хамтдаа',
          sticker: 'rounded',
          image: MemoryPhoto(photo: photo, thumbnail: photo),
        ),
      );
      final creation = client.calls.last as http.Request;
      final body = jsonDecode(creation.body) as Map;
      expect(body['expected_pair_id'], _pair);
      expect(body['command_id'], _command);
      expect(body['photo_base64'], base64Encode(photo));
      expect(body['thumbnail_base64'], base64Encode(photo));
      expect(creation.headers['Authorization'], 'Bearer token-a');
    },
  );

  for (final status in [200, 401]) {
    test(
      'late $status response cannot expose data or reject a newer login',
      () async {
        final reply = Completer<http.StreamedResponse>();
        client.onSend = (_) => reply.future;
        final request = repository.list(_pair, _month);
        final assertion = expectLater(request, _failure('unauthenticated'));
        await auth.verifyEmailCode('b@example.com', '123456');
        reply.complete(
          _json(
            status == 200
                ? _listJson()
                : {'ok': false, 'code': 'unauthenticated'},
            status: status,
          ),
        );
        await assertion;
        expect(auth.current.userId, 'b');
        expect(auth.current.isSignedIn, isTrue);
        expect(client.calls.single.headers['Authorization'], 'Bearer token-a');
        expect(repository.isCurrent, isFalse);
      },
    );
  }

  test(
    'current 401 invalidates login but service failure preserves it',
    () async {
      client.onSend = (_) async =>
          _json({'ok': false, 'code': 'temporarily_unavailable'}, status: 503);
      await expectLater(
        repository.list(_pair, _month),
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
      await expectLater(
        repository.list(_pair, _month),
        _failure('unauthenticated'),
      );
      expect(auth.current.isSignedIn, isFalse);
      expect(invalidations, 1);
    },
  );

  test(
    'same-account fresh login still invalidates the old repository',
    () async {
      await auth.verifyEmailCode('a@example.com', '123456');
      await expectLater(
        repository.list(_pair, _month),
        _failure('unauthenticated'),
      );
      expect(client.calls, isEmpty);
      expect(auth.current.userId, 'a');
    },
  );

  test('rejects list envelopes or rows from another pair or month', () async {
    final invalid = [
      _listJson(pair: _otherPair),
      _listJson(memories: [_memoryJson(pair: _otherPair)]),
      _listJson(memories: [_memoryJson(day: '2026-11-01')]),
    ];
    for (final reply in invalid) {
      client.onSend = (_) async => _json(reply);
      await expectLater(
        repository.list(_pair, _month),
        _failure('invalid_response'),
      );
    }
  });

  test('legitimate large monthly list fits below the four MiB cap', () async {
    final rows = List.generate(
      310,
      (index) => _memoryJson(
        id: '${index.toRadixString(16).padLeft(8, '0')}-1111-4111-8111-111111111111',
        day: '2026-10-${(index ~/ 10 + 1).toString().padLeft(2, '0')}',
        note: 'Ө' * 2000,
      ),
    );
    expect(
      utf8.encode(jsonEncode(_listJson(memories: rows))).length,
      greaterThan(1200 * 1024),
    );
    client.onSend = (_) async => _json(_listJson(memories: rows));
    expect(await repository.list(_pair, _month), hasLength(310));
  });

  test('rejects JSON responses above four MiB', () async {
    client.onSend = (_) async =>
        _json({..._listJson(memories: []), 'padding': 'x' * (4 * 1024 * 1024)});
    await expectLater(
      repository.list(_pair, _month),
      _failure('invalid_response'),
    );
  });

  test(
    'create rejects a response attributed to another actor or pair',
    () async {
      final photo = _jpeg();
      final draft = MemoryDraft(
        day: '2026-10-08',
        title: 'Кофе',
        note: 'Хамтдаа',
        sticker: 'rounded',
        image: MemoryPhoto(photo: photo, thumbnail: photo),
      );
      for (final reply in [
        _memoryJson(actor: 'b'),
        _memoryJson(pair: _otherPair),
        _memoryJson(day: '2026-10-09'),
      ]) {
        client.onSend = (_) async => _json({'ok': true, 'memory': reply});
        await expectLater(
          repository.create(_pair, _command, draft),
          _failure('invalid_response'),
        );
      }
    },
  );

  test(
    'photo uses private GET and rejects wrong MIME or malformed JPEG',
    () async {
      final memory = SharedMemory.fromJson(_memoryJson());
      final bytes = _jpeg();
      client.onSend = (_) async => http.StreamedResponse(
        Stream.value(bytes),
        200,
        headers: {'content-type': 'image/jpeg'},
      );
      expect(await repository.photo(memory, thumbnail: true), bytes);
      final request = client.calls.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/memories/$_id/thumbnail');
      expect(request.headers['Authorization'], 'Bearer token-a');
      client.onSend = (_) async => http.StreamedResponse(
        Stream.value(bytes),
        200,
        headers: {'content-type': 'text/html'},
      );
      await expectLater(repository.photo(memory), _failure('invalid_response'));
      client.onSend = (_) async => http.StreamedResponse(
        Stream.value([1, 2, 3, 4]),
        200,
        headers: {'content-type': 'image/jpeg'},
      );
      await expectLater(repository.photo(memory), _failure('invalid_response'));
    },
  );

  test(
    'thumbnail and full photo have separate bounded response sizes',
    () async {
      final memory = SharedMemory.fromJson(_memoryJson());
      for (final thumbnail in [true, false]) {
        final bytes = Uint8List((thumbnail ? 64 : 768) * 1024 + 1);
        bytes[0] = 0xff;
        bytes[1] = 0xd8;
        bytes[bytes.length - 2] = 0xff;
        bytes[bytes.length - 1] = 0xd9;
        client.onSend = (_) async => http.StreamedResponse(
          Stream.value(bytes),
          200,
          headers: {'content-type': 'image/jpeg'},
        );
        await expectLater(
          repository.photo(memory, thumbnail: thumbnail),
          _failure('invalid_response'),
        );
      }
    },
  );

  test(
    'deletion requires explicit confirmation and pins expected version',
    () async {
      final memory = SharedMemory.fromJson(_memoryJson());
      client.onSend = (_) async => _json({'ok': true});
      await expectLater(
        repository.delete(memory, _command),
        _failure('invalid_response'),
      );
      client.onSend = (_) async => _json({'ok': true, 'deleted': true});
      await repository.delete(memory, _command);
      final request = client.calls.last as http.Request;
      expect(jsonDecode(request.body), {
        'expected_pair_id': _pair,
        'id': _id,
        'expected_version': 1,
        'command_id': _command,
      });
    },
  );

  test(
    'dispose aborts an outstanding request and rejects its late result',
    () async {
      client.onSend = (request) async {
        await (request as http.AbortableRequest).abortTrigger;
        throw http.ClientException('aborted');
      };
      final pending = repository.list(_pair, _month);
      final assertion = expectLater(pending, _failure('unauthenticated'));
      await repository.dispose();
      await assertion;
      expect(client.closed, isTrue);
    },
  );
}
