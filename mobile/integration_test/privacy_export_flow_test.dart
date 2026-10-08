// Native filesystem + actual navigation and ZIP creation. The unattended test
// captures only the OS share boundary. Set PRIVACY_SHARE_REVIEW=true to review
// the real iOS/Android sheet and cancel it manually; nothing is sent by the test.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/main.dart';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<(Directory, AppController, File)> _launch(WidgetTester tester) async {
  final base = await getTemporaryDirectory();
  final directory = await Directory(base.path).createTemp('hamtdaa-privacy-');
  final media = await Directory(
    '${directory.path}/memories_media',
  ).create(recursive: true);
  final photo = File('${media.path}/fixture.jpg');
  await photo.writeAsBytes(
    (await rootBundle.load('assets/gifts/mountains.jpg')).buffer.asUint8List(),
  );
  final controller = AppController(
    FileAppStore(File('${directory.path}/hamtdaa.json')),
  );
  await controller.load();
  await controller.updateProfile(const UserProfile(name: 'Туршилтын Ану'));
  await controller.saveMemory(
    MemoryEntry(
      id: 'own-private-memory',
      title: 'Миний хуулбарын дурсамж',
      date: DateTime(2026, 9, 20),
      text: 'Зөвхөн туршилтын мэдээлэл.',
      photoPath: photo.path,
    ),
  );
  await tester.pumpWidget(HamtdaaApp(controller: controller));
  await tester.pumpAndSettle();
  await _tap(
    tester,
    find.descendant(of: find.byType(NavigationBar), matching: find.text('Бид')),
  );
  await _tap(tester, find.byKey(const Key('openPrivacyScreen')));
  return (directory, controller, photo);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');

  testWidgets(
    'native profile exports actual records and photos ZIP and cleans staging',
    (tester) async {
      final (directory, controller, photo) = await _launch(tester);
      String? sharedPath;
      List<int>? exportedBytes;
      Map<Object?, Object?>? shareArguments;
      var shareCalls = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method != 'share') throw UnsupportedError(call.method);
        shareCalls++;
        shareArguments = call.arguments as Map<Object?, Object?>;
        sharedPath = (shareArguments!['paths'] as List).single as String;
        exportedBytes = await File(sharedPath!).readAsBytes();
        // Empty native result means the user dismissed the sheet.
        return '';
      });
      try {
        expect(find.textContaining('Та төхөөрөмж дээрээ ашиглаж байна.'), findsOneWidget);
        await _tap(tester, find.byKey(const Key('exportAccountData')));
        expect(find.text('Хуулбар бэлэн боллоо.'), findsOneWidget);
        expect(shareCalls, 1);
        expect(shareArguments!['mimeTypes'], ['application/zip']);
        expect(shareArguments!['subject'], 'Хамтдаа — миний мэдээлэл');
        expect(shareArguments!['originWidth'], greaterThan(0));
        final archive = ZipDecoder().decodeBytes(exportedBytes!, verify: true);
        final records = jsonDecode(
          utf8.decode(archive.findFile('records.json')!.content),
        ) as Map<String, dynamic>;
        expect(records['format'], 'hamtdaa-personal-export');
        final device = records['deviceRecords'] as Map<String, dynamic>;
        expect((device['profile'] as Map)['name'], 'Туршилтын Ану');
        final memory = (device['memories'] as List).single as Map;
        expect(memory['id'], 'own-private-memory');
        expect(memory.containsKey('photoPath'), isFalse);
        final exportedPhoto = archive.findFile(memory['exportPhoto'] as String)!;
        expect(exportedPhoto.content, await photo.readAsBytes());
        expect(await File(sharedPath!).exists(), isFalse);
        expect(await File(sharedPath!).parent.exists(), isFalse);
        expect(await photo.exists(), isTrue);
        expect((await controller.exportOwnSnapshot()).memories.single.photoPath, photo.path);
        expect(tester.takeException(), isNull);
      } finally {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'personal ZIP opens native share sheet and cancellation erases staging',
    (tester) async {
      final (directory, controller, photo) = await _launch(tester);
      final exports = Directory('${(await getTemporaryDirectory()).path}/account_exports');
      final previous = await exports.exists()
          ? (await exports.list().toList()).map((entry) => entry.path).toSet()
          : <String>{};
      try {
        final button = find.byKey(const Key('exportAccountData'));
        await tester.scrollUntilVisible(button, 220, scrollable: find.byType(Scrollable).last);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        debugPrint('Privacy ZIP share review: inspect the native sheet, then cancel.');
        await tester.pumpAndSettle(
          const Duration(milliseconds: 200),
          EnginePhase.sendSemanticsUpdate,
          const Duration(minutes: 2),
        );
        expect(find.text('Хуулбар бэлэн боллоо.'), findsOneWidget);
        expect(
          (await exports.list().toList()).where((entry) => !previous.contains(entry.path)),
          isEmpty,
        );
        expect(await photo.exists(), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('PRIVACY_SHARE_REVIEW'),
  );
}
