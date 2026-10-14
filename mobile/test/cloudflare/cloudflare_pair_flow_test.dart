import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_session_storage.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';
import 'package:hamtdaa/features/pair/pair_screen.dart';
import 'package:hamtdaa/main_cloudflare.dart';

import 'shell_fakes.dart';

class _MemoryStorage implements CloudflareSessionStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

/// A small HTTP fixture for driving the actual Flutter screens. Backend
/// authorization and transaction correctness are covered by the Worker suite.
class _PairServer implements CloudflareTransport {
  final requests =
      <({String path, String? token, Map<String, dynamic>? body})>[];
  final names = {'a': 'Ану', 'b': 'Тэмүүлэн'};
  int phase = 0;
  int version = 1;
  String? tokenHash;

  Map<String, dynamic> invitation(String actor, {bool preview = false}) => {
    'id': 'invitation-1',
    'version': version,
    'state': phase == 1 ? 'open' : 'awaiting_creator',
    'role': preview
        ? 'viewer'
        : actor == 'a'
        ? 'creator'
        : 'requester',
    'creator': {'user_id': 'a', 'display_name': names['a']},
    'requester': phase == 2 && !preview
        ? {'user_id': 'b', 'display_name': names['b']}
        : null,
    'expires_at': DateTime.now()
        .add(const Duration(hours: 24))
        .toUtc()
        .toIso8601String(),
  };

  @override
  Future<CloudflareResponse> send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    requests.add((path: path, token: token, body: body));
    if (path == '/v1/auth/verify-code') {
      final actor = (body!['email'] as String).split('@').first;
      return CloudflareResponse(200, {
        'token': actor,
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
        'user': {'id': actor, 'email': '$actor@example.com'},
      });
    }
    expectSync(token, anyOf('a', 'b'));
    if (path == '/v1/pair/status') {
      expectSync(method, 'GET');
      return CloudflareResponse(200, {
        'ok': true,
        'server_time': DateTime.now().toUtc().toIso8601String(),
        'profile': {
          'user_id': token,
          'display_name': names[token],
          'version': 1,
        },
        'pair': phase == 3
            ? {
                'id': 'pair-1',
                'version': 1,
                'partner': {
                  'user_id': token == 'a' ? 'b' : 'a',
                  'display_name': names[token == 'a' ? 'b' : 'a'],
                },
              }
            : null,
        'invitations': (phase == 1 && token == 'a') || phase == 2
            ? [invitation(token!)]
            : [],
      });
    }
    expectSync(method, 'POST');
    if (path == '/v1/pair/commands/update-name') {
      expectSync(body!['expected_version'], 1);
      names[token!] = body['display_name'] as String;
      return const CloudflareResponse(200, {'ok': true});
    }
    if (path == '/v1/pair/commands/create') {
      expectSync(token, 'a');
      expectSync(body!.containsKey('token'), isFalse);
      expectSync(body['command_id'], isNotEmpty);
      tokenHash = body['token_hash'] as String;
      phase = 1;
      return CloudflareResponse(200, {
        'ok': true,
        'invitation': invitation(token!),
      });
    }
    if (path == '/v1/pair/preview') {
      expectSync(token, 'b');
      expectSync(
        sha256.convert(utf8.encode(body!['token'] as String)).toString(),
        tokenHash,
      );
      // Preview must leave the pair untouched.
      expectSync(phase, 1);
      return CloudflareResponse(200, {
        'ok': true,
        'invitation': invitation(token!, preview: true),
      });
    }
    if (path == '/v1/pair/commands/request') {
      expectSync(token, 'b');
      expectSync(body!['expected_version'], 1);
      phase = 2;
      version = 2;
      return CloudflareResponse(200, {
        'ok': true,
        'invitation': invitation(token!),
      });
    }
    if (path == '/v1/pair/commands/confirm') {
      expectSync(token, 'a');
      expectSync(body!['expected_version'], 2);
      expectSync(body['invitation_id'], 'invitation-1');
      phase = 3;
      return const CloudflareResponse(200, {'ok': true});
    }
    if (path == '/v1/pair/commands/unlink') {
      expectSync(token, 'b');
      expectSync(body!['expected_version'], 1);
      expectSync(body['pair_id'], 'pair-1');
      phase = 4;
      return const CloudflareResponse(200, {'ok': true});
    }
    fail('Unexpected endpoint: $path');
  }

  @override
  void close() {}
}

