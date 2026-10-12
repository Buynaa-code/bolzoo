import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';
import 'package:hamtdaa/main_cloudflare.dart';
import 'package:hamtdaa/notifications/reminders.dart';
import 'package:hamtdaa/together/together_reminders.dart';
import 'package:hamtdaa/together/together_repository.dart';

import '../together/together_fakes.dart';
import 'shell_fakes.dart';

void main() {
  late TogetherTransport transport;
  late CloudflareAuthRepository auth;
  late _Scheduler scheduler;
  late _Preferences preferences;
  late Map<String, dynamic> calendar;
  final coordinators = <TogetherReminderCoordinator>[];
  setUp(() async {
    transport = TogetherTransport();
    auth = CloudflareAuthRepository(
      transport: transport,
      storage: TogetherStorage(),
    );
    await auth.verifyEmailCode('a@example.com', '123456');
    calendar = stateJson(events: [eventJson(status: 'accepted')]);
    transport.onCall = (path, body) async => CloudflareResponse(200, calendar);
    scheduler = _Scheduler();
    preferences = _Preferences();
    coordinators.clear();
  });
  tearDown(() async {
    await auth.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      CloudflareOnboardingApp(
        repository: auth,
        subscriptionControllerFactory: shellBilling,
        reminderCoordinatorFactory: (auth) {
          final coordinator = TogetherReminderCoordinator(
            repository: CloudflareTogetherRepository(auth),
            scheduler: scheduler,
            preferences: preferences,
            now: () => today,
          );
          coordinators.add(coordinator);
          return coordinator;
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTogether(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('cloudflareOpenTogether')));
    await tester.tap(find.byKey(const Key('cloudflareOpenTogether')));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets(
    'home owns consented reminders after calendar pop and reconciles on resume',
    (tester) async {
      await mount(tester);
      expect(scheduler.permissionRequests, 0);
      await openTogether(tester);
      await tester.tap(find.byKey(const Key('togetherReminders')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('togetherRemindersEnabled')));
      await tester.pumpAndSettle();
      expect(scheduler.permissionRequests, 1);
      expect(scheduler.notices, hasLength(1));
      await tester.tap(find.text('Хаах'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Буцах'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloudflareHome')), findsOneWidget);
      expect(coordinators, hasLength(1));
      expect(coordinators.single.current, isTrue);
      expect(scheduler.notices, hasLength(1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final requests = transport.calls.length;
      calendar = stateJson(paired: false);
      await tester.pump(const Duration(seconds: 35));
      expect(transport.calls, hasLength(requests));
      expect(scheduler.notices, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(scheduler.notices, isEmpty);
      expect(coordinators.single.pairId, isNull);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'account switch destroys the old route and does not inherit its reminder consent',
    (tester) async {
      preferences.values['a:$pairId'] = true;
      await mount(tester);
      expect(scheduler.notices, hasLength(1));
      await openTogether(tester);
      await tester.runAsync(() => auth.verifyEmailCode('b@example.com', '123456'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloudflareHome')), findsOneWidget);
      expect(find.byKey(const Key('togetherReminders')), findsNothing);
      expect(coordinators, hasLength(2));
      expect(coordinators.first.current, isFalse);
      expect(coordinators.last.repository.actorId, 'b');
      expect(coordinators.last.enabled, isFalse);
      expect(scheduler.notices, isEmpty);
      expect(scheduler.permissionRequests, 0);
      await unmount(tester);
    },
  );
}

class _Preferences implements TogetherReminderPreferences {
  final values = <String, bool>{};
  @override
  Future<bool> read(String actorId, String pairId) async =>
      values['$actorId:$pairId'] ?? false;
  @override
  Future<void> write(String actorId, String pairId, bool enabled) async {
    values['$actorId:$pairId'] = enabled;
  }
}

class _Scheduler implements ReminderScheduler {
  @override
  bool get supported => true;
  int permissionRequests = 0;
  List<ReminderNotice> notices = [];
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> syncNotices(List<ReminderNotice> notices) async {
    this.notices = notices;
  }

  @override
  Future<void> clear() async {
    notices = [];
  }
}
