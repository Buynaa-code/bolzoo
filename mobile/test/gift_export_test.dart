import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/features/gifts/gift_export.dart';

void main() {
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const shares = MethodChannel('dev.fluttercommunity.plus/share');
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('hamtdaa-gift-export-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (call) async {
          if (call.method == 'getTemporaryDirectory' ||
              call.method == 'getTemporaryPath') {
            return temporary.path;
          }
          throw PlatformException(code: 'unexpected_path_request');
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(paths, null)
      ..setMockMethodCallHandler(shares, null);
    await temporary.delete(recursive: true);
  });

  Future<BuildContext> render(WidgetTester tester, GlobalKey key) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return RepaintBoundary(
                key: key,
                child: const SizedBox(
                  width: 100,
                  height: 100,
                  child: ColoredBox(color: Colors.pink),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return context;
  }

  testWidgets('permanent PNG is written in supplied account directory', (tester) async {
    final key = GlobalKey();
    await render(tester, key);
    final account = Directory('${temporary.path}/accounts/example');
    await tester.runAsync(() async {
      final capture = captureGiftPng(key, permanent: true, documentsDirectory: account);
      await tester.pump();
      final path = await capture;
      expect(path, startsWith('${account.path}/memories_media/'));
      expect((await File(path).readAsBytes()).take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });
  });

  for (final result in ['success', 'dismissed', 'failure']) {
    testWidgets('share $result removes only its temporary PNG', (tester) async {
      final key = GlobalKey();
      final context = await render(tester, key);
      var invoked = false;
      String? sharedPath;
      await tester.runAsync(() async {
        final directory = await Directory('${temporary.path}/gift_exports').create();
        final unrelated = await File('${directory.path}/other-account.png').writeAsString('keep');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(shares, (call) async {
              invoked = true;
              final arguments = call.arguments as Map;
              sharedPath = (arguments['paths'] as List).single as String;
              expect(await File(sharedPath!).exists(), isTrue);
              expect(await File(sharedPath!).length(), greaterThan(0));
              if (result == 'failure') throw PlatformException(code: 'share_failed');
              return result == 'dismissed' ? '' : 'example.application';
            });
        final sharing = shareGiftPng(key, context, title: 'Greeting');
        final checked = result == 'failure'
            ? expectLater(sharing, throwsA(isA<PlatformException>()))
            : sharing;
        await tester.pump();
        await checked;
        expect(invoked, isTrue);
        expect(await File(sharedPath!).exists(), isFalse);
        expect(await unrelated.readAsString(), 'keep');
      });
    });
  }
}
