import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'memory_models.dart';
import 'memory_repository.dart';

class MemoryController extends ChangeNotifier {
  MemoryController(this.repository) {
    _changes = repository.invalidations.listen((_) => bind(null, null));
  }
  final MemoryRepository repository;
  late final StreamSubscription<void> _changes;
  String? pairId, month;
  List<SharedMemory> items = const [];
  final thumbnails = <String, Uint8List>{};
  String? error;
  MemoryFailure? failure;
  bool loading = false, saving = false, _disposed = false, _visible = true;
  int _epoch = 0, _loadEpoch = 0;
  String? _pendingSignature;
  final _deleteCommands = <String, String>{};
  String? _pendingCommand;
  bool get current => !_disposed && repository.isCurrent && pairId != null;
  List<SharedMemory> onDay(String day) =>
      items.where((m) => m.day == day).toList();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void bind(String? pair, String? value) {
    if (_disposed || (pair == pairId && value == month)) return;
    _epoch++;
    _loadEpoch++;
    pairId = pair;
    month = value;
    items = const [];
    thumbnails.clear();
    loading = false;
    saving = false;
    error = null;
    failure = null;
    _pendingSignature = null;
    _deleteCommands.clear();
    _pendingCommand = null;
    _notify();
    if (current && month != null) unawaited(refresh());
  }

  void setVisible(bool value) {
    _visible = value;
    if (!value) {
      _loadEpoch++;
      loading = false;
      items = const [];
      thumbnails.clear();
      _notify();
    }
  }

  Future<void> refresh() async {
    if (!_visible || !current || month == null || loading || saving) return;
    final scope = _epoch, load = ++_loadEpoch, pair = pairId!;
    loading = true;
    _notify();
    try {
      final next = await repository.list(pair, month!);
      if (!current || scope != _epoch || load != _loadEpoch) return;
      items = next;
      thumbnails.removeWhere((id, _) => !items.any((m) => m.id == id));
      error = null;
      failure = null;
      _notify();
      // Only one cover per day appears in the grid; serial fetches bound memory.
      final covers = <String, SharedMemory>{};
      for (final item in items) {
        covers.putIfAbsent(item.day, () => item);
      }
      for (final item in covers.values) {
        if (!current || scope != _epoch || load != _loadEpoch) return;
        if (thumbnails.containsKey(item.id)) continue;
        final bytes = await repository.photo(item, thumbnail: true);
        if (!current || scope != _epoch || load != _loadEpoch) return;
        if (bytes.length > 64 * 1024)
          throw const MemoryFailure('invalid_response');
        thumbnails[item.id] = bytes;
        _notify();
      }
    } on MemoryFailure catch (e) {
      if (scope == _epoch && load == _loadEpoch && !_disposed) {
        _recordFailure(e);
      }
    } finally {
      if (!_disposed && scope == _epoch && load == _loadEpoch) {
        loading = false;
        _notify();
      }
    }
  }

  Future<bool> save(MemoryDraft draft) async {
    if (!current || saving) return false;
    final epoch = _epoch, pair = pairId!;
    // A lost response can be retried safely with the same command and draft.
    final signature = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              draft.day,
              draft.title,
              draft.note,
              draft.sticker,
              sha256.convert(draft.image.photo).toString(),
              sha256.convert(draft.image.thumbnail).toString(),
            ]),
          ),
        )
        .toString();
    if (_pendingSignature != signature) {
      _pendingSignature = signature;
      _pendingCommand = const Uuid().v4();
    }
    _loadEpoch++;
    loading = false;
    saving = true;
    error = null;
    failure = null;
    _notify();
    try {
      await repository.create(pair, _pendingCommand!, draft);
      if (!current || epoch != _epoch) return false;
      _pendingSignature = null;
      _pendingCommand = null;
      saving = false;
      await refresh();
      return current && epoch == _epoch;
    } on MemoryFailure catch (e) {
      if (!_disposed && epoch == _epoch) {
        _recordFailure(e);
      }
      return false;
    } finally {
      if (!_disposed && epoch == _epoch) {
        saving = false;
        _notify();
      }
    }
  }

  Future<Uint8List> photo(SharedMemory memory) async {
    if (!current || memory.pairId != pairId)
      throw const MemoryFailure('pair_changed');
    final epoch = _epoch;
    try {
      final bytes = await repository.photo(memory);
      if (!current || epoch != _epoch)
        throw const MemoryFailure('pair_changed');
      return bytes;
    } on MemoryFailure catch (e) {
      if (!_disposed && epoch == _epoch) _recordFailure(e);
      rethrow;
    }
  }

  Future<bool> delete(SharedMemory memory) async {
    if (!current ||
        saving ||
        memory.pairId != pairId ||
        memory.creatorId != repository.actorId)
      return false;
    final epoch = _epoch;
    _loadEpoch++;
    loading = false;
    saving = true;
    error = null;
    failure = null;
    _notify();
    try {
      final key = '${memory.id}:${memory.version}';
      final command = _deleteCommands.putIfAbsent(key, () => const Uuid().v4());
      await repository.delete(memory, command);
      if (!current || epoch != _epoch) return false;
      items = items.where((m) => m.id != memory.id).toList();
      thumbnails.remove(memory.id);
      _deleteCommands.remove(key);
      return true;
    } on MemoryFailure catch (e) {
      if (!_disposed && epoch == _epoch) _recordFailure(e);
      return false;
    } finally {
      if (!_disposed && epoch == _epoch) {
        saving = false;
        _notify();
      }
    }
  }

  void _recordFailure(MemoryFailure value) {
    if ([
      'unauthenticated',
      'pair_changed',
      'pair_required',
      'forbidden',
    ].contains(value.code)) {
      bind(null, null);
    }
    error = value.message;
    failure = value;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    items = const [];
    thumbnails.clear();
    unawaited(_changes.cancel());
    unawaited(repository.dispose());
    super.dispose();
  }
}
