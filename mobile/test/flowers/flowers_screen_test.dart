import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/flowers/flower_controller.dart';
import 'package:hamtdaa/flowers/flower_models.dart';
import 'package:hamtdaa/flowers/flowers_screen.dart';
import 'package:hamtdaa/ui/theme.dart';
import '../together/together_fakes.dart';
import 'flower_fakes.dart';

void main() {
  late FakeFlowersRepository repository;
  late FlowersController controller;
  late CloudflareAuthRepository auth;
  setUp(() {
    repository = FakeFlowersRepository();
    controller = FlowersController(repository);
    auth = CloudflareAuthRepository(
      transport: TogetherTransport(),
      storage: TogetherStorage(),
    );
  });
  tearDown(() async {
    controller.dispose();
    await auth.dispose();
  });
  Future<void> open(WidgetTester tester, {VoidCallback? onPair}) async {
    tester.view.physicalSize = const Size(430, 940);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: FlowersScreen(auth: auth, controller: controller, onPair: onPair),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.setVisible(false);
  }

  Future<void> preview(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('flowersCompose')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('flowersMessage')),
      'Өнөөдөр чамдаа баярлалаа ♡',
    );
    await tester.ensureVisible(find.byKey(const Key('flowersPreview')));
    await tester.tap(find.byKey(const Key('flowersPreview')));
    await tester.pumpAndSettle();
  }

  testWidgets('compose preview explicit send lands real sent inbox', (
    tester,
  ) async {
    await open(tester);
    await preview(tester);
    expect(repository.commands, isEmpty);
    expect(find.text('Өнөөдөр чамдаа баярлалаа ♡'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('flowersSend')));
    await tester.tap(find.byKey(const Key('flowersSend')));
    await tester.pumpAndSettle();
    expect(repository.commands, hasLength(1));
    expect(
      repository.commands.single.body['message'],
      'Өнөөдөр чамдаа баярлалаа ♡',
    );
    expect(find.byKey(const Key('flowersGift-gift-1')), findsOneWidget);
    expect(find.byKey(const Key('flowersPreviewPage')), findsNothing);
    await close(tester);
  });
  testWidgets('received card opens correct partner greeting', (tester) async {
    repository.value = flowersJson(gifts: [giftJson()]);
    await open(tester);
    await tester.ensureVisible(find.byKey(const Key('flowersGift-gift-1')));
    await tester.tap(find.byKey(const Key('flowersGift-gift-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flowersDetail')), findsOneWidget);
    expect(find.text('Ану, чамдаа'), findsOneWidget);
    expect(find.text('Тэмүүлэн-ээс ♡'), findsOneWidget);
    await close(tester);
  });
  testWidgets('unpaired account sees pair CTA and cannot send', (tester) async {
    repository.value = flowersJson(paired: false);
    var pairs = 0;
    await open(tester, onPair: () => pairs++);
    expect(find.byKey(const Key('flowersCompose')), findsNothing);
    await tester.tap(find.byKey(const Key('flowersPair')));
    expect(pairs, 1);
    expect(repository.commands, isEmpty);
    await close(tester);
  });
  testWidgets('pair revocation removes editor and private draft', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('flowersCompose')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('flowersMessage')),
      'Нууц мэндчилгээ',
    );
    repository.value = flowersJson(paired: false);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Нууц мэндчилгээ'), findsNothing);
    expect(find.byKey(const Key('flowersEditor')), findsNothing);
    repository.value = flowersJson(pair: 'pair-b');
    await controller.refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flowersCompose')));
    await tester.pumpAndSettle();
    expect(find.text('Нууц мэндчилгээ'), findsNothing);
    await close(tester);
  });
  testWidgets('back preserves unsaved draft until explicit discard', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('flowersCompose')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('flowersMessage')),
      'Нууц мэндчилгээ',
    );
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Мэндчилгээнээс гарах уу?'), findsOneWidget);
    await tester.tap(find.text('Үргэлжлүүлэх'));
    await tester.pumpAndSettle();
    expect(find.text('Нууц мэндчилгээ'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flowersConfirmLeave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flowersInbox')), findsOneWidget);
    await close(tester);
  });
  testWidgets('background hides cards and confirmed send resumes sent inbox', (
    tester,
  ) async {
    await open(tester);
    await preview(tester);
    final reply = Completer<String>();
    repository.onSend = (_) => reply.future;
    await tester.ensureVisible(find.byKey(const Key('flowersSend')));
    await tester.tap(find.byKey(const Key('flowersSend')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pump();
    expect(find.byKey(const Key('flowersPreviewPage')), findsNothing);
    reply.complete('gift-confirmed');
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flowersInbox')), findsOneWidget);
    expect(find.byKey(const Key('flowersSend')), findsNothing);
    expect(repository.commands, hasLength(1));
    await close(tester);
  });
  testWidgets(
    'network failure retries same gift without editing unknown command',
    (tester) async {
      repository.onSend = (_) async =>
          throw const FlowerFailure('network_error', retryable: true);
      await open(tester);
      await preview(tester);
      await tester.ensureVisible(find.byKey(const Key('flowersSend')));
      await tester.tap(find.byKey(const Key('flowersSend')));
      await tester.pumpAndSettle();
      expect(find.text('Засах'), findsNothing);
      repository.onSend = (_) async => 'gift-confirmed';
      await tester.tap(find.byKey(const Key('flowersSend')));
      await tester.pumpAndSettle();
      expect(repository.commands, hasLength(2));
      expect(
        identical(repository.commands.first, repository.commands.last),
        isTrue,
      );
      await close(tester);
    },
  );
}
