import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/wishes/wish_controller.dart';
import 'package:hamtdaa/wishes/wish_models.dart';

import 'wish_fakes.dart';

void main() {
  late WishFakeRepository repository;
  late WishController controller;
  setUp(() {
    repository = WishFakeRepository();
    controller = WishController(repository);
  });
  tearDown(() => controller.dispose());

  test(
    'unavailable feature blocks commands until a successful refresh recovers it',
    () async {
      repository.onList = (_) async =>
          throw const WishFailure('feature_unavailable');
      controller.bind(wishPair);
      await flushWishes();
      expect(controller.failure?.code, 'feature_unavailable');
      expect(controller.failure?.needsRetry, isFalse);
      expect(controller.canMutate, isFalse);
      expect(await controller.create(wishDraft), isNull);
      expect(await controller.like(wish(), false), isNull);
      expect(
        await controller.plan(wish(partnerLiked: true), DateTime.utc(2027)),
        isNull,
      );
      expect(await controller.complete(wish(status: 'planned')), isNull);
      expect(await controller.delete(wish()), isFalse);
      expect(repository.calls, isEmpty);
      expect(controller.pendingCommand, isNull);
      expect(await controller.retry(), isFalse);
      repository.onList = null;
      await controller.refresh();
      expect(controller.failure, isNull);
      expect(controller.canMutate, isTrue);
      expect(await controller.create(wishDraft), isNotNull);
      expect(repository.calls, hasLength(1));
    },
  );

  test(
    'late list cannot restore private rows after session invalidation',
    () async {
      final reply = Completer<List<SharedWish>>();
      repository.onList = (_) => reply.future;
      controller.bind(wishPair);
      repository.invalidate();
      reply.complete([wish()]);
      await flushWishes();
      expect(controller.current, isFalse);
      expect(controller.pairId, isNull);
      expect(controller.items, isEmpty);
      expect(controller.loading, isFalse);
    },
  );

  test('late old pair reply cannot replace new pair records', () async {
    final reply = Completer<List<SharedWish>>();
    repository.onList = (pair) async =>
        pair == wishPair ? reply.future : [wish(pair: wishOtherPair)];
    controller.bind(wishPair);
    controller.bind(wishOtherPair);
    await flushWishes();
    reply.complete([wish()]);
    await flushWishes();
    expect(controller.items.single.pairId, wishOtherPair);
  });

  test(
    'hidden tab clears records and discards late read then refreshes on return',
    () async {
      repository.rows = [wish()];
      controller.bind(wishPair);
      await flushWishes();
      final reply = Completer<List<SharedWish>>();
      repository.onList = (_) => reply.future;
      final refresh = controller.refresh();
      controller.setVisible(false);
      reply.complete([wish()]);
      await refresh;
      expect(controller.items, isEmpty);
      expect(controller.canMutate, isFalse);
      repository.onList = null;
      controller.setVisible(true);
      await flushWishes();
      expect(controller.items, hasLength(1));
    },
  );

  test(
    'lost create response retains immutable command and blocks changed drafts',
    () async {
      controller.bind(wishPair);
      await flushWishes();
      repository.onCreate = (_, _, _) async =>
          throw const WishFailure('unavailable');
      expect(await controller.create(wishDraft), isNull);
      final command = controller.pendingCommand;
      expect(command, isNotNull);
      expect(controller.canMutate, isFalse);
      expect(
        await controller.create(const WishDraft(title: 'Өөр хүсэл')),
        isNull,
      );
      expect(await controller.like(wish(), false), isNull);
      expect(repository.calls, hasLength(1));
      repository.onCreate = null;
      expect(await controller.retry(), isTrue);
      await flushWishes();
      expect(repository.calls.last.command, command);
      expect(repository.calls.last.draft, same(wishDraft));
      expect(controller.pendingCommand, isNull);
      expect(controller.items, hasLength(1));
      expect(controller.notice, isNotNull);
    },
  );

  test(
    'plan retry pins original expected version and dates after a newer read',
    () async {
      final original = wish(partnerLiked: true);
      repository.rows = [original];
      controller.bind(wishPair);
      await flushWishes();
      final start = DateTime.utc(2027, 1, 2, 10),
          end = DateTime.utc(2027, 1, 2, 11);
      repository.onMutation = (_, _, _) async =>
          throw const WishFailure('unavailable');
      expect(await controller.plan(original, start, endsAt: end), isNull);
      repository.rows = [
        wish(status: 'planned', partnerLiked: true, version: 2),
      ];
      await controller.refresh();
      repository.onMutation = null;
      expect(await controller.retry(), isTrue);
      expect(repository.calls.last.command, repository.calls.first.command);
      expect(repository.calls.last.wish!.version, 1);
      expect(repository.calls.last.starts, start);
      expect(repository.calls.last.ends, end);
    },
  );

  test('late save and its retry cannot follow pair rebinding', () async {
    controller.bind(wishPair);
    await flushWishes();
    final reply = Completer<SharedWish>();
    repository.onCreate = (_, _, _) => reply.future;
    final create = controller.create(wishDraft);
    final previousCommand = controller.pendingCommand;
    controller.bind(wishOtherPair);
    reply.complete(wish());
    expect(await create, isNull);
    expect(controller.items, isEmpty);
    expect(controller.pendingCommand, isNull);
    repository.onCreate = (_, _, _) async =>
        throw const WishFailure('unavailable');
    await controller.create(wishDraft);
    expect(controller.pendingCommand, isNot(previousCommand));
  });

  test('pre-mutation refresh cannot resurrect a deleted wish', () async {
    final value = wish();
    repository.rows = [value];
    controller.bind(wishPair);
    await flushWishes();
    final reply = Completer<List<SharedWish>>();
    var initial = true;
    repository.onList = (_) async {
      if (initial) {
        initial = false;
        return reply.future;
      }
      return repository.rows;
    };
    final refresh = controller.refresh();
    expect(await controller.delete(value), isTrue);
    reply.complete([value]);
    await refresh;
    await flushWishes();
    expect(controller.items, isEmpty);
  });

  test(
    'conflict is definite, refreshes partner change, and leaves a notice',
    () async {
      final original = wish();
      repository.rows = [original];
      controller.bind(wishPair);
      await flushWishes();
      repository.onMutation = (_, _, _) async {
        repository.rows = [wish(partnerLiked: true, version: 2)];
        throw const WishFailure('conflict');
      };
      expect(await controller.like(original, false), isNull);
      await flushWishes();
      expect(controller.pendingCommand, isNull);
      expect(controller.canMutate, isTrue);
      expect(controller.items.single.partnerLiked, isTrue);
      expect(controller.notice, contains('шинэчлэгдсэн'));
    },
  );

  test(
    'permissions and incomplete consent stop invalid actions before sending',
    () async {
      controller.bind(wishPair);
      await flushWishes();
      expect(await controller.delete(wish(actor: 'b')), isFalse);
      expect(await controller.plan(wish(), DateTime.utc(2027)), isNull);
      expect(
        await controller.complete(
          wish(status: 'planned', eventStatus: 'pending'),
        ),
        isNull,
      );
      expect(
        await controller.complete(
          wish(status: 'planned', eventStatus: 'declined'),
        ),
        isNull,
      );
      expect(await controller.like(wish(status: 'done'), false), isNull);
      expect(repository.calls, isEmpty);
      final accepted = wish(status: 'planned');
      expect(await controller.complete(accepted), isNotNull);
    },
  );

  test(
    'unknown delete retries exactly once and does not optimistically remove',
    () async {
      final value = wish();
      repository.rows = [value];
      controller.bind(wishPair);
      await flushWishes();
      repository.onDelete = (_, _) async =>
          throw const WishFailure('unavailable');
      expect(await controller.delete(value), isFalse);
      expect(controller.items, hasLength(1));
      repository.onDelete = null;
      expect(await controller.retry(), isTrue);
      expect(repository.calls.first.command, repository.calls.last.command);
      expect(controller.items, isEmpty);
    },
  );

  test('pair revocation clears rows and unknown commands', () async {
    repository.rows = [wish()];
    controller.bind(wishPair);
    await flushWishes();
    repository.onMutation = (_, _, _) async =>
        throw const WishFailure('pair_required');
    expect(await controller.like(wish(), false), isNull);
    expect(controller.items, isEmpty);
    expect(controller.pendingCommand, isNull);
    expect(controller.current, isFalse);
    expect(controller.error, isNotNull);
  });
}
