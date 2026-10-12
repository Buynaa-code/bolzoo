import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/notifications/reminders.dart';
import 'package:hamtdaa/together/together_controller.dart';
import 'package:hamtdaa/together/together_models.dart';
import 'package:hamtdaa/together/together_reminders.dart';
import 'package:hamtdaa/together/together_screen.dart';

import 'together_fakes.dart';

void main() {
  late TogetherFakeRepository repository;
  late _Scheduler scheduler;
  late _Preferences preferences;
  late TogetherReminderCoordinator coordinator;
  setUp(() {
    repository = TogetherFakeRepository();
    scheduler = _Scheduler();
    preferences = _Preferences();
    coordinator = TogetherReminderCoordinator(
      repository: repository,
      scheduler: scheduler,
      preferences: preferences,
      now: () => today,
    );
    coordinator.setForeground(true);
  });
  tearDown(() async {
    coordinator.dispose();
    await coordinator.cleared;
  });

  test(
    'startup verifies scope and clears native notices without asking permission',
    () async {
      scheduler.notices = [ReminderNotice(id: 'old-login', at: today)];
      repository.value = stateJson(events: [eventJson(status: 'accepted')]);
      await coordinator.initialize();
      expect(scheduler.permissionRequests, 0);
      expect(scheduler.notices, isEmpty);
      expect(coordinator.pairId, pairId);
      expect(coordinator.enabled, isFalse);
      expect(repository.months, ['2026-10']);
    },
  );

  test(
    'explicit consent persists per actor and pair and schedules only approved future dates privately',
    () async {
      repository.value = stateJson(
        events: [
          eventJson(status: 'accepted', title: 'Private title'),
          {...eventJson(status: 'pending'), 'id': 'pending'},
          {...eventJson(status: 'declined'), 'id': 'declined'},
          {
            ...eventJson(status: 'accepted'),
            'id': 'past',
            'starts_at': today
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
          },
          {
            ...eventJson(status: 'accepted'),
            'id': 'far',
            'starts_at': today.add(const Duration(days: 70)).toIso8601String(),
          },
        ],
      );
      await coordinator.initialize();
      await coordinator.setEnabled(true);
      expect(scheduler.permissionRequests, 1);
      expect(preferences.values, {'a:$pairId': true});
      expect(scheduler.notices.map((notice) => notice.id), ['event-1']);
      expect(scheduler.notices.single.at, DateTime.utc(2026, 10, 6, 9));
      expect(scheduler.notices.single.body, 'Аппаа нээж сануулгаа шалгаарай.');
      expect(scheduler.notices.single.body, isNot(contains('Private')));
      expect(repository.months.toSet(), {'2026-10', '2026-11', '2026-12'});
    },
  );

  test(
    'permission denial never stores consent or schedules a notification',
    () async {
      scheduler.permission = false;
      await coordinator.initialize();
      await coordinator.setEnabled(true);
      expect(preferences.values, isEmpty);
      expect(coordinator.enabled, isFalse);
      expect(scheduler.notices, isEmpty);
      expect(coordinator.message, isNotNull);
    },
  );

  test('persisted opt-in restores without another permission prompt', () async {
    preferences.values['a:$pairId'] = true;
    repository.value = stateJson(events: [eventJson(status: 'accepted')]);
    await coordinator.initialize();
    expect(coordinator.enabled, isTrue);
    expect(scheduler.permissionRequests, 0);
    expect(scheduler.notices, hasLength(1));
  });

  test('another actor cannot inherit the same pair preference', () async {
    preferences.values['b:$pairId'] = true;
    repository.value = stateJson(events: [eventJson(status: 'accepted')]);
    await coordinator.initialize();
    expect(coordinator.enabled, isFalse);
    expect(scheduler.notices, isEmpty);
  });

  test(
    'late initialization and stale callbacks cannot clear a newer account',
    () async {
      final initialized = Completer<void>();
      scheduler.initializeGate = initialized;
      final oldInitialize = coordinator.initialize();
      coordinator.dispose();
      scheduler.initializeGate = null;
      final nextRepository = _OtherActorRepository()
        ..value = stateJson(events: [eventJson(status: 'accepted')]);
      preferences.values['b:$pairId'] = true;
      final next = TogetherReminderCoordinator(
        repository: nextRepository,
        scheduler: scheduler,
        preferences: preferences,
        now: () => today,
      )..setForeground(true);
      try {
        await next.initialize();
        expect(scheduler.notices, hasLength(1));
        initialized.complete();
        await oldInitialize;
        coordinator.observe(null);
        await coordinator.cleared;
        expect(scheduler.notices, hasLength(1));
      } finally {
        next.dispose();
        await next.cleared;
      }
    },
  );

  test(
    'same-pair screen response after background retains the existing queue',
    () async {
      preferences.values['a:$pairId'] = true;
      repository.value = stateJson(events: [eventJson(status: 'accepted')]);
      await coordinator.initialize();
      coordinator.setForeground(false);
      coordinator.observe(TogetherSnapshot.fromJson(repository.value));
      await coordinator.cleared;
      expect(scheduler.notices, hasLength(1));
    },
  );

  testWidgets(
    'calendar exposes explicit reminder opt-in and honest local-sync limits',
    (tester) async {
      final auth = CloudflareAuthRepository(
        transport: TogetherTransport(),
        storage: TogetherStorage(),
      );
      final calendar = TogetherController(
        repository: TogetherFakeRepository(),
        now: () => today,
      );
      await coordinator.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: TogetherScreen(
            auth: auth,
            controller: calendar,
            reminders: coordinator,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scheduler.permissionRequests, 0);
      await tester.tap(find.byKey(const Key('togetherReminders')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Апп хаалттай'), findsOneWidget);
      expect(find.textContaining('60 хүртэлх'), findsOneWidget);
      await tester.tap(find.byKey(const Key('togetherRemindersEnabled')));
      await tester.pumpAndSettle();
      expect(scheduler.permissionRequests, 1);
      expect(preferences.values['a:$pairId'], isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      calendar.dispose();
      await auth.dispose();
    },
  );

  test(
    'updated accepted date is rescheduled and pending/deleted dates disappear',
    () async {
      preferences.values['a:$pairId'] = true;
      repository.value = stateJson(events: [eventJson(status: 'accepted')]);
      await coordinator.initialize();
      repository.value = stateJson(
        events: [
          {
            ...eventJson(status: 'accepted'),
            'starts_at': '2026-10-07T10:00:00.000Z',
          },
        ],
      );
      await coordinator.refresh();
      expect(scheduler.notices.single.at, DateTime.utc(2026, 10, 7, 9));
      repository.value = stateJson(events: [eventJson(status: 'pending')]);
      await coordinator.refresh();
      expect(scheduler.notices, isEmpty);
      repository.value = stateJson(events: []);
      await coordinator.refresh();
      expect(scheduler.notices, isEmpty);
    },
  );

  test(
    'unlink and re-pair clear the queue and require separate consent',
    () async {
      preferences.values['a:$pairId'] = true;
      repository.value = stateJson(events: [eventJson(status: 'accepted')]);
      await coordinator.initialize();
      repository.value = stateJson(paired: false);
      await coordinator.refresh();
      expect(scheduler.notices, isEmpty);
      expect(coordinator.pairId, isNull);
      repository.value = stateJson(
        pair: otherPairId,
        events: [eventJson(status: 'accepted')],
      );
      await coordinator.refresh();
      expect(coordinator.enabled, isFalse);
      expect(scheduler.notices, isEmpty);
      expect(preferences.values['a:$otherPairId'], isNull);
    },
  );

  test('late old-session fetch cannot schedule after sign-out', () async {
    preferences.values['a:$pairId'] = true;
    await coordinator.initialize();
    final response = Completer<TogetherSnapshot>();
    repository.onState = (_) => response.future;
    final refreshing = coordinator.refresh();
    repository.invalidate();
    response.complete(
      TogetherSnapshot.fromJson(
        stateJson(events: [eventJson(status: 'accepted')]),
      ),
    );
    await refreshing;
    await coordinator.cleared;
    expect(coordinator.pairId, isNull);
    expect(scheduler.notices, isEmpty);
  });

  test(
    'backgrounding stops refresh; foreground resume reconciles remote unlink',
    () async {
      preferences.values['a:$pairId'] = true;
      repository.value = stateJson(events: [eventJson(status: 'accepted')]);
      await coordinator.initialize();
      final requests = repository.months.length;
      coordinator.setForeground(false);
      repository.value = stateJson(paired: false);
      await coordinator.refresh();
      expect(repository.months, hasLength(requests));
      expect(scheduler.notices, hasLength(1));
      coordinator.setForeground(true);
      await _settle();
      expect(scheduler.notices, isEmpty);
    },
  );

  test('permission prompt lifecycle changes retain explicit consent', () async {
    scheduler.permissionGate = Completer<bool>();
    await coordinator.initialize();
    final enabling = coordinator.setEnabled(true);
    coordinator.setForeground(false);
    scheduler.permissionGate!.complete(true);
    await enabling;
    expect(preferences.values['a:$pairId'], isTrue);
    coordinator.setForeground(true);
    await _settle();
    expect(coordinator.enabled, isTrue);
  });

  test(
    'a late snapshot for a different pair clears instead of merging ranges',
    () async {
      preferences.values['a:$pairId'] = true;
      repository.onState = (month) async => TogetherSnapshot.fromJson(
        stateJson(
          pair: month == '2026-10' ? pairId : otherPairId,
          events: [eventJson(status: 'accepted')],
        ),
      );
      await coordinator.initialize();
      expect(scheduler.notices, isEmpty);
      expect(coordinator.pairId, isNull);
      expect(coordinator.enabled, isFalse);
    },
  );

  test(
    'disable clears immediately even when storing the preference fails',
    () async {
      preferences.values['a:$pairId'] = true;
      repository.value = stateJson(events: [eventJson(status: 'accepted')]);
      await coordinator.initialize();
      preferences.failWrite = true;
      await coordinator.setEnabled(false);
      await coordinator.refresh();
      expect(coordinator.enabled, isFalse);
      expect(scheduler.notices, isEmpty);
    },
  );

  test(
    'dispose clears schedules and stale fetch results cannot restore them',
    () async {
      preferences.values['a:$pairId'] = true;
      repository.value = stateJson(events: [eventJson(status: 'accepted')]);
      await coordinator.initialize();
      final response = Completer<TogetherSnapshot>();
      repository.onState = (_) => response.future;
      final refreshing = coordinator.refresh();
      coordinator.dispose();
      response.complete(TogetherSnapshot.fromJson(repository.value));
      await refreshing;
      await coordinator.cleared;
      expect(scheduler.notices, isEmpty);
    },
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Preferences implements TogetherReminderPreferences {
  final values = <String, bool>{};
  bool failWrite = false;
  @override
  Future<bool> read(String actorId, String pairId) async =>
      values['$actorId:$pairId'] ?? false;
  @override
  Future<void> write(String actorId, String pairId, bool enabled) async {
    if (failWrite) throw StateError('storage failed');
    values['$actorId:$pairId'] = enabled;
  }
}

class _Scheduler implements ReminderScheduler {
  @override
  bool supported = true;
  bool permission = true;
  int permissionRequests = 0, clears = 0;
  Completer<bool>? permissionGate;
  Completer<void>? initializeGate;
  List<ReminderNotice> notices = [];
  @override
  Future<void> initialize() async {
    await initializeGate?.future;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGate?.future ?? permission;
  }

  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<void> syncNotices(List<ReminderNotice> notices) async {
    this.notices = notices;
  }

  @override
  Future<void> clear() async {
    clears++;
    notices = [];
  }
}

class _OtherActorRepository extends TogetherFakeRepository {
  @override
  String get actorId => 'b';
}
