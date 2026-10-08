import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_models.dart';
import 'auth_repository.dart';

/// Supabase Auth adapter. The rest of the app depends only on AuthRepository,
/// so a local fake can be used in tests and offline development.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client) {
    _current = _fromSupabaseSession(_client.auth.currentSession);
    _subscription = _client.auth.onAuthStateChange.listen((state) {
      _current = _fromSupabaseSession(state.session);
      _events.add(_current);
    });
  }

  final SupabaseClient _client;
  final StreamController<AuthSession> _events =
      StreamController<AuthSession>.broadcast();
  late final StreamSubscription<AuthState> _subscription;
  late AuthSession _current;
  int _epoch = 0;

  @override
  AuthSession get current => _current;

  @override
  Stream<AuthSession> get sessions => _events.stream;

  AuthSession _fromSupabaseSession(Session? session) {
    final user = session?.user;
    if (user == null) {
      return const AuthSession.signedOut();
    }
    final email = user.email;
    if (email == null || email.isEmpty) {
      return AuthSession.signedIn(
        userId: user.id,
        email: '',
        epoch: _epoch,
      );
    }
    return AuthSession.signedIn(
      userId: user.id,
      email: email,
      epoch: _epoch,
    );
  }

  @override
  Future<void> requestEmailCode(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!_validEmail(normalized)) {
      throw const AuthFailure(
        'invalid_email',
        'Зөв имэйл хаяг оруулна уу.',
      );
    }
    try {
      await _client.auth.signInWithOtp(
        email: normalized,
        shouldCreateUser: true,
      );
      _current = AuthSession.awaitingCode(normalized);
      _events.add(_current);
    } on AuthException catch (error) {
      throw AuthFailure(
        error.statusCode ?? 'auth_error',
        _friendlyMessage(error.message),
        retryable: true,
      );
    } catch (_) {
      throw const AuthFailure(
        'network_error',
        'Сүлжээний алдаа гарлаа. Дахин оролдоно уу.',
        retryable: true,
      );
    }
  }

  @override
  Future<AuthSession> verifyEmailCode(String email, String code) async {
    final normalized = email.trim().toLowerCase();
    if (!_validEmail(normalized) || !RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw const AuthFailure('invalid_code', '6 оронтой код оруулна уу.');
    }
    try {
      final response = await _client.auth.verifyOTP(
        email: normalized,
        token: code.trim(),
        type: OtpType.email,
      );
      final user = response.user;
      if (user == null) {
        throw const AuthFailure(
          'missing_user',
          'Нэвтрэлт баталгаажаагүй байна. Дахин оролдоно уу.',
        );
      }
      _epoch++;
      _current = AuthSession.signedIn(
        userId: user.id,
        email: user.email ?? normalized,
        epoch: _epoch,
      );
      _events.add(_current);
      return _current;
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      throw AuthFailure(
        error.statusCode ?? 'invalid_code',
        _friendlyMessage(error.message),
        retryable: false,
      );
    } catch (_) {
      throw const AuthFailure(
        'network_error',
        'Сүлжээний алдаа гарлаа. Дахин оролдоно уу.',
        retryable: true,
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
      _epoch++;
      _current = const AuthSession.signedOut();
      _events.add(_current);
    } on AuthException catch (error) {
      throw AuthFailure(
        error.statusCode ?? 'sign_out_error',
        'Гарах үед алдаа гарлаа. Дахин оролдоно уу.',
        retryable: true,
      );
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _events.close();
  }

  static bool _validEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  static String _friendlyMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('expired') || lower.contains('invalid')) {
      return 'Код буруу эсвэл хугацаа нь дууссан байна.';
    }
    if (lower.contains('rate limit')) {
      return 'Хэт олон удаа хүсэлт илгээлээ. Түр хүлээгээд дахин оролдоно уу.';
    }
    return 'Нэвтрэх үед алдаа гарлаа. Дахин оролдоно уу.';
  }
}
