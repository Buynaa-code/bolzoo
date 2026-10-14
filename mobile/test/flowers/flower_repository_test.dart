import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';
import 'package:hamtdaa/flowers/flower_models.dart';
import 'package:hamtdaa/flowers/flower_repository.dart';
import '../together/together_fakes.dart';
import 'flower_fakes.dart';

void main() {
  late TogetherTransport transport;
  late CloudflareAuthRepository auth;
  late CloudflareFlowersRepository repository;
  setUp(() async {
    transport = TogetherTransport();
    auth = CloudflareAuthRepository(
      transport: transport,
      storage: TogetherStorage(),
    );
    await auth.verifyEmailCode('a@example.com', '123456');
    repository = CloudflareFlowersRepository(auth);
    transport.onCall = (_, _) async => CloudflareResponse(200, flowersJson());
  });
  tearDown(() async {
    await repository.dispose();
    await auth.dispose();
  });
  test(
    'scoped POST gift send never accepts client recipient authority',
    () async {
      transport.onCall = (path, _) async => CloudflareResponse(
        200,
        path.endsWith('/send') ? {'ok': true, 'id': 'gift-new'} : flowersJson(),
      );
      final state = await repository.state();
      final command = FlowerCommand(
        state.pairId!,
        const FlowerDraft(message: 'Сайн уу ♡'),
      );
      expect(await repository.send(command), 'gift-new');
      expect(transport.calls.last.path, '/v1/gifts/send');
      expect(transport.calls.last.body, command.body);
      expect(command.body.containsKey('recipient_id'), isFalse);
      expect(transport.calls.map((c) => c.token), everyElement('token-a'));
      expect(transport.calls.map((c) => c.method), everyElement('POST'));
    },
  );
  test('late state cannot leak into new account', () async {
    final reply = Completer<CloudflareResponse>();
    transport.onCall = (_, _) => reply.future;
    final request = repository.state();
    final assertion = expectLater(
      request,
      throwsA(
        isA<FlowerFailure>().having((e) => e.code, 'code', 'unauthenticated'),
      ),
    );
    await auth.verifyEmailCode('c@example.com', '123456');
    reply.complete(CloudflareResponse(200, flowersJson(gifts: [giftJson()])));
    await assertion;
    expect(repository.isCurrent, isFalse);
    expect(transport.calls.single.token, 'token-a');
  });
  test('unpaired response discards private leftovers', () async {
    transport.onCall = (_, _) async => CloudflareResponse(
      200,
      flowersJson(paired: false, gifts: [giftJson()]),
    );
    final state = await repository.state();
    expect(state.paired, isFalse);
    expect(state.gifts, isEmpty);
  });
  test('mismatched pair or recipient and repeated cursor rejected', () async {
    for (final json in [
      flowersJson(gifts: [giftJson(pair: 'other')]),
      flowersJson(gifts: [giftJson(recipient: 'c')]),
    ]) {
      transport.onCall = (_, _) async => CloudflareResponse(200, json);
      await expectLater(repository.state(), throwsA(isA<FlowerFailure>()));
    }
    var page = 0;
    transport.onCall = (_, _) async => CloudflareResponse(
      200,
      flowersJson(
        gifts: [giftJson(id: 'gift-${page++}')],
        cursor: 'same-cursor',
      ),
    );
    await expectLater(repository.state(), throwsA(isA<FlowerFailure>()));
    expect(page, 2);
  });
  test('paging pair changes are rejected atomically', () async {
    transport.onCall = (_, body) async => CloudflareResponse(
      200,
      body!['cursor'] == null
          ? flowersJson(gifts: [giftJson()], cursor: 'next')
          : flowersJson(pair: 'pair-b'),
    );
    await expectLater(
      repository.state(),
      throwsA(
        isA<FlowerFailure>().having((e) => e.code, 'code', 'pair_changed'),
      ),
    );
  });
  test('401 invalidates signed-in session and 503 is retryable', () async {
    transport.onCall = (_, _) async => const CloudflareResponse(503, {
      'ok': false,
      'code': 'temporarily_unavailable',
    });
    await expectLater(
      repository.state(),
      throwsA(
        isA<FlowerFailure>().having((e) => e.retryable, 'retryable', isTrue),
      ),
    );
    expect(auth.current.isSignedIn, isTrue);
    transport.onCall = (_, _) async =>
        const CloudflareResponse(401, {'ok': false, 'code': 'unauthenticated'});
    await expectLater(repository.state(), throwsA(isA<FlowerFailure>()));
    expect(auth.current.isSignedIn, isFalse);
  });
  test(
    'concurrent deletion restarts once without retaining an old page',
    () async {
      var page = 0;
      transport.onCall = (_, body) async => switch (page++) {
        0 => CloudflareResponse(
          200,
          flowersJson(
            gifts: [giftJson(id: 'deleted')],
            cursor: 'old-next',
          ),
        ),
        1 => const CloudflareResponse(409, {
          'ok': false,
          'code': 'gifts_changed',
        }),
        2 => CloudflareResponse(
          200,
          flowersJson(
            gifts: [giftJson(id: 'current-first')],
            cursor: 'new-next',
          ),
        ),
        _ => CloudflareResponse(
          200,
          flowersJson(gifts: [giftJson(id: 'current-last')]),
        ),
      };
      final state = await repository.state();
      expect(state.gifts.map((g) => g.id), ['current-first', 'current-last']);
      expect(transport.calls.map((c) => c.body!['cursor']), [
        null,
        'old-next',
        null,
        'new-next',
      ]);
    },
  );
  test('continuously changing pages fail after one restart', () async {
    transport.onCall = (_, body) async => body!['cursor'] == null
        ? CloudflareResponse(
            200,
            flowersJson(gifts: [giftJson()], cursor: 'next'),
          )
        : const CloudflareResponse(409, {'ok': false, 'code': 'gifts_changed'});
    await expectLater(
      repository.state(),
      throwsA(
        isA<FlowerFailure>().having((e) => e.code, 'code', 'gifts_changed'),
      ),
    );
    expect(transport.calls, hasLength(4));
  });
}
