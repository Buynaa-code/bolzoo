import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/features/home/cloudflare_home_controller.dart';
import 'package:hamtdaa/memories/memory_controller.dart';
import 'package:hamtdaa/memories/memory_models.dart';
import 'package:hamtdaa/memories/memory_repository.dart';
import 'package:hamtdaa/pair/pair_models.dart';
import 'package:hamtdaa/together/together_models.dart';

import '../pair/pair_flow_test.dart' as pairing;
import '../together/together_fakes.dart' as together;

const _otherPair = ActivePair(
  id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  version: 1,
  partner: PairPerson(userId: 'new-partner', displayName: 'Саруул'),
);

TogetherSnapshot _calendar({
  ActivePair pair = pairing.pair,
  String? partnerId,
}) => TogetherSnapshot(
  paired: true,
  pairId: pair.id,
  partnerId: partnerId ?? pair.partner.userId,
  partnerName: pair.partner.displayName,
  events: [TogetherEvent.fromJson(together.eventJson())],
);

SharedMemory _memory(String pairId) => SharedMemory(
  id: 'photo-$pairId',
  pairId: pairId,
  creatorId: pairing.a.userId,
  day: '2026-10-06',
  title: 'Бидний кофе',
  note: '',
  sticker: 'rounded',
  version: 1,
  createdAt: together.today,
);

class _Photos implements MemoryRepository {
  final changes = StreamController<void>.broadcast(sync: true);
  final reads = <({String pairId, String month})>[];
  bool disposed = false;

  @override
  bool get isCurrent => !disposed;
  @override
  String get actorId => pairing.a.userId;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<List<SharedMemory>> list(String pairId, String month) async {
    reads.add((pairId: pairId, month: month));
    return [_memory(pairId)];
  }

  @override
  Future<Uint8List> photo(
    SharedMemory memory, {
    bool thumbnail = false,
  }) async => Uint8List.fromList([1, 2, 3]);
  @override
  Future<SharedMemory> create(
    String pairId,
    String commandId,
    MemoryDraft draft,
  ) => throw UnimplementedError('The home projection must not create memories');
  @override
  Future<void> delete(SharedMemory memory, String commandId) =>
      throw UnimplementedError('The home projection must not delete memories');
  @override
  Future<void> dispose() async {
    disposed = true;
    await changes.close();
  }
}

