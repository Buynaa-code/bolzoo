import 'package:flutter/foundation.dart';

/// The only identity a cloud-backed repository may use for record ownership.
@immutable
class AccountScope {
  const AccountScope({required this.userId, required this.epoch});

  final String userId;
  final int epoch;

  @override
  bool operator ==(Object other) =>
      other is AccountScope && other.userId == userId && other.epoch == epoch;

  @override
  int get hashCode => Object.hash(userId, epoch);
}

enum AuthStatus { signedOut, sendingCode, awaitingCode, signedIn, signingOut }

@immutable
class AuthSession {
  const AuthSession._({
    required this.status,
    this.userId,
    this.email,
    this.epoch = 0,
    this.message,
  });

  const AuthSession.signedOut() : this._(status: AuthStatus.signedOut);

  const AuthSession.sendingCode(String email)
    : this._(status: AuthStatus.sendingCode, email: email);

  const AuthSession.awaitingCode(String email)
    : this._(status: AuthStatus.awaitingCode, email: email);

  const AuthSession.signedIn({
    required String userId,
    required String email,
    required int epoch,
  }) : this._(
         status: AuthStatus.signedIn,
         userId: userId,
         email: email,
         epoch: epoch,
       );

  final AuthStatus status;
  final String? userId;
  final String? email;
  final int epoch;
  final String? message;

  bool get isSignedIn => status == AuthStatus.signedIn && userId != null;

  AccountScope get scope {
    final id = userId;
    if (!isSignedIn || id == null) {
      throw StateError('A signed-in session is required.');
    }
    return AccountScope(userId: id, epoch: epoch);
  }

  AuthSession withMessage(String? value) => AuthSession._(
    status: status,
    userId: userId,
    email: email,
    epoch: epoch,
    message: value,
  );
}

class AuthFailure implements Exception {
  const AuthFailure(this.code, this.message, {this.retryable = false});

  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => 'AuthFailure($code): $message';
}
