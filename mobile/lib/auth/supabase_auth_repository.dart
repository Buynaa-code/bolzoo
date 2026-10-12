import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_models.dart';
import 'auth_repository.dart';

/// Supabase Auth adapter. The rest of the app depends only on AuthRepository,
/// so a local fake can be used in tests and offline development.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(SupabaseClient client)
    : this.withAuthClient(client.auth);

  SupabaseAuthRepository.withAuthClient(this._auth) {
    _applySupabaseSession(_auth.currentSession);
    _subscription = _auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.initialSession &&
            state.session == null &&
            _current.status == AuthStatus.awaitingCode) {
          return;
        }
        _applySupabaseSession(state.session);
      },
      onError: (Object _, StackTrace _) {
        _publish(
          _current.withMessage(
            'Нэвтрэлтийг шинэчилж чадсангүй. Интернэт холболтоо шалгана уу.',
          ),
        );
      },
    );
  }

  final GoTrueClient _auth;
  final _events = StreamController<AuthSession>.broadcast();
  late final StreamSubscription<AuthState> _subscription;
  AuthSession _current = const AuthSession.signedOut();
  int _epoch = 0;
  String? _identity;
  bool _closed = false;

  @override
  AuthSession get current => _current;

  @override
  Stream<AuthSession> get sessions => _events.stream;

  void _applySupabaseSession(Session? session) {
    if (_closed) return;
    final user = session?.user;
    if (_identity != user?.id) {
      _epoch++;
      _identity = user?.id;
    }
    _publish(
      user == null
          ? const AuthSession.signedOut()
          : AuthSession.signedIn(
              userId: user.id,
              email: user.email ?? '',
              epoch: _epoch,
            ),
    );
  }

  void _publish(AuthSession session) {
    if (_closed) return;
    if (_current.status == session.status &&
        _current.userId == session.userId &&
        _current.email == session.email &&
        _current.epoch == session.epoch &&
        _current.message == session.message) {
      return;
    }
    _current = session;
    _events.add(session);
  }

  @override
  Future<void> requestEmailCode(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!_validEmail(normalized)) {
      throw const AuthFailure('invalid_email', 'Зөв имэйл хаяг оруулна уу.');
    }
    try {
      await _auth.signInWithOtp(email: normalized, shouldCreateUser: true);
      if (!_current.isSignedIn) _publish(AuthSession.awaitingCode(normalized));
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
      final response = await _auth.verifyOTP(
        email: normalized,
        token: code.trim(),
        type: OtpType.email,
      );
      if (response.session == null) {
        throw const AuthFailure(
          'missing_user',
          'Нэвтрэлт баталгаажаагүй байна. Дахин оролдоно уу.',
        );
      }
      // The callback and verification response share one transition.
      _applySupabaseSession(response.session);
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
      await _auth.signOut(scope: SignOutScope.local);
      // A later login may complete while the old logout awaits its response.
      _applySupabaseSession(_auth.currentSession);
    } on AuthException catch (error) {
      throw AuthFailure(
        error.statusCode ?? 'sign_out_error',
        'Гарах үед алдаа гарлаа. Дахин оролдоно уу.',
        retryable: true,
      );
    } catch (_) {
      throw const AuthFailure(
        'sign_out_error',
        'Гарах үед алдаа гарлаа. Дахин оролдоно уу.',
        retryable: true,
      );
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
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
