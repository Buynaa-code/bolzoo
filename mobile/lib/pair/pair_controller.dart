import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pair_models.dart';
import 'pair_repository.dart';

/// Account-scoped, memory-only state. Partner projections expire after 45s and
/// are removed immediately on background, auth failure or network failure.
class PairController extends ChangeNotifier {
  PairController(this.repository) {
    _authSubscription = repository.invalidations.listen((_) => _invalidate());
  }

  final PairRepository repository;
  late final StreamSubscription<void> _authSubscription;
  Timer? _poll;
  Timer? _lease;
  Timer? _previewLease;
  int _epoch = 0;
  int _readSerial = 0;
  bool _disposed = false;
  bool _foreground = false;
  bool _authorized = true;
  bool _busy = false;
  bool _loading = false;
  PairSnapshot? _snapshot;
  PairInvitation? _preview;
  String? _previewToken;
  String? _issuedToken;
  String? _issuedInvitationId;
  PairCommand? _pending;
  PairFailure? _failure;
  String? _notice;

  PairSnapshot? get snapshot => _snapshot;
  PairInvitation? get preview => _preview;
  PairFailure? get failure => _failure;
  String? get notice => _notice;
  bool get busy => _busy;
  bool get loading => _loading;
  bool get authorized => _authorized;
  bool get canRetry => _pending != null && !_busy && _authorized && _foreground;
  bool get canAct =>
      !_busy && _pending == null && _foreground && _authorized && _snapshot != null;

