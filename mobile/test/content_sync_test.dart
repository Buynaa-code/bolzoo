import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/content/content_repository.dart';
import 'package:hamtdaa/content/supabase_content_repository.dart';
import 'package:hamtdaa/data/app_controller.dart';

final _date = DateTime(2026, 9, 28, 18);
DateEvent _event(String id, {String title = 'Date', bool shared = false}) =>
    DateEvent(id: id, title: title, startsAt: _date, createdAt: _date, shared: shared);
MemoryEntry _memory(String id, {String? mediaKey, String? photoPath}) =>
    MemoryEntry(id: id, title: 'Memory', date: _date, mediaKey: mediaKey, photoPath: photoPath);

Map<String, dynamic> _json({required String id, String kind = 'event',
    bool partner = false, bool shared = false, bool deleted = false,
    int version = 1, Map<String, Object?>? payload}) => {
  'id': id, 'kind': kind, 'owner_id': partner ? 'partner' : 'owner',
  'owner_name': partner ? 'Partner' : 'Me', 'pair_id': shared || partner ? 'pair' : null,
  'role': partner ? 'partner' : 'owner', 'state': deleted ? 'deleted' : 'active',
  'version': version, 'revision': version,
  'updated_at': _date.toUtc().toIso8601String(),
  'payload': deleted ? <String, Object?>{} : payload ?? _event(id).toJson(),
};
ContentItem _item({required String id, String kind = 'event',
    bool partner = false, bool shared = false, bool deleted = false,
    int version = 1, Map<String, Object?>? payload}) => ContentItem.fromJson(
  _json(id: id, kind: kind, partner: partner, shared: shared, deleted: deleted,
      version: version, payload: payload));
Future<void> _settle() async {
  for (var i = 0; i < 8; i++) { await Future<void>.delayed(Duration.zero); }
}
Future<AppController> _connect(_Repository repository, [_Store? store]) async {
  final controller = AppController(store ?? _Store());
  addTearDown(controller.dispose);
  await controller.load();
  controller.connectCloud(repository);
  await _settle();
  return controller;
}
Matcher _code(String value) => isA<ContentException>().having((e) => e.code, 'code', value);

