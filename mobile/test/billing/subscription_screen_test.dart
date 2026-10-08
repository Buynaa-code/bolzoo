import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/billing/billing_models.dart';
import 'package:hamtdaa/billing/subscription_controller.dart';
import 'package:hamtdaa/features/subscription/subscription_screen.dart';
import 'package:hamtdaa/ui/theme.dart';

import 'billing_fakes.dart';

void main() {
  late FakeBillingRepository repository;
  late FakeStoreGateway store;
  late SubscriptionController controller;
  final legal = SubscriptionLegalLinks(terms: Uri.parse('https://api.example.com/terms'), privacy: Uri.parse('https://api.example.com/privacy'));
  setUp(() {
    repository = FakeBillingRepository(); store = FakeStoreGateway();
    controller = SubscriptionController(repository: repository, store: store, now: () => testNow);
  });
  tearDown(() => controller.dispose());

  Future<void> mount(WidgetTester tester, {SubscriptionLegalLinks? links, VoidCallback? openCards, Future<bool> Function(Uri)? openLink}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: SubscriptionScreen(controller: controller, legalLinks: links ?? legal, onOpenCards: openCards, openLink: openLink)));
    await tester.pumpAndSettle();
  }

  testWidgets('unconfigured checkout is disabled without fake prices or external checkout', (tester) async {
    repository.enabled = false;
    await mount(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('subscriptionBuy')), 400, scrollable: find.byType(Scrollable));
    expect(tester.widget<FilledButton>(find.byKey(const Key('subscriptionBuy'))).onPressed, isNull);
    expect(find.textContaining('9,900'), findsNothing);
    expect(find.textContaining('QPay'), findsNothing);
    expect(store.buys, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('localized store price shown and exact selected product purchased', (tester) async {
    store.offered = [StoreProduct(id: PlusPeriod.month.productId, price: '¥1,500', period: PlusPeriod.month), StoreProduct(id: PlusPeriod.year.productId, price: '¥12,000', period: PlusPeriod.year)];
    await mount(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('subscriptionPlanmonth')), 300, scrollable: find.byType(Scrollable));
    expect(find.text('¥1,500'), findsOneWidget);
    await tester.tap(find.byKey(const Key('subscriptionPlanmonth')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('subscriptionBuy')), 250, scrollable: find.byType(Scrollable));
    await tester.tap(find.byKey(const Key('subscriptionBuy')));
    await tester.pump();
    expect(store.buys.single.product.period, PlusPeriod.month);
    expect(store.buys.single.account, appleAccount);
    expect(controller.premiumCards, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing legal URL disables buy even when product exists', (tester) async {
    await mount(tester, links: SubscriptionLegalLinks(terms: Uri(), privacy: legal.privacy));
    await tester.scrollUntilVisible(find.byKey(const Key('subscriptionBuy')), 350, scrollable: find.byType(Scrollable));
    expect(tester.widget<FilledButton>(find.byKey(const Key('subscriptionBuy'))).onPressed, isNull);
    expect(store.buys, isEmpty);
  });

  testWidgets('partner Plus shows card entry without charging or owner management', (tester) async {
    repository.value = snapshot(plus: true, source: 'partner');
    var opened = 0;
    await mount(tester, openCards: () => opened++);
    expect(find.text('Хосын тань Plus эрх'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('subscriptionOpenCards')), 300, scrollable: find.byType(Scrollable));
    await tester.tap(find.byKey(const Key('subscriptionOpenCards')));
    await tester.pump();
    expect(opened, 1);
    expect(find.byKey(const Key('subscriptionBuy')), findsNothing);
    expect(find.byKey(const Key('subscriptionManage')), findsNothing);
    expect(store.buys, isEmpty);
  });

  testWidgets('terms and privacy open only configured policy URLs', (tester) async {
    final opened = <Uri>[];
    await mount(tester, openLink: (uri) async { opened.add(uri); return true; });
    await tester.scrollUntilVisible(find.byKey(const Key('subscriptionTerms')), 400, scrollable: find.byType(Scrollable));
    await tester.tap(find.byKey(const Key('subscriptionTerms'))); await tester.pump();
    await tester.tap(find.byKey(const Key('subscriptionPrivacy'))); await tester.pump();
    expect(opened, [legal.terms, legal.privacy]);
    expect(tester.takeException(), isNull);
  });
}
