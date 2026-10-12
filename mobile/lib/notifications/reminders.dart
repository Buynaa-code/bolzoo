import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../data/models.dart';

@immutable
class ReminderNotice {
  const ReminderNotice({
    required this.id,
    required this.at,
    this.body = 'Аппаа нээж сануулгаа шалгаарай.',
  });
  final String id, body;
  final DateTime at;
}

abstract interface class ReminderScheduler {
  bool get supported;
  Future<void> initialize();
  Future<bool> requestPermission();
  Future<bool> hasPermission();
  Future<void> syncNotices(List<ReminderNotice> notices);
  Future<void> clear();
}

/// One serial queue is shared by all account lifetimes. A logout is a barrier:
/// old in-flight native work finishes, is cancelled, then new-account work runs.
class Reminders implements ReminderScheduler {
  Reminders._()
    : this.withPlugin(
        FlutterLocalNotificationsPlugin(),
        supported:
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android),
      );
  @visibleForTesting
  Reminders.withPlugin(
    this._plugin, {
    DateTime Function()? now,
    this.supported = true,
  }) : _now = now ?? DateTime.now;
  static final instance = Reminders._();
  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _now;
  @override
  final bool supported;
  bool ready = false;
  ValueChanged<String>? onTap;
  String? pendingEventId;
  int _revision = 0;
  Future<void> _pending = Future.value();
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> initialize() => _serial(() async {
    if (ready || !supported) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        if (id != null) {
          pendingEventId = id;
          onTap?.call(id);
        }
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      pendingEventId = launch?.notificationResponse?.payload;
    }
    ready = true;
  });
  @override
  Future<bool> requestPermission() => _serial(() async {
    if (!ready || !supported) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: true) ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        false;
  });
  @override
  Future<bool> hasPermission() => _serial(() async {
    if (!ready || !supported) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return (await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.checkPermissions())
              ?.isEnabled ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled() ??
        false;
  });
  Future<void> sync(List<DateEvent> events) => syncNotices([
    for (final event in events)
      if (event.reminderMinutes > 0)
        ReminderNotice(
          id: event.id,
          at: event.startsAt.subtract(Duration(minutes: event.reminderMinutes)),
        ),
  ]);
  @override
  Future<void> syncNotices(List<ReminderNotice> notices) {
    final revision = ++_revision;
    final snapshot = List<ReminderNotice>.of(notices);
    return _serial(() async {
      if (!ready || revision != _revision) return;
      await _plugin.cancelAllPendingNotifications();
      if (revision != _revision) return;
      final upcoming = snapshot.where((n) => n.at.isAfter(_now())).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      var id = 1;
      // iOS allows only 64 pending notifications; keep room for future categories.
      for (final notice in upcoming.take(60)) {
        if (revision != _revision) return;
        await _plugin.zonedSchedule(
          id: id++,
          title: 'Нандин мөч',
          body: notice.body,
          scheduledDate: tz.TZDateTime.from(notice.at.toUtc(), tz.UTC),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'date_reminders',
              'Болзооны сануулга',
              channelDescription: 'Таны сонгосон болзооны сануулгууд',
              importance: Importance.high,
              visibility: NotificationVisibility.private,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: notice.id,
        );
      }
    });
  }

  @override
  Future<void> clear() {
    ++_revision;
    pendingEventId = null;
    return _serial(() async {
      // Initialization may have returned an old launch payload while this
      // account-clear barrier was waiting for native work to finish.
      pendingEventId = null;
      if (ready) await _plugin.cancelAll();
    });
  }
}
