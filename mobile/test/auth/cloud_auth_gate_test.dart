import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/auth/auth_models.dart';
import 'package:hamtdaa/auth/auth_repository.dart';
import 'package:hamtdaa/account/account_deletion.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/auth/auth_screen.dart';
import 'package:hamtdaa/main_supabase_legacy.dart';

const _a = AuthSession.signedIn(userId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', email: 'a@example.com', epoch: 1);
const _b = AuthSession.signedIn(userId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', email: 'b@example.com', epoch: 1);

class _Auth implements AuthRepository {
  _Auth([this.current = const AuthSession.signedOut()]);
  final events = StreamController<AuthSession>.broadcast();
  bool failSignOut = false;
  @override
  AuthSession current;
  @override
  Stream<AuthSession> get sessions => events.stream;
  void emit(AuthSession value) { current = value; events.add(value); }
  @override
  Future<void> requestEmailCode(String email) async => emit(AuthSession.awaitingCode(email));
  @override
  Future<AuthSession> verifyEmailCode(String email, String code) async {
    emit(_a);
    return _a;
  }
  @override
  Future<void> signOut() async {
    if (failSignOut) throw const AuthFailure('network', 'Холболтоо шалгана уу.');
    emit(const AuthSession.signedOut());
  }
}

class _DeferredStore implements AppStore {
  final readResult = Completer<AppData>();
  @override
  Future<AppData> read() => readResult.future;
  @override
  Future<void> write(AppData data) async {}
}

Widget _gate(_Auth auth, AppStore Function(AccountScope) store, {Widget Function(AppController)? builder}) => CloudAuthGate(
  documentsDirectory: Directory.systemTemp,
  repository: auth,
  storeFactory: store,
  appBuilder: builder ?? (controller) => Scaffold(body: Text(controller.data.profile.name)),
);

void main() {
  testWidgets('interrupted deletion never opens content and resumes after retry', (tester) async {
    final auth = _Auth(_a);
    var resumes = 0, stores = 0;
    await tester.pumpWidget(CloudAuthGate(
      documentsDirectory: Directory.systemTemp, repository: auth,
      accountInitializer: (_) async => throw const AccountDeletionPending(),
      storeFactory: (_) { stores++; return MemoryAppStore(); },
      appBuilder: (_) => const Text('Private data'),
      onResumeAccountDeletion: (scope) async {
        expect(scope.userId, _a.userId);
        if (++resumes == 1) throw StateError('offline');
        await auth.signOut();
      },
    ));
    await tester.pumpAndSettle();
    expect(stores, 0);
    expect(find.text('Бүртгэлийн устгалыг үргэлжлүүлье'), findsOneWidget);
    await tester.tap(find.text('Устгал үргэлжлүүлэх'));
    await tester.pumpAndSettle();
    expect(find.text('Устгал дуусаагүй байна. Холболтоо шалгаад дахин оролдоорой.'), findsOneWidget);
    await tester.tap(find.text('Устгал үргэлжлүүлэх'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(resumes, 2); expect(stores, 0);
    await tester.pumpWidget(const SizedBox()); await auth.events.close();
  });

  testWidgets('late deletion failure cannot replace the new account screen', (tester) async {
    final auth = _Auth(_a);
    final pending = Completer<void>();
    await tester.pumpWidget(CloudAuthGate(
      documentsDirectory: Directory.systemTemp, repository: auth,
      accountInitializer: (scope) async { if (scope.userId == _a.userId) throw const AccountDeletionPending(); },
      storeFactory: (_) => MemoryAppStore(),
      appBuilder: (_) => const Scaffold(body:Text('Account B')),
      onResumeAccountDeletion: (_) => pending.future,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Устгал үргэлжлүүлэх')); await tester.pump();
    auth.emit(_b); await tester.pumpAndSettle();
    pending.completeError(StateError('old request')); await tester.pumpAndSettle();
    expect(find.text('Account B'), findsOneWidget);
    expect(find.text('Устгал үргэлжлүүлэх'), findsNothing);
    await tester.pumpWidget(const SizedBox()); await auth.events.close();
  });

  testWidgets('account status signout reports failure then returns to OTP', (tester) async {
    final auth = _Auth(_a)..failSignOut = true;
    await tester.pumpWidget(_gate(auth, (_) => MemoryAppStore(), builder: (controller) => AppShell(controller: controller, session: auth.current, onSignOut: auth.signOut)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Бид'));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('accountSignOutButton'));
    await tester.scrollUntilVisible(button, 300, scrollable: find.descendant(of: find.byType(IndexedStack), matching: find.byType(Scrollable)).last);
    await tester.pumpAndSettle();
    expect(find.text('a@example.com'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Холболтоо шалгана уу.'), findsOneWidget);
    expect(find.byType(AuthScreen), findsNothing);
    auth.failSignOut = false;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('a@example.com'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await auth.events.close();
  });

  testWidgets('OTP entry survives awaiting-code events and login loads once', (tester) async {
    final auth = _Auth();
    var reads = 0;
    await tester.pumpWidget(_gate(auth, (_) { reads++; return MemoryAppStore(AppData(profile: const UserProfile(name: 'Account A'))); }));
    await tester.enterText(find.byType(TextField).first, 'a@example.com');
    await tester.tap(find.text('Код авах'));
    await tester.pumpAndSettle();
    expect(find.text('6 оронтой код'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '123456');
    auth.emit(const AuthSession.awaitingCode('a@example.com'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, '123456');
    await tester.tap(find.text('Нэвтрэх'));
    await tester.pumpAndSettle();
    expect(find.text('Account A'), findsOneWidget);
    expect(reads, 1);
    auth.emit(_a);
    await tester.pumpAndSettle();
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox());
    await auth.events.close();
  });

  testWidgets('signed-in load failure stays signed in and can retry', (tester) async {
    final auth = _Auth(_a);
    final failed = _DeferredStore();
    var attempts = 0;
    await tester.pumpWidget(_gate(auth, (_) => ++attempts == 1 ? failed : MemoryAppStore(AppData(profile: const UserProfile(name: 'Recovered')))));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AuthScreen), findsNothing);
    failed.readResult.completeError(const FormatException('corrupt snapshot'));
    await tester.pumpAndSettle();
    expect(find.text('Мэдээллийг нээж чадсангүй'), findsOneWidget);
    expect(find.byType(AuthScreen), findsNothing);
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await auth.events.close();
  });

  testWidgets('account switch drops late reads and clears nested private routes', (tester) async {
    final auth = _Auth(_a);
    final lateA = _DeferredStore();
    var aLoads = 0;
    await tester.pumpWidget(_gate(auth, (scope) {
      if (scope.userId == _a.userId && aLoads++ == 0) return lateA;
      return MemoryAppStore(AppData(profile: UserProfile(name: scope.userId == _a.userId ? 'A' : 'B')));
    }, builder: (controller) => Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Private detail')))),
      child: Text(controller.data.profile.name),
    )))));
    await tester.pump();
    auth.emit(_b);
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    lateA.readResult.complete(AppData(profile: const UserProfile(name: 'Leaked A')));
    await tester.pumpAndSettle();
    expect(find.text('Leaked A'), findsNothing);
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(find.text('Private detail'), findsOneWidget);
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Private detail'), findsNothing);
    expect(find.byType(AuthScreen), findsOneWidget);
    auth.emit(_a);
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await auth.events.close();
  });
}