void main() {
  test('partner records and social data are visible only in the current lease', () async {
    final social = {..._memory('own').toJson(), 'likeCount': 2, 'likedByMe': true,
      'comments': [{'id': 'comment', 'authorName': 'Partner', 'text': 'Private comment',
        'createdAt': _date.toIso8601String()}]};
    final repository = _Repository([
      _item(id: 'own', kind: 'memory', shared: true, payload: social),
      _item(id: 'partner', kind: 'memory', partner: true, payload: _memory('partner').toJson()),
    ]);
    final store = _Store();
    final controller = await _connect(repository, store);
    expect(controller.data.memories, hasLength(2));
    expect(controller.data.memories.first.comments.single.text, 'Private comment');
    final disk = await store.read();
    expect(disk.memories.map((m) => m.id), ['own']);
    expect(disk.memories.single.comments, isEmpty);
    expect(disk.memories.single.likeCount, 0);
    controller.setCloudForeground(false);
    expect(controller.data.memories.map((m) => m.id), ['own']);
    expect(controller.data.memories.single.comments, isEmpty);
    expect(controller.data.notices, isEmpty);
  });

  test('local write failure keeps visible state and reuses accepted save', () async {
    final repository = _Repository();
    final store = _Store();
    final controller = await _connect(repository, store);
    final previous = controller.data;
    var notifications = 0;
    controller.addListener(() => notifications++);
    store.failNext = true;
    await expectLater(controller.saveEvent(_event('new', shared: true)),
      throwsA(isA<FileSystemException>()));
    expect(identical(previous, controller.data), isTrue);
    expect(notifications, 0);
    expect((await store.read()).events, isEmpty);
    await controller.saveEvent(_event('new', shared: true));
    expect(controller.data.events.single.id, 'new');
    expect(repository.saves, hasLength(1));
    expect(repository.saves.single.shared, isTrue);
  });

  test('uncertain save replays original command and version after refresh', () async {
    final repository = _Repository([_item(id: 'date')]);
    final controller = await _connect(repository);
    var first = true;
    repository.saveHook = (call) async {
      final result = repository.applySave(call);
      if (first) { first = false; throw const ContentException('network'); }
      return result;
    };
    await expectLater(controller.saveEvent(_event('date', title: 'Changed')),
      throwsA(_code('network')));
    await controller.refreshCloud();
    // A slightly different local field still requires the pending original save
    // when a photo stage is outstanding; event replay uses the identical intent.
    repository.records['date'] = _item(id: 'date');
    await controller.refreshCloud();
    await controller.saveEvent(_event('date', title: 'Changed'));
    expect(repository.saves, hasLength(2));
    expect(repository.saves[1].command, repository.saves[0].command);
    expect(repository.saves[1].expectedVersion, repository.saves[0].expectedVersion);
    expect(repository.records['date']!.version, 1); // the fake receipt did not reapply
    expect(controller.data.events.single.title, 'Changed');
  });

  test('photo retry reuses metadata, uploaded bytes, and original attach receipt', () async {
    final directory = await Directory.systemTemp.createTemp('content-photo-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/photo.jpg');
    await file.writeAsBytes([0xff, 0xd8, 0xff, 0xe0, 1, 2]);
    final repository = _Repository();
    final controller = await _connect(repository);
    var failAttachment = true;
    repository.saveHook = (call) async {
      final result = repository.applySave(call);
      if (call.payload['mediaKey'] != null && failAttachment) {
        failAttachment = false;
        throw const ContentException('network');
      }
      return result;
    };
    final memory = _memory('photo', photoPath: file.path);
    await expectLater(controller.saveMemory(memory), throwsA(_code('network')));
    await controller.refreshCloud();
    await controller.saveMemory(memory);
    expect(repository.uploads, 1);
    expect(repository.saves, hasLength(3));
    expect(repository.saves[1].command, repository.saves[2].command);
    expect(repository.saves[1].expectedVersion, 1);
    expect(repository.saves[2].expectedVersion, 1);
    expect(controller.data.memories.single.mediaKey, 'photo/key');
    expect(controller.data.memories.single.photoPath, file.path);
  });

  test('refresh preserves newer consent when retrying a disk failure', () async {
    final repository = _Repository();
    final store = _Store();
    final controller = await _connect(repository, store);
    store.failNext = true;
    await expectLater(controller.saveEvent(_event('date', shared: true)),
      throwsA(isA<FileSystemException>()));
    repository.records['date'] = _item(id: 'date', shared: true, version: 2,
      payload: {..._event('date', shared: true).toJson(), 'status': 'accepted'});
    await controller.refreshCloud();
    await controller.saveEvent(_event('date', shared: true));
    expect(controller.consentState('date'), 'accepted');
    expect(repository.saves, hasLength(1));
  });

  test('late snapshot is discarded after background and fresh lease recovers', () async {
    final repository = _Repository();
    final controller = await _connect(repository);
    final deferred = Completer<List<ContentItem>>();
    repository.snapshotHook = () => deferred.future;
    final refresh = controller.refreshCloud();
    await _settle();
    controller.setCloudForeground(false);
    deferred.complete([_item(id: 'late', partner: true)]);
    await refresh;
    expect(controller.data.events, isEmpty);
    repository.snapshotHook = null;
    repository.records['fresh'] = _item(id: 'fresh', partner: true);
    controller.setCloudForeground(true);
    await _settle();
    expect(controller.data.events.single.id, 'fresh');
  });

  test('late writes never restore a revoked projection', () async {
    final repository = _Repository();
    final controller = await _connect(repository);
    final deferred = Completer<ContentItem>();
    repository.saveHook = (_) => deferred.future;
    final saving = controller.saveEvent(_event('late'));
    final failure = expectLater(saving, throwsA(_code('stale_response')));
    await _settle();
    controller.setCloudForeground(false);
    deferred.complete(_item(id: 'late'));
    await failure;
    expect(controller.data.events, isEmpty);
  });

  test('late gift gateway receipt fails explicitly after epoch changes', () async {
    final controller = await _connect(_Repository());
    final epoch = controller.cloudEpoch;
    controller.setCloudForeground(false);
    await expectLater(controller.acceptContentItem(_item(id: 'late', partner: true), epoch: epoch),
      throwsA(_code('stale_response')));
    expect(controller.data.events, isEmpty);
  });

  test('tombstones remove own cross-device records and detach both links', () async {
    final place = PlaceEntry(id: 'place', name: 'Place', createdAt: _date);
    final memory = _memory('memory').copyWith(eventId: 'date', placeId: 'place');
    final repository = _Repository([
      _item(id: 'date'), _item(id: 'place', kind: 'place', payload: place.toJson()),
      _item(id: 'memory', kind: 'memory', payload: memory.toJson()),
    ]);
    final store = _Store();
    final controller = await _connect(repository, store);
    repository.records['date'] = _item(id: 'date', deleted: true, version: 2);
    repository.records['place'] = _item(id: 'place', kind: 'place', deleted: true, version: 2);
    await controller.refreshCloud();
    expect(controller.data.events, isEmpty);
    expect(controller.data.places, isEmpty);
    expect(controller.data.memories.single.eventId, isNull);
    expect(controller.data.memories.single.placeId, isNull);
    final restored = await store.read();
    expect(restored.events, isEmpty);
    expect(restored.memories.single.eventId, isNull);
    expect(restored.memories.single.placeId, isNull);
  });

  test('shared places preserve sharing through cloud save and projection', () async {
    final repository = _Repository();
    final controller = await _connect(repository);
    await controller.savePlace(PlaceEntry(id: 'place', name: 'Park', createdAt: _date, shared: true));
    expect(repository.saves.single.kind, 'place');
    expect(repository.saves.single.shared, isTrue);
    expect(controller.data.places.single.shared, isTrue);
  });

  test('media queue is bounded and late photo bytes cannot survive unlink', () async {
    final repository = _Repository(List.generate(4, (i) => _item(id: 'photo$i', kind: 'memory',
      partner: true, payload: _memory('photo$i', mediaKey: 'key$i').toJson())));
    repository.delayMedia = true;
    final controller = await _connect(repository);
    expect(repository.downloads, hasLength(2));
    repository.downloads['key0']!.complete(Uint8List.fromList([1]));
    await _settle();
    expect(repository.downloads, hasLength(3));
    expect(controller.mediaBytes('key0'), [1]);
    repository.records.clear();
    controller.invalidateSharedContent();
    expect(controller.mediaBytes('key0'), isNull);
    expect(controller.data.memories, isEmpty);
    for (final pending in repository.downloads.values.where((c) => !c.isCompleted)) {
      pending.complete(Uint8List.fromList([9]));
    }
    await _settle();
    expect(controller.mediaBytes('key1'), isNull);
    expect(controller.mediaBytes('key2'), isNull);
    expect(repository.downloads, hasLength(3));
  });

  test('controller rejects a different account repository', () async {
    final controller = await _connect(_Repository());
    final other = _Repository()..account = 'other';
    expect(() => controller.connectCloud(other), throwsStateError);
    expect(controller.currentUserId, 'owner');
  });

  test('delete retry after durable failure reuses the successful tombstone', () async {
    final repository = _Repository([_item(id: 'date')]);
    final store = _Store();
    final controller = await _connect(repository, store);
    store.failNext = true;
    await expectLater(controller.deleteEvent('date'), throwsA(isA<FileSystemException>()));
    expect(controller.data.events.single.id, 'date');
    await controller.deleteEvent('date');
    expect(controller.data.events, isEmpty);
    expect(repository.deletes, 1);
  });

  test('adapter permanently rejects a session changed while request is in flight', () async {
    var current = true;
    var calls = 0;
    final response = Completer<dynamic>();
    final repository = SupabaseContentRepository.withTransport(accountId: 'owner',
      sessionCurrent: () => current, rpc: (_, _) { calls++; return response.future; });
    final request = repository.snapshot();
    final failure = expectLater(request, throwsA(_code('unauthenticated')));
    current = false;
    response.complete({'ok': true, 'items': [_json(id: 'date')]});
    await failure;
    current = true;
    await expectLater(repository.snapshot(), throwsA(_code('unauthenticated')));
    expect(calls, 1);
  });

  test('adapter rejects incorrect account/role projections before exposing data', () async {
    for (final malformed in [
      {..._json(id: 'date'), 'owner_id': 'other'},
      {..._json(id: 'date'), 'role': 'partner'},
      {..._json(id: 'date', partner: true), 'pair_id': null},
      {..._json(id: 'date'), 'role': 'unknown'},
    ]) {
      final repository = SupabaseContentRepository.withTransport(accountId: 'owner',
        sessionCurrent: () => true, rpc: (_, _) async => {'ok': true, 'items': [malformed]});
      await expectLater(repository.snapshot(), throwsA(_code('unauthenticated')));
    }
  });

  test('adapter masks transport and malformed record details but allows retry', () async {
    var calls = 0;
    final repository = SupabaseContentRepository.withTransport(accountId: 'owner',
      sessionCurrent: () => true, rpc: (_, _) async {
        calls++;
        if (calls == 1) throw StateError('sensitive transport detail');
        if (calls == 2) return {'ok': true, 'items': [{'id': 1}]};
        return {'ok': true, 'items': [_json(id: 'date')]};
      });
    await expectLater(repository.snapshot(), throwsA(_code('network')));
    await expectLater(repository.snapshot(), throwsA(_code('network')));
    expect((await repository.snapshot()).single.id, 'date');
  });
}

