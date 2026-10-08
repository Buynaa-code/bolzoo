import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/memories/memory_controller.dart';
import 'package:hamtdaa/memories/memory_models.dart';
import 'package:hamtdaa/memories/memory_repository.dart';
import 'package:hamtdaa/memories/memory_sticker.dart';
import 'package:hamtdaa/together/together_controller.dart';
import 'package:hamtdaa/together/together_screen.dart';
import 'package:hamtdaa/ui/theme.dart';
import '../together/together_fakes.dart';

// Generated test landscape; no real user photographs or accounts are used.
Uint8List fixturePhoto() {
  final picture = img.Image(width: 200, height: 220);
  for (var y = 0; y < 220; y++) {
    for (var x = 0; x < 200; x++) {
      final ridge = 90 + 24 * math.sin(x / 24);
      final foreground = 149 + 18 * math.cos(x / 39);
      picture.setPixelRgb(
        x,
        y,
        y > foreground
            ? 82
            : y > ridge
            ? 96
            : 159,
        y > foreground
            ? 115
            : y > ridge
            ? 133
            : 196,
        y > foreground
            ? 58
            : y > ridge
            ? 134
            : 218,
      );
    }
  }
  return img.encodeJpg(picture);
}

class CalendarMemoriesFake implements MemoryRepository {
  final Uint8List bytes = fixturePhoto();
  final changes = StreamController<void>.broadcast(sync: true);
  final rows = <SharedMemory>[];
  bool active = true;
  int saves = 0;
  @override
  bool get isCurrent => active;
  @override
  String get actorId => 'a';
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<List<SharedMemory>> list(String pair, String month) async =>
      rows.where((r) => r.pairId == pair && r.day.startsWith(month)).toList();
  @override
  Future<SharedMemory> create(
    String pair,
    String command,
    MemoryDraft draft,
  ) async {
    final row = SharedMemory(
      id: 'memory-${++saves}',
      pairId: pair,
      creatorId: 'a',
      day: draft.day,
      title: draft.title,
      note: draft.note,
      sticker: draft.sticker,
      version: 1,
      createdAt: DateTime.utc(2026, 10, 8),
    );
    rows.add(row);
    return row;
  }

  @override
  Future<Uint8List> photo(
    SharedMemory memory, {
    bool thumbnail = false,
  }) async => bytes;
  @override
  Future<void> delete(SharedMemory memory, String command) async =>
      rows.removeWhere((r) => r.id == memory.id);
  @override
  Future<void> dispose() async {
    active = false;
    await changes.close();
  }
}

