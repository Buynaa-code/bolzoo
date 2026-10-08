import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/content/content_repository.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/calendar/calendar_screen.dart';
import 'package:hamtdaa/ui/components.dart';
import 'package:hamtdaa/ui/theme.dart';

class _ProposalRepository extends Fake implements ContentRepository {
  _ProposalRepository({required this.original, required this.proposed}) {
    item = record();
  }
  final DateTime original;
  final DateTime? proposed;
  late ContentItem item;
  final response = Completer<ContentItem>();
  int responses = 0;
  String? action;
  int? version;

  @override
  String get userId => 'owner';

  ContentItem record({bool accepted = false}) => ContentItem.fromJson({
    'id': 'proposed-event',
    'kind': 'event',
    'owner_id': 'owner',
    'owner_name': 'Ану',
    'pair_id': 'pair',
    'version': accepted ? 2 : 1,
    'revision': accepted ? 2 : 1,
    'state': 'active',
    'role': 'owner',
    'updated_at': DateTime.now().toIso8601String(),
    'payload': {
      'title': 'Хамт кофе уух',
      'startsAt': (accepted ? proposed! : original).toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'status': accepted ? 'accepted' : 'proposed',
      'proposedAt': accepted ? null : proposed?.toIso8601String(),
    },
  });

  @override
  Future<List<ContentItem>> snapshot() async => [item];

  @override
  Future<ContentItem> respond({
    required String commandId,
    required String id,
    required int expectedVersion,
    required String action,
    DateTime? proposedAt,
  }) async {
    responses++;
    this.action = action;
    version = expectedVersion;
    return item = await response.future;
  }
}

Future<void> _open(WidgetTester tester, AppController controller) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 844);
  tester.platformDispatcher.textScaleFactorTestValue = 1.6;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                openEventDetail(context, controller, 'proposed-event'),
            child: const Text('Нээх'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Нээх'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('eventProposalCard')),
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner sees the proposed day and time before server confirmation', (
    tester,
  ) async {
    final future = DateTime.now().add(const Duration(days: 2));
    final original = DateTime(future.year, future.month, future.day, 16);
    final proposed = original.add(const Duration(days: 3, hours: 3, minutes: 45));
    final repository = _ProposalRepository(original: original, proposed: proposed);
    final controller = AppController(MemoryAppStore());
    await controller.load();
    controller.connectCloud(repository);
    try {
      await _open(tester, controller);
      final displayed = tester.widget<Text>(find.byKey(const Key('eventProposedTime')));
      expect(
        displayed.data,
        '${proposed.year} · ${shortDate(proposed)} · ${clockText(proposed)}',
      );
      expect(controller.data.events.single.startsAt, original);
      expect(controller.consentState('proposed-event'), 'proposed');
      final accept = find.byKey(const Key('eventAcceptButton'));
      await tester.scrollUntilVisible(
        accept,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Санал болгосон цагийг зөвшөөрөх ♡'), findsOneWidget);
      await tester.tap(accept);
      await tester.pump();
      expect(repository.responses, 1);
      expect(repository.action, 'accept');
      expect(repository.version, 1);
      expect(controller.data.events.single.startsAt, original);
      expect(controller.consentState('proposed-event'), 'proposed');
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
      repository.response.complete(repository.record(accepted: true));
      await tester.pumpAndSettle();
      expect(controller.data.events.single.startsAt, proposed);
      expect(controller.consentState('proposed-event'), 'accepted');
      expect(find.byKey(const Key('eventProposalCard')), findsNothing);
      expect(find.text('Хоёулаа тохирсон ♡'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets('owner cannot confirm a proposal without a readable time', (
    tester,
  ) async {
    final repository = _ProposalRepository(
      original: DateTime.now().add(const Duration(days: 2)),
      proposed: null,
    );
    final controller = AppController(MemoryAppStore());
    await controller.load();
    controller.connectCloud(repository);
    try {
      await _open(tester, controller);
      expect(find.byKey(const Key('eventAcceptButton')), findsNothing);
      expect(
        find.text('Санал болгосон цагийг ачаалж чадсангүй. Дахин шинэчилнэ үү.'),
        findsOneWidget,
      );
      expect(repository.responses, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
}