void main() {
  late pairing.FakePairRepository pairs;
  late together.TogetherFakeRepository calendar;
  late _Photos photos;
  late MemoryController memories;
  late CloudflareHomeController home;
  late int statusReads;

  setUp(() {
    statusReads = 0;
    pairs = pairing.FakePairRepository()
      ..current = pairing.snapshot(active: pairing.pair);
    pairs.read = () async {
      ++statusReads;
      return pairs.current;
    };
    calendar = together.TogetherFakeRepository()
      ..onState = (_) async => _calendar();
    photos = _Photos();
    memories = MemoryController(photos);
    home = CloudflareHomeController(
      pairs: pairs,
      together: calendar,
      memories: memories,
      clock: () => together.today,
    );
  });
  void testHomeWidgets(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        // Cancel fake-clock timers before the widget binding checks invariants.
        home.dispose();
      }
    });
  }

  void expectPrivateDataCleared() {
    expect(home.pair, isNull);
    expect(home.calendar, isNull);
    expect(home.paired, isFalse);
    expect(memories.pairId, isNull);
    expect(memories.items, isEmpty);
    expect(memories.thumbnails, isEmpty);
  }

  testHomeWidgets('hidden home sends no reads and stops periodic work', (
    tester,
  ) async {
    await home.refresh();
    await tester.pump(const Duration(minutes: 1));
    expect(statusReads, 0);
    expect(calendar.months, isEmpty);
    expect(photos.reads, isEmpty);

    home.setVisible(true);
    await tester.pump();
    expect(statusReads, 1);
    expect(memories.thumbnails, isNotEmpty);
    home.setVisible(false);
    expectPrivateDataCleared();
    await home.refresh();
    await tester.pump(const Duration(minutes: 1));
    expect(statusReads, 1);
    expect(calendar.months, ['2026-10']);
    expect(photos.reads, hasLength(1));
  });

  testHomeWidgets(
    'unpaired profile has no invented partner, events, or photos',
    (tester) async {
      pairs.current = pairing.snapshot();
      home.setVisible(true);
      expect(home.pair, isNull);
      await tester.pump();
      expect(home.pair?.profile, same(pairs.current.profile));
      expect(home.paired, isFalse);
      expect(home.calendar, isNull);
      expect(calendar.months, isEmpty);
      expect(photos.reads, isEmpty);
      expect(memories.items, isEmpty);
      expect(pairs.commands, isEmpty);
      expect(calendar.commands, isEmpty);
    },
  );

  testHomeWidgets(
    'publishes verified pair, calendar, and photos only in the same scope',
    (tester) async {
      final response = Completer<TogetherSnapshot>();
      calendar.onState = (_) => response.future;
      home.setVisible(true);
      await tester.pump();
      expect(home.loading, isTrue);
      expectPrivateDataCleared();
      expect(photos.reads, isEmpty);

      response.complete(_calendar());
      await tester.pump();
      expect(home.pair, same(pairs.current));
      expect(home.calendar?.partnerId, pairing.pair.partner.userId);
      expect(home.calendar?.events.single.title, 'Кофе уух уу?');
      expect(memories.pairId, pairing.pair.id);
      expect(memories.items.single.pairId, pairing.pair.id);
      expect(memories.thumbnails.keys, [memories.items.single.id]);
      expect(home.loading, isFalse);
      expect(home.error, isNull);
      expect(pairs.commands, isEmpty);
      expect(calendar.commands, isEmpty);
    },
  );

  for (final mismatch in ['pair id', 'partner id', 'unpaired']) {
    testHomeWidgets('rejects a calendar with mismatched $mismatch', (
      tester,
    ) async {
      calendar.onState = (_) async => switch (mismatch) {
        'pair id' => _calendar(pair: _otherPair),
        'partner id' => _calendar(partnerId: 'unrelated-person'),
        _ => const TogetherSnapshot(paired: false),
      };
      home.setVisible(true);
      await tester.pump();
      expectPrivateDataCleared();
      expect(home.error, const TogetherFailure('pair_changed').message);
      expect(photos.reads, isEmpty);
      expect(home.loading, isFalse);
    });
  }

  testHomeWidgets(
    'pair change removes previous partner and photos before new calendar arrives',
    (tester) async {
      home.setVisible(true);
      await tester.pump();
      expect(memories.thumbnails, isNotEmpty);
      pairs.current = pairing.snapshot(active: _otherPair);
      final response = Completer<TogetherSnapshot>();
      calendar.onState = (_) => response.future;
      final refreshing = home.refresh();
      await tester.pump();
      expectPrivateDataCleared();

      response.complete(_calendar(pair: _otherPair));
      await refreshing;
      await tester.pump();
      expect(home.pair?.pair?.partner.displayName, 'Саруул');
      expect(memories.items.single.pairId, _otherPair.id);
      expect(
        memories.thumbnails.containsKey(_memory(pairing.pair.id).id),
        isFalse,
      );
    },
  );

  testHomeWidgets(
    'confirmed unlink clears all shared projections without reading calendar',
    (tester) async {
      home.setVisible(true);
      await tester.pump();
      pairs.current = pairing.snapshot();
      await home.refresh();
      expect(home.pair, same(pairs.current));
      expect(home.calendar, isNull);
      expect(home.paired, isFalse);
      expect(memories.pairId, isNull);
      expect(memories.items, isEmpty);
      expect(memories.thumbnails, isEmpty);
      expect(calendar.months, hasLength(1));
    },
  );

  testHomeWidgets(
    'network failure clears private data and allows a fresh retry',
    (tester) async {
      home.setVisible(true);
      await tester.pump();
      calendar.onState = (_) async =>
          throw const TogetherFailure('network_error');
      await home.refresh();
      expectPrivateDataCleared();
      expect(home.error, const TogetherFailure('network_error').message);
      expect(home.loading, isFalse);

      calendar.onState = (_) async => _calendar();
      await home.refresh();
      await tester.pump();
      expect(home.paired, isTrue);
      expect(home.error, isNull);
      expect(memories.thumbnails, isNotEmpty);
    },
  );

  for (final stage in ['pair', 'calendar']) {
    testHomeWidgets(
      'late $stage response after hide cannot replace resumed home',
      (tester) async {
        final oldPair = Completer<PairSnapshot>();
        final oldCalendar = Completer<TogetherSnapshot>();
        if (stage == 'pair') {
          pairs.read = () => oldPair.future;
        } else {
          calendar.onState = (_) => oldCalendar.future;
        }
        home.setVisible(true);
        await tester.pump();
        home.setVisible(false);
        expectPrivateDataCleared();
        pairs.current = pairing.snapshot(active: _otherPair);
        pairs.read = () async => pairs.current;
        calendar.onState = (_) async => _calendar(pair: _otherPair);
        home.setVisible(true);
        await tester.pump();
        expect(home.pair?.pair?.id, _otherPair.id);

        if (stage == 'pair') {
          oldPair.complete(pairing.snapshot(active: pairing.pair));
        } else {
          oldCalendar.complete(_calendar());
        }
        await tester.pump();
        expect(home.pair?.pair?.id, _otherPair.id);
        expect(home.calendar?.pairId, _otherPair.id);
        expect(memories.pairId, _otherPair.id);
        expect(home.loading, isFalse);
      },
    );
  }

  for (final source in ['pair', 'calendar']) {
    testHomeWidgets(
      '$source account invalidation clears data and rejects pending responses',
      (tester) async {
        home.setVisible(true);
        await tester.pump();
        final response = Completer<TogetherSnapshot>();
        calendar.onState = (_) => response.future;
        final refreshing = home.refresh();
        await tester.pump();
        if (source == 'pair') {
          pairs.events.add(null);
        } else {
          calendar.invalidate();
        }
        expectPrivateDataCleared();
        expect(home.current, isFalse);
        response.complete(_calendar());
        await refreshing;
        await tester.pump(const Duration(minutes: 1));
        expectPrivateDataCleared();
        expect(statusReads, 2);
        expect(calendar.months, hasLength(2));
      },
    );
  }

  testHomeWidgets(
    '45 second lease hides data if refresh hangs and rejects its late answer',
    (tester) async {
      home.setVisible(true);
      await tester.pump();
      expect(memories.thumbnails, isNotEmpty);
      final response = Completer<PairSnapshot>();
      pairs.read = () => response.future;
      await tester.pump(const Duration(seconds: 10));
      expect(home.loading, isTrue);
      await tester.pump(const Duration(seconds: 35));
      expectPrivateDataCleared();
      expect(home.error, isNotNull);
      response.complete(pairing.snapshot(active: pairing.pair));
      await tester.pump();
      expectPrivateDataCleared();

      pairs.read = () async => pairs.current;
      await home.refresh();
      await tester.pump();
      expect(home.paired, isTrue);
      expect(home.error, isNull);
    },
  );

  testHomeWidgets(
    'dispose owns repositories and suppresses a late calendar answer',
    (tester) async {
      final response = Completer<TogetherSnapshot>();
      calendar.onState = (_) => response.future;
      var notifications = 0;
      home.addListener(() => ++notifications);
      home.setVisible(true);
      await tester.pump();
      home.dispose();
      final before = notifications;
      expect(pairs.disposed, isTrue);
      expect(calendar.isCurrent, isFalse);
      expect(photos.disposed, isTrue);
      response.complete(_calendar());
      await tester.pump(const Duration(minutes: 1));
      expect(notifications, before);
      expect(home.current, isFalse);
      expect(photos.reads, isEmpty);
      expect(statusReads, 1);
    },
  );
}