class _Store extends MemoryAppStore {
  bool failNext = false;
  @override
  Future<void> write(AppData data) async {
    if (failNext) { failNext = false; throw const FileSystemException('Disk full'); }
    await super.write(data);
  }
}
class _Save {
  _Save(this.command, this.id, this.kind, this.payload, this.shared, this.expectedVersion);
  final String command, id, kind;
  final Map<String, Object?> payload;
  final bool shared;
  final int? expectedVersion;
}
class _Repository implements ContentRepository {
  _Repository([List<ContentItem> initial = const []]) {
    records.addEntries(initial.map((i) => MapEntry(i.id, i)));
  }
  String account = 'owner';
  @override
  String get userId => account;
  final records = <String, ContentItem>{};
  final receipts = <String, ContentItem>{};
  final saves = <_Save>[];
  int uploads = 0, deletes = 0;
  bool delayMedia = false;
  final downloads = <String, Completer<Uint8List>>{};
  Future<List<ContentItem>> Function()? snapshotHook;
  Future<ContentItem> Function(_Save)? saveHook;
  @override
  Future<List<ContentItem>> snapshot() async => snapshotHook == null ? records.values.toList() : snapshotHook!();
  ContentItem applySave(_Save call) {
    if (receipts.containsKey(call.command)) return receipts[call.command]!;
    final result = _item(id: call.id, kind: call.kind, shared: call.shared,
      version: (records[call.id]?.version ?? 0) + 1, payload: call.payload);
    records[call.id] = result;
    receipts[call.command] = result;
    return result;
  }
  @override
  Future<ContentItem> save({required String commandId, required String id, required String kind,
      required Map<String, Object?> payload, required bool shared, int? expectedVersion}) async {
    final call = _Save(commandId, id, kind, Map.of(payload), shared, expectedVersion);
    saves.add(call);
    return saveHook == null ? applySave(call) : saveHook!(call);
  }
  @override
  Future<ContentItem> delete({required String commandId, required String id, required int expectedVersion}) async {
    deletes++;
    return records[id] = _item(id: id, deleted: true, version: expectedVersion + 1);
  }
  @override
  Future<String> uploadPhoto(String itemId, Uint8List bytes, String extension) async { uploads++; return '$itemId/key'; }
  @override
  Future<Uint8List> downloadPhoto(String key) async {
    if (!delayMedia) return Uint8List.fromList([1, 2, 3]);
    return (downloads[key] = Completer<Uint8List>()).future;
  }
  @override
  Future<ContentItem> comment({required String commandId, required String id, required String text}) async => throw UnimplementedError();
  @override
  Future<ContentItem> react({required String commandId, required String id, required bool liked}) async => throw UnimplementedError();
  @override
  Future<ContentItem> respond({required String commandId, required String id, required int expectedVersion,
      required String action, DateTime? proposedAt}) async => throw UnimplementedError();
}
