import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hamtdaa/auth/auth_models.dart';
import 'package:hamtdaa/billing/subscription_controller.dart';
import 'package:hamtdaa/features/account/cloudflare_account_screen.dart';
import 'package:hamtdaa/features/florists/nearby_florists_screen.dart';
import 'package:hamtdaa/flowers/flowers_screen.dart';
import 'package:hamtdaa/features/premium_cards/premium_cards_screen.dart';
import 'package:hamtdaa/features/subscription/subscription_screen.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_environment.dart';
import 'package:hamtdaa/cloudflare/cloudflare_pair_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_session_storage.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';
import 'package:hamtdaa/main_cloudflare.dart';
import 'package:hamtdaa/pair/pair_models.dart';
import 'package:hamtdaa/together/together_screen.dart';

import '../billing/billing_fakes.dart' as billing;
import 'shell_fakes.dart';

class MemoryStorage implements CloudflareSessionStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class Request {
  Request(this.method, this.path, this.token, this.body);
  final String method;
  final String path;
  final String? token;
  final Map<String, dynamic>? body;
}

class FakeTransport implements CloudflareTransport {
  final requests = <Request>[];
  bool failSignOut = false;
  late Future<CloudflareResponse> Function(Request) handle;
  @override
  Future<CloudflareResponse> send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) {
    final request = Request(method, path, token, body);
    requests.add(request);
    if (path == '/v1/auth/sign-out') {
      if (failSignOut) throw const SocketException('offline');
      return Future.value(const CloudflareResponse(200, {'ok': true}));
    }
    return handle(request);
  }

  @override
  void close() {}
}

Map<String, dynamic> session(String id, String email, {String? token}) => {
  'token': ?token,
  'expires_at': DateTime.now()
      .add(const Duration(hours: 1))
      .toUtc()
      .toIso8601String(),
  'user': {'id': id, 'email': email},
};

Map<String, dynamic> snapshot(String id, {String name = 'Ану'}) => {
  'ok': true,
  'server_time': DateTime.now().toUtc().toIso8601String(),
  'profile': {'user_id': id, 'display_name': name, 'version': 1},
  'pair': null,
  'invitations': <dynamic>[],
};

