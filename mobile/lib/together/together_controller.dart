import 'dart:async';
import 'package:flutter/foundation.dart';
import 'together_models.dart';
import 'together_repository.dart';

class TogetherController extends ChangeNotifier {
  TogetherController({required this.repository, DateTime Function()? now,
    this.pollInterval = const Duration(seconds: 20)}) {
    final today = togetherTime((now ?? DateTime.now)());
    selectedDay = DateTime.utc(today.year, today.month, today.day);
    month = DateTime.utc(today.year, today.month);
    _invalidations = repository.invalidations.listen((_) => _clearSession());
  }
  final TogetherRepository repository;
  final Duration pollInterval;
  late final StreamSubscription<void> _invalidations;
  late DateTime month, selectedDay;
  TogetherSnapshot? data;
  TogetherFailure? failure;
  String? notice;
  TogetherCommand? pendingCommand;
  List<TogetherDaily> history = const [];
  String? nextBeforeDay;
  bool historyLoaded = false, loadingHistory = false, loading = false, saving = false;
  bool _disposed = false, _visible = false, _refreshing = false;
  int _epoch = 0, _historyEpoch = 0;
  Timer? _poll;
  bool get current => !_disposed && repository.isCurrent;
  bool get paired => current && data?.paired == true;
  bool get canMutate => paired && !saving && pendingCommand == null;
  String get actorId => repository.actorId;
  List<TogetherEvent> get selectedEvents => data?.events.where((e) => e.occursOn(selectedDay)).toList() ?? [];
  TogetherEvent? event(String id) => data?.events.where((e) => e.id == id).firstOrNull;
  void _notify() { if (!_disposed) notifyListeners(); }
  void _clearSession() {
    _epoch++;
    _historyEpoch++;
    _poll?.cancel();
    data = null;
    history = const [];
    pendingCommand = null;
    loading = saving = loadingHistory = false;
    failure = const TogetherFailure('unauthenticated');
    _notify();
  }
  void setVisible(bool visible) {
    _visible = visible;
    _poll?.cancel();
    if (visible && current) {
      unawaited(refresh());
      _schedule();
    }
  }
  void _schedule() {
    _poll?.cancel();
    if (!_visible || !current) return;
    _poll = Timer(pollInterval, () async {
      if (_visible && !saving) await refresh(quiet: true);
      _schedule();
    });
  }
  void selectDay(DateTime value) {
    selectedDay = DateTime.utc(value.year, value.month, value.day);
    _notify();
  }
  Future<void> browseMonth(int delta) async {
    if (saving || !current) return;
    final next = DateTime.utc(month.year, month.month + delta);
    if (next.year < 2000 || next.year > 2099) return;
    month = next;
    selectedDay = month;
    // Do not show previous month's calendar under the new heading.
    data = data == null ? null : TogetherSnapshot(paired: data!.paired,
      pairId: data!.pairId, partnerId: data!.partnerId, partnerName: data!.partnerName,
      daily: data!.daily);
    _refreshing = false;
    await refresh();
  }
  Future<void> refresh({bool quiet = false}) async {
    if (!current || _refreshing || saving) return;
    final epoch = ++_epoch;
    _refreshing = true;
    loading = !quiet;
    if (!quiet) failure = null;
    _notify();
    try {
      final next = await repository.state(togetherMonth(month));
      if (!current || epoch != _epoch) return;
      if (data?.pairId != next.pairId || !next.paired) {
        history = const [];
        historyLoaded = false;
        nextBeforeDay = null;
        _historyEpoch++;
        loadingHistory = false;
        if (pendingCommand?.pairId != next.pairId) pendingCommand = null;
      }
      data = next;
      if (!quiet || failure?.code == 'network_error') failure = null;
    } on TogetherFailure catch (error) {
      if (!current || epoch != _epoch) return;
      failure = error;
      // Never retain private partner content when its current scope is unverified.
      data = null;
      history = const [];
      historyLoaded = false;
      _historyEpoch++;
    } finally {
      if (!_disposed && epoch == _epoch) {
        _refreshing = false;
        loading = false;
        _notify();
      }
    }
  }
  TogetherCommand? command(String path, Map<String, dynamic> body) => canMutate
      ? TogetherCommand(path, data!.pairId!, body) : null;
  Future<bool> send(TogetherCommand command) async {
    if (!current || saving || !paired || command.pairId != data!.pairId ||
        (pendingCommand != null && !identical(pendingCommand, command))) return false;
    saving = true;
    failure = null;
    notice = null;
    _epoch++;
    _refreshing = false;
    _notify();
    var success = false;
    try {
      await repository.mutate(command);
      if (!current) return false;
      pendingCommand = null;
      notice = 'Хадгаллаа. Хосын тань утсанд мөн харагдана.';
      success = true;
    } on TogetherFailure catch (error) {
      if (!current) return false;
      failure = error;
      pendingCommand = error.retryable ? command : null;
      if (error.code == 'pair_changed' || error.code == 'pair_required') {
        data = null;
        history = const [];
        historyLoaded = false;
      }
    } finally {
      if (!_disposed) { saving = false; loading = false; _notify(); }
    }
    if (!current) return false;
    final mutationFailure = failure;
    if (pendingCommand == null) {
      await refresh(quiet: true);
      if (mutationFailure != null && current) { failure = mutationFailure; _notify(); }
    }
    return success;
  }
  Future<bool> retry() async {
    final command = pendingCommand;
    if (command == null || saving) return false;
    await refresh(quiet: true);
    if (!current || !paired || pendingCommand != command || data!.pairId != command.pairId) return false;
    return send(command);
  }
  Future<void> loadHistory({bool more = false}) async {
    if (!paired || loadingHistory || (more && nextBeforeDay == null)) return;
    final pair = data!.pairId;
    final epoch = ++_historyEpoch;
    loadingHistory = true;
    _notify();
    try {
      final next = await repository.history(beforeDay: more ? nextBeforeDay : null);
      // A fresh scope check prevents an old history response surviving unlink/re-pair.
      await refresh(quiet: true);
      if (!current || epoch != _historyEpoch || data?.pairId != pair) return;
      history = List.unmodifiable({for (final entry in [...(more ? history : <TogetherDaily>[]), ...next.entries]) entry.day: entry}.values);
      nextBeforeDay = next.nextBeforeDay;
      historyLoaded = true;
    } on TogetherFailure catch (error) {
      if (current && epoch == _historyEpoch) { failure = error; history = const []; }
    } finally {
      if (!_disposed && epoch == _historyEpoch) { loadingHistory = false; _notify(); }
    }
  }
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _historyEpoch++;
    _poll?.cancel();
    unawaited(_invalidations.cancel());
    unawaited(repository.dispose());
    super.dispose();
  }
}
