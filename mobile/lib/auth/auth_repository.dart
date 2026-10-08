import 'auth_models.dart';

abstract interface class AuthRepository {
  AuthSession get current;
  Stream<AuthSession> get sessions;

  Future<void> requestEmailCode(String email);
  Future<AuthSession> verifyEmailCode(String email, String code);
  Future<void> signOut();
}
