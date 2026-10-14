import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../memories/memory_controller.dart';
import '../../pair/pair_models.dart';
import '../../pair/pair_repository.dart';
import '../../together/together_models.dart';
import '../../together/together_repository.dart';

/// Read-only home projection. Never combines data from different pair scopes.
class CloudflareHomeController extends ChangeNotifier {
  CloudflareHomeController({
    required this.pairs,
    required this.together,
    this.memories,
    this.clock = DateTime.now,
  }) {
    _pairChanges = pairs.invalidations.listen((_) => _invalidate());
    _togetherChanges = together.invalidations.listen((_) => _invalidate());
    memories?.addListener(_memoryChanged);
  }

  final PairRepository pairs;
  final TogetherRepository together;
  final MemoryController? memories;
  final DateTime Function() clock;
  late final StreamSubscription<void> _pairChanges, _togetherChanges;
  Timer? _poll, _lease;
  PairSnapshot? pair;
  TogetherSnapshot? calendar;
  String? error;
  bool loading = false;
  bool _visible = false, _valid = true, _disposed = false;
  int _epoch = 0;

  bool get paired => pair?.pair != null;
  bool get current => !_disposed && _valid && together.isCurrent;
  String get month => togetherMonth(togetherTime(clock()));

  bool _accepts(int epoch) => current && _visible && epoch == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _memoryChanged() => _notify();

  void _clear() {
    ++_epoch;
    _lease?.cancel();
    pair = null;
    calendar = null;
    loading = false;
    memories?.bind(null, null);
  }

  void _invalidate() {
    if (_disposed) return;
    _valid = false;
    _poll?.cancel();
    _clear();
    _notify();
  }

  void setVisible(bool visible) {
    if (_disposed || visible == _visible) return;
    _visible = visible;
    _poll?.cancel();
    memories?.setVisible(visible);
    _clear();
    if (visible && current) {
      unawaited(refresh());
      _poll = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(refresh());
      });
    }
    _notify();
  }

  Future<void> refresh() async {
    if (!current || !_visible || loading) return;
    final epoch = ++_epoch;
    loading = true;
    _notify();
    try {
      final nextPair = await pairs.status();
      if (!_accepts(epoch)) return;
      // Clear a former partner immediately, even while a fresh calendar loads.
      if (pair?.pair?.id != nextPair.pair?.id) {
        pair = null;
        calendar = null;
        memories?.bind(null, null);
        _notify();
      }
      TogetherSnapshot? nextCalendar;
      if (nextPair.pair != null) {
        nextCalendar = await together.state(month);
        if (!_accepts(epoch)) return;
        if (!nextCalendar.paired ||
            nextCalendar.pairId != nextPair.pair!.id ||
            nextCalendar.partnerId != nextPair.pair!.partner.userId) {
          throw const TogetherFailure('pair_changed');
        }
      }
      pair = nextPair;
      calendar = nextCalendar;
      error = null;
      final pairId = nextPair.pair?.id;
      final memoryMonth = pairId == null ? null : month;
      final alreadyBound =
          memories?.pairId == pairId && memories?.month == memoryMonth;
      memories?.bind(pairId, memoryMonth);
      if (alreadyBound) unawaited(memories?.refresh());
      _lease?.cancel();
      _lease = Timer(const Duration(seconds: 45), () {
        if (!current || !_visible) return;
        _clear();
        error = 'Холболтоо шалгаад мэдээллээ шинэчлээрэй.';
        _notify();
      });
    } catch (failure) {
      if (!_accepts(epoch)) return;
      _clear();
      error = failure is PairFailure
          ? failure.message
          : failure is TogetherFailure
          ? failure.message
          : 'Мэдээллийг шинэчилж чадсангүй. Дахин оролдоорой.';
    } finally {
      if (!_disposed && _visible) {
        // A hidden or invalidated response must not stop a newer request.
        if (epoch == _epoch || !loading) loading = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _poll?.cancel();
    _lease?.cancel();
    unawaited(_pairChanges.cancel());
    unawaited(_togetherChanges.cancel());
    memories?.removeListener(_memoryChanged);
    memories?.dispose();
    pairs.dispose();
    unawaited(together.dispose());
    super.dispose();
  }
}
