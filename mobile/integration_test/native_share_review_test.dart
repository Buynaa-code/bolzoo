// Manual OS-sheet review: run on an iPhone simulator and close the share sheet.
// No message or photo is sent. Disabled in unattended native suites.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/gifts/gifts_screen.dart';
import 'package:hamtdaa/ui/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('flower PNG opens native share and cancellation returns safely', (
    tester,
  ) async {
    final controller = AppController(MemoryAppStore());
    await controller.load();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: FlowerPreview(controller: controller, greeting: FlowerGreeting(
        id: 'native-share-fixture', templateId: 'letter', colorId: 'rose',
        occasion: 'Зүгээр л', recipientName: 'Ану', senderName: 'Тэмүүлэн',
        message: 'Чамтай өдөр бүр илүү гоё.', createdAt: DateTime.now(),
      )),
    ));
    await tester.pumpAndSettle();
    final directory = Directory('${(await getTemporaryDirectory()).path}/gift_exports');
    final previous = await directory.exists()
        ? (await directory.list().toList()).map((file) => file.path).toSet()
        : <String>{};
    final share = find.text('Зураг татах / хуваалцах');
    await tester.ensureVisible(share);
    await tester.pumpAndSettle();
    await tester.tap(share);
    debugPrint('Native share review: inspect the iOS sheet, then cancel.');
    await tester.pumpAndSettle(const Duration(milliseconds: 200),
      EnginePhase.sendSemanticsUpdate, const Duration(minutes: 2));
    expect(find.text('Зураг бэлдэж чадсангүй. Дахин оролдоорой.'), findsNothing);
    final button = tester.widget<OutlinedButton>(find.ancestor(of: share, matching: find.byType(OutlinedButton)));
    expect(button.onPressed, isNotNull);
    final created = (await directory.list().toList()).where((file) => !previous.contains(file.path));
    expect(created, isNotEmpty);
    for (final file in created) {
      expect(await File(file.path).length(), greaterThan(1000));
      await file.delete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  }, skip: !const bool.fromEnvironment('NATIVE_SHARE_REVIEW'));
}
