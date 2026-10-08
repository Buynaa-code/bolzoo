import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/gifts/gifts_screen.dart';
import 'package:hamtdaa/features/home/home_screen.dart';
import 'package:hamtdaa/features/notifications/notifications_screen.dart';
import 'package:hamtdaa/ui/theme.dart';

Future<AppController> launch(WidgetTester tester, {AppData? data, double width = 390, double scale = 1}) async {
  tester.view.devicePixelRatio = 1; tester.view.physicalSize = Size(width, 844);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final c = AppController(MemoryAppStore(data)); await c.load(); addTearDown(c.dispose);
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(
    body: HomeScreen(controller: c, onTab: (_) {}))));
  await tester.pumpAndSettle(); return c;
}

void main() {
  testWidgets('home uses real together date and launches native invitation', (tester) async {
    final now = DateTime.now();
    await launch(tester, data: AppData(profile: UserProfile(name: 'Ану', togetherSince: now.subtract(const Duration(days: 424)))));
    expect(find.text('425'), findsOneWidget);
    final invite = find.byKey(const Key('homeInviteButton'));
    await tester.ensureVisible(invite); await tester.tap(invite); await tester.pumpAndSettle();
    expect(find.byType(InvitationEditor), findsOneWidget);
    expect(find.byKey(const Key('inviteSender')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty home invents no history and notifications are empty', (tester) async {
    final c = await launch(tester);
    expect(find.byKey(const Key('togetherDayCount')), findsNothing);
    expect(find.text('Танилцсан өдрөө нэмэх'), findsOneWidget);
    await tester.tap(find.byKey(const Key('homeNotificationsButton'))); await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text('Одоогоор мэдэгдэл алга'), findsOneWidget);
    expect(c.data.notices, isEmpty); expect(tester.takeException(), isNull);
  });

  testWidgets('notice opens its actual event and marks it read', (tester) async {
    final now = DateTime.now();
    final c = await launch(tester, data: AppData(
      events: [DateEvent(id: 'event-1', title: 'Хамт кофе', startsAt: now.add(const Duration(days: 1)), createdAt: now)],
      notices: [AppNotice(id: 'notice-1', title: 'Болзоо нэмэгдлээ', body: 'Хамт кофе', createdAt: now,
        kind: 'event', sourceId: 'event-1')],
    ));
    await tester.tap(find.byKey(const Key('homeNotificationsButton'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notice-notice-1'))); await tester.pumpAndSettle();
    expect(c.data.notices.single.read, isTrue);
    expect(find.text('Хамт кофе'), findsWidgets);
    expect(find.byType(NotificationsScreen).hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a removed source gets a graceful notice instead of invented detail', (tester) async {
    final c = await launch(tester, data: AppData(notices: [AppNotice(id: 'notice-1', title: 'Шинэ дурсамж', body: 'Дурсамж',
      createdAt: DateTime.now(), kind: 'memory', sourceId: 'deleted-1')]));
    await tester.tap(find.byKey(const Key('homeNotificationsButton'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notice-notice-1'))); await tester.pumpAndSettle();
    expect(find.text('Энэ мэдээлэл устсан эсвэл хуваалцах эрх нь дууссан байна.'), findsOneWidget);
    expect(c.data.notices.single.read, isTrue); expect(tester.takeException(), isNull);
  });

  testWidgets('small device and large text home stays usable', (tester) async {
    await launch(tester, width: 320, scale: 1.6);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, -550)); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('populated home remains usable throughout large text scrolling', (
    tester,
  ) async {
    final now = DateTime.now();
    await launch(
      tester,
      width: 360,
      scale: 1.6,
      data: AppData(
        profile: UserProfile(name: 'Номин', togetherSince: DateTime(2020)),
        events: [
          DateEvent(
            id: 'event',
            title: 'Хамтдаа удаан ярилцаж кофе уух өдөр',
            startsAt: now.add(const Duration(days: 1)),
            createdAt: now,
          ),
        ],
        memories: [
          MemoryEntry(
            id: 'memory',
            title: 'Санаж үлдмээр бидний нэгэн сайхан өдөр',
            date: now,
          ),
        ],
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
