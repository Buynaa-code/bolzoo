import 'dart:async';
import 'package:flutter/foundation.dart';
import 'flower_models.dart';
import 'flower_repository.dart';

class FlowersController extends ChangeNotifier {
  FlowersController(this.repository) {
    _changes = repository.invalidations.listen((_) => _revoke());
  }
  final FlowersRepository repository;
  late final StreamSubscription<void> _changes;
  Timer? _poll, _lease;
  FlowersSnapshot? snapshot;
  FlowerFailure? failure;
  FlowerCommand? _pending;
  bool loading = false, saving = false;
  bool _visible = false, _disposed = false;
  int _epoch = 0, _load = 0;
  int privacyRevision = 0;
  String? _pair, _partner;
  String? sentId;
  String get actorId => repository.actorId;
  bool get current => !_disposed && repository.isCurrent;
  bool get pending => _pending != null;
  bool get canSend =>
      current && _visible && snapshot?.paired == true && !saving && !pending;
  String? get error => failure?.message;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _accepts(int epoch) => current && _visible && epoch == _epoch;
  void _clearProjection() {
    ++_load;
    snapshot = null;
    loading = false;
    _lease?.cancel();
  }

  void _revoke() {
    ++_epoch;
    ++privacyRevision;
    _pair = _partner = null;
    _pending = null;
    sentId = null;
    saving = false;
    _clearProjection();
    if (!current) _poll?.cancel();
    _notify();
  }

  void setVisible(bool value) {
    if (_disposed || value == _visible) return;
    _visible = value;
    _poll?.cancel();
    _clearProjection();
    if (value && current) {
      unawaited(refresh());
      _poll = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(refresh());
      });
    }
    _notify();
  }

  Future<void> refresh() async {
    if (!current || !_visible || loading || saving) return;
    final epoch = _epoch, load = ++_load;
    loading = true;
    _notify();
    try {
      final next = await repository.state();
      if (!_accepts(epoch) || load != _load) return;
      if (_pair != next.pairId || _partner != next.partnerId) {
        ++privacyRevision;
        _pending = null;
        sentId = null;
      }
      _pair = next.pairId;
      _partner = next.partnerId;
      snapshot = next;
      if (!pending) failure = null;
      _lease?.cancel();
      _lease = Timer(const Duration(seconds: 45), () {
        if (!current || !_visible) return;
        _clearProjection();
        failure = const FlowerFailure('network_error', retryable: true);
        _notify();
      });
    } on FlowerFailure catch (error) {
      if (!_accepts(epoch) || load != _load) return;
      _clearProjection();
      if (error.code == 'pair_changed' ||
          error.code == 'pair_required' ||
          error.code == 'unauthenticated') {
        _revoke();
      }
      failure = error;
    } catch (_) {
      if (!_accepts(epoch) || load != _load) return;
      _clearProjection();
      failure = const FlowerFailure('network_error', retryable: true);
    } finally {
      if (_accepts(epoch) && (load == _load || !loading)) {
        loading = false;
        _notify();
      }
    }
  }

  Future<bool> send(FlowerDraft draft) async {
    if (!canSend) return false;
    try {
      _pending = FlowerCommand(snapshot!.pairId!, draft);
    } on FlowerFailure catch (error) {
      failure = error;
      _notify();
      return false;
    }
    return _submit();
  }

  Future<bool> retry() async {
    if (!current ||
        !_visible ||
        saving ||
        _pending == null ||
        snapshot?.pairId != _pending!.body['expected_pair_id']) {
      return false;
    }
    return _submit();
  }

  Future<bool> _submit() async {
    final command = _pending!, epoch = _epoch;
    saving = true;
    failure = null;
    ++_load;
    loading = false;
    _notify();
    var confirmed = false;
    try {
      final id = await repository.send(command);
      if (!current || epoch != _epoch) return false;
      sentId = id;
      _pending = null;
      confirmed = true;
    } on FlowerFailure catch (error) {
      if (!current || epoch != _epoch) return false;
      failure = error;
      if (error.code == 'pair_changed' ||
          error.code == 'pair_required' ||
          error.code == 'unauthenticated') {
        _revoke();
      } else if (!error.retryable) {
        _pending = null;
      }
    } catch (_) {
      if (current && epoch == _epoch) {
        failure = const FlowerFailure('network_error', retryable: true);
      }
    } finally {
      if (!_disposed && epoch == _epoch) {
        saving = false;
        _notify();
      }
    }
    if (confirmed && _visible) await refresh();
    return confirmed;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _poll?.cancel();
    _lease?.cancel();
    unawaited(_changes.cancel());
    unawaited(repository.dispose());
    super.dispose();
  }
}
