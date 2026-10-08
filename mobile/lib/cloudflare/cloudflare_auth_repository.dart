import 'dart:async';
import 'dart:convert';

import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import 'cloudflare_session_storage.dart';
import 'cloudflare_transport.dart';

class CloudflareCredential {
  const CloudflareCredential({
    required this.token,
    required this.scope,
    required this.expiresAt,
  });
  final String token;
  final AccountScope scope;
  final DateTime expiresAt;
}

class CloudflareAuthRepository implements AuthRepository {
  CloudflareAuthRepository({
    required this.transport,
    required CloudflareSessionStorage storage,
    DateTime Function()? now,
  }) : _storage = storage,
       _now = now ?? DateTime.now;

  final CloudflareTransport transport;
  final CloudflareSessionStorage _storage;
  final DateTime Function() _now;
  final _events = StreamController<AuthSession>.broadcast(sync: true);
  AuthSession _current = const AuthSession.signedOut();
  CloudflareCredential? _credential;
  Timer? _expiry;
  int _generation = 0;
  int _epoch = 0;
  bool _disposed = false;
  Future<void> _storagePending = Future.value();

  @override
  AuthSession get current => _current;
  @override
  Stream<AuthSession> get sessions => _events.stream;

  CloudflareCredential? get credential {
    final value = _credential;
    if (value == null || !value.expiresAt.isAfter(_now())) return null;
    return value;
  }

  bool accepts(CloudflareCredential value) =>
      !_disposed && identical(credential, value) && _current.isSignedIn;

  Future<T> _storageOperation<T>(Future<T> Function() operation) {
    final result = _storagePending.then((_) => operation());
    _storagePending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _check(int generation) {
    if (!_isCurrent(generation)) {
      throw const AuthFailure('session_changed', 'Нэвтрэлтийн төлөв өөрчлөгдсөн байна.');
    }
  }

  void _publish(AuthSession session) {
    if (_disposed) return;
    _current = session;
    _events.add(session);
  }

  /// A saved bearer is never sufficient to open an account. Server validation
  /// must succeed; transient failures retain the key and keep onboarding closed.
  Future<void> initialize() async {
    final generation = ++_generation;
    final stored = await _storageOperation(_storage.read);
    _check(generation);
    if (stored == null) return;
    String token;
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      token = json['token'] as String;
      final expires = DateTime.parse(json['expires_at'] as String);
      if (token.isEmpty || !expires.isAfter(_now())) {
        await _forget(generation);
        return;
      }
    } catch (_) {
      await _forget(generation);
      return;
    }
    try {
      final response = await transport.send('GET', '/v1/auth/session', token: token);
      _check(generation);
      if (response.status == 401) {
        await _forget(generation);
        return;
      }
      _requireSuccess(response);
      await _install(response.body, token, generation);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('network_error', 'Нэвтрэлтийг шалгаж чадсангүй. Дахин оролдоорой.', retryable: true);
    }
  }

