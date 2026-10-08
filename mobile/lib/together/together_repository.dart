import 'dart:async';

import '../cloudflare/cloudflare_auth_repository.dart';
import 'together_models.dart';

abstract interface class TogetherRepository {
  String get actorId;
  bool get isCurrent;
  Stream<void> get invalidations;
  Future<TogetherSnapshot> state(String month);
  Future<void> mutate(TogetherCommand command);
  Future<TogetherHistory> history({String? beforeDay});
  Future<void> dispose();
}

class CloudflareTogetherRepository implements TogetherRepository {
  CloudflareTogetherRepository(this._auth) : _credential = _auth.credential {
    _changes = _auth.sessions.listen((_) { if (!isCurrent) _invalidate(); });
  }
  final CloudflareAuthRepository _auth;
  final CloudflareCredential? _credential;
  late final StreamSubscription<dynamic> _changes;
  final _events = StreamController<void>.broadcast(sync: true);
  bool _valid = true, _disposed = false;
  @override
  String get actorId => _credential?.scope.userId ?? '';
  @override
  bool get isCurrent => !_disposed && _valid && _credential != null && _auth.accepts(_credential);
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
      throw const TogetherFailure('unauthenticated');
    }
  }
  Future<Map<String, dynamic>> _call(String path, Map<String, dynamic> body) async {
    _check();
    try {
      final response = await _auth.transport.send('POST', '/v1/together/$path',
        token: _credential!.token, body: body);
      _check();
      if (response.status == 401) {
        _invalidate();
        try { await _auth.reject(_credential); } catch (_) { /* Already closed. */ }
        throw const TogetherFailure('unauthenticated');
      }
      if (response.status < 200 || response.status >= 300 || response.body['ok'] != true) {
        throw TogetherFailure(response.body['code'] is String ? response.body['code'] as String : 'invalid_response',
          retryable: response.status >= 500 || response.body['retryable'] == true);
      }
      return response.body;
    } on TogetherFailure { rethrow; }
    catch (_) {
      _check();
      throw const TogetherFailure('network_error', retryable: true);
    }
  }
  @override
  Future<TogetherSnapshot> state(String month) async {
    try {
      return await _pagedState(month);
    } on TogetherFailure catch (error) {
      if (error.code != 'calendar_changed') rethrow;
      // A concurrent edit can move an event across pages. Restart once rather
      // than display a partial calendar; a second conflict waits for refresh.
      return _pagedState(month);
    }
  }

  Future<TogetherSnapshot> _pagedState(String month) async {
    final result = await _call('state', {'month': month});
    try { return TogetherSnapshot.fromJson(result); }
    catch (_) { throw const TogetherFailure('invalid_response', retryable: true); }
  }
  @override
  Future<void> mutate(TogetherCommand command) async {
    await _call(command.path, command.body);
  }
  @override
  Future<TogetherHistory> history({String? beforeDay}) async {
    final result = await _call('daily/history', {if (beforeDay != null) 'before_day': beforeDay});
    try { return TogetherHistory.fromJson(result); }
    catch (_) { throw const TogetherFailure('invalid_response', retryable: true); }
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
