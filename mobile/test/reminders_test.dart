import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/data/models.dart';
import 'package:hamtdaa/notifications/reminders.dart';
import 'package:timezone/timezone.dart' as tz;

final _now = DateTime(2026, 9, 28, 12);
DateEvent _event(String id, {int minutes = 60, int reminder = 10}) => DateEvent(
  id: id, title: id, startsAt: _now.add(Duration(minutes: minutes)),
  createdAt: _now, reminderMinutes: reminder,
);
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) { await Future<void>.delayed(Duration.zero); }
}
Reminders _reminders(_Plugin plugin) => Reminders.withPlugin(plugin, now: () => _now)..ready = true;

void main() {
  test('overlapping refreshes serialize native work and only latest queued data schedules', () async {
    final plugin = _Plugin()..cancelGate = Completer<void>();
    final reminders = _reminders(plugin);
    final first = reminders.sync([_event('old')]);
    await _settle();
    final skipped = reminders.sync([_event('intermediate')]);
    final latest = reminders.sync([_event('latest')]);
    expect(plugin.calls, ['cancelPending']);
    plugin.cancelGate!.complete();
    await Future.wait([first, skipped, latest]);
    expect(plugin.calls, ['cancelPending', 'cancelPending', 'schedule:latest']);
    expect(plugin.pending.values.map((n) => n.payload), ['latest']);
    expect(plugin.maximumConcurrentCalls, 1);
  });

  test('account clear interrupts an active batch and remains a barrier before new account sync', () async {
    final plugin = _Plugin()..scheduleGate = Completer<void>();
    final reminders = _reminders(plugin)..pendingEventId = 'old-tap';
    final oldAccount = reminders.sync([_event('old-1'), _event('old-2', minutes: 90)]);
    await _settle();
    expect(plugin.calls, ['cancelPending', 'schedule:old-1']);
    final clearing = reminders.clear();
    final newAccount = reminders.sync([_event('new-account')]);
    expect(reminders.pendingEventId, isNull);
    expect(plugin.calls, ['cancelPending', 'schedule:old-1']);
    plugin.scheduleGate!.complete();
    await Future.wait([oldAccount, clearing, newAccount]);
    expect(plugin.calls, [
      'cancelPending', 'schedule:old-1', 'cancelAll', 'cancelPending', 'schedule:new-account',
    ]);
    expect(plugin.pending.values.map((n) => n.payload), ['new-account']);
    expect(plugin.maximumConcurrentCalls, 1);
  });

  test('sign-out while native cancellation is pending never schedules old events', () async {
    final plugin = _Plugin()..cancelGate = Completer<void>();
    final reminders = _reminders(plugin);
    final syncing = reminders.sync([_event('private-date')]);
    await _settle();
    final clearing = reminders.clear();
    plugin.cancelGate!.complete();
    await Future.wait([syncing, clearing]);
    expect(plugin.calls, ['cancelPending', 'cancelAll']);
    expect(plugin.pending, isEmpty);
  });

  test('a scheduling error is returned and does not prevent later cleanup or sync', () async {
    final plugin = _Plugin()..failSchedule = true;
    final reminders = _reminders(plugin);
    await expectLater(reminders.sync([_event('fails')]), throwsStateError);
    await reminders.clear();
    await reminders.sync([_event('retry')]);
    expect(plugin.calls, [
      'cancelPending', 'schedule:fails', 'cancelAll', 'cancelPending', 'schedule:retry',
    ]);
    expect(plugin.pending.values.map((n) => n.payload), ['retry']);
    expect(plugin.maximumConcurrentCalls, 1);
  });

  test('a failed cancellation is surfaced and a newer sync can recover', () async {
    final plugin = _Plugin()..failCancel = true;
    final reminders = _reminders(plugin);
    await expectLater(reminders.sync([_event('fails')]), throwsStateError);
    await reminders.sync([_event('recovered')]);
    expect(plugin.calls, ['cancelPending', 'cancelPending', 'schedule:recovered']);
    expect(plugin.pending.values.map((n) => n.payload), ['recovered']);
  });

  test('capacity uses the soonest reminder times and ignores expired or disabled dates', () async {
    final plugin = _Plugin();
    final reminders = _reminders(plugin);
    final events = [
      _event('disabled', reminder: 0), _event('expired', minutes: 5, reminder: 10),
      for (var i = 0; i < 65; i++)
        _event('date-$i', minutes: (i + 1) * 1440, reminder: (i + 1) * 1440 - (65 - i)),
    ];
    await reminders.sync(events);
    final scheduled = plugin.pending.values.toList();
    expect(scheduled, hasLength(60));
    expect(scheduled.first.payload, 'date-64');
    expect(scheduled.last.payload, 'date-5');
    expect(scheduled.first.at.toUtc(), _now.add(const Duration(minutes: 1)).toUtc());
    expect(scheduled.map((n) => n.mode).toSet(), {AndroidScheduleMode.inexactAllowWhileIdle});
  });

  test('caller list mutation cannot change a queued snapshot', () async {
    final plugin = _Plugin();
    final reminders = _reminders(plugin);
    final events = [_event('saved')];
    final syncing = reminders.sync(events);
    events.clear();
    await syncing;
    expect(plugin.pending.values.single.payload, 'saved');
  });

  test('uninitialized reminders do no native work but clear pending tap state', () async {
    final plugin = _Plugin();
    final reminders = Reminders.withPlugin(plugin)..pendingEventId = 'old';
    await reminders.sync([_event('date')]);
    await reminders.clear();
    expect(plugin.calls, isEmpty);
    expect(reminders.pendingEventId, isNull);
  });

  test('clear during initialization removes a late launch payload at its native barrier', () async {
    final plugin = _Plugin()..initializeGate = Completer<void>();
    final reminders = Reminders.withPlugin(plugin);
    final initialization = reminders.initialize();
    await _settle();
    final clearing = reminders.clear();
    plugin.initializeGate!.complete();
    await Future.wait([initialization, clearing]);
    expect(reminders.ready, isTrue);
    expect(reminders.pendingEventId, isNull);
    expect(plugin.calls, ['initialize', 'launchDetails', 'cancelAll']);
  });

  test('unsupported platforms never initialize, request permission, or touch native notices', () async {
    final plugin = _Plugin();
    final reminders = Reminders.withPlugin(plugin, supported: false)
      ..pendingEventId = 'old';
    await reminders.initialize();
    expect(await reminders.requestPermission(), isFalse);
    expect(await reminders.hasPermission(), isFalse);
    await reminders.sync([_event('date')]);
    await reminders.clear();
    expect(reminders.ready, isFalse);
    expect(reminders.pendingEventId, isNull);
    expect(plugin.calls, isEmpty);
  });
}

