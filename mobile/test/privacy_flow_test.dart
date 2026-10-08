import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/auth/auth_models.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/profile/privacy_screen.dart';
import 'package:hamtdaa/features/profile/profile_screen.dart';
import 'package:hamtdaa/ui/theme.dart';

Future<void> launch(
  WidgetTester tester, {
  bool cloud = true,
  Future<void> Function(BuildContext)? export,
  Future<void> Function()? delete,
  double width = 390,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: PrivacyScreen(
        isCloudAccount: cloud,
        onExportData: export,
        onDeleteAccount: delete,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> confirmDeletion(WidgetTester tester) async {
  await reveal(tester, 'deleteAccountButton');
  await tester.tap(find.byKey(const Key('deleteAccountButton')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('deleteAccountConfirmation')),
    'УСТГАХ',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('confirmAccountDeletion')));
  // Leave pending operations pending so tests can inspect single-flight state.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('profile opens accurate cloud privacy and forwards callbacks', (
    tester,
  ) async {
    final controller = AppController(MemoryAppStore());
    await controller.load();
    addTearDown(controller.dispose);
    var exports = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            controller: controller,
            session: const AuthSession.signedIn(
              userId: 'account-a',
              email: 'a@example.invalid',
              epoch: 1,
            ),
            onExportData: (_) async => exports++,
            onDeleteAccount: () async {},
          ),
        ),
      ),
    );
    await reveal(tester, 'openPrivacyScreen');
    await tester.tap(find.byKey(const Key('openPrivacyScreen')));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyScreen), findsOneWidget);
    expect(find.textContaining('Аппыг устгах нь бүртгэлийг устгахгүй.'), findsOneWidget);
    expect(find.text('Зөвхөн танд харагдана'), findsNothing);
    await reveal(tester, 'exportAccountData');
    await tester.tap(find.byKey(const Key('exportAccountData')));
    await tester.pumpAndSettle();
    expect(exports, 1);
  });

  testWidgets('local privacy has local copy and never exposes cloud deletion', (
    tester,
  ) async {
    var deletes = 0;
    await launch(tester, cloud: false, delete: () async => deletes++);
    expect(find.textContaining('Та төхөөрөмж дээрээ ашиглаж байна.'), findsOneWidget);
    await tester.drag(find.byKey(const Key('privacyList')), const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deleteAccountButton')), findsNothing);
    expect(deletes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unwired cloud account never offers a nonworking deletion action', (
    tester,
  ) async {
    await launch(tester);
    await tester.drag(find.byKey(const Key('privacyList')), const Offset(0, -2500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deleteAccountButton')), findsNothing);
    final export = tester.widget<OutlinedButton>(
      find.byKey(const Key('exportAccountData')),
    );
    expect(export.onPressed, isNull);
  });

  testWidgets('export guards double taps and retries a sanitized failure', (
    tester,
  ) async {
    var exports = 0;
    final pending = Completer<void>();
    await launch(
      tester,
      export: (_) async {
        exports++;
        if (exports == 1) await pending.future;
      },
      delete: () async {},
    );
    await reveal(tester, 'exportAccountData');
    final button = find.byKey(const Key('exportAccountData'));
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(exports, 1);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    pending.completeError(StateError('sensitive transport error'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sensitive'), findsNothing);
    expect(find.text('Дахин бэлтгэх'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(exports, 2);
    expect(find.text('Хуулбар бэлэн боллоо.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deletion requires exact confirmation and a final deliberate tap', (
    tester,
  ) async {
    var deletes = 0;
    await launch(tester, delete: () async => deletes++);
    await reveal(tester, 'deleteAccountButton');
    await tester.tap(find.byKey(const Key('deleteAccountButton')));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    final confirm = find.byKey(const Key('confirmAccountDeletion'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('deleteAccountConfirmation')),
      'устгах',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('deleteAccountConfirmation')),
      'УСТГАХ',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    expect(deletes, 0);
    await tester.tap(find.byKey(const Key('cancelAccountDeletion')));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await confirmDeletion(tester);
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(find.text('Бүртгэл устлаа'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('deleteAccountButton'))).onPressed, isNull);
  });

  testWidgets('pending deletion blocks duplicates and failed deletion can retry', (
    tester,
  ) async {
    final pending = Completer<void>();
    var deletes = 0;
    await launch(
      tester,
      delete: () async {
        deletes++;
        if (deletes == 1) await pending.future;
      },
    );
    await confirmDeletion(tester);
    expect(deletes, 1);
    final button = find.byKey(const Key('deleteAccountButton'));
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    await tester.tap(button);
    expect(deletes, 1);
    pending.completeError(StateError('private backend detail'));
    await tester.pumpAndSettle();
    expect(find.textContaining('баталгаажуулж чадсангүй'), findsOneWidget);
    expect(find.textContaining('private backend detail'), findsNothing);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
    await confirmDeletion(tester);
    await tester.pumpAndSettle();
    expect(deletes, 2);
    expect(find.text('Бүртгэл устлаа'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth reroute during deletion never uses a stale navigator', (
    tester,
  ) async {
    final pending = Completer<void>();
    await launch(tester, delete: () => pending.future);
    await confirmDeletion(tester);
    await tester.pumpWidget(const MaterialApp(home: Text('Нэвтрэх')));
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Нэвтрэх'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screen with large text retains all privacy and delete controls', (
    tester,
  ) async {
    await launch(tester, width: 320, scale: 1.6, delete: () async {});
    await reveal(tester, 'deleteAccountButton');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('deleteAccountButton')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('cancelAccountDeletion')));
    await tester.tap(find.byKey(const Key('cancelAccountDeletion')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
