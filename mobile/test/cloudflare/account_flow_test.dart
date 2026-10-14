import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/cloudflare/cloudflare_session_storage.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';
import 'package:hamtdaa/features/account/cloudflare_account_screen.dart';

class _Storage implements CloudflareSessionStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> clear() async => value = null;
}

class _Request {
  _Request(this.path, this.token, this.body);
  final String path;
  final String? token;
  final Map<String, dynamic> body;
}

class _Transport implements CloudflareTransport {
  final requests = <_Request>[];
  Future<CloudflareResponse> Function(_Request)? handle;
  @override
  Future<CloudflareResponse> send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    if (path == '/v1/auth/verify-code') {
      final actor = (body!['email'] as String).split('@').first;
      return CloudflareResponse(200, {
        'ok': true,
        'token': 'token-$actor',
        'user': {'id': actor, 'email': body['email']},
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
      });
    }
    final request = _Request(path, token, body ?? {});
    requests.add(request);
    expect(method, 'POST');
    if (path == '/v1/auth/sign-out')
      return const CloudflareResponse(401, {'ok': false});
    return handle!(request);
  }

  @override
  void close() {}
}

CloudflareResponse _page(
  String section, {
  String? cursor,
  String actor = 'a',
  List<Object> data = const [],
  List<String>? sections,
}) => CloudflareResponse(200, {
  'ok': true,
  'export': {
    'schema_version': 1,
    'section': section,
    if (section == 'profile')
      'account': {'id': actor, 'email': '$actor@example.test'},
    if (section == 'profile') 'pair': null,
    if (section == 'profile' && sections != null) 'sections': sections,
    if (section != 'profile') 'data': data,
    'next_cursor': cursor,
  },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const shares = MethodChannel('dev.fluttercommunity.plus/share');
  late Directory temporary;
  late _Storage storage;
  late _Transport transport;
  late CloudflareAuthRepository auth;
  late List<Map<String, dynamic>> shared;
  late List<String> sharedPaths;
  Future<String> Function()? shareResult;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('hamtdaa-account-test-');
    storage = _Storage();
    transport = _Transport();
    auth = CloudflareAuthRepository(transport: transport, storage: storage);
    await auth.verifyEmailCode('a@example.test', '123456');
    shared = [];
    sharedPaths = [];
    shareResult = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (call) async {
      expect(call.method, anyOf('getTemporaryDirectory', 'getTemporaryPath'));
      return temporary.path;
    });
    messenger.setMockMethodCallHandler(shares, (call) async {
      final arguments = call.arguments as Map;
      final path = (arguments['paths'] as List).single as String;
      sharedPaths.add(path);
      final zip = ZipDecoder().decodeBytes(await File(path).readAsBytes());
      final records = zip.findFile('records.json')!;
      shared.add(
        jsonDecode(utf8.decode(records.content)) as Map<String, dynamic>,
      );
      return shareResult == null ? 'example.application' : await shareResult!();
    });
  });
  tearDown(() async {
    await auth.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(paths, null)
      ..setMockMethodCallHandler(shares, null);
    await temporary.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    // Keep the repository's queued secure-storage futures in the widget clock.
    await tester.runAsync(auth.dispose);
    auth = CloudflareAuthRepository(transport: transport, storage: storage);
    await auth.verifyEmailCode('a@example.test', '123456');
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: CloudflareAccountScreen(auth: auth)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDelete(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Бүртгэл устгах'));
    await tester.tap(find.text('Бүртгэл устгах'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'УСТГАХ');
    await tester.tap(find.text('Устгах'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await auth.dispose();
    expect(tester.takeException(), isNull);
  }

  Future<void> until(WidgetTester tester, bool Function() condition) async {
    final limit = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(limit))
        fail('Expected async operation did not finish');
      // Drain widget-test microtasks while real file/plugin work is running.
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  testWidgets('cancel and wrong confirmation never send deletion', (
    tester,
  ) async {
    await mount(tester);
    await openDelete(tester);
    expect(
      find.textContaining('бүх зурагтай дурсамж, хамтын хүсэл'),
      findsOneWidget,
    );
    expect(
      find.textContaining('хоёр талын аппд нээгдэхгүй болж устгагдана'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Хэрэгтэй мэдээллээ эхлээд татаж аваарай'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.tap(find.text('Устгах'));
    await tester.pump();
    expect(find.text('Бүртгэлээ устгах уу?'), findsOneWidget);
    expect(transport.requests, isEmpty);
    await tester.tap(find.text('Болих'));
    await tester.pumpAndSettle();
    expect(auth.current.isSignedIn, isTrue);
    expect(storage.value, contains('token-a'));
    expect(transport.requests, isEmpty);
    await unmount(tester);
  });

  testWidgets(
    'old login shows fresh-code instruction and retains the credential',
    (tester) async {
      transport.handle = (_) async => const CloudflareResponse(409, {
        'ok': false,
        'code': 'reauthentication_required',
      });
      await mount(tester);
      await openDelete(tester);
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('имэйл кодоор дахин нэвтэрсний'),
        findsOneWidget,
      );
      expect(auth.current.isSignedIn, isTrue);
      expect(storage.value, contains('token-a'));
      expect(transport.requests.single.path, '/v1/account/delete');
      expect(transport.requests.single.body, {'confirmation': 'УСТГАХ'});
      expect(transport.requests.single.token, 'token-a');
      await unmount(tester);
    },
  );

  testWidgets(
    'confirmed deletion clears saved login without revoking a different session',
    (tester) async {
      transport.handle = (_) async =>
          const CloudflareResponse(200, {'ok': true, 'deleted': true});
      await mount(tester);
      await openDelete(tester);
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(auth.current.isSignedIn, isFalse);
      expect(auth.credential, isNull);
      expect(storage.value, isNull);
      expect(transport.requests.map((r) => r.path), ['/v1/account/delete']);
      await unmount(tester);
    },
  );

  testWidgets(
    'unconfirmed success and server failure do not erase local login',
    (tester) async {
      transport.handle = (_) async =>
          const CloudflareResponse(200, {'ok': true});
      await mount(tester);
      await openDelete(tester);
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Устгалтыг баталгаажуулж чадсангүй'),
        findsOneWidget,
      );
      expect(auth.current.isSignedIn, isTrue);
      transport.handle = (_) async => const CloudflareResponse(503, {
        'ok': false,
        'code': 'temporarily_unavailable',
      });
      await openDelete(tester);
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(storage.value, contains('token-a'));
      await unmount(tester);
    },
  );

  testWidgets('late delete success cannot clear a newly signed-in account', (
    tester,
  ) async {
    final pending = Completer<CloudflareResponse>();
    transport.handle = (_) => pending.future;
    await mount(tester);
    await openDelete(tester);
    await confirm(tester);
    expect(transport.requests.single.token, 'token-a');
    await auth.verifyEmailCode('b@example.test', '654321');
    pending.complete(
      const CloudflareResponse(200, {'ok': true, 'deleted': true}),
    );
    await tester.pumpAndSettle();
    expect(auth.current.userId, 'b');
    expect(storage.value, contains('token-b'));
    expect(find.byKey(const Key('accountMessage')), findsNothing);
    expect(transport.requests, hasLength(1));
    await unmount(tester);
  });

  testWidgets('old account screen cannot act on a newer login', (tester) async {
    await mount(tester);
    await auth.verifyEmailCode('b@example.test', '654321');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мэдээллээ татах'));
    await tester.tap(find.text('Бүртгэл устгах'));
    await tester.tap(find.text('Гарах'));
    await tester.pumpAndSettle();
    expect(transport.requests, isEmpty);
    expect(auth.current.userId, 'b');
    expect(storage.value, contains('token-b'));
    expect(find.text('Бүртгэлээ устгах уу?'), findsNothing);
    await unmount(tester);
  });

  testWidgets('401 closes only the rejected login', (tester) async {
    transport.handle = (_) async =>
        const CloudflareResponse(401, {'ok': false, 'code': 'unauthenticated'});
    await mount(tester);
    await tester.tap(find.text('Мэдээллээ татах'));
    await tester.pumpAndSettle();
    expect(auth.current.isSignedIn, isFalse);
    expect(storage.value, isNull);
    expect(shared, isEmpty);
    await unmount(tester);
  });

  testWidgets(
    'export waits for all sections and cursor pages before sharing a complete file',
    (tester) async {
      final finalPage = Completer<CloudflareResponse>();
      transport.handle = (request) async {
        final section = request.body['section'] as String? ?? 'profile';
        if (section == 'billing_subscriptions') return finalPage.future;
        if (section == 'calendar' && request.body['cursor'] == null) {
          return _page(
            section,
            cursor: 'page-two',
            data: [
              {'title': 'First date'},
            ],
          );
        }
        return _page(
          section,
          data: section == 'calendar'
              ? [
                  {'title': 'Second date'},
                ]
              : [],
        );
      };
      await mount(tester);
      await tester.tap(find.text('Мэдээллээ татах'));
      await tester.pump();
      expect(transport.requests, hasLength(6));
      expect(shared, isEmpty);
      expect(temporary.listSync(), isEmpty);
      await tester.runAsync(() async {
        finalPage.complete(_page('billing_subscriptions'));
        await until(tester, () => shared.length == 1);
        await until(tester, () => temporary.listSync().isEmpty);
        // Real filesystem deletion can become visible before its Future resumes
        // the widget. Keep draining real I/O until the busy state also clears.
        await until(
          tester,
          () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
        );
      });
      await tester.pumpAndSettle();
      final pages = shared.single['pages'] as List;
      expect(pages.map((p) => (p as Map)['section']), [
        'profile',
        'calendar',
        'calendar',
        'daily_answers',
        'billing_orders',
        'billing_subscriptions',
      ]);
      expect(jsonEncode(shared), contains('First date'));
      expect(jsonEncode(shared), contains('Second date'));
      expect(transport.requests[2].body, {
        'section': 'calendar',
        'cursor': 'page-two',
      });
      expect(transport.requests.every((r) => r.token == 'token-a'), isTrue);
      expect(sharedPaths.single, endsWith('/hamtdaa-data.zip'));
      expect(shared.single['memories'], containsPair('count', 0));
      expect(File(sharedPaths.single).existsSync(), isFalse);
      expect(find.textContaining('Мэдээлэл бэлэн.'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('export includes digital greetings advertised by this server', (
    tester,
  ) async {
    transport.handle = (request) async {
      final section = request.body['section'] as String? ?? 'profile';
      return _page(
        section,
        sections: const [
          'profile',
          'calendar',
          'daily_answers',
          'flower_gifts',
          'billing_orders',
          'billing_subscriptions',
        ],
        data: section == 'flower_gifts'
            ? [
                {'message': 'Чамтай өдөр бүр илүү гоё.'},
              ]
            : [],
      );
    };
    await mount(tester);
    await tester.tap(find.text('Мэдээллээ татах'));
    await tester.pump();
    await tester.runAsync(() async {
      await until(tester, () => shared.length == 1);
      await until(tester, () => temporary.listSync().isEmpty);
      await until(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
    });
    await tester.pumpAndSettle();
    expect(
      (shared.single['pages'] as List).where(
        (p) => (p as Map)['section'] == 'flower_gifts',
      ),
      hasLength(1),
    );
    expect(jsonEncode(shared), contains('Чамтай өдөр бүр илүү гоё.'));
    await unmount(tester);
  });

  testWidgets('failed or repeating export page never shares a partial file', (
    tester,
  ) async {
    var repeat = false;
    transport.handle = (request) async {
      final section = request.body['section'] as String? ?? 'profile';
      if (section == 'profile') return _page(section);
      return repeat
          ? _page(section, cursor: 'same-cursor')
          : const CloudflareResponse(503, {'ok': false, 'code': 'unavailable'});
    };
    await mount(tester);
    await tester.tap(find.text('Мэдээллээ татах'));
    await tester.pumpAndSettle();
    expect(shared, isEmpty);
    expect(temporary.listSync(), isEmpty);
    expect(find.textContaining('Мэдээлэл татаж чадсангүй'), findsOneWidget);
    repeat = true;
    transport.requests.clear();
    await tester.tap(find.text('Мэдээллээ татах'));
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(3));
    expect(shared, isEmpty);
    expect(temporary.listSync(), isEmpty);
    await unmount(tester);
  });

  testWidgets('wrong profile identity cannot export another account', (
    tester,
  ) async {
    transport.handle = (_) async => _page('profile', actor: 'other');
    await mount(tester);
    await tester.tap(find.text('Мэдээллээ татах'));
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(1));
    expect(shared, isEmpty);
    expect(temporary.listSync(), isEmpty);
    expect(find.textContaining('Мэдээлэл татаж чадсангүй'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('missing pagination completion marker never shares an export', (
    tester,
  ) async {
    transport.handle = (_) async => const CloudflareResponse(200, {
      'ok': true,
      'export': {
        'schema_version': 1,
        'section': 'profile',
        'account': {'id': 'a'},
      },
    });
    await mount(tester);
    await tester.tap(find.text('Мэдээллээ татах'));
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(1));
    expect(shared, isEmpty);
    expect(temporary.listSync(), isEmpty);
    expect(find.textContaining('Мэдээлэл татаж чадсангүй'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'late export 401 after account switch neither shares nor logs out new user',
    (tester) async {
      final pending = Completer<CloudflareResponse>();
      transport.handle = (_) => pending.future;
      await mount(tester);
      await tester.tap(find.text('Мэдээллээ татах'));
      await tester.pump();
      await auth.verifyEmailCode('b@example.test', '654321');
      pending.complete(
        const CloudflareResponse(401, {'ok': false, 'code': 'unauthenticated'}),
      );
      await tester.pumpAndSettle();
      expect(auth.current.userId, 'b');
      expect(storage.value, contains('token-b'));
      expect(shared, isEmpty);
      expect(temporary.listSync(), isEmpty);
      expect(find.byKey(const Key('accountMessage')), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets(
    'closing an old account share sheet cannot publish success in the new account',
    (tester) async {
      final closeShare = Completer<String>();
      shareResult = () => closeShare.future;
      transport.handle = (request) async =>
          _page(request.body['section'] as String? ?? 'profile');
      await mount(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Мэдээллээ татах'));
        await until(tester, () => shared.length == 1);
      });
      await auth.verifyEmailCode('b@example.test', '654321');
      await tester.pump();
      await tester.runAsync(() async {
        closeShare.complete('example.application');
        await until(tester, () => temporary.listSync().isEmpty);
        // Real filesystem deletion can become visible before its Future resumes
        // the widget. Keep draining real I/O until the busy state also clears.
        await until(
          tester,
          () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
        );
      });
      await tester.pumpAndSettle();
      expect(auth.current.userId, 'b');
      expect(storage.value, contains('token-b'));
      expect(find.byKey(const Key('accountMessage')), findsNothing);
      expect(shared, hasLength(1));
      await unmount(tester);
    },
  );
}