void main() {
  late TogetherFakeRepository dates;
  late TogetherController calendar;
  late CalendarMemoriesFake storage;
  late MemoryController memories;
  late CloudflareAuthRepository auth;
  setUp(() {
    dates = TogetherFakeRepository()
      ..value = stateJson(events: [eventJson(status: 'accepted')]);
    calendar = TogetherController(repository: dates, now: () => today);
    storage = CalendarMemoriesFake();
    memories = MemoryController(storage);
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
  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: RepaintBoundary(
          key: const Key('captureCalendar'),
          child: TogetherScreen(
            auth: auth,
            controller: calendar,
            memories: memories,
            memoryPhotoPicker: () async => storage.bytes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    final finder = find.byKey(const Key('memoryChoosePhoto'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(finder);
      await tester.pump();
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (tester.widget<OutlinedButton>(finder).onPressed == null) {
        if (DateTime.now().isAfter(deadline)) fail('Photo processing timeout');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> waitForStickerImages(WidgetTester tester) async {
    final stickers = find.byType(MemorySticker);
    final expected = stickers.evaluate().length;
    expect(expected, greaterThan(0));
    expect(
      tester.widgetList<MemorySticker>(stickers).every((s) => s.bytes != null),
      isTrue,
      reason:
          'The controller must load every sticker thumbnail before capture.',
    );
    final images = find.descendant(
      of: stickers,
      matching: find.byType(RawImage),
    );
    bool ready() {
      final rendered = tester.widgetList<RawImage>(images).toList();
      return rendered.length == expected &&
          rendered.every((image) => image.image != null);
    }

    // Engine image decoding uses real asynchronous work. pumpAndSettle only
    // drains scheduled frames and can finish while every photo is still loading.
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    await tester.pump();
    expect(images, findsNWidgets(expected));
    expect(
      tester.widgetList<RawImage>(images).every((image) => image.image != null),
      isTrue,
      reason: 'Capture must show decoded photos, not loading placeholders.',
    );
  }

  testWidgets('gallery lifecycle preserves an unsaved photo draft', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'calendarAddMemory');
    await tester.enterText(
      find.byKey(const Key('memoryTitle')),
      'Буцаж ирэхэд хэвээр',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byKey(const Key('memoryEditor')), findsNothing);
    expect(memories.thumbnails, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Буцаж ирэхэд хэвээр'), findsOneWidget);
    await choose(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tap(tester, 'memorySave');
    expect(storage.rows.single.title, 'Буцаж ирэхэд хэвээр');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'date photo flow saves chosen day, opens sticker, toggles photos and deletes',
    (tester) async {
      await mount(tester);
      await tap(tester, 'togetherDay5');
      await tap(tester, 'calendarAddMemory');
      expect(find.text('2026-10-05'), findsOneWidget);
      await choose(tester);
      await tester.enterText(
        find.byKey(const Key('memoryTitle')),
        'Тэрэлжийн нэг өдөр',
      );
      await tester.enterText(
        find.byKey(const Key('memoryNote')),
        'Хамт байсан болохоор гоё.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap(tester, 'memorySave');
      expect(storage.saves, 1);
      expect(storage.rows.single.day, '2026-10-05');
      expect(memories.thumbnails, contains('memory-1'));
      await tap(tester, 'calendarMemorymemory-1');
      expect(find.text('Хамт байсан болохоор гоё.'), findsOneWidget);
      await tester.tap(find.byTooltip('Буцах'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('calendarPhotoToggle'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isFalse);
      await tap(tester, 'calendarMemorymemory-1');
      await tap(tester, 'memoryDelete');
      await tap(tester, 'memoryConfirmDelete');
      expect(storage.rows, isEmpty);
      expect(memories.thumbnails, isEmpty);
      expect(find.byKey(const Key('togetherCalendar')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'app bar back protects unsaved diary; unlink closes it and clears photos',
    (tester) async {
      await mount(tester);
      await tap(tester, 'calendarAddMemory');
      await tester.enterText(
        find.byKey(const Key('memoryTitle')),
        'Хадгалаагүй дурсамж',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Буцах'));
      await tester.pumpAndSettle();
      expect(find.text('Дурсамжаа хадгалахгүй гарах уу?'), findsOneWidget);
      await tester.tap(find.text('Үргэлжлүүлэх'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('memoryEditor')), findsOneWidget);
      dates.value = stateJson(paired: false);
      await calendar.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('memoryEditor')), findsNothing);
      expect(memories.items, isEmpty);
      expect(memories.thumbnails, isEmpty);
      expect(storage.saves, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('calendar photo layout fits narrow and enlarged text displays', (
    tester,
  ) async {
    for (final day in [2, 5, 6, 11, 17, 20, 26]) {
      await storage.create(
        pairId,
        '$day',
        MemoryDraft(
          day: '2026-10-${day.toString().padLeft(2, '0')}',
          title: 'Хамтдаа аялсан өдөр',
          note: 'Нандин мөч',
          sticker: day.isEven ? 'polaroid' : 'rounded',
          image: MemoryPhoto(photo: storage.bytes, thumbnail: storage.bytes),
        ),
      );
    }
    await mount(tester);
    tester.view.physicalSize = const Size(320, 844);
    await tester.pumpAndSettle();
    expect(find.byType(MemorySticker), findsWidgets);
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'capture calendar with explicitly synthetic test photos',
    (tester) async {
      await (FontLoader(
        'Nunito',
      )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final day in [2, 5, 6, 11, 17, 20, 26]) {
        await storage.create(
          pairId,
          '$day',
          MemoryDraft(
            day: '2026-10-${day.toString().padLeft(2, '0')}',
            title: 'Тэрэлжийн нэг өдөр',
            note: 'Хамт байсан болохоор гоё.',
            sticker: day.isEven ? 'polaroid' : 'rounded',
            image: MemoryPhoto(photo: storage.bytes, thumbnail: storage.bytes),
          ),
        );
      }
      await mount(tester);
      expect(memories.thumbnails, hasLength(7));
      await waitForStickerImages(tester);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('captureCalendar')),
      );
      await tester.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 2);
        final bytes = (await picture.toByteData(
          format: ui.ImageByteFormat.png,
        ))!;
        await Directory('verification').create(recursive: true);
        await File(
          'verification/calendar-photo-stickers.png',
        ).writeAsBytes(bytes.buffer.asUint8List());
        picture.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !const bool.fromEnvironment('CAPTURE_MEMORIES_UI'),
  );
}
