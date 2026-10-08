import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/memories/memory_controller.dart';
import 'package:hamtdaa/memories/memory_editor.dart';
import 'package:hamtdaa/memories/memory_models.dart';
import 'package:hamtdaa/memories/memory_repository.dart';
import 'package:hamtdaa/together/together_controller.dart';
import 'package:hamtdaa/together/together_models.dart';
import 'package:hamtdaa/together/together_screen.dart';
import 'package:hamtdaa/ui/theme.dart';
import 'package:hamtdaa/wishes/wish_controller.dart';
import 'package:hamtdaa/wishes/wish_models.dart';

import '../together/together_fakes.dart';
import 'wish_fakes.dart';

class _Memories implements MemoryRepository {
  final changes = StreamController<void>.broadcast(sync: true);
  final months = <String>[];
  bool disposed = false;
  @override
  String get actorId => 'a';
  @override
  bool get isCurrent => !disposed;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<List<SharedMemory>> list(String pairId, String month) async {
    months.add(month);
    return [];
  }

  @override
  Future<SharedMemory> create(
    String pairId,
    String commandId,
    MemoryDraft draft,
  ) => throw UnimplementedError('This flow only opens the memory editor.');
  @override
  Future<void> delete(SharedMemory memory, String commandId) async {}
  @override
  Future<Uint8List> photo(
    SharedMemory memory, {
    bool thumbnail = false,
  }) async => Uint8List(0);
  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await changes.close();
  }
}

SharedWish _linkedWish({required String status, required DateTime startsAt}) =>
    SharedWish(
      id: wishId,
      pairId: wishPair,
      creatorId: 'a',
      title: 'Хамтдаа кофе',
      note: 'Амралтын өдөр',
      location: 'Улаанбаатар',
      category: 'food',
      budget: 'low',
      status: status,
      version: 2,
      myLiked: true,
      partnerLiked: true,
      createdAt: DateTime.utc(2020),
      updatedAt: DateTime.utc(2020, 1, 2),
      eventId: 'event-1',
      eventStartsAt: startsAt,
      eventStatus: status == 'done' ? 'accepted' : 'pending',
    );

void main() {
  late TogetherFakeRepository calendarRepository;
  late TogetherController calendar;
  late WishFakeRepository wishRepository;
  late WishController wishes;
  late _Memories memoryRepository;
  late MemoryController memories;
  late CloudflareAuthRepository auth;
  setUp(() {
    calendarRepository = TogetherFakeRepository();
    calendar = TogetherController(
      repository: calendarRepository,
      now: () => DateTime.utc(2020, 1, 1),
    );
    wishRepository = WishFakeRepository();
    wishes = WishController(wishRepository);
    memoryRepository = _Memories();
    memories = MemoryController(memoryRepository);
    auth = CloudflareAuthRepository(
      transport: TogetherTransport(),
      storage: TogetherStorage(),
    );
  });
  tearDown(() async {
    calendar.dispose();
    wishes.dispose();
    memories.dispose();
    await auth.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: TogetherScreen(
          auth: auth,
          controller: calendar,
          memories: memories,
          wishes: wishes,
          memoryPhotoPicker: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openWishes(WidgetTester tester) async {
    expect(find.text('Хуанли'), findsOneWidget);
    expect(find.text('Асуулт'), findsOneWidget);
    expect(find.text('Хүслүүд'), findsOneWidget);
    await tester.tap(find.text('Хүслүүд'));
    await tester.pumpAndSettle();
  }

  for (final screen in [
    (width: 390.0, scale: 1.0),
    (width: 320.0, scale: 1.35),
  ]) {
    testWidgets(
      'three Together tabs plan a wish into its calendar date at ${screen.width}px',
      (tester) async {
        wishRepository.rows = [wish(partnerLiked: true)];
        DateTime? plannedAt;
        wishRepository.onMutation = (operation, previous, command) async {
          expect(operation, 'plan');
          expect(wishes.pendingOperation, 'plan');
          expect(wishes.pendingWishId, wishId);
          plannedAt = wishRepository.calls.last.starts!;
          calendarRepository.value = stateJson(
            events: [
              {
                ...eventJson(title: previous.title),
                'starts_at': plannedAt!.toIso8601String(),
              },
            ],
          );
          return _linkedWish(status: 'planned', startsAt: plannedAt!);
        };
        await mount(tester, width: screen.width, scale: screen.scale);
        await openWishes(tester);
        await tapKey(tester, 'wishPlan$wishId');
        await tapKey(tester, 'wishConfirmPlan');
        expect(plannedAt, isNotNull);
        final day = togetherTime(plannedAt!);
        expect(calendar.month, DateTime.utc(day.year, day.month));
        expect(
          calendar.selectedDay,
          DateTime.utc(day.year, day.month, day.day),
        );
        expect(calendarRepository.months.last, togetherMonth(day));
        expect(memoryRepository.months.last, togetherMonth(day));
        expect(find.text('Бидний болзоо'), findsOneWidget);
        expect(find.text('Хамтдаа кофе'), findsOneWidget);
        expect(find.byKey(const Key('togetherEdit')), findsOneWidget);
        expect(wishes.pendingCommand, isNull);
        expect(wishes.pendingOperation, isNull);
        expect(wishes.pendingWishId, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'completed wish opens memory for its Ulaanbaatar day and pair change closes it',
    (tester) async {
      // 20:30 UTC is already the following day in Ulaanbaatar.
      final starts = DateTime.utc(2026, 9, 30, 20, 30);
      wishRepository.rows = [_linkedWish(status: 'done', startsAt: starts)];
      await mount(tester);
      await openWishes(tester);
      await tapKey(tester, 'wishFilterdone');
      await tapKey(tester, 'wishMemory$wishId');
      expect(calendar.month, DateTime.utc(2026, 10));
      expect(calendar.selectedDay, DateTime.utc(2026, 10, 1));
      expect(
        tester.widget<MemoryEditor>(find.byType(MemoryEditor)).day,
        '2026-10-01',
      );
      expect(memories.pairId, wishPair);
      expect(memories.month, '2026-10');
      calendarRepository.value = stateJson(pair: wishOtherPair);
      await calendar.refresh(quiet: true);
      await tester.pumpAndSettle();
      expect(find.byType(MemoryEditor), findsNothing);
      expect(wishes.pairId, wishOtherPair);
      expect(wishes.items, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background hides unsaved wish draft, resume retains it, pair change discards it',
    (tester) async {
      await mount(tester);
      await openWishes(tester);
      await tapKey(tester, 'wishAdd');
      await tester.enterText(
        find.byKey(const Key('wishTitle')),
        'Зөвхөн бидний бичиж буй хүсэл',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final polls = calendarRepository.months.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 65));
      expect(find.byKey(const Key('wishTitle')), findsNothing);
      expect(find.text('Зөвхөн бидний бичиж буй хүсэл'), findsNothing);
      expect(calendarRepository.months.length, polls);
      expect(wishes.items, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('wishTitle')))
            .controller!
            .text,
        'Зөвхөн бидний бичиж буй хүсэл',
      );
      calendarRepository.value = stateJson(pair: wishOtherPair);
      await calendar.refresh(quiet: true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wishTitle')), findsNothing);
      expect(find.text('Зөвхөн бидний бичиж буй хүсэл'), findsNothing);
      expect(wishes.pairId, wishOtherPair);
      expect(wishRepository.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
