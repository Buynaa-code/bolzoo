import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/data/app_controller.dart';

DateEvent event(String id, {String title = 'Болзоо'}) => DateEvent(
  id: id,
  title: title,
  startsAt: DateTime(2026, 9, 26, 18, 30),
  createdAt: DateTime(2026, 9, 24, 10, 15, 8, 123, 456),
  place: 'Кофе шоп',
);

void main() {
  group('FileAppStore', () {
    late Directory directory;
    late File file;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('hamtdaa_data_test_');
      file = File('${directory.path}/nested/app.json');
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('new installation is empty; durable data survives a fresh controller', () async {
      final first = AppController(FileAppStore(file));
      await first.load();
      expect(first.loaded, isTrue);
      expect(first.data.events, isEmpty);
      expect(first.data.memories, isEmpty);
      expect(first.data.profile.name, '');

      await first.updateProfile(
        UserProfile(name: '  Ану  ', togetherSince: DateTime(2020, 2, 29, 23)),
      );
      await first.saveEvent(event('date-1', title: '  Кофе уух  '));
      await first.saveMemory(
        MemoryEntry(
          id: 'memory-1',
          title: '  Сайхан өдөр  ',
          date: DateTime(2026, 9, 26, 23, 50),
          text: '  Дахиад ирнэ.  ',
          photoPath: '/private/photos/our-day.jpg',
          eventId: 'date-1',
        ),
      );
      first.dispose();

      final second = AppController(FileAppStore(File(file.path)));
      addTearDown(second.dispose);
      await second.load();
      expect(second.data.profile.name, 'Ану');
      expect(second.data.profile.togetherSince, DateTime(2020, 2, 29));
      expect(second.data.events.single.title, 'Кофе уух');
      expect(second.data.events.single.startsAt, DateTime(2026, 9, 26, 18, 30));
      expect(second.data.events.single.createdAt, event('date-1').createdAt);
      expect(second.data.memories.single.title, 'Сайхан өдөр');
      expect(second.data.memories.single.date, DateTime(2026, 9, 26));
      expect(second.data.memories.single.text, 'Дахиад ирнэ.');
      expect(second.data.memories.single.photoPath, '/private/photos/our-day.jpg');
      expect(second.data.memories.single.eventId, 'date-1');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(json['schemaVersion'], 2);
      expect(await file.parent.list().where((entry) => entry.path.endsWith('.tmp')).isEmpty, isTrue);
    });

    test('malformed data remains untouched and cannot be overwritten after a failed load', () async {
      await file.parent.create(recursive: true);
      const original = '{ broken private data';
      await file.writeAsString(original);
      final controller = AppController(FileAppStore(file));
      addTearDown(controller.dispose);

      await expectLater(controller.load(), throwsFormatException);
      expect(controller.loaded, isFalse);
      await expectLater(controller.saveEvent(event('date-1')), throwsStateError);
      expect(await file.readAsString(), original);

      // A repaired file can be explicitly reloaded; a failed load is not sticky.
      await file.writeAsString(jsonEncode(AppData().toJson()));
      await controller.load();
      await controller.saveEvent(event('date-1'));
      expect(controller.data.events.single.id, 'date-1');
    });

    test('unsupported schema stays intact', () async {
      await file.parent.create(recursive: true);
      final unsupported = jsonEncode({...AppData().toJson(), 'schemaVersion': 99});
      await file.writeAsString(unsupported);
      await expectLater(FileAppStore(file).read(), throwsFormatException);
      expect(await file.readAsString(), unsupported);
    });

    test('failed replacement preserves target and cleans temporary file', () async {
      await Directory(file.path).create(recursive: true);
      final marker = File('${file.path}/keep.txt');
      await marker.writeAsString('preserved');
      await expectLater(
        FileAppStore(file).write(AppData(events: [event('date-1')])),
        throwsA(isA<FileSystemException>()),
      );
      expect(await marker.readAsString(), 'preserved');
      expect(await file.parent.list().where((entry) => entry.path.endsWith('.tmp')).isEmpty, isTrue);
    });

    test('deleting an event detaches and persists memories without deleting them', () async {
      final controller = AppController(FileAppStore(file));
      addTearDown(controller.dispose);
      await controller.load();
      await controller.saveEvent(event('date-1'));
      await controller.saveMemory(
        MemoryEntry(
          id: 'memory-1',
          title: 'Дурсамж',
          date: DateTime(2026, 9, 26),
          eventId: 'date-1',
          photoPath: '/photos/one.jpg',
        ),
      );
      await controller.deleteEvent('date-1');

      final reloaded = await FileAppStore(file).read();
      expect(reloaded.events, isEmpty);
      expect(reloaded.memories.single.id, 'memory-1');
      expect(reloaded.memories.single.eventId, isNull);
      expect(reloaded.memories.single.photoPath, '/photos/one.jpg');
    });
  });

  group('AppController', () {
    test('state stays unchanged until the durable write completes', () async {
      final store = _GatedStore();
      final controller = AppController(store);
      addTearDown(controller.dispose);
      await controller.load();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final saving = controller.saveEvent(event('date-1'));
      await store.started.future;
      expect(controller.data.events, isEmpty);
      expect(notifications, 0);
      store.finish.complete();
      await saving;
      expect(controller.data.events.single.id, 'date-1');
      expect(notifications, 1);
    });

    test('a memory cannot reference an absent event', () async {
      final controller = AppController(MemoryAppStore());
      addTearDown(controller.dispose);
      await controller.load();
      await expectLater(
        controller.saveMemory(
          MemoryEntry(
            id: 'memory-1',
            title: 'Дурсамж',
            date: DateTime(2026),
            eventId: 'missing-event',
          ),
        ),
        throwsArgumentError,
      );
      expect(controller.data.memories, isEmpty);
    });

    test('concurrent operations serialize and never lose each other’s changes', () async {
      final store = _ControlledStore(delay: const Duration(milliseconds: 5));
      final controller = AppController(store);
      addTearDown(controller.dispose);
      await controller.load();
      await Future.wait([
        controller.saveEvent(event('date-1')),
        controller.saveEvent(event('date-2')),
        controller.saveMemory(
          MemoryEntry(
            id: 'memory-1',
            title: 'Дурсамж',
            date: DateTime(2026, 9, 26),
            eventId: 'date-2',
          ),
        ),
        controller.updateProfile(const UserProfile(name: 'Ану')),
      ]);
      expect(store.maximumConcurrentWrites, 1);
      expect(controller.data.events.map((item) => item.id), ['date-1', 'date-2']);
      expect(controller.data.memories.single.eventId, 'date-2');
      expect(controller.data.profile.name, 'Ану');
      expect((await store.read()).toJson(), controller.data.toJson());
    });

    test('write failure retains old snapshot, sends no notification, and permits retry', () async {
      final store = _ControlledStore();
      final controller = AppController(store);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.saveEvent(event('date-1'));
      final previous = controller.data;
      var notifications = 0;
      controller.addListener(() => notifications++);
      store.failNextWrite = true;

      await expectLater(
        controller.saveEvent(event('date-2')),
        throwsA(isA<FileSystemException>()),
      );
      expect(identical(controller.data, previous), isTrue);
      expect(notifications, 0);
      expect((await store.read()).events.length, 1);

      await controller.saveEvent(event('date-2'));
      expect(controller.data.events.length, 2);
      expect(notifications, 1);
    });

    test('saving the same ID replaces one item and preserves other records', () async {
      final controller = AppController(MemoryAppStore());
      addTearDown(controller.dispose);
      await controller.load();
      await controller.saveEvent(event('date-1'));
      await controller.saveEvent(event('date-2'));
      await controller.saveEvent(event('date-1', title: 'Шинэ нэр'));
      expect(controller.data.events.length, 2);
      expect(controller.data.events.first.title, 'Шинэ нэр');
    });

    test('validates nonblank titles and future profile date before writing', () async {
      final store = _ControlledStore();
      final controller = AppController(store);
      addTearDown(controller.dispose);
      await controller.load();
      await expectLater(controller.saveEvent(event('date-1', title: ' \n ')), throwsArgumentError);
      await expectLater(
        controller.saveMemory(MemoryEntry(id: 'memory-1', title: ' ', date: DateTime(2026))),
        throwsArgumentError,
      );
      final now = DateTime.now();
      await expectLater(
        controller.updateProfile(
          UserProfile(togetherSince: DateTime(now.year, now.month, now.day + 1)),
        ),
        throwsArgumentError,
      );
      expect(store.writeCount, 0);
      // Today is valid even if the incoming time is later than now.
      await controller.updateProfile(
        UserProfile(togetherSince: DateTime(now.year, now.month, now.day, 23, 59)),
      );
      expect(controller.data.profile.togetherSince, DateTime(now.year, now.month, now.day));
      await controller.updateProfile(controller.data.profile.copyWith(togetherSince: null));
      expect(controller.data.profile.togetherSince, isNull);
    });

    test('deleting a memory leaves its event available', () async {
      final controller = AppController(MemoryAppStore());
      addTearDown(controller.dispose);
      await controller.load();
      await controller.saveEvent(event('date-1'));
      await controller.saveMemory(
        MemoryEntry(id: 'memory-1', title: 'Дурсамж', date: DateTime(2026), eventId: 'date-1'),
      );
      await controller.deleteMemory('memory-1');
      expect(controller.data.memories, isEmpty);
      expect(controller.data.events.single.id, 'date-1');
    });
  });

  group('Models', () {
    test('nullable copyWith fields can be retained or explicitly cleared', () {
      final memory = MemoryEntry(
        id: 'memory-1',
        title: 'Дурсамж',
        date: DateTime(2026),
        photoPath: '/photos/one.jpg',
        eventId: 'date-1',
      );
      expect(memory.copyWith(title: 'Шинэ нэр').photoPath, '/photos/one.jpg');
      expect(memory.copyWith(photoPath: null).photoPath, isNull);
      expect(memory.copyWith(eventId: null).eventId, isNull);
      expect(memory.copyWith(photoPath: null).eventId, 'date-1');
    });

    test('snapshots copy input lists and disallow list mutation', () {
      final events = [event('date-1')];
      final data = AppData(events: events);
      events.clear();
      expect(data.events.length, 1);
      expect(() => data.events.clear(), throwsUnsupportedError);
      expect(() => AppData(events: [event('date-1'), event('date-1')]), throwsFormatException);
    });

    test('invalid calendar days and impossible local times are rejected', () {
      expect(
        () => MemoryEntry.fromJson({
          'id': 'memory-1', 'title': 'Дурсамж', 'date': '2026-02-30',
        }),
        throwsFormatException,
      );
      expect(
        () => DateEvent.fromJson({...event('date-1').toJson(), 'startsAt': '2026-09-26T25:00:00'}),
        throwsFormatException,
      );
    });

    test('wall-clock date/time components are saved without UTC offsets', () {
      final original = event('date-1').copyWith(startsAt: DateTime.utc(2026, 9, 26, 18, 30));
      final restored = DateEvent.fromJson(original.toJson());
      expect(restored.startsAt.isUtc, isFalse);
      expect(restored.startsAt, DateTime(2026, 9, 26, 18, 30));
      expect(original.toJson()['startsAt'], '2026-09-26T18:30:00.000');
    });
  });
}

class _ControlledStore extends MemoryAppStore {
  _ControlledStore({this.delay = Duration.zero});

  final Duration delay;
  bool failNextWrite = false;
  int _activeWrites = 0;
  int maximumConcurrentWrites = 0;
  int writeCount = 0;

  @override
  Future<void> write(AppData data) async {
    writeCount++;
    _activeWrites++;
    if (_activeWrites > maximumConcurrentWrites) {
      maximumConcurrentWrites = _activeWrites;
    }
    try {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (failNextWrite) {
        failNextWrite = false;
        throw const FileSystemException('Simulated disk write failure.');
      }
      await super.write(data);
    } finally {
      _activeWrites--;
    }
  }
}

class _GatedStore extends MemoryAppStore {
  final started = Completer<void>();
  final finish = Completer<void>();

  @override
  Future<void> write(AppData data) async {
    started.complete();
    await finish.future;
    await super.write(data);
  }
}
