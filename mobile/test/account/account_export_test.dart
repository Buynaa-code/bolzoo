import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/account/account_export.dart';
import 'package:hamtdaa/account/account_repository.dart';
import 'package:hamtdaa/content/content_repository.dart';
import 'package:hamtdaa/data/app_controller.dart';

const _user = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
final _day = DateTime(2026, 9, 28);

class _Account implements AccountRepository {
  Map<String, dynamic> data = {'schemaVersion': 1, 'account': {'userId': _user}, 'items': [], 'media': []};
  final requested = <String>[];
  Future<Uint8List> Function(String)? download;
  @override
  String get userId => _user;
  @override
  bool sessionCurrent = true;
  @override
  Future<Map<String, dynamic>> exportData() async => data;
  @override
  Future<Uint8List> downloadMedia(String key) async {
    requested.add(key);
    return download == null ? Uint8List.fromList([7, 8, 9]) : download!(key);
  }
  @override
  Future<void> deleteAccount() async => throw UnimplementedError();
}

class _Content implements ContentRepository {
  _Content(this.items);
  final List<ContentItem> items;
  @override
  String get userId => _user;
  @override
  Future<List<ContentItem>> snapshot() async => items;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedStore extends MemoryAppStore {
  Completer<void>? delay;
  Completer<void>? entered;
  @override
  Future<void> write(AppData data) async {
    entered?.complete();
    await delay?.future;
    await super.write(data);
  }
}

ContentItem _memoryItem(String id, {bool partner = false}) => ContentItem.fromJson({
  'id': id, 'kind': 'memory', 'owner_id': partner ? 'partner' : _user,
  'owner_name': partner ? 'Partner private name' : 'Me', 'pair_id': 'pair',
  'version': 1, 'revision': 1, 'state': 'active', 'role': partner ? 'partner' : 'owner',
  'updated_at': _day.toIso8601String(),
  'payload': {'id': id, 'title': partner ? 'Partner private memory' : 'My memory', 'date': '2026-09-28', 'text': '', 'comments': [{'id': 'comment', 'authorName': 'Partner private name', 'text': 'Partner private comment', 'createdAt': _day.toIso8601String()}]},
});

void main() {
  late Directory temporary;
  setUp(() async => temporary = await Directory.systemTemp.createTemp('hamtdaa-export-test-'));
  tearDown(() => temporary.delete(recursive: true));

  Future<Archive> read(Directory work) async => ZipDecoder().decodeBytes(await File('${work.path}/hamtdaa.zip').readAsBytes());
  Map<String, dynamic> manifest(Archive archive) => jsonDecode(utf8.decode(archive.find('records.json')!.content)) as Map<String, dynamic>;
  Future<List<FileSystemEntity>> remainingWork() async {
    final staging = Directory('${temporary.path}/account_exports');
    return await staging.exists() ? staging.list().toList() : [];
  }

  test('ZIP contains original local photo bytes without filesystem paths', () async {
    final source = await File('${temporary.path}/source.jpg').writeAsBytes([1, 2, 3, 4]);
    final data = AppData(memories: [MemoryEntry(id: 'mine', title: 'My memory', date: _day, photoPath: source.path)]);
    final work = await buildAccountExport(ownData: data, temporaryDirectory: temporary);
    final archive = await read(work);
    final record = manifest(archive);
    final memory = (record['deviceRecords']['memories'] as List).single as Map;
    expect(memory.containsKey('photoPath'), isFalse);
    expect(archive.find(memory['exportPhoto'] as String)!.content, [1, 2, 3, 4]);
    expect(jsonEncode(record), isNot(contains(temporary.path)));
    expect(await source.readAsBytes(), [1, 2, 3, 4]);
    expect(archive.find('README.txt'), isNotNull);
  });

  test('private export excludes visible partner records and social projection', () async {
    final controller = AppController(MemoryAppStore());
    addTearDown(controller.dispose);
    await controller.load();
    controller.connectCloud(_Content([_memoryItem('mine'), _memoryItem('theirs', partner: true)]));
    for (var i = 0; i < 8; i++) { await Future<void>.delayed(Duration.zero); }
    expect(controller.data.memories, hasLength(2));
    expect(controller.data.memories.first.comments, isNotEmpty);
    final own = await controller.exportOwnSnapshot();
    final work = await buildAccountExport(ownData: own, temporaryDirectory: temporary);
    final raw = jsonEncode(manifest(await read(work)));
    expect(raw, contains('My memory'));
    expect(raw, isNot(contains('Partner private')));
    expect(raw, isNot(contains('theirs')));
  });

  test('cloud archive includes owned orphan media once and preserves own comments', () async {
    final repository = _Account();
    const key = '$_user/orphan/photo.png';
    repository.data['media'] = [{'key': key}, {'key': key}];
    repository.data['comments'] = [{'text': 'My own comment'}];
    final work = await buildAccountExport(ownData: AppData(), temporaryDirectory: temporary, repository: repository);
    final archive = await read(work);
    final record = manifest(archive);
    expect(repository.requested, [key]);
    final mapping = (record['photos'] as List).single as Map;
    expect(mapping['mediaKey'], key);
    expect(archive.find(mapping['file'] as String)!.content, [7, 8, 9]);
    expect(record['cloudRecords']['comments'].single['text'], 'My own comment');
  });

  test('missing photo removes partial archive and preserves unrelated exports', () async {
    final sibling = await Directory('${temporary.path}/account_exports/other').create(recursive: true);
    await File('${sibling.path}/keep.zip').writeAsString('keep');
    final data = AppData(memories: [MemoryEntry(id: 'missing', title: 'Missing', date: _day, photoPath: '${temporary.path}/missing.jpg')]);
    await expectLater(buildAccountExport(ownData: data, temporaryDirectory: temporary), throwsA(anything));
    expect((await remainingWork()).map((entry) => entry.path), [sibling.path]);
    expect(await File('${sibling.path}/keep.zip').readAsString(), 'keep');
  });

  test('account switch during media download discards all staged output', () async {
    final repository = _Account();
    repository.data['media'] = [{'key': '$_user/photo.png'}];
    final entered = Completer<void>();
    final download = Completer<Uint8List>();
    repository.download = (_) { entered.complete(); return download.future; };
    final operation = buildAccountExport(ownData: AppData(), temporaryDirectory: temporary, repository: repository);
    await entered.future;
    repository.sessionCurrent = false;
    final assertion = expectLater(operation, throwsA(isA<AccountOperationException>().having((e) => e.code, 'code', 'session_changed')));
    download.complete(Uint8List.fromList([1, 2]));
    await assertion;
    expect(await remainingWork(), isEmpty);
  });

  test('invalid media manifest removes partial archive', () async {
    final repository = _Account();
    repository.data['media'] = [{'key': 123}];
    await expectLater(buildAccountExport(ownData: AppData(), temporaryDirectory: temporary, repository: repository), throwsA(isA<AccountOperationException>()));
    expect(repository.requested, isEmpty);
    expect(await remainingWork(), isEmpty);
  });

  test('deletion freeze drains an active write and rejects later writes and export', () async {
    final store = _DelayedStore();
    final controller = AppController(store);
    addTearDown(controller.dispose);
    await controller.load();
    store.delay = Completer<void>();
    store.entered = Completer<void>();
    final write = controller.updateProfile(const UserProfile(name: 'Saving'));
    await store.entered!.future;
    var frozen = false;
    final freezing = controller.freezeForAccountDeletion().then((_) => frozen = true);
    await Future<void>.delayed(Duration.zero);
    expect(frozen, isFalse);
    store.delay!.complete();
    await write;
    await freezing;
    expect(controller.data.profile.name, isEmpty);
    await expectLater(controller.updateProfile(const UserProfile(name: 'Late')), throwsStateError);
    await expectLater(controller.exportOwnSnapshot(), throwsStateError);
  });
}
