import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/memories/memory_controller.dart';
import 'package:hamtdaa/memories/memory_models.dart';
import 'package:hamtdaa/memories/memory_sticker.dart';
import 'package:hamtdaa/together/together_controller.dart';
import 'package:hamtdaa/together/together_screen.dart';
import 'package:hamtdaa/ui/theme.dart';
import 'package:hamtdaa/wishes/wish_controller.dart';
import '../memories/calendar_memories_flow_test.dart' show CalendarMemoriesFake;
import 'together_fakes.dart';
import '../wishes/wish_fakes.dart';

class _RevokedAlbumPhotos extends CalendarMemoriesFake {
  @override
  Future<Uint8List> photo(SharedMemory memory, {bool thumbnail = false}) async {
    if (memory.id == 'two') throw const MemoryFailure('forbidden');
    return bytes;
  }
}

void main() {
  late TogetherFakeRepository dates;
  late TogetherController calendar;
  late CalendarMemoriesFake photos;
  late MemoryController memories;
  late CloudflareAuthRepository auth;
  late GlobalKey<TogetherScreenState> key;
  var homeCalls = 0, pairCalls = 0;
  setUp(() {
    dates = TogetherFakeRepository()..value = stateJson(events: [eventJson()]);
    calendar = TogetherController(repository: dates, now: () => today);
    photos = CalendarMemoriesFake();
    memories = MemoryController(photos);
    key = GlobalKey<TogetherScreenState>();
    homeCalls = pairCalls = 0;
    auth = CloudflareAuthRepository(
      transport: TogetherTransport(),
      storage: TogetherStorage(),
    );
  });
  tearDown(() async {
    calendar.dispose();
    memories.dispose();
    await auth.dispose();
  });
  Future<void> mount(
    WidgetTester tester,
    TogetherSection section, {
    String? memoryId,
    String? eventId,
    WishController? wishes,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: TogetherScreen(
          key: key,
          auth: auth,
          controller: calendar,
          memories: memories,
          wishes: wishes,
          embedded: true,
          initialSection: section,
          initialMemoryId: memoryId,
          initialEventId: eventId,
          onHome: () => homeCalls++,
          onPair: () => pairCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String name) async {
    final finder = find.byKey(Key(name));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  void addPhoto(String id) => photos.rows.add(
    SharedMemory(
      id: id,
      pairId: pairId,
      creatorId: 'a',
      day: '2026-10-06',
      title: 'Хамтын зураг $id',
      note: 'Нандин мөч',
      sticker: 'polaroid',
      version: 1,
      createdAt: today,
    ),
  );

  testWidgets(
    'embedded calendar has no inner tabs or root back and system back opens home',
    (tester) async {
      await mount(tester, TogetherSection.calendar);
      expect(find.text('Бидний хуанли'), findsOneWidget);
      expect(find.byType(SegmentedButton<int>), findsNothing);
      expect(find.byTooltip('Буцах'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(homeCalls, 1);
      expect(dates.commands, isEmpty);
    },
  );

  testWidgets(
    'album uses real pair month rows including multiple memories on a day',
    (tester) async {
      addPhoto('one');
      addPhoto('two');
      await mount(tester, TogetherSection.memories);
      expect(find.text('Хамтын зураг one'), findsOneWidget);
      expect(find.text('Хамтын зураг two'), findsOneWidget);
      expect(find.byType(MemorySticker), findsNWidgets(2));
      expect(
        tester
            .widgetList<MemorySticker>(find.byType(MemorySticker))
            .every((sticker) => sticker.bytes != null),
        isTrue,
      );
      await tap(tester, 'albumMemorytwo');
      expect(find.text('Нандин мөч'), findsOneWidget);
      expect(await key.currentState!.requestLeave(), isTrue);
      await tester.pumpAndSettle();
      await tap(tester, 'albumNextMonth');
      expect(memories.month, '2026-11');
      expect(find.text('Хамтын зураг one'), findsNothing);
      expect(find.text('Энэ сарын анхны дурсамжаа нэмье'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shell leave preserves a calendar draft until discard is confirmed',
    (tester) async {
      await mount(tester, TogetherSection.calendar);
      await tester.scrollUntilVisible(
        find.byKey(const Key('togetherCreate')),
        350,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('togetherCalendar')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tap(tester, 'togetherCreate');
      await tester.enterText(
        find.byKey(const Key('togetherTitle')),
        'Хадгалаагүй болзоо',
      );
      final first = key.currentState!.requestLeave();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Үргэлжлүүлэх'));
      await tester.pumpAndSettle();
      expect(await first, isFalse);
      expect(find.text('Хадгалаагүй болзоо'), findsOneWidget);
      final second = key.currentState!.requestLeave();
      await tester.pumpAndSettle();
      await tap(tester, 'togetherDiscard');
      expect(await second, isTrue);
      await mount(tester, TogetherSection.memories);
      expect(find.byKey(const Key('togetherMemoryAlbum')), findsOneWidget);
      expect(dates.commands, isEmpty);
    },
  );

  testWidgets('shell leave reuses memory draft confirmation', (tester) async {
    await mount(tester, TogetherSection.memories);
    await tap(tester, 'albumAddMemory');
    await tester.tap(find.text('Сонгох'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('memoryTitle')),
      'Хадгалаагүй зураг',
    );
    final first = key.currentState!.requestLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Үргэлжлүүлэх'));
    await tester.pumpAndSettle();
    expect(await first, isFalse);
    expect(find.text('Хадгалаагүй зураг'), findsOneWidget);
    final second = key.currentState!.requestLeave();
    await tester.pumpAndSettle();
    await tap(tester, 'memoryDiscard');
    expect(await second, isTrue);
    expect(photos.saves, 0);
  });

  testWidgets('album adds memory on the chosen day after browsing month', (
    tester,
  ) async {
    await mount(tester, TogetherSection.memories);
    await tap(tester, 'albumNextMonth');
    expect(calendar.selectedDay, DateTime.utc(2026, 11, 1));
    await tap(tester, 'albumAddMemory');
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.firstDate, DateTime(2026, 11, 1));
    expect(picker.lastDate, DateTime(2026, 11, 30));
    expect(picker.initialDate, DateTime(2026, 11, 1));
    expect(await key.currentState!.requestLeave(), isFalse);
    await tester.tap(find.text('19'));
    await tester.tap(find.text('Сонгох'));
    await tester.pumpAndSettle();
    expect(calendar.selectedDay, DateTime.utc(2026, 11, 19));
    expect(find.byKey(const Key('memoryEditor')), findsOneWidget);
    expect(find.text('2026-11-19'), findsOneWidget);
    expect(photos.saves, 0);
  });

  testWidgets('canceling album date picker retains month and opens no editor', (
    tester,
  ) async {
    await mount(tester, TogetherSection.memories);
    await tap(tester, 'albumNextMonth');
    await tap(tester, 'albumAddMemory');
    await tester.tap(find.text('19'));
    await tester.tap(find.text('Болих'));
    await tester.pumpAndSettle();
    expect(calendar.selectedDay, DateTime.utc(2026, 11, 1));
    expect(find.byKey(const Key('memoryEditor')), findsNothing);
    expect(find.byKey(const Key('togetherMemoryAlbum')), findsOneWidget);
    expect(photos.saves, 0);
  });

  for (final invalidation in ['month', 'pair']) {
    testWidgets('album date selection is ignored after $invalidation changes', (
      tester,
    ) async {
      await mount(tester, TogetherSection.memories);
      await tap(tester, 'albumAddMemory');
      await tester.tap(find.text('19'));
      if (invalidation == 'month') {
        await calendar.browseMonth(1);
      } else {
        dates.value = stateJson(paired: false);
        await calendar.refresh();
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сонгох'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('memoryEditor')), findsNothing);
      expect(photos.saves, 0);
    });
  }

  testWidgets(
    'unpaired embedded tab offers pair invitation rather than private rows',
    (tester) async {
      addPhoto('one');
      dates.value = stateJson(paired: false);
      await mount(tester, TogetherSection.memories);
      await tap(tester, 'togetherConnectPair');
      expect(pairCalls, 1);
      expect(find.byType(MemorySticker), findsNothing);
    },
  );

  testWidgets('shell leave reuses wish draft confirmation', (tester) async {
    final wishes = WishController(WishFakeRepository());
    addTearDown(wishes.dispose);
    await mount(tester, TogetherSection.wishes, wishes: wishes);
    await tap(tester, 'wishAdd');
    await tester.enterText(
      find.byKey(const Key('wishTitle')),
      'Хадгалаагүй хүсэл',
    );
    final first = key.currentState!.requestLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Үргэлжлүүлэх'));
    await tester.pumpAndSettle();
    expect(await first, isFalse);
    expect(find.text('Хадгалаагүй хүсэл'), findsOneWidget);
    final second = key.currentState!.requestLeave();
    await tester.pumpAndSettle();
    await tap(tester, 'wishDiscard');
    expect(await second, isTrue);
  });

  testWidgets('revoked album thumbnail access clears private rows', (
    tester,
  ) async {
    memories.dispose();
    photos = _RevokedAlbumPhotos();
    memories = MemoryController(photos);
    addPhoto('one');
    addPhoto('two');
    await mount(tester, TogetherSection.memories);
    expect(memories.current, isFalse);
    expect(memories.items, isEmpty);
    expect(find.text('Хамтын зураг one'), findsNothing);
    expect(find.text('Хамтын зураг two'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dashboard deep link waits for loaded memory and unlink erases it',
    (tester) async {
      addPhoto('one');
      await mount(tester, TogetherSection.memories, memoryId: 'one');
      expect(find.text('Нандин мөч'), findsOneWidget);
      dates.value = stateJson(paired: false);
      await calendar.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Нандин мөч'), findsNothing);
      expect(find.text('Хосоороо холбогдоорой'), findsOneWidget);
      expect(memories.items, isEmpty);
    },
  );

  testWidgets('missing dashboard event uses nonmutating missing state', (
    tester,
  ) async {
    await mount(tester, TogetherSection.calendar, eventId: 'deleted');
    expect(find.text('Болзоо өөрчлөгдсөн байна'), findsOneWidget);
    expect(dates.commands, isEmpty);
  });
}
