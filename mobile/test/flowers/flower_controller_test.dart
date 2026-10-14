import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/flowers/flower_controller.dart';
import 'package:hamtdaa/flowers/flower_models.dart';
import 'flower_fakes.dart';

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeFlowersRepository repository;
  late FlowersController controller;
  setUp(() {
    repository = FakeFlowersRepository();
    controller = FlowersController(repository);
  });
  tearDown(() {
    controller.dispose();
  });
  Future<void> open() async {
    controller.setVisible(true);
    await settle();
  }

  test('confirmed server send refreshes real sent gifts', () async {
    await open();
    expect(
      await controller.send(const FlowerDraft(message: 'Чамдаа ♡')),
      isTrue,
    );
    expect(controller.sentId, 'gift-1');
    expect(controller.snapshot!.gifts.single.senderId, 'a');
  });
  test(
    'failed network send retries identical command and cannot double-tap',
    () async {
      await open();
      repository.onSend = (_) async =>
          throw const FlowerFailure('network_error', retryable: true);
      expect(
        await controller.send(const FlowerDraft(message: 'Чамдаа ♡')),
        isFalse,
      );
      expect(controller.pending, isTrue);
      expect(
        await controller.send(const FlowerDraft(message: 'өөр үг')),
        isFalse,
      );
      repository.onSend = (_) async => 'gift-confirmed';
      expect(await controller.retry(), isTrue);
      expect(repository.commands.length, 2);
      expect(identical(repository.commands[0], repository.commands[1]), isTrue);
      expect(controller.pending, isFalse);
    },
  );
  test('concurrent send ignored while first server write pending', () async {
    await open();
    final reply = Completer<String>();
    repository.onSend = (_) => reply.future;
    final first = controller.send(const FlowerDraft(message: 'Чамдаа'));
    expect(await controller.send(const FlowerDraft(message: 'Дахин')), isFalse);
    expect(await controller.retry(), isFalse);
    reply.complete('gift-confirmed');
    await first;
    expect(repository.commands.length, 1);
  });
  test(
    'revocation clears private data, pending command and draft revision',
    () async {
      repository.value = flowersJson(gifts: [giftJson()]);
      await open();
      final before = controller.privacyRevision;
      repository.onSend = (_) async =>
          throw const FlowerFailure('network_error', retryable: true);
      await controller.send(const FlowerDraft(message: 'Чамдаа'));
      repository.value = flowersJson(paired: false);
      await controller.refresh();
      expect(controller.snapshot!.paired, isFalse);
      expect(controller.pending, isFalse);
      expect(controller.privacyRevision, greaterThan(before));
      expect(controller.canSend, isFalse);
    },
  );
  test('pair change rejection removes draft scope immediately', () async {
    await open();
    repository.onSend = (_) async => throw const FlowerFailure('pair_changed');
    final revision = controller.privacyRevision;
    expect(
      await controller.send(const FlowerDraft(message: 'Чамдаа')),
      isFalse,
    );
    expect(controller.snapshot, isNull);
    expect(controller.pending, isFalse);
    expect(controller.saving, isFalse);
    expect(controller.privacyRevision, greaterThan(revision));
  });
  test('background clears cards and ignores old foreground load', () async {
    await open();
    final reply = Completer<FlowersSnapshot>();
    repository.onState = () => reply.future;
    final load = controller.refresh();
    controller.setVisible(false);
    reply.complete(
      FlowersSnapshot.fromJson(flowersJson(gifts: [giftJson()]), 'a'),
    );
    await load;
    expect(controller.snapshot, isNull);
    expect(controller.canSend, isFalse);
  });
  test('auth invalidation rejects late write acknowledgement', () async {
    await open();
    final reply = Completer<String>();
    repository.onSend = (_) => reply.future;
    final write = controller.send(const FlowerDraft(message: 'Чамдаа'));
    repository.invalidate();
    reply.complete('gift-confirmed');
    expect(await write, isFalse);
    expect(controller.snapshot, isNull);
    expect(controller.sentId, isNull);
    expect(controller.pending, isFalse);
  });
  test('network refresh failure hides previously private messages', () async {
    repository.value = flowersJson(gifts: [giftJson()]);
    await open();
    repository.onState = () async =>
        throw const FlowerFailure('network_error', retryable: true);
    await controller.refresh();
    expect(controller.snapshot, isNull);
    expect(controller.canSend, isFalse);
  });
  testWidgets('lease expiry hides private projection when refresh hangs', (
    tester,
  ) async {
    controller.setVisible(true);
    await tester.pump();
    expect(controller.snapshot, isNotNull);
    final reply = Completer<FlowersSnapshot>();
    repository.onState = () => reply.future;
    await tester.pump(const Duration(seconds: 46));
    expect(controller.snapshot, isNull);
    reply.complete(const FlowersSnapshot(paired: false));
    await tester.pump();
    expect(controller.snapshot, isNull);
    controller.setVisible(false);
  });
}
