import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/pair/pair_controller.dart';
import 'package:hamtdaa/pair/pair_models.dart';

import 'pair_flow_test.dart' show FakePairRepository, invite, pair, snapshot;

void main() {
  testWidgets(
    'create acknowledgement supersedes a pre-create status read after resume',
    (tester) async {
      final repository = FakePairRepository();
      final controller = PairController(repository)..setForeground(true);
      try {
        await tester.pump();

        final acknowledged = Completer<Map<String, dynamic>>();
        repository.run = (_) => acknowledged.future;
        final creating = controller.createInvitation();
        controller.setForeground(false);

        final oldStatus = Completer<PairSnapshot>();
        repository.read = () => oldStatus.future;
        controller.setForeground(true);
        await tester.pump();
        expect(controller.loading, isTrue);

        final createdInvitation = invite(role: 'creator');
        repository.current = snapshot(invitations: [createdInvitation]);
        repository.read = null;
        acknowledged.complete({
          'ok': true,
          'invitation': {'id': createdInvitation.id},
        });
        await creating;
        expect(
          controller.snapshot?.invitations.single.id,
          createdInvitation.id,
        );
        expect(
          controller.tokenFor(createdInvitation),
          repository.commands.single.inviteToken,
        );

        // The earlier response was assembled before creation reached the server.
        // Receiving it late must not erase either the invitation or its code.
        oldStatus.complete(snapshot());
        await tester.pump();
        expect(
          controller.snapshot?.invitations.single.id,
          createdInvitation.id,
        );
        expect(
          controller.tokenFor(createdInvitation),
          repository.commands.single.inviteToken,
        );
      } finally {
        controller.dispose();
        repository.dispose();
      }
    },
  );

  testWidgets('foreground polling observes request and connection changes', (
    tester,
  ) async {
    final repository = FakePairRepository()
      ..current = snapshot(invitations: [invite(role: 'creator')]);
    final controller = PairController(repository)..setForeground(true);
    try {
      await tester.pump();
      expect(controller.snapshot?.invitations.single.isOpen, isTrue);

      repository.current = snapshot(
        invitations: [
          invite(role: 'creator', state: 'awaiting_creator', version: 2),
        ],
      );
      await tester.pump(const Duration(seconds: 10));
      expect(controller.snapshot?.invitations.single.isPending, isTrue);
      expect(repository.commands, isEmpty);

      controller.setForeground(false);
      expect(controller.snapshot, isNull);
      repository.current = snapshot(active: pair);
      await tester.pump(const Duration(seconds: 20));
      expect(controller.snapshot, isNull);
      controller.setForeground(true);
      await tester.pump();
      expect(controller.snapshot?.pair?.id, pair.id);
      expect(repository.commands, isEmpty);
    } finally {
      controller.dispose();
      repository.dispose();
    }
  });

  testWidgets(
    'resume and polling never replay uncertain consent automatically',
    (tester) async {
      final repository = FakePairRepository();
      final controller = PairController(repository)..setForeground(true);
      try {
        await tester.pump();
        await controller.previewToken(PairCommand.create().inviteToken!);
        repository.run = (_) async =>
            throw const PairFailure('network_error', retryable: true);
        await controller.requestPair();
        expect(repository.commands, hasLength(1));
        expect(controller.canRetry, isTrue);
        controller.setForeground(false);
        expect(controller.canRetry, isFalse);
        controller.setForeground(true);
        await tester.pump(const Duration(seconds: 20));
        expect(repository.commands, hasLength(1));
        expect(controller.canRetry, isTrue);
        expect(controller.canAct, isFalse);
      } finally {
        controller.dispose();
        repository.dispose();
      }
    },
  );
}
