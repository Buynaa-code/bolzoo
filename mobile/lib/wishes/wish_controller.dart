import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'wish_models.dart';
import 'wish_repository.dart';

class WishController extends ChangeNotifier {
  WishController(this.repository) {
    _changes = repository.invalidations.listen((_) => bind(null));
  }

  final WishRepository repository;
  late final StreamSubscription<void> _changes;
  String? pairId;
  List<SharedWish> items = const [];
  bool loading = false, saving = false;
  WishFailure? failure;
  String? notice;
  bool _disposed = false, _visible = true;
  int _epoch = 0, _loadEpoch = 0;
  _WishCommand? _pending;

  bool get current => !_disposed && repository.isCurrent && pairId != null;
  bool get canMutate =>
      current &&
      _visible &&
      !saving &&
      _pending == null &&
      failure?.code != 'feature_unavailable';
  String get actorId => repository.actorId;
  String? get error => failure?.message;
  String? get pendingCommand => _pending?.id;
  String? get pendingOperation => _pending?.operation;
  String? get pendingWishId => _pending?.wish?.id;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void bind(String? pair) {
    if (_disposed ||
        (pair == pairId && (pair == null || repository.isCurrent))) {
      return;
    }
    _epoch++;
    _loadEpoch++;
    pairId = pair;
    items = const [];
    loading = false;
    saving = false;
    failure = null;
    notice = null;
    _pending = null;
    _notify();
    if (current && _visible) unawaited(refresh());
  }

