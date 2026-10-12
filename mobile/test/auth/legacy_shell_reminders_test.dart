import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/auth/auth_models.dart';
import 'package:hamtdaa/content/content_repository.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/main_supabase_legacy.dart';
import 'package:hamtdaa/notifications/reminders.dart';
import 'package:hamtdaa/pair/pair_models.dart';
import 'package:hamtdaa/pair/pair_repository.dart';

final _when = DateTime.now().add(const Duration(days: 2));

DateEvent _event(String id, {bool shared = false, int minutes = 30}) =>
    DateEvent(
      id: id,
      title: 'Private $id',
      startsAt: _when,
      createdAt: _when.subtract(const Duration(days: 3)),
      shared: shared,
      reminderMinutes: minutes,
    );

class _Scheduler implements ReminderScheduler {
  final calls = <String>[];
  List<ReminderNotice> notices = [];
  Completer<void>? initialization;
  Completer<bool>? permissionCheck;
  bool permitted = true;
  int permissionRequests = 0;
  @override
  bool get supported => true;
  @override
  Future<void> initialize() async {
    calls.add('initialize');
    final gate = initialization;
    initialization = null;
    await gate?.future;
  }

  @override
  Future<bool> hasPermission() async =>
      await permissionCheck?.future ?? permitted;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permitted;
  }

  @override
  Future<void> clear() async {
    calls.add('clear');
    notices = [];
  }

  @override
  Future<void> syncNotices(List<ReminderNotice> value) async {
    calls.add('sync');
    notices = List.of(value);
  }
}

