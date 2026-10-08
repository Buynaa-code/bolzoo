import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/auth/auth_models.dart';
import 'package:hamtdaa/auth/auth_repository.dart';
import 'package:hamtdaa/features/auth/auth_screen.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth({bool synchronousEvents = false})
    : _events = StreamController<AuthSession>.broadcast(
        sync: synchronousEvents,
      );
  final StreamController<AuthSession> _events;
  AuthSession _current = const AuthSession.signedOut();
  int sends = 0;
  final sentEmails = <String>[];
  Completer<void>? sendGate;
  Completer<void>? verifyGate;

  @override
  AuthSession get current => _current;

  @override
  Stream<AuthSession> get sessions => _events.stream;

  @override
  Future<void> requestEmailCode(String email) async {
    sends++;
    sentEmails.add(email);
    await sendGate?.future;
  }

  @override
  Future<AuthSession> verifyEmailCode(String email, String code) async {
    await verifyGate?.future;
    _current = AuthSession.signedIn(
      userId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      email: email,
      epoch: 1,
    );
    _events.add(_current);
    return _current;
  }

  @override
  Future<void> signOut() async {}

  Future<void> dispose() => _events.close();
}

void main() {
  testWidgets('email OTP screen moves from request to verify', (tester) async {
    final auth = _FakeAuth();
    AuthSession? signedIn;
    var callbackCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          repository: auth,
          onSignedIn: (session) {
            signedIn = session;
            callbackCount++;
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'a@example.com');
    await tester.tap(find.text('Код авах'));
    await tester.pump();
    expect(find.text('6 оронтой код'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Нэвтрэх'));
    await tester.pump();
    expect(signedIn?.userId, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    expect(callbackCount, 1);
    await tester.pumpWidget(const SizedBox());
    await auth.dispose();
  });

  testWidgets(
    'resend is disabled for 60 seconds and email change clears code',
    (tester) async {
      final auth = _FakeAuth();
      await tester.pumpWidget(MaterialApp(home: AuthScreen(repository: auth)));
      await tester.enterText(find.byType(TextField).first, 'a@example.com');
      await tester.tap(find.text('Код авах'));
      await tester.pump();
      expect(auth.sends, 1);
      await tester.enterText(find.byType(TextField).last, '123456');
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Дахин илгээх · 60 сек'),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 59));
      expect(auth.sends, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Код дахин илгээх'));
      await tester.pump();
      expect(auth.sends, 2);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      await tester.tap(find.text('Имэйлээ өөрчлөх'));
      await tester.pump();
      expect(find.text('6 оронтой код'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await auth.dispose();
    },
  );

  testWidgets('duplicate send taps and late response after disposal are safe', (
    tester,
  ) async {
    final auth = _FakeAuth()..sendGate = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: AuthScreen(repository: auth)));
    await tester.enterText(find.byType(TextField).first, 'a@example.com');
    await tester.tap(find.text('Код авах'));
    await tester.tap(find.text('Код авах'));
    expect(auth.sends, 1);
    await tester.pumpWidget(const SizedBox());
    auth.sendGate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await auth.dispose();
  });

  testWidgets(
    'synchronous auth events and verify result deliver one callback',
    (tester) async {
      final auth = _FakeAuth(synchronousEvents: true);
      var callbacks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AuthScreen(repository: auth, onSignedIn: (_) => callbacks++),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'a@example.com');
      await tester.tap(find.text('Код авах'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.tap(find.text('Нэвтрэх'));
      await tester.pump();
      expect(callbacks, 1);
      await tester.pumpWidget(const SizedBox());
      await auth.dispose();
    },
  );

  testWidgets(
    'editing email clears its challenge and preserves address cooldown',
    (tester) async {
      final auth = _FakeAuth();
      await tester.pumpWidget(MaterialApp(home: AuthScreen(repository: auth)));
      await tester.enterText(find.byType(TextField).first, ' A@Example.COM ');
      await tester.tap(find.text('Код авах'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.enterText(find.byType(TextField).first, 'b@example.com');
      await tester.pump();
      expect(find.text('6 оронтой код'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );

      await tester.tap(find.text('Код авах'));
      await tester.pump();
      expect(auth.sentEmails, ['a@example.com', 'b@example.com']);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );

      await tester.enterText(find.byType(TextField).first, 'a@example.com');
      await tester.pump();
      expect(find.text('6 оронтой код'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 60));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(auth.sends, 2);
      await tester.pumpWidget(const SizedBox());
      await auth.dispose();
    },
  );

  testWidgets(
    'old email response cannot repaint or unlock a newer pending send',
    (tester) async {
      final first = Completer<void>();
      final second = Completer<void>();
      final auth = _FakeAuth()..sendGate = first;
      await tester.pumpWidget(MaterialApp(home: AuthScreen(repository: auth)));
      await tester.enterText(find.byType(TextField).first, 'a@example.com');
      await tester.tap(find.text('Код авах'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

      // Also protect programmatic/autofill changes while a request is pending.
      tester.widget<TextField>(find.byType(TextField)).controller!.text =
          'b@example.com';
      await tester.pump();
      auth.sendGate = second;
      await tester.tap(find.text('Код авах'));
      await tester.pump();
      first.complete();
      await tester.pump();
      expect(find.text('6 оронтой код'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      second.complete();
      await tester.pump();
      expect(find.text('6 оронтой код'), findsOneWidget);
      expect(auth.sentEmails, ['a@example.com', 'b@example.com']);
      expect(find.text('Дахин илгээх · 60 сек'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 61));
      expect(tester.takeException(), isNull);
      await auth.dispose();
    },
  );

  testWidgets('old email error does not attach to the new address', (
    tester,
  ) async {
    final gate = Completer<void>();
    final auth = _FakeAuth()..sendGate = gate;
    await tester.pumpWidget(MaterialApp(home: AuthScreen(repository: auth)));
    await tester.enterText(find.byType(TextField).first, 'a@example.com');
    await tester.tap(find.text('Код авах'));
    await tester.pump();
    tester.widget<TextField>(find.byType(TextField)).controller!.text =
        'b@example.com';
    await tester.pump();
    gate.completeError(const AuthFailure('network_error', 'Old email error'));
    await tester.pump();
    expect(find.text('Old email error'), findsNothing);
    expect(find.text('6 оронтой код'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    await auth.dispose();
  });

  testWidgets('obsolete verification does not deliver a screen callback', (
    tester,
  ) async {
    final gate = Completer<void>();
    final auth = _FakeAuth(synchronousEvents: true)..verifyGate = gate;
    var callbacks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(repository: auth, onSignedIn: (_) => callbacks++),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'a@example.com');
    await tester.tap(find.text('Код авах'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Нэвтрэх'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      isFalse,
    );
    tester.widget<TextField>(find.byType(TextField).first).controller!.text =
        'b@example.com';
    await tester.pump();
    gate.complete();
    await tester.pump();
    expect(callbacks, 0);
    expect(find.text('6 оронтой код'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await auth.dispose();
  });
}
