import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hamtdaa/data/models.dart';
import 'package:hamtdaa/notifications/reminders.dart';
import 'package:hamtdaa/main_supabase_legacy.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native reminder initializes, schedules, clears, and app boots', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final reminders = Reminders.instance;
    await reminders.initialize();
    expect(reminders.ready, isTrue);
    final plugin = FlutterLocalNotificationsPlugin();
    final event = DateEvent(
      id: 'native-reminder-fixture',
      title: 'Туршилтын болзоо',
      startsAt: DateTime.now().add(const Duration(days: 2)),
      createdAt: DateTime.now(),
      reminderMinutes: 60,
    );
    try {
      await reminders.sync([event]);
      final pending = await plugin.pendingNotificationRequests();
      expect(pending.any((item) => item.payload == event.id), isTrue);
    } finally {
      await reminders.clear();
    }
    expect(await plugin.pendingNotificationRequests(), isEmpty);
    // Exercise the legacy startup entrypoint; no login or account is created.
    app.main();
    await tester.pumpAndSettle();
    expect(find.byType(app.AppShell), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
