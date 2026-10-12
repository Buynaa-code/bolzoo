import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/features/pair/pair_screen.dart';
import 'package:hamtdaa/pair/pair_controller.dart';
import 'package:hamtdaa/pair/pair_models.dart';
import 'package:hamtdaa/pair/pair_repository.dart';
import 'package:hamtdaa/pair/supabase_pair_repository.dart';
import 'package:hamtdaa/ui/theme.dart';

const a = PairPerson(userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', displayName: 'Ану');
const b = PairPerson(userId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', displayName: 'Болд');
const pair = ActivePair(id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', version: 1, partner: b);
PairInvitation invite({String role = 'viewer', String state = 'open', int version = 1}) => PairInvitation(
  id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', version: version, role: role,
  state: state, creator: a, requester: state == 'open' ? null : b,
  expiresAt: DateTime.utc(2027),
);
PairSnapshot snapshot({ActivePair? active, List<PairInvitation> invitations = const []}) => PairSnapshot(
  serverTime: DateTime.utc(2026, 9, 25),
  profile: PairProfile(userId: a.userId, displayName: a.displayName, version: 1),
  pair: active, invitations: invitations,
);

class FakePairRepository implements PairRepository {
  final events = StreamController<void>.broadcast(sync: true);
  PairSnapshot current = snapshot();
  Future<PairSnapshot> Function()? read;
  Future<Map<String, dynamic>> Function(PairCommand)? run;
  final commands = <PairCommand>[];
  int previews = 0;
  bool disposed = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<PairSnapshot> status() => read?.call() ?? Future.value(current);
  @override
  Future<PairInvitation> preview(String token) async { previews++; return invite(); }
  @override
  Future<Map<String, dynamic>> execute(PairCommand command) async {
    commands.add(command);
    return await run?.call(command) ?? {'ok': true};
  }
  @override
  void dispose() { disposed = true; unawaited(events.close()); }
}

void main() {
  test('invite secrets have 256 random bits and only hash is sent on create', () {
    final first = PairCommand.create();
    final second = PairCommand.create();
    expect(base64Url.decode(base64Url.normalize(first.inviteToken!)), hasLength(32));
    expect(first.inviteToken, isNot(second.inviteToken));
    expect(first.parameters['p_token_hash'], sha256.convert(utf8.encode(first.inviteToken!)).toString());
    expect(first.parameters.containsKey('p_token'), isFalse);
    expect(first.parameters['p_command_id'], matches(RegExp(r'^[0-9a-f-]{14}4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(() => first.parameters['p_token_hash'] = 'other', throwsUnsupportedError);
  });

  testWidgets('preview creates no consent and request carries the viewed version', (tester) async {
    final repo = FakePairRepository();
    final controller = PairController(repo)..setForeground(true);
    await tester.pump();
    await controller.previewToken(PairCommand.create().inviteToken!);
    expect(repo.commands, isEmpty);
    expect(controller.preview?.creator.displayName, 'Ану');
    repo.run = (_) async {
      repo.current = snapshot(invitations: [invite(role: 'requester', state: 'awaiting_creator', version: 2)]);
      return {'ok': true};
    };
    await controller.requestPair();
    expect(repo.commands.single.kind, PairCommandKind.request);
    expect(repo.commands.single.parameters['p_expected_version'], 1);
    expect(controller.snapshot?.pair, isNull);
    expect(controller.snapshot?.invitations.single.isPending, isTrue);
    controller.dispose(); repo.dispose();
  });

  testWidgets('uncertain mutation retries identical command and blocks duplicate taps', (tester) async {
    final repo = FakePairRepository();
    final controller = PairController(repo)..setForeground(true);
    await tester.pump();
    final gate = Completer<Map<String, dynamic>>();
    repo.run = (_) => gate.future;
    final first = controller.createInvitation();
    await controller.createInvitation();
    expect(repo.commands, hasLength(1));
    gate.completeError(const PairFailure('network_error', retryable: true));
    await first;
    expect(controller.snapshot, isNull);
    expect(controller.canRetry, isTrue);
    repo.run = (_) async {
      repo.current = snapshot(invitations: [invite(role: 'creator')]);
      return {'ok': true, 'invitation': {'id': invite().id}};
    };
    await controller.retry();
    expect(repo.commands, hasLength(2));
    expect(identical(repo.commands[0], repo.commands[1]), isTrue);
    expect(controller.tokenFor(repo.current.invitations.single), repo.commands.first.inviteToken);
    controller.dispose(); repo.dispose();
  });

  testWidgets('background and account invalidation clear projections and ignore stale reads', (tester) async {
    final repo = FakePairRepository()..current = snapshot(active: pair);
    final controller = PairController(repo)..setForeground(true);
    await tester.pump();
    expect(controller.snapshot?.pair?.partner.displayName, 'Болд');
    controller.setForeground(false);
    expect(controller.snapshot, isNull);
    final late = Completer<PairSnapshot>();
    repo.read = () => late.future;
    controller.setForeground(true);
    repo.events.add(null);
    late.complete(snapshot(active: pair));
    await tester.pump();
    expect(controller.snapshot, isNull);
    expect(controller.authorized, isFalse);
    controller.dispose(); repo.dispose();
  });

  testWidgets('conflict is preserved after status reconciliation', (tester) async {
    final repo = FakePairRepository()..current = snapshot(active: pair);
    final controller = PairController(repo)..setForeground(true);
    await tester.pump();
    repo.run = (_) async => throw const PairFailure('conflict');
    await controller.unlink(pair);
    expect(controller.failure?.code, 'conflict');
    expect(controller.snapshot?.pair, isNotNull);
    expect(controller.canRetry, isFalse);
    controller.dispose(); repo.dispose();
  });

  testWidgets('acknowledged unlink clears pairing before status reconciliation', (tester) async {
    final repo = FakePairRepository()..current = snapshot(active: pair);
    final controller = PairController(repo)..setForeground(true);
    await tester.pump();
    expect(controller.snapshot?.pair?.id, pair.id);
    final status = Completer<PairSnapshot>();
    final observed = <PairSnapshot?>[];
    controller.addListener(() => observed.add(controller.snapshot));
    repo.run = (_) async {
      repo.read = () => status.future;
      return {'ok': true};
    };
    final unlink = controller.unlink(pair);
    await tester.pump();
    expect(controller.snapshot, isNull);
    expect(observed.last, isNull);
    expect(controller.canAct, isFalse);
    expect(status.isCompleted, isFalse);
    status.complete(snapshot());
    await unlink;
    expect(controller.snapshot, isNotNull);
    expect(controller.snapshot?.pair, isNull);
    controller.dispose(); repo.dispose();
  });

  test('repository rejects a late response after account switch', () async {
    var active = true;
    final response = Completer<dynamic>();
    final repo = SupabasePairRepository.withTransport(
      rpc: (_, _) => response.future, sessionCurrent: () => active, accountId: a.userId,
    );
    final result = repo.status();
    active = false;
    response.complete({'ok': true});
    await expectLater(result, throwsA(isA<PairFailure>().having((e) => e.code, 'code', 'unauthenticated')));
    repo.dispose();
  });

  testWidgets('creator must explicitly confirm the named requester', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakePairRepository()..current = snapshot(invitations: [invite(role: 'creator', state: 'awaiting_creator', version: 2)]);
    repo.run = (_) async { repo.current = snapshot(active: pair); return {'ok': true}; };
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), navigatorObservers: [pairRouteObserver], home: PairScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(repo.commands, isEmpty);
    await tester.ensureVisible(find.byKey(const Key('pairConfirm')));
    await tester.tap(find.byKey(const Key('pairConfirm')));
    await tester.pumpAndSettle();
    expect(find.text('Болд-тай холбогдох уу?'), findsOneWidget);
    expect(repo.commands, isEmpty);
    await tester.tap(find.byKey(const Key('pairDialogConfirm')));
    await tester.pumpAndSettle();
    expect(repo.commands.single.kind, PairCommandKind.confirm);
    expect(repo.commands.single.parameters['p_expected_version'], 2);
    expect(find.byKey(const Key('pairPartnerName')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(repo.disposed, isTrue);
  });

  testWidgets('recipient preview requires a separate request button', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakePairRepository();
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), navigatorObservers: [pairRouteObserver], home: PairScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pairTokenField')), PairCommand.create().inviteToken!);
    await tester.ensureVisible(find.byKey(const Key('pairPreview')));
    await tester.tap(find.byKey(const Key('pairPreview')));
    await tester.pumpAndSettle();
    expect(repo.previews, 1);
    expect(repo.commands, isEmpty);
    expect(find.byKey(const Key('pairRequest')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'pair owner hears an acknowledged unlink while the app is backgrounded',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakePairRepository()..current = snapshot(active: pair);
      final changes = <PairSnapshot?>[];
      final acknowledgement = Completer<Map<String, dynamic>>();
      repo.run = (_) => acknowledgement.future;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          navigatorObservers: [pairRouteObserver],
          home: PairScreen(repository: repo, onPairChanged: changes.add),
        ),
      );
      await tester.pumpAndSettle();
      expect(changes.single?.pair?.id, pair.id);
      await tester.ensureVisible(find.byKey(const Key('pairUnlink')));
      await tester.tap(find.byKey(const Key('pairUnlink')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pairDialogConfirm')));
      await tester.pump();
      expect(repo.commands.single.kind, PairCommandKind.unlink);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(changes, hasLength(1));

      acknowledgement.complete({'ok': true});
      await tester.pump();
      expect(changes, hasLength(2));
      expect(changes.last, isNull);

      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );

  testWidgets(
    'pair owner hears unlink and invalidation without repeated refresh callbacks',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakePairRepository()..current = snapshot(active: pair);
      final changes = <PairSnapshot?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          navigatorObservers: [pairRouteObserver],
          home: PairScreen(repository: repo, onPairChanged: changes.add),
        ),
      );
      await tester.pumpAndSettle();
      expect(changes, hasLength(1));
      expect(changes.single?.pair?.id, pair.id);

      await tester.tap(find.byKey(const Key('pairRefresh')));
      await tester.pumpAndSettle();
      expect(changes, hasLength(1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(changes, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(changes, hasLength(1));

      repo.run = (command) async {
        expect(command.kind, PairCommandKind.unlink);
        repo.current = snapshot();
        return {'ok': true};
      };
      await tester.ensureVisible(find.byKey(const Key('pairUnlink')));
      await tester.tap(find.byKey(const Key('pairUnlink')));
      await tester.pumpAndSettle();
      expect(changes, hasLength(1));
      await tester.tap(find.byKey(const Key('pairDialogConfirm')));
      await tester.pumpAndSettle();
      expect(changes, hasLength(3));
      expect(changes[1], isNull);
      expect(changes.last, isNotNull);
      expect(changes.last?.pair, isNull);

      repo.events.add(null);
      expect(changes, hasLength(4));
      expect(changes.last, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
