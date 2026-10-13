import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/features/pair/pair_screen.dart';
import 'package:hamtdaa/pair/pair_models.dart';
import 'package:hamtdaa/pair/pair_repository.dart';

class _Repository implements PairRepository {
  final invalidated = StreamController<void>.broadcast();
  final previews = <String>[];
  final commands = <PairCommand>[];
  @override
  Stream<void> get invalidations => invalidated.stream;
  @override
  Future<PairSnapshot> status() async => PairSnapshot(
    serverTime: DateTime.utc(2026),
    profile: const PairProfile(
      userId: 'recipient',
      displayName: 'Recipient',
      version: 1,
    ),
    invitations: const [],
  );
  @override
  Future<PairInvitation> preview(String token) async {
    previews.add(token);
    return PairInvitation(
      id: 'invitation',
      version: 1,
      state: 'open',
      role: 'viewer',
      creator: const PairPerson(userId: 'sender', displayName: 'Sender'),
      expiresAt: DateTime.utc(2027),
    );
  }

  @override
  Future<Map<String, dynamic>> execute(PairCommand command) async {
    commands.add(command);
    return {'ok': true};
  }

  @override
  void dispose() => unawaited(invalidated.close());
}

Future<void> _open(WidgetTester tester, _Repository repository) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: PairScreen(repository: repository)),
  );
  await tester.pumpAndSettle();
}

Future<void> _pasteAndPreview(WidgetTester tester, String input) async {
  await tester.enterText(find.byKey(const Key('pairTokenField')), input);
  await tester.ensureVisible(find.byKey(const Key('pairPreview')));
  await tester.tap(find.byKey(const Key('pairPreview')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pasted outer whitespace does not truncate an invitation code', (
    tester,
  ) async {
    final repository = _Repository();
    final code = PairCommand.create().inviteToken!;
    await _open(tester, repository);
    await _pasteAndPreview(tester, '  \n$code\n  ');
    expect(repository.previews, [code]);
    expect(repository.commands, isEmpty);
    expect(find.byKey(const Key('pairRequest')), findsOneWidget);
    expect(find.byKey(const Key('pairPartnerName')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'an overlong paste is rejected rather than truncated into a valid code',
    (tester) async {
      final repository = _Repository();
      final code = PairCommand.create().inviteToken!;
      await _open(tester, repository);
      await _pasteAndPreview(tester, '${code}X');
      expect(repository.previews, isEmpty);
      expect(repository.commands, isEmpty);
      expect(find.byKey(const Key('pairRequest')), findsNothing);
      expect(
        find.text(const PairFailure('invalid_code_format').message),
        findsOneWidget,
      );
      await _pasteAndPreview(tester, code);
      expect(repository.previews, [code]);
      expect(repository.commands, isEmpty);
      expect(
        find.text(const PairFailure('invalid_code_format').message),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'malformed pasted codes remain rejected without network requests',
    (tester) async {
      final repository = _Repository();
      final code = PairCommand.create().inviteToken!;
      await _open(tester, repository);
      for (final input in [
        code.substring(1),
        '${code.substring(0, 42)}!',
        '${code.substring(0, 20)} ${code.substring(20)}',
        'https://example.com/invite/$code',
      ]) {
        await _pasteAndPreview(tester, input);
        expect(repository.previews, isEmpty);
        expect(repository.commands, isEmpty);
        expect(
          find.text(const PairFailure('invalid_code_format').message),
          findsOneWidget,
        );
        expect(find.byKey(const Key('pairRequest')), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