  String? tokenFor(PairInvitation invitation) =>
      _foreground && invitation.isOpen && invitation.id == _issuedInvitationId
      ? _issuedToken
      : null;

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    _epoch++;
    _poll?.cancel();
    _clearProjection();
    if (foreground && _authorized) {
      unawaited(refresh());
      _poll = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!_busy) unawaited(refresh(clearFailure: false));
      });
    }
    _emit();
  }

  void _clearProjection() {
    _readSerial++;
    _loading = false;
    _snapshot = null;
    _lease?.cancel();
    _clearPreview();
  }

  void _clearPreview() {
    _previewLease?.cancel();
    _preview = null;
    _previewToken = null;
  }

  void _invalidate() {
    if (_disposed) return;
    _authorized = false;
    _epoch++;
    _poll?.cancel();
    _clearProjection();
    _issuedToken = null;
    _issuedInvitationId = null;
    _pending = null;
    _failure = const PairFailure('unauthenticated');
    _emit();
  }

  Future<void> refresh({bool clearFailure = true}) async {
    if (_disposed || !_foreground || !_authorized || _loading) return;
    final epoch = _epoch;
    final serial = ++_readSerial;
    _loading = true;
    _emit();
    try {
      final result = await repository.status();
      if (!_current(epoch) || serial != _readSerial) return;
      _snapshot = result;
      if (_pending == null &&
          (clearFailure ||
              _failure?.code == 'network_error' ||
              _failure?.code == 'invalid_response')) {
        _failure = null;
      }
      final matchingInvitation = result.invitations.any(
        (item) => item.id == _issuedInvitationId && item.isOpen,
      );
      if (!matchingInvitation) {
        _issuedToken = null;
        _issuedInvitationId = null;
      }
      if (result.pair != null || result.invitations.any((i) => !i.isCreator && i.isPending)) {
        _clearPreview();
      }
      _lease?.cancel();
      _lease = Timer(const Duration(seconds: 45), () {
        if (!_current(epoch)) return;
        _clearProjection();
        _failure = const PairFailure('network_error', retryable: true);
        _emit();
      });
    } catch (error) {
      if (!_current(epoch) || serial != _readSerial) return;
      _setFailure(error);
    } finally {
      if (_current(epoch) && serial == _readSerial) {
        _loading = false;
        _emit();
      }
    }
  }

  Future<void> previewToken(String input) async {
    if (!canAct) return;
    final token = input.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      _clearPreview();
      _failure = const PairFailure('not_found');
      _emit();
      return;
    }
    _busy = true;
    _failure = null;
    _notice = null;
    _clearPreview();
    final epoch = _epoch;
    _emit();
    try {
      final result = await repository.preview(token);
      if (!_current(epoch)) return;
      _preview = result;
      _previewToken = token;
      _previewLease = Timer(const Duration(seconds: 45), () {
        if (!_current(epoch)) return;
        _clearPreview();
        _notice = 'Урилгыг дахин шалгаж байж хүсэлт илгээнэ.';
        _emit();
      });
    } catch (error) {
      if (_current(epoch)) _setFailure(error);
    } finally {
      _busy = false;
      _emit();
    }
  }

  void cancelPreview() {
    if (_busy) return;
    _clearPreview();
    _emit();
  }

  Future<void> createInvitation() => _start(PairCommand.create());

  Future<void> requestPair() async {
    final invitation = _preview;
    final token = _previewToken;
    if (!canAct || invitation == null || token == null) return;
    await _start(PairCommand.request(token, invitation.version));
  }

  Future<void> confirm(PairInvitation invitation) =>
      _start(PairCommand.confirm(invitation));

  Future<void> close(PairInvitation invitation, String action) =>
      _start(PairCommand.close(invitation, action));

  Future<void> unlink(ActivePair pair) => _start(PairCommand.unlink(pair));

  Future<void> updateName(String name) async {
    final profile = _snapshot?.profile;
    if (profile == null) return;
    final clean = name.trim();
    if (clean.isEmpty || clean.runes.length > 40) {
      _failure = const PairFailure('validation');
      _emit();
      return;
    }
    await _start(PairCommand.updateName(clean, profile.version));
  }

  Future<void> _start(PairCommand command) async {
    if (!canAct) return;
    _pending = command;
    await retry();
  }

  Future<void> retry() async {
    if (!canRetry) return;
    final command = _pending!;
    _busy = true;
    _failure = null;
    _notice = null;
    // A status started before this command must not overwrite the new state.
    _readSerial++;
    _loading = false;
    final epoch = _epoch;
    _emit();
    var succeeded = false;
    try {
      final result = await repository.execute(command);
      if (_disposed || !_authorized) return;
      succeeded = true;
      _pending = null;
      if (command.kind == PairCommandKind.create) {
        final invitation = result['invitation'];
        if (invitation is Map && invitation['id'] is String) {
          _issuedToken = command.inviteToken;
          _issuedInvitationId = invitation['id'] as String;
        }
      } else if (command.kind != PairCommandKind.updateName) {
        _issuedToken = null;
        _issuedInvitationId = null;
      }
      _clearPreview();
      if (_current(epoch)) {
        _notice = switch (command.kind) {
          PairCommandKind.request => 'Хүсэлт илгээгдлээ. Нөгөө хүн баталгаажуулна.',
          PairCommandKind.confirm => 'Хоёр тал зөвшөөрч холбогдлоо.',
          PairCommandKind.unlink => 'Хосын холболт саллаа.',
          PairCommandKind.close => 'Хүсэлт хаагдлаа.',
          PairCommandKind.updateName => 'Хосод харагдах нэр хадгалагдлаа.',
          PairCommandKind.create => 'Урилга бэлэн боллоо.',
        };
      }
    } catch (error) {
      if (_disposed || !_authorized) return;
      final failure = error is PairFailure
          ? error
          : const PairFailure('network_error', retryable: true);
      if (!failure.retryable) _pending = null;
      if (_current(epoch)) _setFailure(failure);
    } finally {
      _busy = false;
      if (_current(epoch)) {
        _emit();
        // Never replay a consent command automatically after an error.
        if (succeeded || _pending == null) await refresh(clearFailure: false);
      } else if (!_disposed && _foreground && _authorized) {
        await refresh();
      }
    }
  }

  void _setFailure(Object error) {
    _notice = null;
    _failure = error is PairFailure
        ? error
        : const PairFailure('network_error', retryable: true);
    _clearProjection();
    if (_failure!.code == 'unauthenticated') _invalidate();
  }

  bool _current(int epoch) =>
      !_disposed && _foreground && _authorized && epoch == _epoch;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _poll?.cancel();
    _lease?.cancel();
    _previewLease?.cancel();
    _snapshot = null;
    _preview = null;
    _previewToken = null;
    _issuedToken = null;
    _pending = null;
    unawaited(_authSubscription.cancel());
    super.dispose();
  }
}
