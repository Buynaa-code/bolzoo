import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/calendar/calendar_screen.dart';
import 'package:hamtdaa/features/gifts/gifts_screen.dart';
import 'package:hamtdaa/features/home/home_screen.dart';
import 'package:hamtdaa/features/memories/memories_screen.dart';
import 'package:hamtdaa/features/profile/profile_screen.dart';
import 'package:hamtdaa/main_supabase_legacy.dart';

void _setDevice(WidgetTester tester, {double width = 390, double scale = 1}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<AppController> _launch(
  WidgetTester tester,
  MemoryAppStore store,
) async {
  final controller = AppController(store);
  await controller.load();
  addTearDown(controller.dispose);
  await tester.pumpWidget(HamtdaaApp(controller: controller));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _tab(WidgetTester tester, String label) async {
  final destination = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  await tester.tap(destination);
  await tester.pumpAndSettle();
}

Future<void> _enter(
  WidgetTester tester,
  String key,
  String text,
) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey(key));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('five tabs show their real empty states without inventing records', (
    tester,
  ) async {
    _setDevice(tester);
    final controller = await _launch(tester, MemoryAppStore());

    expect(find.text('Хэзээ уулзах вэ?').hitTestable(), findsOneWidget);
    await _tab(tester, 'Хуанли');
    expect(find.text('Сайхан өдрүүдээ төлөвлөе.').hitTestable(), findsOneWidget);
    expect(find.text('0 төлөвлөгөө'), findsOneWidget);
    await _tab(tester, 'Дурсамж');
    expect(
      find.text('Жижигхэн мөчүүд. Нандин дурсамжууд.').hitTestable(),
      findsOneWidget,
    );
    await _tab(tester, 'Бэлэг');
    expect(find.text('Баярлуулах уу?').hitTestable(), findsOneWidget);
    expect(find.text('BOLZOO'), findsOneWidget);
    expect(find.text('FLOWERTOI'), findsOneWidget);
    // Product buttons are deliberately not tapped: this suite is fully local.
    await _tab(tester, 'Бид');
    expect(find.text('Бидний орон зай').hitTestable(), findsOneWidget);
    expect(find.text('Таны орон зай').hitTestable(), findsOneWidget);
    await _tab(tester, 'Нүүр');
    expect(find.text('Хэзээ уулзах вэ?').hitTestable(), findsOneWidget);

    expect(controller.data.events, isEmpty);
    expect(controller.data.memories, isEmpty);
    expect(controller.data.profile.name, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank and whitespace event titles stay in the editor without saving', (
    tester,
  ) async {
    _setDevice(tester);
    final store = MemoryAppStore();
    final controller = await _launch(tester, store);
    await _tab(tester, 'Хуанли');
    await _tapKey(tester, 'calendarAddEvent');

    await _tapKey(tester, 'saveEventButton');
    expect(find.text('Төлөвлөгөөний нэрээ бичээрэй.'), findsOneWidget);
    expect(find.text('Шинэ төлөвлөгөө'), findsOneWidget);
    expect(controller.data.events, isEmpty);

    await _enter(tester, 'eventTitle', '   ');
    await _tapKey(tester, 'saveEventButton');
    expect(find.text('Төлөвлөгөөний нэрээ бичээрэй.'), findsOneWidget);
    expect(controller.data.events, isEmpty);
    expect((await store.read()).events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved event returns to its selected calendar day and survives reload', (
    tester,
  ) async {
    _setDevice(tester);
    final store = MemoryAppStore();
    final controller = await _launch(tester, store);
    final now = DateTime.now();
    await _tab(tester, 'Хуанли');
    // Day 15 exists in every month, so next/previous month does not clamp it.
    await tester.tap(find.text('15').hitTestable());
    await tester.pumpAndSettle();
    await _tapKey(tester, 'calendarAddEvent');
    await _enter(tester, 'eventTitle', '  Хамт кофе уух  ');
    await _enter(tester, 'eventPlace', '  Дуртай кафе  ');
    await _enter(tester, 'eventNote', '  Цонхны дэргэд суух.  ');
    await _tapKey(tester, 'saveEventButton');

    expect(find.text('Шинэ төлөвлөгөө'), findsNothing);
    expect(controller.data.events, hasLength(1));
    final saved = controller.data.events.single;
    expect(saved.title, 'Хамт кофе уух');
    expect(saved.place, 'Дуртай кафе');
    expect(saved.note, 'Цонхны дэргэд суух.');
    expect(saved.startsAt, DateTime(now.year, now.month, 15, 18));
    expect(find.text('1 төлөвлөгөө'), findsOneWidget);

    await tester.tap(find.byTooltip('Дараагийн сар'));
    await tester.pumpAndSettle();
    expect(find.text('0 төлөвлөгөө'), findsOneWidget);
    await tester.tap(find.byTooltip('Өмнөх сар'));
    await tester.pumpAndSettle();
    expect(find.text('1 төлөвлөгөө'), findsOneWidget);

    final reloaded = AppController(store);
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.data.events.single.toJson(), saved.toJson());
    expect(tester.takeException(), isNull);
  });

  testWidgets('event detail creates a linked text memory and displays it in memories', (
    tester,
  ) async {
    _setDevice(tester);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final event = DateEvent(
      id: 'event-to-memory',
      title: 'Хоёулаа алхъя',
      startsAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18),
      createdAt: DateTime.now(),
    );
    final store = MemoryAppStore(AppData(events: [event]));
    final controller = await _launch(tester, store);
    await _tapKey(tester, 'homePlanButton');
    expect(find.text('Хоёулаа алхъя').hitTestable(), findsOneWidget);
    final addMemory = find.text('Дурсамж нэмэх');
    await tester.ensureVisible(addMemory);
    await tester.tap(addMemory);
    await tester.pumpAndSettle();
    expect(find.text('Шинэ дурсамж'), findsOneWidget);

    await _enter(tester, 'memoryTitle', 'Алхсан орой');
    await _enter(tester, 'memoryText', 'Удаан ярилцсан сайхан орой байлаа.');
    await _tapKey(tester, 'saveMemoryButton');
    expect(find.text('Шинэ дурсамж'), findsNothing);
    expect(controller.data.memories, hasLength(1));
    final memory = controller.data.memories.single;
    expect(memory.eventId, event.id);
    expect(memory.title, 'Алхсан орой');
    expect(memory.text, 'Удаан ярилцсан сайхан орой байлаа.');
    expect(memory.photoPath, isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tab(tester, 'Дурсамж');
    expect(find.text('Алхсан орой'), findsOneWidget);
    expect((await store.read()).memories.single.eventId, event.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile edits survive a fresh app and preserve the anniversary', (
    tester,
  ) async {
    _setDevice(tester);
    final anniversary = DateTime(2020, 2, 29);
    final store = MemoryAppStore(
      AppData(profile: UserProfile(name: 'Ану', togetherSince: anniversary)),
    );
    await _launch(tester, store);
    await _tab(tester, 'Бид');
    await _tapKey(tester, 'profileEditButton');
    await _enter(tester, 'profileNameField', '  Номин  ');
    await _tapKey(tester, 'profileSaveButton');
    expect(find.text('Миний мэдээлэл'), findsNothing);

    // Tear down the whole widget tree, then reopen from the same store.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final reloaded = await _launch(tester, store);
    expect(reloaded.data.profile.name, 'Номин');
    expect(reloaded.data.profile.togetherSince, anniversary);
    expect(find.text('Сайн уу, Номин ☀').hitTestable(), findsOneWidget);
    await _tab(tester, 'Бид');
    expect(find.text('Номин').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all main tabs remain usable at 360 wide and 1.6 text scale', (
    tester,
  ) async {
    _setDevice(tester, width: 360, scale: 1.6);
    final now = DateTime.now();
    final future = now.add(const Duration(days: 1));
    await _launch(
      tester,
      MemoryAppStore(
        AppData(
          profile: UserProfile(name: 'Номин', togetherSince: DateTime(2020, 2, 29)),
          events: [
            DateEvent(
              id: 'large-text-event',
              title: 'Хамтдаа удаан ярилцаж кофе уух өдөр',
              startsAt: future,
              createdAt: now,
              place: 'Цонхны дэргэдэх бидний дуртай жижиг кафе',
            ),
          ],
          memories: [
            MemoryEntry(
              id: 'large-text-memory',
              title: 'Санаж үлдмээр бидний нэгэн сайхан өдөр',
              date: DateTime(now.year, now.month, now.day),
              text: 'Удаан ярилцаж, хамт алхсан орой.',
            ),
          ],
        ),
      ),
    );

    const pages = <(String, Type)>[
      ('Нүүр', HomeScreen),
      ('Хуанли', CalendarScreen),
      ('Дурсамж', MemoriesScreen),
      ('Бэлэг', GiftsScreen),
      ('Бид', ProfileScreen),
    ];
    for (final (label, type) in pages) {
      await _tab(tester, label);
      final page = find.byType(type);
      expect(
        MediaQuery.textScalerOf(tester.element(page)).scale(10),
        closeTo(16, 0.001),
      );
      expect(tester.takeException(), isNull, reason: '$label initial layout');
      final scrollable = find.descendant(
        of: page,
        matching: find.byType(Scrollable),
      ).first;
      // Visit content below the fold as well as each tab's initial viewport.
      for (var i = 0; i < 4; i++) {
        await tester.drag(scrollable, const Offset(0, -350));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label scrolled layout');
      }
      expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
    }
  });
}
