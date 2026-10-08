import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/billing/subscription_controller.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_session_storage.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';
import 'package:hamtdaa/features/premium_cards/premium_cards_screen.dart';
import 'package:hamtdaa/features/subscription/subscription_screen.dart';
import 'package:hamtdaa/ui/theme.dart';

import 'billing_fakes.dart';

const _capture = bool.fromEnvironment('CAPTURE_BILLING_UI');
const _output = '/Users/izzy/Downloads/bolzoo/output/billing-ui';
final _card = <String, dynamic>{
  'names': 'Ану & Тэмүүлэн',
  'message': 'Чамтай өдөр бүр илүү гоё.\nБидний түүх үргэлжилсээр.',
  'date': '2026-10-06',
  'colors': ['#FFF0F6', '#FFE1EE', '#CB176C'],
};

class _Storage implements CloudflareSessionStorage {
  String? value;
  @override Future<String?> read() async => value;
  @override Future<void> write(String value) async => this.value = value;
  @override Future<void> clear() async => value = null;
}

class _Transport implements CloudflareTransport {
  int cardRequests = 0;
  final cardTokens = <String?>[];
  Future<CloudflareResponse> Function()? onCard;
  @override
  Future<CloudflareResponse> send(String method, String path, {String? token, Map<String, dynamic>? body}) async {
    if (path == '/v1/auth/verify-code') {
      final actor = (body!['email'] as String).split('@').first;
      return CloudflareResponse(200, {'ok': true, 'token': 'token-$actor', 'user': {'id': actor, 'email': body['email']}, 'expires_at': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String()});
    }
    if (path == '/v1/auth/sign-out') return const CloudflareResponse(200, {'ok': true});
    expect(method, 'POST');
    expect(path, '/v1/premium/cards');
    expect(body!.keys.toSet(), {'names', 'message', 'date', 'theme'});
    cardRequests++; cardTokens.add(token);
    return onCard == null ? CloudflareResponse(200, {'ok': true, 'card': _card}) : await onCard!();
  }
  @override void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Transport transport;
  late CloudflareAuthRepository auth;
  var shareCalls = 0;
  const shares = MethodChannel('dev.fluttercommunity.plus/share');
  setUpAll(() async {
    final loader = FontLoader('Nunito')..addFont(rootBundle.load('assets/fonts/Nunito.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() async {
    transport = _Transport();
    auth = CloudflareAuthRepository(transport: transport, storage: _Storage());
    await auth.verifyEmailCode('a@example.com', '123456');
    shareCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(shares, (_) async { shareCalls++; return 'success'; });
  });
  tearDown(() async {
    await auth.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(shares, null);
  });

  Finder preview() => find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is CoupleCardPainter);

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: RepaintBoundary(key: const Key('billingCapture'), child: PremiumCardsScreen(auth: auth))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Ану & Тэмүүлэн');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Картыг харах'), 280, scrollable: find.byType(Scrollable).last);
  }

  testWidgets('403 cannot create preview or export', (tester) async {
    transport.onCard = () async => const CloudflareResponse(403, {'ok': false, 'code': 'plus_required'});
    await mount(tester);
    await tester.tap(find.text('Картыг харах')); await tester.pumpAndSettle();
    expect(preview(), findsNothing);
    expect(find.text('Зураг хадгалах / хуваалцах'), findsNothing);
    expect(shareCalls, 0);
    expect(transport.cardRequests, 1);
    expect(find.textContaining('Plus багцад'), findsOneWidget);
  });

  testWidgets('preview success does not bypass fresh export entitlement check', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Картыг харах')); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(preview(), 320, scrollable: find.byType(Scrollable).last);
    expect(preview(), findsOneWidget);
    transport.onCard = () async => const CloudflareResponse(403, {'ok': false, 'code': 'plus_required'});
    await tester.scrollUntilVisible(find.text('Зураг хадгалах / хуваалцах'), 320, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Зураг хадгалах / хуваалцах')); await tester.pumpAndSettle();
    expect(transport.cardRequests, 2);
    expect(transport.cardTokens, ['token-a', 'token-a']);
    expect(preview(), findsNothing);
    expect(shareCalls, 0);
  });

  testWidgets('account switch discards a late card response', (tester) async {
    final response = Completer<CloudflareResponse>();
    transport.onCard = () => response.future;
    await mount(tester);
    await tester.tap(find.text('Картыг харах')); await tester.pump();
    await tester.runAsync(() => auth.verifyEmailCode('b@example.com', '123456'));
    response.complete(CloudflareResponse(200, {'ok': true, 'card': _card}));
    await tester.pumpAndSettle();
    expect(preview(), findsNothing);
    expect(shareCalls, 0);
    expect(transport.cardTokens.single, 'token-a');
    expect(auth.current.userId, 'b');
  });

  testWidgets('rendered export is a full 1080 by 1920 PNG', (tester) async {
    final bytes = await tester.runAsync(() => renderCoupleCard(_card));
    expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(16), 1080); expect(header.getUint32(20), 1920);
  });

  testWidgets('capture subscription and couple card for visual review', (tester) async {
    final repository = FakeBillingRepository();
    final controller = SubscriptionController(repository: repository, store: FakeStoreGateway(), now: () => testNow);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: RepaintBoundary(key: const Key('billingCapture'), child: SubscriptionScreen(controller: controller, legalLinks: SubscriptionLegalLinks(terms: Uri.parse('https://example.test/terms'), privacy: Uri.parse('https://example.test/privacy'))))));
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('billingCapture')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          await Directory(_output).create(recursive: true);
          await File('$_output/$name.png').writeAsBytes(bytes.buffer.asUint8List());
        } finally { image.dispose(); }
      });
    }
    await capture('01-plus-overview');
    await tester.scrollUntilVisible(find.byKey(const Key('subscriptionBuy')), 300, scrollable: find.byType(Scrollable));
    await tester.pumpAndSettle();
    await capture('02-plus-plans');
    await tester.runAsync(() async {
      await File('$_output/03-couple-card.png').writeAsBytes(await renderCoupleCard(_card));
    });
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  }, skip: !_capture);
}
