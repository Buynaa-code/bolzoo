import 'dart:async';
import '../cloudflare/cloudflare_auth_repository.dart';
import 'flower_models.dart';

abstract interface class FlowersRepository {
  String get actorId;
  bool get isCurrent;
  Stream<void> get invalidations;
  Future<FlowersSnapshot> state();
  Future<String> send(FlowerCommand command);
  Future<void> dispose();
}

class CloudflareFlowersRepository implements FlowersRepository {
  CloudflareFlowersRepository(this._auth) : _credential = _auth.credential {
    _changes = _auth.sessions.listen((_) {
      if (!isCurrent) _invalidate();
    });
  }
  final CloudflareAuthRepository _auth;
  final CloudflareCredential? _credential;
  late final StreamSubscription<dynamic> _changes;
  final _events = StreamController<void>.broadcast(sync: true);
  bool _valid = true, _disposed = false;
  @override
  String get actorId => _credential?.scope.userId ?? '';
  @override
  bool get isCurrent =>
      !_disposed && _valid && _credential != null && _auth.accepts(_credential);
  @override
  Stream<void> get invalidations => _events.stream;
  void _invalidate() {
    if (_disposed || !_valid) return;
    _valid = false;
    _events.add(null);
  }

  void _check() {
    if (!isCurrent) {
      _invalidate();
      throw const FlowerFailure('unauthenticated');
    }
  }

  Future<Map<String, dynamic>> _call(
    String path,
    Map<String, dynamic> body,
  ) async {
    _check();
    try {
      final result = await _auth.transport.send(
        'POST',
        '/v1/gifts/$path',
        token: _credential!.token,
        body: body,
      );
      _check();
      if (result.status == 401) {
        _invalidate();
        try {
          await _auth.reject(_credential);
        } catch (_) {
          /* Already closed. */
        }
        throw const FlowerFailure('unauthenticated');
      }
      if (result.status < 200 ||
          result.status >= 300 ||
          result.body['ok'] != true) {
        throw FlowerFailure(
          result.body['code'] is String
              ? result.body['code'] as String
              : 'invalid_response',
          retryable: result.status >= 500 || result.body['retryable'] == true,
        );
      }
      return result.body;
    } on FlowerFailure {
      rethrow;
    } catch (_) {
      _check();
      throw const FlowerFailure('network_error', retryable: true);
    }
  }

  @override
  Future<FlowersSnapshot> state() async {
    try {
      return await _pagedState();
    } on FlowerFailure catch (error) {
      if (error.code != 'gifts_changed') rethrow;
      // Restart once when a concurrent send/delete changes the snapshot. Never
      // combine old cards with a later page or retry an endlessly changing list.
      return _pagedState();
    }
  }

  Future<FlowersSnapshot> _pagedState() async {
    FlowersSnapshot? first;
    final gifts = <DigitalFlower>[];
    final ids = <String>{}, cursors = <String>{};
    String? cursor;
    do {
      final result = await _call('state', {'cursor': ?cursor});
      try {
        final page = FlowersSnapshot.fromJson(result, actorId);
        if (first != null &&
            (page.pairId != first.pairId ||
                page.partnerId != first.partnerId ||
                page.paired != first.paired)) {
          throw const FlowerFailure('pair_changed');
        }
        first ??= page;
        for (final gift in page.gifts) {
          if (!ids.add(gift.id)) throw const FormatException();
          gifts.add(gift);
        }
        final next = result['next_cursor'];
        if (next != null &&
            (next is! String ||
                next.isEmpty ||
                !page.paired ||
                page.gifts.isEmpty ||
                !cursors.add(next))) {
          throw const FormatException();
        }
        if (gifts.length > 500 || cursors.length > 500) {
          throw const FormatException();
        }
        cursor = next as String?;
      } on FlowerFailure {
        rethrow;
      } catch (_) {
        throw const FlowerFailure('invalid_response', retryable: true);
      }
    } while (cursor != null);
    return FlowersSnapshot(
      paired: first.paired,
      pairId: first.pairId,
      partnerId: first.partnerId,
      partnerName: first.partnerName,
      gifts: List.unmodifiable(gifts),
    );
  }

  @override
  Future<String> send(FlowerCommand command) async {
    final result = await _call('send', command.body);
    final id = result['id'];
    if (id is! String || id.isEmpty) {
      throw const FlowerFailure('invalid_response', retryable: true);
    }
    return id;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _valid = false;
    await _changes.cancel();
    await _events.close();
  }
}
