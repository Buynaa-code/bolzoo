import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../notifications/reminders.dart';
import 'together_models.dart';
import 'together_repository.dart';

abstract interface class TogetherReminderPreferences {
  Future<bool> read(String actorId, String pairId);
  Future<void> write(String actorId, String pairId, bool enabled);
}

/// Consent belongs to one person and one pairing, on this device only.
class SecureTogetherReminderPreferences implements TogetherReminderPreferences {
  SecureTogetherReminderPreferences({
    this.namespace = 'default',
    FlutterSecureStorage? storage,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.unlocked_this_device,
             ),
             mOptions: MacOsOptions(usesDataProtectionKeychain: false),
           );
  final FlutterSecureStorage _storage;
  final String namespace;
  static Future<void> _pending = Future.value();
  String _key(String actor, String pair) =>
      'hamtdaa.cloudflare.reminders.v1.${base64Url.encode(utf8.encode(jsonEncode([namespace, actor, pair])))}';
  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _pending.then((_) => work());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<bool> read(String actorId, String pairId) => _serial(
    () async => await _storage.read(key: _key(actorId, pairId)) == 'enabled',
  );
  @override
  Future<void> write(String actorId, String pairId, bool enabled) => _serial(
    () => enabled
        ? _storage.write(key: _key(actorId, pairId), value: 'enabled')
        : _storage.delete(key: _key(actorId, pairId)),
  );
}