void main() {
  late FakeTransport transport;
  late MemoryStorage storage;
  late CloudflareAuthRepository auth;

  setUp(() {
    transport = FakeTransport();
    storage = MemoryStorage();
    auth = CloudflareAuthRepository(transport: transport, storage: storage);
  });
  tearDown(() async {
    await auth.dispose();
  });

  Future<void> login({
    String id = 'account-a',
    String email = 'a@example.com',
    String token = 'bearer-a',
  }) async {
    transport.handle = (_) async =>
        CloudflareResponse(200, session(id, email, token: token));
    await auth.verifyEmailCode(email, '123456');
    transport.handle = (request) async => CloudflareResponse(
      200,
      request.path == '/v1/pair/status'
          ? snapshot(id)
          : {'ok': true, 'paired': false},
    );
  }

  test('default app build points to the production API', () {
    expect(
      cloudflareDefaultApiUrl,
      'https://hamtdaa-api-production.mendmedey.workers.dev',
    );
  });

  for (final origin in [
    'https://hamtdaa-api-staging.mendmedey.workers.dev',
    'https://custom.example',
    'https://hamtdaa-api-production.mendmedey.workers.dev:8443',
    cloudflareProductionApiUrl,
  ]) {
    testWidgets('login and home identify the configured server at $origin', (
      tester,
    ) async {
      final requests = <Uri>[];
      late HttpCloudflareTransport api;
      final environmentAuth = (await tester.runAsync(() async {
        api = HttpCloudflareTransport(
          Uri.parse(origin),
          client: MockClient((request) async {
            requests.add(request.url);
            return http.Response(
              jsonEncode({
                'ok': true,
                ...session(
                  'environment-user',
                  'compare@example.com',
                  token: 'test-bearer',
                ),
              }),
              200,
            );
          }),
        );
        return CloudflareAuthRepository(
          transport: api,
          storage: MemoryStorage(),
        );
      }))!;
      addTearDown(() async {
        await environmentAuth.dispose();
        api.close();
      });
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        CloudflareOnboardingApp(
          repository: environmentAuth,
          subscriptionControllerFactory: shellBilling,
        ),
      );
      await tester.pumpAndSettle();
      final production = origin == cloudflareProductionApiUrl;
      expect(
        find.byKey(const Key('cloudflareBuildEnvironmentNotice')),
        production ? findsNothing : findsOneWidget,
      );
      if (!production) {
        expect(
          find.textContaining('Урилгын код зөвхөн ижил серверт ажиллана.'),
          findsOneWidget,
        );
        expect(find.text('Сервер: $origin'), findsOneWidget);
      }
      expect(find.byKey(const Key('cloudflareSignedInEmail')), findsNothing);
      // Keyboard-sized insets must leave both the notice and login scrollable.
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.runAsync(
        () => environmentAuth.verifyEmailCode('compare@example.com', '123456'),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('cloudflareBuildEnvironmentNotice')),
        production ? findsNothing : findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('navUs')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('cloudflareSignedInEmail')),
        200,
      );
      expect(find.text('Нэвтэрсэн имэйл: compare@example.com'), findsOneWidget);
      expect(requests, isNotEmpty);
      expect(requests.map((uri) => uri.origin), everyElement(origin));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test(
    'configuration accepts HTTPS and only explicitly allowed loopback HTTP',
    () {
      expect(
        const CloudflareEnvironment(
          apiUrl: 'https://staging.example.com',
        ).validationError,
        isNull,
      );
      for (final url in [
        '',
        'http://example.com',
        'https://x.example/api',
        'https://user:x@host',
        'https://host?token=x',
      ]) {
        expect(CloudflareEnvironment(apiUrl: url).validationError, isNotNull);
      }
      expect(
        const CloudflareEnvironment(
          apiUrl: 'http://127.0.0.1:8787',
        ).validationError,
        isNotNull,
      );
      expect(
        const CloudflareEnvironment(
          apiUrl: 'http://127.0.0.1:8787',
          allowLoopback: true,
        ).validationError,
        isNull,
      );
      expect(
        const CloudflareEnvironment(
          apiUrl: 'http://192.168.1.10',
          allowLoopback: true,
        ).validationError,
        isNotNull,
      );
    },
  );

  test(
    'OTP request normalizes email and validates inputs before network',
    () async {
      transport.handle = (_) async =>
          const CloudflareResponse(200, {'ok': true});
      await auth.requestEmailCode(' A@Example.COM ');
      expect(transport.requests.single.body, {'email': 'a@example.com'});
      expect(auth.current.status, AuthStatus.awaitingCode);
      await expectLater(
        auth.verifyEmailCode('a@example.com', 'xx'),
        throwsA(isA<AuthFailure>()),
      );
      expect(transport.requests.length, 1);
    },
  );

  test(
    'verified credentials only persist bearer and expiry, not private profiles',
    () async {
      await login();
      expect(auth.current.userId, 'account-a');
      expect(auth.credential!.token, 'bearer-a');
      final stored = jsonDecode(storage.value!) as Map;
      expect(stored.keys.toSet(), {'token', 'expires_at'});
      expect(stored['token'], 'bearer-a');
    },
  );

  test('restored bearer is not trusted before server validation', () async {
    storage.value = jsonEncode({
      'token': 'saved',
      'expires_at': session('a', 'a@example.com')['expires_at'],
    });
    final pending = Completer<CloudflareResponse>();
    transport.handle = (_) => pending.future;
    final restore = auth.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(auth.current.isSignedIn, isFalse);
    expect(transport.requests.single.token, 'saved');
    pending.complete(
      CloudflareResponse(200, session('server-user', 'a@example.com')),
    );
    await restore;
    expect(auth.current.userId, 'server-user');
  });

  test(
    'network failure during restore keeps credential and does not enter app',
    () async {
      storage.value = jsonEncode({
        'token': 'saved',
        'expires_at': session('a', 'a@example.com')['expires_at'],
      });
      transport.handle = (_) async => throw const SocketException('offline');
      await expectLater(auth.initialize(), throwsA(isA<AuthFailure>()));
      expect(storage.value, isNotNull);
      expect(auth.current.isSignedIn, isFalse);
    },
  );

  test('401 during restore clears stored bearer', () async {
    storage.value = jsonEncode({
      'token': 'saved',
      'expires_at': session('a', 'a@example.com')['expires_at'],
    });
    transport.handle = (_) async =>
        const CloudflareResponse(401, {'ok': false, 'code': 'unauthenticated'});
    await auth.initialize();
    expect(storage.value, isNull);
    expect(auth.current.isSignedIn, isFalse);
  });

  test('late OTP success after logout never resurrects credentials', () async {
    final pending = Completer<CloudflareResponse>();
    transport.handle = (_) => pending.future;
    final verification = auth.verifyEmailCode('a@example.com', '123456');
    final assertion = expectLater(verification, throwsA(isA<AuthFailure>()));
    await auth.signOut();
    pending.complete(
      CloudflareResponse(
        200,
        session('account-a', 'a@example.com', token: 'late'),
      ),
    );
    await assertion;
    await Future<void>.delayed(Duration.zero);
    expect(auth.current.isSignedIn, isFalse);
    expect(storage.value, isNull);
    expect(transport.requests.last.path, '/v1/auth/sign-out');
    expect(transport.requests.last.token, 'late');
  });

  test('rejection for an old bearer cannot clear a newer login', () async {
    await login();
    final old = auth.credential!;
    await login(id: 'account-b', email: 'b@example.com', token: 'bearer-b');
    await auth.reject(old);
    expect(auth.current.userId, 'account-b');
    expect(jsonDecode(storage.value!)['token'], 'bearer-b');
  });

  test(
    'pair replies from the previous login cannot reach the new account',
    () async {
      await login();
      final pairs = CloudflarePairRepository(auth);
      addTearDown(pairs.dispose);
      final delayed = Completer<CloudflareResponse>();
      transport.handle = (_) => delayed.future;
      final status = pairs.status();
      final assertion = expectLater(
        status,
        throwsA(
          isA<PairFailure>().having(
            (failure) => failure.code,
            'code',
            'unauthenticated',
          ),
        ),
      );
      expect(transport.requests.last.token, 'bearer-a');
      await login(id: 'account-b', email: 'b@example.com', token: 'bearer-b');
      delayed.complete(CloudflareResponse(200, snapshot('account-a')));
      await assertion;
      expect(auth.current.userId, 'account-b');
    },
  );

  test('pair rejects mismatched server identity', () async {
    await login();
    final pairs = CloudflarePairRepository(auth);
    addTearDown(pairs.dispose);
    transport.handle = (_) async =>
        CloudflareResponse(200, snapshot('unexpected'));
    await expectLater(
      pairs.status(),
      throwsA(
        isA<PairFailure>().having((f) => f.code, 'code', 'unauthenticated'),
      ),
    );
  });

  test(
    'pair HTTP 401 expires this exact login and removes disk bearer',
    () async {
      await login();
      final pairs = CloudflarePairRepository(auth);
      addTearDown(pairs.dispose);
      transport.handle = (_) async => const CloudflareResponse(401, {
        'ok': false,
        'code': 'unauthenticated',
      });
      await expectLater(pairs.status(), throwsA(isA<PairFailure>()));
      expect(auth.current.isSignedIn, isFalse);
      expect(storage.value, isNull);
    },
  );

  test(
    'pair command retries keep command ID and creation never sends plaintext invitation',
    () async {
      await login();
      final pairs = CloudflarePairRepository(auth);
      addTearDown(pairs.dispose);
      transport.handle = (_) async =>
          const CloudflareResponse(200, {'ok': true});
      final command = PairCommand.create();
      await pairs.execute(command);
      await pairs.execute(command);
      final sent = transport.requests
          .where((r) => r.path.endsWith('/create'))
          .toList();
      expect(sent.length, 2);
      expect(sent.first.body, sent.last.body);
      expect(
        sent.first.body!['command_id'],
        command.parameters['p_command_id'],
      );
      expect(sent.first.body!['token_hash'], hasLength(64));
      expect(
        jsonEncode(sent.first.body),
        isNot(contains(command.inviteToken!)),
      );
      expect(sent.first.body!.containsKey('p_command_id'), isFalse);
    },
  );

  testWidgets(
    'isolated entrypoint opens pair flow and logout destroys nested route',
    (tester) async {
      await tester.runAsync(() => login());
      transport.handle = (_) async =>
          CloudflareResponse(200, snapshot('account-a'));
      await tester.pumpWidget(
        CloudflareOnboardingApp(
          repository: auth,
          subscriptionControllerFactory: shellBilling,
        ),
      );
      expect(find.text('Хоёулаа хамтдаа эхэлье'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Сайн уу, Ану ♡'), findsOneWidget);
      expect(
        find.byKey(const Key('cloudflareBottomNavigation')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('navUs')));
      await tester.pumpAndSettle();
      expect(find.text('Нэвтэрсэн имэйл: a@example.com'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloudflareOpenPair')));
      await tester.pumpAndSettle();
      expect(find.text('Хосоор холбогдох'), findsOneWidget);
      expect(
        find.text(
          '1. Нэг нь код үүсгээд нөгөөдөө илгээнэ.\n2. Нөгөө нь кодыг шалгаж, хүсэлт илгээнэ.\n3. Код илгээсэн хүн хүсэлтийг зөвшөөрнө.',
        ),
        findsOneWidget,
      );
      await tester.runAsync(auth.signOut);
      await tester.pumpAndSettle();
      expect(
        find.text(
          '1. Нэг нь код үүсгээд нөгөөдөө илгээнэ.\n2. Нөгөө нь кодыг шалгаж, хүсэлт илгээнэ.\n3. Код илгээсэн хүн хүсэлтийг зөвшөөрнө.',
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('cloudflareOpenPair')), findsNothing);
      expect(find.byKey(const Key('cloudflareSignedInEmail')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'release home hides paid routes while free destinations remain usable',
    (tester) async {
      expect(cloudflarePaidFeaturesEnabled, isFalse);
      await tester.runAsync(() => login());
      await tester.pumpWidget(
        CloudflareOnboardingApp(
          repository: auth,
          subscriptionControllerFactory: shellBilling,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navUs')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('cloudflareOpenAccount')),
        240,
      );
      expect(find.byKey(const Key('cloudflareOpenSubscription')), findsNothing);
      expect(find.byKey(const Key('cloudflareOpenPremiumCards')), findsNothing);
      await tester.tap(find.byKey(const Key('cloudflareOpenAccount')));
      await tester.pumpAndSettle();
      expect(find.byType(CloudflareAccountScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Cloudflare home opens digital flowers, florists, account and premium cards',
    (tester) async {
      await tester.runAsync(() => login());
      await tester.pumpWidget(
        CloudflareOnboardingApp(
          repository: auth,
          subscriptionControllerFactory: shellBilling,
          paidFeaturesEnabled: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'Нандин мөч',
      );
      for (final destination in <String, Type>{
        'cloudflareOpenFlowers': FlowersScreen,
        'cloudflareOpenFlorists': NearbyFloristsScreen,
        'cloudflareOpenAccount': CloudflareAccountScreen,
        'cloudflareOpenSubscription': SubscriptionScreen,
        'cloudflareOpenPremiumCards': PremiumCardsScreen,
      }.entries) {
        await tester.tap(
          find.byKey(
            Key(
              destination.key == 'cloudflareOpenFlowers'
                  ? 'navHome'
                  : destination.key == 'cloudflareOpenFlorists'
                  ? 'navGifts'
                  : 'navUs',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(Key(destination.key)).hitTestable(),
          200,
        );
        await tester.tap(find.byKey(Key(destination.key)));
        await tester.pumpAndSettle();
        expect(find.byType(destination.value), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'active Plus opens cards from subscription and returns through both routes',
    (tester) async {
      await tester.runAsync(() => login());
      final repository = billing.FakeBillingRepository()
        ..value = billing.snapshot(plus: true);
      final store = billing.FakeStoreGateway(provider: null);
      await tester.pumpWidget(
        CloudflareOnboardingApp(
          repository: auth,
          paidFeaturesEnabled: true,
          subscriptionControllerFactory: (_) => SubscriptionController(
            repository: repository,
            store: store,
            now: () => billing.testNow,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navUs')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('cloudflareOpenSubscription')).hitTestable(),
        240,
      );
      await tester.tap(find.byKey(const Key('cloudflareOpenSubscription')));
      await tester.pumpAndSettle();
      expect(find.byType(SubscriptionScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('subscriptionOpenCards')).hitTestable(),
        240,
      );
      await tester.tap(find.byKey(const Key('subscriptionOpenCards')));
      await tester.pumpAndSettle();
      expect(find.byType(PremiumCardsScreen), findsOneWidget);
      expect(find.byType(SubscriptionScreen), findsNothing);
      expect(find.byKey(const Key('cloudflareUs')), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(PremiumCardsScreen), findsNothing);
      expect(find.byType(SubscriptionScreen), findsOneWidget);
      expect(find.byKey(const Key('cloudflareUs')), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SubscriptionScreen), findsNothing);
      expect(find.byKey(const Key('cloudflareUs')), findsOneWidget);
      await tester.tap(find.byKey(const Key('navHome')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloudflareHome')), findsOneWidget);
      expect(find.text('Сайн уу, Ану ♡'), findsOneWidget);
      expect(store.buys, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'five bottom destinations preserve server-backed pair gating and return home',
    (tester) async {
      await tester.runAsync(() => login());
      await tester.pumpWidget(
        CloudflareOnboardingApp(
          repository: auth,
          subscriptionControllerFactory: shellBilling,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Сайн уу, Ану ♡'), findsOneWidget);
      expect(find.byKey(const Key('homeTogetherCard')), findsOneWidget);
      for (final key in [
        'navHome',
        'navCalendar',
        'navMemories',
        'navGifts',
        'navUs',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget);
      }
      for (final (key, section) in [
        ('navCalendar', TogetherSection.calendar),
        ('navMemories', TogetherSection.memories),
      ]) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        final screen = tester.widget<TogetherScreen>(
          find.byType(TogetherScreen),
        );
        expect(screen.embedded, isTrue);
        expect(screen.initialSection, section);
        expect(find.text('Хосоороо холбогдоорой'), findsOneWidget);
        expect(find.byKey(const Key('togetherConnectPair')), findsOneWidget);
        expect(find.byKey(const Key('cloudflareHome')), findsNothing);
      }
      expect(
        transport.requests.where((r) => r.path == '/v1/together/state'),
        isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('navGifts')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloudflareGifts')), findsOneWidget);
      expect(find.byKey(const Key('cloudflareOpenFlowers')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('cloudflareOpenFlorists')),
        200,
      );
      expect(find.byKey(const Key('cloudflareOpenFlorists')), findsOneWidget);
      expect(find.byKey(const Key('cloudflareOpenSubscription')), findsNothing);
      expect(find.byKey(const Key('cloudflareOpenPremiumCards')), findsNothing);
      await tester.tap(find.byKey(const Key('navUs')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloudflareUs')), findsOneWidget);
      expect(find.text('Нэвтэрсэн имэйл: a@example.com'), findsOneWidget);
      await tester.tap(find.byKey(const Key('navHome')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloudflareHome')), findsOneWidget);
      expect(find.text('Сайн уу, Ану ♡'), findsOneWidget);
      expect(find.byKey(const Key('cloudflareSignedInEmail')), findsNothing);
      expect(find.byKey(const Key('cloudflareGifts')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a new login discards private routes and the prior billing controller',
    (tester) async {
      await tester.runAsync(() => login());
      final billing = <SubscriptionController>[];
      await tester.pumpWidget(
        CloudflareOnboardingApp(
          repository: auth,
          subscriptionControllerFactory: (repository) {
            final controller = shellBilling(repository);
            billing.add(controller);
            return controller;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navUs')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('cloudflareOpenAccount')),
        240,
      );
      await tester.tap(find.byKey(const Key('cloudflareOpenAccount')));
      await tester.pumpAndSettle();
      expect(find.byType(CloudflareAccountScreen), findsOneWidget);
      await tester.runAsync(
        () => login(id: 'account-b', email: 'b@example.com', token: 'bearer-b'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CloudflareAccountScreen), findsNothing);
      expect(find.byKey(const Key('cloudflareHome')), findsOneWidget);
      await tester.tap(find.byKey(const Key('navUs')));
      await tester.pumpAndSettle();
      expect(find.text('Нэвтэрсэн имэйл: b@example.com'), findsOneWidget);
      expect(find.text('Нэвтэрсэн имэйл: a@example.com'), findsNothing);
      expect(billing, hasLength(2));
      expect(billing.first.isCurrent, isFalse);
      expect(billing.last.isCurrent, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'sign-out server failure stays visible after private routes close',
    (tester) async {
      await tester.runAsync(() => login());
      transport.failSignOut = true;
      await tester.pumpWidget(
        CloudflareOnboardingApp(
          repository: auth,
          subscriptionControllerFactory: shellBilling,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navUs')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('cloudflareSignOut')));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pumpAndSettle();
      expect(auth.current.isSignedIn, isFalse);
      expect(find.byKey(const Key('cloudflareHome')), findsNothing);
      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.textContaining('Серверийн холболт тасарсан'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'HTTP transport refuses redirect rather than forwarding bearer',
    () async {
      var requests = 0;
      final client = HttpCloudflareTransport(
        Uri.parse('https://test.example'),
        client: MockClient((request) async {
          requests++;
          expect(request.followRedirects, isFalse);
          expect(request.headers['authorization'], 'Bearer test-only');
          return http.Response(
            '{"ok":false}',
            302,
            headers: {'location': '/other'},
          );
        }),
      );
      try {
        final result = await client.send(
          'GET',
          '/v1/auth/session',
          token: 'test-only',
        );
        expect(result.status, 302);
        expect(requests, 1);
      } finally {
        client.close();
      }
    },
  );
}