class _Repository implements ContentRepository {
  List<ContentItem> items = [];
  @override
  String get userId => 'owner';
  @override
  Future<List<ContentItem>> snapshot() async => items;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pairs implements PairRepository {
  final events = StreamController<void>.broadcast();
  final afterUnlink = Completer<PairSnapshot>();
  Completer<void>? acknowledgement;
  bool unlinked = false;
  VoidCallback? onUnlink;
  @override
  Stream<void> get invalidations => events.stream;
  PairSnapshot snapshot({bool paired = true}) => PairSnapshot(
    serverTime: _when,
    profile: const PairProfile(
      userId: 'owner',
      displayName: 'Owner',
      version: 1,
    ),
    invitations: const [],
    pair: paired
        ? const ActivePair(
            id: 'pair',
            version: 1,
            partner: PairPerson(userId: 'partner', displayName: 'Partner'),
          )
        : null,
  );
  @override
  Future<PairSnapshot> status() =>
      unlinked ? afterUnlink.future : Future.value(snapshot());
  @override
  Future<Map<String, dynamic>> execute(PairCommand command) async {
    expect(command.kind, PairCommandKind.unlink);
    await acknowledgement?.future;
    unlinked = true;
    onUnlink?.call();
    return {'ok': true};
  }

  @override
  void dispose() => unawaited(events.close());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ContentItem _item(
  String id, {
  String status = 'accepted',
  bool partner = false,
}) => ContentItem.fromJson({
  'id': id,
  'kind': 'event',
  'owner_id': partner ? 'partner' : 'owner',
  'owner_name': partner ? 'Partner' : 'Owner',
  'pair_id': 'pair',
  'role': partner ? 'partner' : 'owner',
  'state': 'active',
  'version': 1,
  'revision': 1,
  'updated_at': _when.toIso8601String(),
  'payload': {..._event(id, shared: true).toJson(), 'status': status},
});

Future<AppController> _controller(List<DateEvent> events) async {
  final value = AppController(MemoryAppStore(AppData(events: events)));
  await value.load();
  return value;
}

Widget _shell(
  AppController controller,
  _Scheduler scheduler, {
  ContentRepository? repository,
}) => MaterialApp(
  home: AppShell(
    controller: controller,
    reminderScheduler: scheduler,
    contentRepository: repository,
  ),
);

void main() {
  for (final background in [false, true]) {
    testWidgets(
      'profile unlink clears shared content and reminders before status finishes '
      '(background: $background)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = await _controller([_event('private')]);
        final scheduler = _Scheduler();
        final repository = _Repository()
          ..items = [_item('accepted'), _item('partner', partner: true)];
        final acknowledgement = Completer<void>();
        final pairs = _Pairs()
          ..acknowledgement = acknowledgement
          ..onUnlink = () => repository.items = [];
        await tester.pumpWidget(
          MaterialApp(
            home: AppShell(
              controller: controller,
              contentRepository: repository,
              reminderScheduler: scheduler,
              session: const AuthSession.signedIn(
                userId: 'owner',
                email: 'owner@example.com',
                epoch: 1,
              ),
              pairRepositoryFactory: () => pairs,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.isPartnerItem('partner'), isTrue);
        expect(scheduler.notices.map((notice) => notice.id).toSet(), {
          'private',
          'accepted',
        });
        await tester.tap(find.text('Бид'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('openPairScreen')),
          250,
          scrollable: find
              .descendant(
                of: find.byType(IndexedStack),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        await tester.tap(find.byKey(const Key('openPairScreen')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('pairUnlink')));
        await tester.tap(find.byKey(const Key('pairUnlink')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pairDialogConfirm')));
        await tester.pump();
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          expect(scheduler.notices.map((notice) => notice.id).toSet(), {
            'private',
            'accepted',
          });
        }
        acknowledgement.complete();
        await tester.pump(const Duration(milliseconds: 300));
        expect(pairs.unlinked, isTrue);
        expect(pairs.afterUnlink.isCompleted, isFalse);
        expect(
          controller.data.events.any((event) => event.id == 'partner'),
          isFalse,
        );
        expect(
          scheduler.notices.map((notice) => notice.id),
          background ? isEmpty : ['private'],
        );
        pairs.afterUnlink.complete(pairs.snapshot(paired: false));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        controller.dispose();
      },
    );
  }

  testWidgets(
    'legacy startup and saved opt-in sync silently and disposal clears',
    (tester) async {
      final controller = await _controller([
        _event('own'),
        _event('disabled', minutes: 0),
      ]);
      final scheduler = _Scheduler();
      await tester.pumpWidget(_shell(controller, scheduler));
      await tester.pumpAndSettle();
      expect(scheduler.permissionRequests, 0);
      expect(scheduler.notices.map((notice) => notice.id), ['own']);
      expect(
        scheduler.notices.single.at,
        _when.subtract(const Duration(minutes: 30)),
      );
      expect(scheduler.notices.single.body, isNot(contains('Private')));
      await controller.saveEvent(_event('another', minutes: 60));
      await tester.pumpAndSettle();
      expect(scheduler.notices.map((notice) => notice.id), ['own', 'another']);
      expect(scheduler.permissionRequests, 0);
      await tester.pumpWidget(const SizedBox());
      expect(scheduler.notices, isEmpty);
      expect(controller.onEventsChanged, isNull);
      controller.dispose();
    },
  );

  testWidgets('legacy shared reminders require own fresh accepted consent', (
    tester,
  ) async {
    final controller = await _controller([
      _event('private'),
      _event('stale', shared: true),
    ]);
    final scheduler = _Scheduler();
    final repository = _Repository()
      ..items = [
        _item('accepted'),
        _item('pending', status: 'pending'),
        _item('declined', status: 'declined'),
        _item('partner', partner: true),
      ];
    await tester.pumpWidget(
      _shell(controller, scheduler, repository: repository),
    );
    await tester.pumpAndSettle();
    expect(scheduler.notices.map((notice) => notice.id).toSet(), {
      'private',
      'accepted',
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(scheduler.notices.map((notice) => notice.id).toSet(), {
      'private',
      'accepted',
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    repository.items = [];
    controller.invalidateSharedContent();
    await tester.pumpAndSettle();
    expect(scheduler.notices.map((notice) => notice.id), ['private']);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'late old-shell initialization and callback cannot clear a new shell',
    (tester) async {
      final old = await _controller([_event('old')]);
      final next = await _controller([_event('new')]);
      final gate = Completer<void>();
      final scheduler = _Scheduler()..initialization = gate;
      await tester.pumpWidget(_shell(old, scheduler));
      await tester.pump();
      final staleCallback = old.onEventsChanged!;
      await tester.pumpWidget(_shell(next, scheduler));
      await tester.pumpAndSettle();
      expect(scheduler.notices.map((notice) => notice.id), ['new']);
      final calls = List<String>.of(scheduler.calls);
      gate.complete();
      await staleCallback([_event('old')]);
      await tester.pumpAndSettle();
      expect(scheduler.calls, calls);
      expect(scheduler.notices.map((notice) => notice.id), ['new']);
      await tester.pumpWidget(const SizedBox());
      old.dispose();
      next.dispose();
    },
  );

  testWidgets(
    'a pending permission lookup cannot schedule after shell disposal',
    (tester) async {
      final controller = await _controller([_event('old')]);
      final gate = Completer<bool>();
      final scheduler = _Scheduler()..permissionCheck = gate;
      await tester.pumpWidget(_shell(controller, scheduler));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      gate.complete(true);
      await tester.pumpAndSettle();
      expect(scheduler.notices, isEmpty);
      expect(scheduler.calls.where((call) => call == 'sync'), isEmpty);
      controller.dispose();
    },
  );
}