/// Owned by the signed-in home, not by a calendar route. Native schedules keep
/// working while the app is closed. Changes made on another phone are reconciled
/// only while this app is open; local notifications cannot perform remote sync.
class TogetherReminderCoordinator extends ChangeNotifier {
  TogetherReminderCoordinator({
    required this.repository,
    ReminderScheduler? scheduler,
    TogetherReminderPreferences? preferences,
    DateTime Function()? now,
    this.pollInterval = const Duration(seconds: 30),
  }) : scheduler = scheduler ?? Reminders.instance,
       preferences = preferences ?? SecureTogetherReminderPreferences(),
       _now = now ?? DateTime.now {
    _invalidations = repository.invalidations.listen((_) => _invalidate());
  }
  final TogetherRepository repository;
  final ReminderScheduler scheduler;
  final TogetherReminderPreferences preferences;
  final DateTime Function() _now;
  final Duration pollInterval;
  late final StreamSubscription<void> _invalidations;
  Timer? _poll;
  Future<void>? _initialization;
  Future<void> _cleared = Future.value();
  Future<void> get cleared => _cleared;
  bool _disposed = false, _ready = false, _foreground = false;
  bool _refreshing = false, _preferenceBusy = false;
  int _epoch = 0, _preferenceEpoch = 0;
  final _locallyDisabled = <String>{};
  String? pairId, message;
  bool enabled = false;
  bool get supported => scheduler.supported;
  bool get current => !_disposed && repository.isCurrent;
  bool get busy => _refreshing || _preferenceBusy;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _live(int epoch) => current && _foreground && epoch == _epoch;

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    try {
      await scheduler.initialize();
      if (!current) return;
      // Previous native notices may predate this login or the last app launch.
      await _clear();
      if (!current) return;
      _ready = true;
      await refresh();
    } catch (_) {
      if (current) {
        message = 'Сануулгыг бэлдэж чадсангүй. Дахин нээгээд оролдоорой.';
        _notify();
      }
    }
  }

  Future<void> _clear() {
    // Calling clear immediately invalidates any already-running native batch.
    _cleared = scheduler.clear().catchError((Object _) {
      if (current) {
        message = 'Сануулгыг шинэчилж чадсангүй. Дахин шалгаарай.';
        _notify();
      }
    });
    return _cleared;
  }

  void setForeground(bool value) {
    if (_disposed || _foreground == value) return;
    _foreground = value;
    _poll?.cancel();
    if (value) {
      unawaited(refresh());
      _schedule();
    } else {
      ++_epoch;
      _refreshing = false;
    }
  }

  void _schedule() {
    _poll?.cancel();
    if (!_foreground || !current) return;
    _poll = Timer(pollInterval, () async {
      await refresh();
      _schedule();
    });
  }

  /// A calendar mutation/fresh snapshot invalidates the cached native dates.
  /// Refetch the upcoming range, independent of the month being browsed.
  void observe(TogetherSnapshot? snapshot) {
    if (_disposed) return;
    if (!current) {
      _invalidate();
      return;
    }
    // A screen fetch can finish after the app backgrounds. Keep the known
    // same-pair native queue until foreground reconciliation can replace it.
    if (!_foreground &&
        snapshot?.paired == true &&
        snapshot?.pairId == pairId) {
      return;
    }
    ++_epoch;
    _refreshing = false;
    if (snapshot?.pairId != pairId || snapshot?.paired != true) {
      ++_preferenceEpoch;
      pairId = null;
      enabled = false;
    }
    unawaited(_clear());
    if (_foreground && !_preferenceBusy) unawaited(refresh());
    _notify();
  }

  void _invalidate() {
    if (_disposed) return;
    ++_epoch;
    ++_preferenceEpoch;
    _poll?.cancel();
    pairId = null;
    enabled = false;
    _refreshing = false;
    unawaited(_clear());
    _notify();
  }

  Future<void> refresh() async {
    if (!_ready || !_foreground || !current || _refreshing || _preferenceBusy) {
      return;
    }
    final epoch = ++_epoch;
    _refreshing = true;
    _notify();
    try {
      final now = _now().toUtc();
      final start = togetherTime(now);
      final limit = now.add(const Duration(days: 60));
      final end = togetherTime(limit);
      final firstMonth = DateTime.utc(start.year, start.month);
      final first = await repository.state(togetherMonth(firstMonth));
      if (!_live(epoch)) return;
      final pair = first.paired ? first.pairId : null;
      if (pairId != pair) {
        ++_preferenceEpoch;
        pairId = pair;
        enabled = false;
        await _clear();
        if (!_live(epoch)) return;
      }
      if (pair == null) {
        await _clear();
        return;
      }
      final optedIn =
          !_locallyDisabled.contains(pair) &&
          await preferences.read(repository.actorId, pair);
      if (!_live(epoch)) return;
      enabled = optedIn;
      if (!optedIn || !supported) {
        await _clear();
        return;
      }
      final permitted = await scheduler.hasPermission();
      if (!_live(epoch)) return;
      if (!permitted) {
        message = 'Утасны тохиргооноос Нандин мөч аппын мэдэгдлийг зөвшөөрөөрэй.';
        await _clear();
        return;
      }
      final events = <String, TogetherEvent>{
        for (final event in first.events) event.id: event,
      };
      for (
        var month = DateTime.utc(start.year, start.month + 1);
        !month.isAfter(DateTime.utc(end.year, end.month));
        month = DateTime.utc(month.year, month.month + 1)
      ) {
        final next = await repository.state(togetherMonth(month));
        if (!_live(epoch)) return;
        if (!next.paired || next.pairId != pair) {
          pairId = null;
          enabled = false;
          ++_preferenceEpoch;
          await _clear();
          return;
        }
        for (final event in next.events) {
          events[event.id] = event;
        }
      }
      if (!_live(epoch)) return;
      final notices = <ReminderNotice>[
        for (final event in events.values)
          if (event.status == TogetherEventStatus.accepted &&
              event.startsAt.isAfter(now) &&
              !event.startsAt.isAfter(limit))
            ReminderNotice(
              id: event.id,
              // A near-term accepted date still receives a reminder at its start.
              at: event.startsAt.subtract(const Duration(hours: 1)).isAfter(now)
                  ? event.startsAt.subtract(const Duration(hours: 1))
                  : event.startsAt,
            ),
      ];
      await scheduler.syncNotices(notices);
      if (_live(epoch)) message = null;
    } catch (_) {
      if (_live(epoch)) {
        message = 'Сануулгыг шинэчлэхийн тулд интернет холболтоо шалгаарай.';
        pairId = null;
        enabled = false;
        ++_preferenceEpoch;
        await _clear();
      }
    } finally {
      if (!_disposed && epoch == _epoch) {
        _refreshing = false;
        _notify();
      }
    }
  }

  Future<void> setEnabled(bool value) async {
    final pair = pairId;
    if (!_ready ||
        !current ||
        !_foreground ||
        pair == null ||
        busy ||
        !supported) {
      return;
    }
    final preferenceEpoch = ++_preferenceEpoch;
    ++_epoch;
    _preferenceBusy = true;
    message = null;
    if (!value) {
      _locallyDisabled.add(pair);
      enabled = false;
      unawaited(_clear());
    }
    _notify();
    bool applies() =>
        current && pairId == pair && preferenceEpoch == _preferenceEpoch;
    try {
      if (value && !await scheduler.requestPermission()) {
        if (applies()) {
          message =
              'Утасны тохиргооноос Нандин мөч аппын мэдэгдлийг зөвшөөрөөрэй.';
        }
        return;
      }
      if (!applies()) return;
      await preferences.write(repository.actorId, pair, value);
      if (!applies()) return;
      if (value) _locallyDisabled.remove(pair);
      enabled = value;
    } catch (_) {
      if (applies()) {
        enabled = false;
        message = 'Сонголтыг хадгалж чадсангүй. Дахин оролдоорой.';
        await _clear();
      }
    } finally {
      if (!_disposed) {
        _preferenceBusy = false;
        _notify();
        if (_foreground && current) await refresh();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    ++_preferenceEpoch;
    _poll?.cancel();
    unawaited(_clear());
    unawaited(_invalidations.cancel());
    unawaited(repository.dispose());
    super.dispose();
  }
}