  void setVisible(bool visible) {
    if (_disposed || visible == _visible) return;
    _visible = visible;
    _loadEpoch++;
    loading = false;
    if (!visible) {
      items = const [];
      notice = null;
      _notify();
    } else {
      _notify();
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (!_visible || !current || loading || saving) return;
    final epoch = _epoch, load = ++_loadEpoch, pair = pairId!;
    loading = true;
    _notify();
    try {
      final next = await repository.list(pair);
      if (!_accepts(epoch) || load != _loadEpoch || !_visible) return;
      if (next.length > 500 ||
          next.any((wish) => wish.pairId != pair) ||
          next.map((wish) => wish.id).toSet().length != next.length) {
        throw const WishFailure('invalid_response');
      }
      items = List.unmodifiable(next);
      if (_pending == null) failure = null;
    } on WishFailure catch (error) {
      if (_accepts(epoch) && load == _loadEpoch) _recordFailure(error);
    } catch (_) {
      if (_accepts(epoch) && load == _loadEpoch) {
        _recordFailure(const WishFailure('unavailable'));
      }
    } finally {
      if (!_disposed && epoch == _epoch && load == _loadEpoch) {
        loading = false;
        _notify();
      }
    }
  }

  Future<SharedWish?> create(WishDraft draft) async {
    if (!_ready()) return null;
    try {
      draft.toJson();
    } on WishFailure catch (error) {
      _recordFailure(error);
      return null;
    }
    return (await _run(_WishCommand.create(pairId!, draft)))?.wish;
  }

  Future<SharedWish?> like(SharedWish wish, bool liked) async {
    if (!_ready(wish) || !wish.isIdea) return null;
    return (await _run(_WishCommand.forWish('like', wish, liked: liked)))?.wish;
  }

  Future<SharedWish?> plan(
    SharedWish wish,
    DateTime startsAt, {
    DateTime? endsAt,
  }) async {
    if (!_ready(wish)) return null;
    if (!wish.canPlan) {
      _recordFailure(
        WishFailure(wish.isIdea ? 'mutual_like_required' : 'conflict'),
      );
      return null;
    }
    if (endsAt != null && !endsAt.isAfter(startsAt)) {
      _recordFailure(const WishFailure('invalid_dates'));
      return null;
    }
    return (await _run(
      _WishCommand.forWish(
        'plan',
        wish,
        startsAt: startsAt.toUtc(),
        endsAt: endsAt?.toUtc(),
      ),
    ))?.wish;
  }

  Future<SharedWish?> complete(SharedWish wish) async {
    if (!_ready(wish)) return null;
    if (!wish.canComplete) {
      _recordFailure(const WishFailure('conflict'));
      return null;
    }
    return (await _run(_WishCommand.forWish('complete', wish)))?.wish;
  }

  Future<bool> delete(SharedWish wish) async {
    if (!_ready(wish)) return false;
    if (wish.creatorId != actorId) {
      _recordFailure(const WishFailure('creator_only'));
      return false;
    }
    return (await _run(_WishCommand.forWish('delete', wish)))?.deleted == true;
  }

  /// A command retains its exact original payload and UUID until the server
  /// confirms its outcome. In particular a second tap cannot replace an unknown
  /// create or plan with a different command and accidentally duplicate it.
  Future<bool> retry() async {
    final command = _pending;
    if (!current || !_visible || saving || command == null) return false;
    return await _run(command, retry: true) != null;
  }

  bool _ready([SharedWish? wish]) {
    if (!current ||
        !_visible ||
        saving ||
        failure?.code == 'feature_unavailable') {
      return false;
    }
    if (_pending != null) {
      notice = const WishFailure('pending_command').message;
      _notify();
      return false;
    }
    return wish == null || wish.pairId == pairId;
  }

  bool _accepts(int epoch) => current && epoch == _epoch;

  Future<_WishResult?> _run(_WishCommand command, {bool retry = false}) async {
    final epoch = _epoch;
    _pending = command;
    _loadEpoch++;
    loading = false;
    saving = true;
    failure = null;
    notice = null;
    _notify();
    try {
      final result = await command.execute(repository);
      if (!_accepts(epoch) || !identical(_pending, command)) return null;
      if (result.wish != null && result.wish!.pairId != pairId) {
        throw const WishFailure('invalid_response', outcomeUnknown: true);
      }
      _pending = null;
      if (_visible) {
        if (result.deleted) {
          items = List.unmodifiable(
            items.where((wish) => wish.id != command.wish!.id),
          );
        } else {
          final wish = result.wish!;
          final previous = items.where((row) => row.id == wish.id).firstOrNull;
          // A partner's newer snapshot wins over a replayed command response.
          if (previous == null || previous.version <= wish.version) {
            items = List.unmodifiable(
              [
                for (final row in items)
                  if (row.id != wish.id) row,
                wish,
              ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
            );
          }
        }
        if (retry) notice = 'Өмнөх өөрчлөлтийг баталгаажууллаа.';
      }
      return result;
    } on WishFailure catch (error) {
      if (_accepts(epoch) && identical(_pending, command)) {
        if (!error.needsRetry) _pending = null;
        _recordFailure(error);
        if (!error.invalidatesScope && !error.needsRetry) {
          notice = error.message;
        }
      }
      return null;
    } catch (_) {
      if (_accepts(epoch) && identical(_pending, command)) {
        _recordFailure(const WishFailure('unavailable', outcomeUnknown: true));
      }
      return null;
    } finally {
      if (!_disposed && epoch == _epoch) {
        saving = false;
        _notify();
        // A replay may describe a prior version. Read the live state after a
        // confirmed response, including conflicts and deleted linked events.
        if (_pending == null && current && _visible) unawaited(refresh());
      }
    }
  }

  void _recordFailure(WishFailure error) {
    if (error.invalidatesScope) bind(null);
    failure = error;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _loadEpoch++;
    pairId = null;
    items = const [];
    _pending = null;
    failure = null;
    notice = null;
    loading = false;
    saving = false;
    unawaited(_changes.cancel());
    unawaited(repository.dispose());
    super.dispose();
  }
}

final class _WishCommand {
  _WishCommand.create(this.pairId, this.draft)
    : operation = 'create',
      id = const Uuid().v4(),
      wish = null,
      liked = null,
      startsAt = null,
      endsAt = null;
  _WishCommand.forWish(
    this.operation,
    SharedWish value, {
    this.liked,
    this.startsAt,
    this.endsAt,
  }) : id = const Uuid().v4(),
       pairId = value.pairId,
       wish = value,
       draft = null;

  final String operation, id, pairId;
  final SharedWish? wish;
  final WishDraft? draft;
  final bool? liked;
  final DateTime? startsAt, endsAt;

  Future<_WishResult> execute(WishRepository repository) async {
    switch (operation) {
      case 'create':
        return _WishResult(wish: await repository.create(pairId, id, draft!));
      case 'like':
        return _WishResult(wish: await repository.like(wish!, id, liked!));
      case 'plan':
        return _WishResult(
          wish: await repository.plan(wish!, id, startsAt!, endsAt: endsAt),
        );
      case 'complete':
        return _WishResult(wish: await repository.complete(wish!, id));
      case 'delete':
        await repository.delete(wish!, id);
        return const _WishResult(deleted: true);
      default:
        throw StateError('Unknown wish command');
    }
  }
}

final class _WishResult {
  const _WishResult({this.wish, this.deleted = false});
  final SharedWish? wish;
  final bool deleted;
}