  @override
  Future<void> requestEmailCode(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!_validEmail(normalized)) {
      throw const AuthFailure('invalid_email', 'Зөв имэйл хаяг оруулна уу.');
    }
    final generation = ++_generation;
    try {
      final response = await transport.send('POST', '/v1/auth/request-code', body: {'email': normalized});
      _check(generation);
      _requireSuccess(response);
      if (!_current.isSignedIn) _publish(AuthSession.awaitingCode(normalized));
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('network_error', 'Код илгээж чадсангүй. Дахин оролдоорой.', retryable: true);
    }
  }

  @override
  Future<AuthSession> verifyEmailCode(String email, String code) async {
    final normalized = email.trim().toLowerCase();
    if (!_validEmail(normalized) || !RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw const AuthFailure('invalid_code', '6 оронтой код оруулна уу.');
    }
    final generation = ++_generation;
    String? issuedToken;
    try {
      final response = await transport.send('POST', '/v1/auth/verify-code', body: {'email': normalized, 'code': code.trim()});
      if (response.body['token'] is String) issuedToken = response.body['token'] as String;
      _check(generation);
      _requireSuccess(response);
      if (issuedToken == null || issuedToken.isEmpty) throw const FormatException();
      final user = response.body['user'];
      if (user is! Map || user['email'] != normalized) throw const FormatException();
      await _install(response.body, issuedToken, generation);
      return _current;
    } catch (error) {
      // Even an obsolete login can have created a server session. Revoke that
      // exact bearer, never a newer account's credential.
      if (issuedToken != null && _credential?.token != issuedToken) {
        unawaited(_revokeQuietly(issuedToken));
      }
      if (error is AuthFailure) rethrow;
      throw const AuthFailure('network_error', 'Нэвтэрч чадсангүй. Дахин оролдоорой.', retryable: true);
    }
  }

  Future<void> _install(Map<String, dynamic> body, String token, int generation) async {
    final user = body['user'] as Map<String, dynamic>;
    final id = user['id'] as String;
    final email = user['email'] as String;
    final expires = DateTime.parse(body['expires_at'] as String);
    if (id.isEmpty || !_validEmail(email) || !expires.isAfter(_now())) throw const FormatException();
    _check(generation);
    await _storageOperation(() async {
      _check(generation);
      await _storage.write(jsonEncode({'token': token, 'expires_at': expires.toUtc().toIso8601String()}));
    });
    _check(generation);
    _expiry?.cancel();
    final session = AuthSession.signedIn(userId: id, email: email, epoch: ++_epoch);
    final next = CloudflareCredential(token: token, scope: session.scope, expiresAt: expires);
    _credential = next;
    _expiry = Timer(expires.difference(_now()), () {
      if (identical(_credential, next)) unawaited(reject(next));
    });
    _publish(session);
  }

  Future<void> _forget(int generation) async {
    _check(generation);
    _credential = null;
    _expiry?.cancel();
    _publish(const AuthSession.signedOut());
    await _storageOperation(() async {
      // A newer login queues its write after this clear.
      if (_isCurrent(generation)) await _storage.clear();
    });
  }

  /// Called only for a server rejection of a pinned bearer, not arbitrary 403s.
  Future<void> reject(CloudflareCredential rejected) async {
    if (!identical(_credential, rejected) || _disposed) return;
    await _forget(++_generation);
  }

  @override
  Future<void> signOut() async {
    final previous = _credential;
    final generation = ++_generation;
    await _forget(generation);
    if (previous == null) return;
    try {
      final response = await transport.send('POST', '/v1/auth/sign-out', token: previous.token);
      if (response.status != 401) _requireSuccess(response);
    } catch (_) {
      // Local access is already removed. This message does not claim the
      // unreachable server confirmed revocation of the old session.
      throw const AuthFailure('sign_out_error', 'Утаснаас гарлаа. Серверийн холболт тасарсан тул гаралтыг баталгаажуулж чадсангүй.', retryable: true);
    }
  }

  Future<void> _revokeQuietly(String token) async {
    try { await transport.send('POST', '/v1/auth/sign-out', token: token); } catch (_) { /* Local access was never granted. */ }
  }

  static void _requireSuccess(CloudflareResponse response) {
    if (response.status >= 200 && response.status < 300 && response.body['ok'] != false) return;
    final code = response.body['code'] is String ? response.body['code'] as String : 'auth_error';
    final message = switch (code) {
      'rate_limited' => 'Хэт олон хүсэлт илгээлээ. Түр хүлээгээд дахин оролдоорой.',
      'invalid_code' || 'expired' || 'invalid_otp' => 'Код буруу эсвэл хугацаа нь дууссан байна.',
      _ => 'Нэвтрэлтийг баталгаажуулж чадсангүй. Дахин оролдоорой.',
    };
    throw AuthFailure(code, message, retryable: response.body['retryable'] == true || response.status >= 500);
  }

  static bool _validEmail(String value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _expiry?.cancel();
    _credential = null;
    await _events.close();
  }
}