class _Scheduled {
  _Scheduled(this.payload, this.at, this.mode);
  final String? payload;
  final tz.TZDateTime at;
  final AndroidScheduleMode mode;
}
class _Plugin implements FlutterLocalNotificationsPlugin {
  final calls = <String>[];
  final pending = <int, _Scheduled>{};
  Completer<void>? cancelGate, scheduleGate, initializeGate;
  bool failCancel = false, failSchedule = false;
  int concurrentCalls = 0, maximumConcurrentCalls = 0;

  @override
  Future<bool?> initialize({required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse}) async {
    await _call('initialize', () async { await initializeGate?.future; });
    return true;
  }
  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async {
    calls.add('launchDetails');
    return const NotificationAppLaunchDetails(true,
      notificationResponse: NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'old-account-event'));
  }

  Future<void> _call(String name, Future<void> Function() body) async {
    calls.add(name);
    concurrentCalls++;
    if (concurrentCalls > maximumConcurrentCalls) maximumConcurrentCalls = concurrentCalls;
    try { await body(); } finally { concurrentCalls--; }
  }
  @override
  Future<void> cancelAllPendingNotifications() => _call('cancelPending', () async {
    await cancelGate?.future;
    if (failCancel) { failCancel = false; throw StateError('Native cancellation failed'); }
    pending.clear();
  });
  @override
  Future<void> cancelAll() => _call('cancelAll', () async { pending.clear(); });
  @override
  Future<void> zonedSchedule({
    required int id, required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title, String? body, String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) => _call('schedule:$payload', () async {
    await scheduleGate?.future;
    if (failSchedule) { failSchedule = false; throw StateError('Native scheduling failed'); }
    pending[id] = _Scheduled(payload, scheduledDate, androidScheduleMode);
  });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
