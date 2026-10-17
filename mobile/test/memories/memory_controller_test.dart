import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/memories/memory_controller.dart';
import 'package:hamtdaa/memories/memory_models.dart';
import 'package:hamtdaa/memories/memory_repository.dart';

const _pair = '98bd1384-1edf-4890-8d6c-d42287e71142';
const _otherPair = '1cbe789d-215f-47a3-bf83-42130c373551';
const _month = '2026-10';

SharedMemory _memory({
  String id = 'memory-one',
  String pair = _pair,
  String actor = 'a',
  String day = '2026-10-08',
}) => SharedMemory(
  id: id,
  pairId: pair,
  creatorId: actor,
  day: day,
  title: 'Кофе',
  note: 'Хамтдаа',
  sticker: 'rounded',
  version: 1,
  createdAt: DateTime.utc(2026, 10, 8),
);

MemoryDraft _draft({int photoByte = 1, String title = 'Кофе'}) => MemoryDraft(
  day: '2026-10-08',
  title: title,
  note: 'Хамтдаа',
  sticker: 'rounded',
  image: MemoryPhoto(
    photo: Uint8List.fromList([photoByte, 2, 3]),
    thumbnail: Uint8List.fromList([4, 5]),
  ),
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _Repository implements MemoryRepository {
  final changes = StreamController<void>.broadcast(sync: true);
  final creates = <({String pair, String command, MemoryDraft draft})>[];
  final deletes = <({SharedMemory memory, String command})>[];
  List<SharedMemory> rows = [];
  Future<List<SharedMemory>> Function(String, String)? onList;
  Future<SharedMemory> Function(String, String, MemoryDraft)? onCreate;
  Future<Uint8List> Function(SharedMemory, bool)? onPhoto;
  Future<void> Function(SharedMemory, String)? onDelete;
  bool active = true, disposed = false;

  @override
  String get actorId => 'a';
  @override
  bool get isCurrent => active && !disposed;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<List<SharedMemory>> list(String pairId, String month) async =>
      onList == null
      ? rows.where((row) => row.pairId == pairId).toList()
      : onList!(pairId, month);
  @override
  Future<SharedMemory> create(
    String pairId,
    String commandId,
    MemoryDraft draft,
  ) async {
    creates.add((pair: pairId, command: commandId, draft: draft));
    return onCreate == null
        ? _memory(pair: pairId)
        : onCreate!(pairId, commandId, draft);
  }

  @override
  Future<Uint8List> photo(
    SharedMemory memory, {
    bool thumbnail = false,
  }) async => onPhoto == null
      ? Uint8List.fromList([1, 2, 3])
      : onPhoto!(memory, thumbnail);
  @override
  Future<void> delete(SharedMemory memory, String commandId) async {
    deletes.add((memory: memory, command: commandId));
    if (onDelete != null) await onDelete!(memory, commandId);
    rows = rows.where((row) => row.id != memory.id).toList();
  }

  void invalidate() {
    active = false;
    changes.add(null);
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await changes.close();
  }
}

void main() {
  late _Repository repository;
  late MemoryController controller;
  setUp(() {
    repository = _Repository();
    controller = MemoryController(repository);
  });
  tearDown(() => controller.dispose());

  test(
    'auth invalidation discards a late list and all private cached data',
    () async {
      final reply = Completer<List<SharedMemory>>();
      repository.onList = (_, _) => reply.future;
      controller.bind(_pair, _month);
      repository.invalidate();
      reply.complete([_memory()]);
      await _flush();
      expect(controller.current, isFalse);
      expect(controller.pairId, isNull);
      expect(controller.items, isEmpty);
      expect(controller.thumbnails, isEmpty);
      expect(controller.loading, isFalse);
    },
  );

  test('late old-pair list cannot replace a newly bound pair', () async {
    final oldReply = Completer<List<SharedMemory>>();
    final next = _memory(id: 'new-pair-memory', pair: _otherPair);
    repository.onList = (pair, _) async =>
        pair == _pair ? oldReply.future : [next];
    controller.bind(_pair, _month);
    controller.bind(_otherPair, _month);
    await _flush();
    oldReply.complete([_memory()]);
    await _flush();
    expect(controller.pairId, _otherPair);
    expect(controller.items.single, same(next));
    expect(controller.thumbnails.keys, [next.id]);
  });

  test('day covers load in parallel but never more than four at a time', () async {
    final replies = <String, Completer<Uint8List>>{};
    var inFlight = 0, peak = 0;
    repository.rows = [
      for (var day = 1; day <= 6; day++)
        _memory(id: 'memory-$day', day: '2026-10-0$day'),
    ];
    repository.onPhoto = (memory, _) {
      inFlight++;
      if (inFlight > peak) peak = inFlight;
      final reply = Completer<Uint8List>();
      replies[memory.id] = reply;
      return reply.future.whenComplete(() {
        inFlight--;
      });
    };
    controller.bind(_pair, _month);
    await _flush();
    expect(replies, hasLength(4));
    for (final reply in replies.values.toList()) {
      reply.complete(Uint8List.fromList([1]));
    }
    await _flush();
    expect(replies, hasLength(6));
    expect(controller.loading, isTrue);
    for (final reply in replies.values.where((r) => !r.isCompleted).toList()) {
      reply.complete(Uint8List.fromList([1]));
    }
    await _flush();
    expect(peak, 4);
    expect(controller.thumbnails, hasLength(6));
    expect(controller.loading, isFalse);
    expect(controller.error, isNull);
  });

  test('a failed cover stops new requests and is reported once', () async {
    final replies = <String, Completer<Uint8List>>{};
    repository.rows = [
      for (var day = 1; day <= 6; day++)
        _memory(id: 'memory-$day', day: '2026-10-0$day'),
    ];
    repository.onPhoto = (memory, _) =>
        (replies[memory.id] = Completer<Uint8List>()).future;
    controller.bind(_pair, _month);
    await _flush();
    expect(replies.keys, ['memory-1', 'memory-2', 'memory-3', 'memory-4']);
    replies['memory-1']!.completeError(const MemoryFailure('unavailable'));
    await _flush();
    for (final id in ['memory-2', 'memory-3', 'memory-4']) {
      replies[id]!.complete(Uint8List.fromList([1]));
    }
    await _flush();
    expect(replies, hasLength(4));
    expect(controller.failure?.code, 'unavailable');
    expect(controller.pairId, _pair);
    expect(controller.thumbnails.keys.toSet(), {
      'memory-2',
      'memory-3',
      'memory-4',
    });
    expect(controller.loading, isFalse);
  });

  test('late thumbnail cannot restore cache after sign out', () async {
    final reply = Completer<Uint8List>();
    repository.rows = [_memory()];
    repository.onPhoto = (_, _) => reply.future;
    controller.bind(_pair, _month);
    await _flush();
    expect(controller.items, isNotEmpty);
    repository.invalidate();
    reply.complete(Uint8List.fromList([9]));
    await _flush();
    expect(controller.items, isEmpty);
    expect(controller.thumbnails, isEmpty);
  });

  test(
    'full photo response is rejected when its pair changes in flight',
    () async {
      controller.bind(_pair, _month);
      await _flush();
      final reply = Completer<Uint8List>();
      repository.onPhoto = (_, _) => reply.future;
      final result = controller.photo(_memory());
      final assertion = expectLater(
        result,
        throwsA(
          isA<MemoryFailure>().having((e) => e.code, 'code', 'pair_changed'),
        ),
      );
      controller.bind(_otherPair, _month);
      reply.complete(Uint8List.fromList([9]));
      await assertion;
    },
  );

  test(
    'retry reuses command for equivalent drafts but not changed image bytes',
    () async {
      controller.bind(_pair, _month);
      await _flush();
      repository.onCreate = (_, _, _) async =>
          throw const MemoryFailure('unavailable');
      expect(await controller.save(_draft()), isFalse);
      expect(await controller.save(_draft()), isFalse);
      expect(repository.creates[0].command, repository.creates[1].command);
      expect(await controller.save(_draft(photoByte: 8)), isFalse);
      expect(
        repository.creates[2].command,
        isNot(repository.creates[1].command),
      );
      expect(
        await controller.save(_draft(photoByte: 8, title: 'Өөр өдөр')),
        isFalse,
      );
      expect(
        repository.creates[3].command,
        isNot(repository.creates[2].command),
      );
    },
  );

  test(
    'ambiguous deletion retry reuses the exact command identifier',
    () async {
      final memory = _memory();
      repository.rows = [memory];
      controller.bind(_pair, _month);
      await _flush();
      repository.onDelete = (_, _) async =>
          throw const MemoryFailure('unavailable');
      expect(await controller.delete(memory), isFalse);
      repository.onDelete = null;
      expect(await controller.delete(memory), isTrue);
      expect(repository.deletes, hasLength(2));
      expect(repository.deletes[0].command, repository.deletes[1].command);
      expect(controller.items, isEmpty);
      expect(controller.thumbnails, isEmpty);
    },
  );

  test('late pre-delete refresh cannot resurrect a deleted memory', () async {
    final memory = _memory();
    repository.rows = [memory];
    controller.bind(_pair, _month);
    await _flush();
    final oldReply = Completer<List<SharedMemory>>();
    var holdNext = true;
    repository.onList = (_, _) async {
      if (holdNext) {
        holdNext = false;
        return oldReply.future;
      }
      return repository.rows;
    };
    final refresh = controller.refresh();
    expect(await controller.delete(memory), isTrue);
    oldReply.complete([memory]);
    await refresh;
    expect(controller.items, isEmpty);
    expect(controller.thumbnails, isEmpty);
  });

  test('late pre-save refresh cannot hide a newly saved memory', () async {
    controller.bind(_pair, _month);
    await _flush();
    final oldReply = Completer<List<SharedMemory>>();
    var holdNext = true;
    repository.onList = (_, _) async {
      if (holdNext) {
        holdNext = false;
        return oldReply.future;
      }
      return repository.rows;
    };
    final memory = _memory();
    repository.onCreate = (_, _, _) async {
      repository.rows = [memory];
      return memory;
    };
    final refresh = controller.refresh();
    expect(await controller.save(_draft()), isTrue);
    oldReply.complete([]);
    await refresh;
    expect(controller.items.single, same(memory));
  });

  test(
    'obsolete refresh access failure cannot clear a newer successful save',
    () async {
      controller.bind(_pair, _month);
      await _flush();
      final oldReply = Completer<List<SharedMemory>>();
      var holdNext = true;
      repository.onList = (_, _) async {
        if (holdNext) {
          holdNext = false;
          return oldReply.future;
        }
        return repository.rows;
      };
      final memory = _memory();
      repository.onCreate = (_, _, _) async {
        repository.rows = [memory];
        return memory;
      };
      final refresh = controller.refresh();
      expect(await controller.save(_draft()), isTrue);
      oldReply.completeError(const MemoryFailure('pair_required'));
      await refresh;
      expect(controller.items.single, same(memory));
      expect(controller.error, isNull);
    },
  );

  for (final operation in ['save', 'delete', 'photo']) {
    test(
      '$operation clears private cache when server revokes pair access',
      () async {
        final memory = _memory();
        repository.rows = [memory];
        controller.bind(_pair, _month);
        await _flush();
        expect(controller.thumbnails, isNotEmpty);
        repository.onCreate = (_, _, _) async =>
            throw const MemoryFailure('pair_required');
        repository.onDelete = (_, _) async =>
            throw const MemoryFailure('forbidden');
        repository.onPhoto = (_, _) async =>
            throw const MemoryFailure('pair_required');
        if (operation == 'photo') {
          await expectLater(
            controller.photo(memory),
            throwsA(
              isA<MemoryFailure>().having(
                (e) => e.code,
                'code',
                'pair_required',
              ),
            ),
          );
        } else {
          final result = operation == 'save'
              ? await controller.save(_draft())
              : await controller.delete(memory);
          expect(result, isFalse);
        }
        expect(controller.items, isEmpty);
        expect(controller.thumbnails, isEmpty);
        expect(controller.pairId, isNull);
        expect(controller.current, isFalse);
        expect(controller.saving, isFalse);
        expect(controller.loading, isFalse);
        expect(controller.error, isNotNull);
      },
    );
  }

  test(
    'late save completion cannot update a new pair or retain old retry command',
    () async {
      controller.bind(_pair, _month);
      await _flush();
      final reply = Completer<SharedMemory>();
      repository.onCreate = (_, _, _) => reply.future;
      final saving = controller.save(_draft());
      controller.bind(_otherPair, _month);
      reply.complete(_memory());
      expect(await saving, isFalse);
      expect(controller.pairId, _otherPair);
      expect(controller.items, isEmpty);
      repository.onCreate = (_, _, _) async =>
          throw const MemoryFailure('unavailable');
      await controller.save(_draft());
      expect(repository.creates.last.pair, _otherPair);
      expect(
        repository.creates.last.command,
        isNot(repository.creates.first.command),
      );
    },
  );

  test('partner memory cannot be deleted through the controller', () async {
    controller.bind(_pair, _month);
    await _flush();
    expect(await controller.delete(_memory(actor: 'b')), isFalse);
    expect(repository.deletes, isEmpty);
  });
}