void main() {
  testWidgets(
    'two accounts name, invite, preview, request, confirm and unlink through HTTP adapter',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = _PairServer();
      final first = CloudflareAuthRepository(
        transport: server,
        storage: _MemoryStorage(),
      );
      final second = CloudflareAuthRepository(
        transport: server,
        storage: _MemoryStorage(),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.verifyEmailCode('a@example.com', '123456');
      await second.verifyEmailCode('b@example.com', '654321');

      Future<void> open(CloudflareAuthRepository auth) async {
        // Model separate phones without letting one account reuse the other's
        // navigator, controllers, or memory-only invite token.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          CloudflareOnboardingApp(
            repository: auth,
            subscriptionControllerFactory: shellBilling,
          ),
        );
        await tester.tap(find.byKey(const Key('cloudflareOpenPair')));
        await tester.pumpAndSettle();
      }

      Future<void> tapKey(String key) async {
        final finder = find.byKey(Key(key));
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await open(first);
      await tapKey('pairEditName');
      await tester.enterText(find.byKey(const Key('pairNameField')), 'Анука');
      await tapKey('pairSaveName');
      expect(namesOnScreen('Анука'), findsOneWidget);
      await tapKey('pairCreate');
      final code = tester
          .widget<Text>(find.byKey(const Key('pairIssuedToken')))
          .data!;
      expect(code, hasLength(43));

      await open(second);
      await tester.ensureVisible(find.byKey(const Key('pairTokenField')));
      await tester.enterText(
        find.byKey(const Key('pairTokenField')),
        '  \n$code\n  ',
      );
      await tapKey('pairPreview');
      expect(server.phase, 1);
      expect(find.byKey(const Key('pairPartnerName')), findsNothing);
      expect(find.text('Анука'), findsOneWidget);
      await tapKey('pairRequest');
      expect(find.text('Зөвшөөрлийг хүлээж байна'), findsOneWidget);
      expect(find.byKey(const Key('pairPartnerName')), findsNothing);

      await open(first);
      expect(find.text('Танд хүсэлт ирлээ'), findsOneWidget);
      await tapKey('pairConfirm');
      expect(server.phase, 2);
      await tester.tap(find.text('Зөвшөөрч холбогдох'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloudflareHome')), findsOneWidget);
      expect(find.byType(PairScreen), findsNothing);
      expect(
        find.text('Та хоёр холбогдлоо. Хамтын мөчүүдээ эхлүүлээрэй.'),
        findsOneWidget,
      );

      // A newly connected route returns home, but opening an existing pair
      // must still allow the owner to inspect and manage the connection.
      await tester.tap(find.byKey(const Key('cloudflareOpenPair')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('pairPartnerName'))).data,
        'Тэмүүлэн',
      );

      await open(second);
      expect(
        tester.widget<Text>(find.byKey(const Key('pairPartnerName'))).data,
        'Анука',
      );
      await tapKey('pairUnlink');
      expect(server.phase, 3);
      await tester.tap(find.text('Холболт салгах'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pairPartnerName')), findsNothing);
      expect(find.byKey(const Key('pairCreate')), findsOneWidget);

      await open(first);
      expect(find.byKey(const Key('pairPartnerName')), findsNothing);
      expect(find.byKey(const Key('pairCreate')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await first.dispose();
      await second.dispose();
    },
  );

  for (final source in ['refresh', 'poll', 'resume']) {
    testWidgets(
      'requester returns home when $source observes the creator confirmation',
      (tester) async {
        final server = _PairServer()
          ..phase = 2
          ..version = 2;
        final auth = CloudflareAuthRepository(
          transport: server,
          storage: _MemoryStorage(),
        );
        addTearDown(auth.dispose);
        await auth.verifyEmailCode('b@example.com', '654321');
        await tester.pumpWidget(
          CloudflareOnboardingApp(
            repository: auth,
            subscriptionControllerFactory: shellBilling,
          ),
        );
        await tester.tap(find.byKey(const Key('cloudflareOpenPair')));
        await tester.pumpAndSettle();
        expect(find.text('Зөвшөөрлийг хүлээж байна'), findsOneWidget);
        expect(find.byKey(const Key('cloudflareHome')), findsNothing);

        // The other phone accepts while the requester is waiting here.
        if (source == 'resume') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
        }
        server.phase = 3;
        if (source == 'refresh') {
          await tester.tap(find.byKey(const Key('pairRefresh')));
        } else if (source == 'poll') {
          await tester.pump(const Duration(seconds: 10));
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('cloudflareHome')), findsOneWidget);
        expect(find.byType(PairScreen), findsNothing);
        expect(
          find.text('Та хоёр холбогдлоо. Хамтын мөчүүдээ эхлүүлээрэй.'),
          findsOneWidget,
        );
        expect(
          server.requests.where(
            (request) => request.path == '/v1/pair/commands/confirm',
          ),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        await auth.dispose();
      },
    );
  }

  testWidgets('existing pair stays manageable and can explicitly return home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = _PairServer()..phase = 3;
    final auth = CloudflareAuthRepository(
      transport: server,
      storage: _MemoryStorage(),
    );
    addTearDown(auth.dispose);
    await auth.verifyEmailCode('b@example.com', '654321');
    await tester.pumpWidget(
      CloudflareOnboardingApp(
        repository: auth,
        subscriptionControllerFactory: shellBilling,
      ),
    );
    await tester.tap(find.byKey(const Key('cloudflareOpenPair')));
    await tester.pumpAndSettle();
    expect(find.byType(PairScreen), findsOneWidget);
    expect(find.byKey(const Key('pairPartnerName')), findsOneWidget);
    expect(find.byKey(const Key('pairUnlink')), findsOneWidget);
    expect(find.byKey(const Key('cloudflareHome')), findsNothing);

    // Repeated status reads and foreground changes must not misidentify an
    // already active connection as a new pairing and eject this settings page.
    await tester.tap(find.byKey(const Key('pairRefresh')));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('pairPartnerName')),
      findsOneWidget,
      reason: 'Active pair must reload immediately after resuming',
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byType(PairScreen), findsOneWidget);
    expect(find.byKey(const Key('pairUnlink')), findsOneWidget);

    await tester.ensureVisible(find.text('Нүүр хуудас руу'));
    await tester.tap(find.text('Нүүр хуудас руу'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cloudflareHome')), findsOneWidget);
    expect(find.byType(PairScreen), findsNothing);
    expect(
      server.requests.where((request) => request.path.contains('/commands/')),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    await auth.dispose();
  });
}

Finder namesOnScreen(String value) => find.text(value);
