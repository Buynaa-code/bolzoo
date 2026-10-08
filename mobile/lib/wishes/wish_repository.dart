import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cloudflare/cloudflare_auth_repository.dart';
import '../memories/memory_repository.dart';
import 'wish_models.dart';

abstract interface class WishRepository {
  bool get isCurrent;
  String get actorId;
  Stream<void> get invalidations;
  Future<List<SharedWish>> list(String pairId);
  Future<SharedWish> create(String pairId, String commandId, WishDraft draft);
  Future<SharedWish> like(SharedWish wish, String commandId, bool liked);
  Future<SharedWish> plan(
    SharedWish wish,
    String commandId,
    DateTime startsAt, {
    DateTime? endsAt,
  });
  Future<SharedWish> complete(SharedWish wish, String commandId);
  Future<void> delete(SharedWish wish, String commandId);
  Future<WishExport> exportData(String pairId);
  Future<void> dispose();
}

/// One repository is pinned to one exact authenticated session, including fresh
/// logins to the same account. Its bearer never follows a redirect.
class CloudflareWishRepository implements WishRepository {
  CloudflareWishRepository(
    this.auth, {
    Uri? baseUri,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 35),
  }) : _credential = auth.credential,
       _client = client ?? http.Client(),
       _requestTimeout = requestTimeout,
       baseUri = baseUri ?? endpointFor(auth) {
    if (this.baseUri.scheme != 'https' ||
        this.baseUri.host.isEmpty ||
        this.baseUri.userInfo.isNotEmpty ||
        this.baseUri.hasQuery ||
        this.baseUri.hasFragment ||
        (this.baseUri.path.isNotEmpty && this.baseUri.path != '/')) {
      throw ArgumentError('Invalid wishes origin');
    }
    _subscription = auth.sessions.listen((_) {
      if (!isCurrent && !_disposed) {
        _abortRequests();
        _events.add(null);
      }
    });
  }

  static Uri endpointFor(CloudflareAuthRepository auth) =>
      CloudflareMemoryRepository.endpointFor(auth);

  final CloudflareAuthRepository auth;
  final CloudflareCredential? _credential;
  final http.Client _client;
  final Duration _requestTimeout;
  final Uri baseUri;
  final _events = StreamController<void>.broadcast(sync: true);
  final _pending = <Completer<void>>{};
  late final StreamSubscription<dynamic> _subscription;
  bool _disposed = false;

  @override
  bool get isCurrent =>
      !_disposed && _credential != null && auth.accepts(_credential);
  @override
  String get actorId => _credential?.scope.userId ?? '';
  @override
  Stream<void> get invalidations => _events.stream;

  void _check() {
    if (!isCurrent) throw const WishFailure('unauthenticated');
  }

  void _abortRequests() {
    for (final abort in _pending) {
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<Map<String, dynamic>> _json(
    String operation,
    Map<String, dynamic> body, {
    bool mutation = false,
    int maxBytes = 4 * 1024 * 1024,
  }) async {
    _check();
    final abort = Completer<void>();
    _pending.add(abort);
    try {
      return await (() async {
        final request = http.AbortableRequest(
          'POST',
          baseUri.resolve('/v1/wishes/$operation'),
          abortTrigger: abort.future,
        )..followRedirects = false;
        request.headers.addAll({
          'Authorization': 'Bearer ${_credential!.token}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        });
        request.body = jsonEncode(body);
        final response = await _client.send(request);
        _check();
        if (response.statusCode == 401) {
          await auth.reject(_credential);
          throw const WishFailure('unauthenticated');
        }
        if (response.statusCode == 404 &&
            const {'list', 'create', 'export'}.contains(operation)) {
          throw const WishFailure('feature_unavailable');
        }
        if ((response.contentLength ?? 0) > maxBytes) {
          throw WishFailure('invalid_response', outcomeUnknown: mutation);
        }
        final bytes = <int>[];
        await for (final part in response.stream) {
          if (bytes.length + part.length > maxBytes) {
            throw WishFailure('invalid_response', outcomeUnknown: mutation);
          }
          bytes.addAll(part);
        }
        _check();
        final contentType = response.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase();
        if (contentType != 'application/json') {
          throw WishFailure('invalid_response', outcomeUnknown: mutation);
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) {
          throw WishFailure('invalid_response', outcomeUnknown: mutation);
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final code = decoded['code'];
          throw WishFailure(
            code is String ? code : 'unavailable',
            outcomeUnknown:
                mutation &&
                (response.statusCode >= 500 || response.statusCode < 400),
          );
        }
        if (decoded['ok'] != true) {
          throw WishFailure('invalid_response', outcomeUnknown: mutation);
        }
        return decoded;
      })().timeout(_requestTimeout);
    } on WishFailure {
      rethrow;
    } on FormatException {
      _check();
      throw WishFailure('invalid_response', outcomeUnknown: mutation);
    } catch (_) {
      _check();
      throw WishFailure('unavailable', outcomeUnknown: mutation);
    } finally {
      _pending.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }
  }

  @override
  Future<List<SharedWish>> list(String pairId) async {
    final value = await _json('list', {'expected_pair_id': pairId});
    try {
      if (value['pair_id'] != pairId || value['wishes'] is! List) {
        throw const FormatException();
      }
      final rows = value['wishes'] as List;
      if (rows.length > 500) throw const FormatException();
      final wishes = rows
          .map(
            (row) => SharedWish.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
      if (wishes.any((wish) => wish.pairId != pairId) ||
          wishes.map((wish) => wish.id).toSet().length != wishes.length) {
        throw const FormatException();
      }
      _check();
      return List.unmodifiable(wishes);
    } on WishFailure {
      rethrow;
    } catch (_) {
      throw const WishFailure('invalid_response');
    }
  }

  SharedWish _wish(Map<String, dynamic> response, String pairId, {String? id}) {
    try {
      final wish = SharedWish.fromJson(
        Map<String, dynamic>.from(response['wish'] as Map),
      );
      if (wish.pairId != pairId || (id != null && wish.id != id)) {
        throw const FormatException();
      }
      _check();
      return wish;
    } on WishFailure {
      rethrow;
    } catch (_) {
      throw const WishFailure('invalid_response', outcomeUnknown: true);
    }
  }

  Map<String, dynamic> _command(SharedWish wish, String commandId) => {
    'expected_pair_id': wish.pairId,
    'command_id': commandId,
    'id': wish.id,
    'expected_version': wish.version,
  };

  @override
  Future<SharedWish> create(
    String pairId,
    String commandId,
    WishDraft draft,
  ) async {
    final value = await _json(
      'create',
      {'expected_pair_id': pairId, 'command_id': commandId, ...draft.toJson()},
      mutation: true,
      maxBytes: 64 * 1024,
    );
    final wish = _wish(value, pairId);
    if (wish.creatorId != actorId) {
      throw const WishFailure('invalid_response', outcomeUnknown: true);
    }
    return wish;
  }

  @override
  Future<SharedWish> like(
    SharedWish wish,
    String commandId,
    bool liked,
  ) async => _wish(
    await _json(
      'like',
      {..._command(wish, commandId), 'liked': liked},
      mutation: true,
      maxBytes: 64 * 1024,
    ),
    wish.pairId,
    id: wish.id,
  );

  @override
  Future<SharedWish> plan(
    SharedWish wish,
    String commandId,
    DateTime startsAt, {
    DateTime? endsAt,
  }) async {
    final start = DateTime.fromMillisecondsSinceEpoch(
      startsAt.millisecondsSinceEpoch,
      isUtc: true,
    );
    final end = endsAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            endsAt.millisecondsSinceEpoch,
            isUtc: true,
          );
    if (start.year < 2000 ||
        start.year > 2099 ||
        (end != null &&
            (end.year < 2000 ||
                end.year > 2099 ||
                !end.isAfter(start) ||
                end.difference(start) > const Duration(days: 31)))) {
      throw const WishFailure('invalid_dates');
    }
    final value = await _json(
      'plan',
      {
        ..._command(wish, commandId),
        'starts_at': start.toIso8601String(),
        'ends_at': end?.toIso8601String(),
      },
      mutation: true,
      maxBytes: 64 * 1024,
    );
    final result = _wish(value, wish.pairId, id: wish.id);
    if (result.eventId == null || value['event_id'] != result.eventId) {
      throw const WishFailure('invalid_response', outcomeUnknown: true);
    }
    return result;
  }

  @override
  Future<SharedWish> complete(SharedWish wish, String commandId) async => _wish(
    await _json(
      'complete',
      _command(wish, commandId),
      mutation: true,
      maxBytes: 64 * 1024,
    ),
    wish.pairId,
    id: wish.id,
  );

  @override
  Future<void> delete(SharedWish wish, String commandId) async {
    if (wish.creatorId != actorId) throw const WishFailure('creator_only');
    final value = await _json(
      'delete',
      _command(wish, commandId),
      mutation: true,
      maxBytes: 64 * 1024,
    );
    if (value['deleted'] != true) {
      throw const WishFailure('invalid_response', outcomeUnknown: true);
    }
  }

  @override
  Future<WishExport> exportData(String pairId) async {
    final value = await _json('export', {'expected_pair_id': pairId});
    try {
      final result = WishExport.fromJson(
        value,
        pairId: pairId,
        actorId: actorId,
      );
      _check();
      return result;
    } on WishFailure {
      rethrow;
    } catch (_) {
      throw const WishFailure('invalid_response');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _abortRequests();
    _client.close();
    await _subscription.cancel();
    await _events.close();
  }
}
