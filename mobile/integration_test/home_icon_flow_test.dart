// Native render/share flow with only the photo picker and OS share boundary
// substituted. HOME_ICON_SHARE_REVIEW opens the real sheet for manual review.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/profile/home_icon_screen.dart';
import 'package:hamtdaa/main_supabase_legacy.dart';
import 'package:hamtdaa/ui/theme.dart';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<Uint8List> _photoFixture() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFFFD9E9), BlendMode.src);
  for (var i = 0; i < 2; i++) {
    final x = 260.0 + 480 * i;
    canvas.drawOval(Rect.fromCenter(center: Offset(x, 800), width: 500, height: 660),
      Paint()..color = i == 0 ? const Color(0xFFBD426E) : const Color(0xFF44577B));
    canvas.drawOval(Rect.fromCenter(center: Offset(x, 330), width: 275, height: 350),
      Paint()..color = const Color(0xFF5D3930));
    canvas.drawOval(Rect.fromCenter(center: Offset(x, 380), width: 235, height: 290),
      Paint()..color = const Color(0xFFF7C49D));
    canvas.drawCircle(Offset(x - 45, 370), 12, Paint()..color = const Color(0xFF422D34));
    canvas.drawCircle(Offset(x + 45, 370), 12, Paint()..color = const Color(0xFF422D34));
    canvas.drawArc(Rect.fromCenter(center: Offset(x, 400), width: 75, height: 65),
      0, 3.14, false, Paint()..color = const Color(0xFFB04863)..style = PaintingStyle.stroke..strokeWidth = 10);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(1000, 1000);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  const review = bool.fromEnvironment('HOME_ICON_SHARE_REVIEW');

  testWidgets('native profile to couple icon, PNG share, and cleanup', (tester) async {
    final controller = AppController(MemoryAppStore());
    await controller.load();
    await tester.pumpWidget(HamtdaaApp(controller: controller));
    await tester.pumpAndSettle();
    await _tap(tester, find.descendant(of: find.byType(NavigationBar), matching: find.text('Бид')));
    await tester.scrollUntilVisible(find.byKey(const Key('openHomeIconScreen')), 220,
      scrollable: find.byType(Scrollable).last);
    await _tap(tester, find.byKey(const Key('openHomeIconScreen')));
    expect(find.byType(HomeIconScreen), findsOneWidget);
    final fixture = await _photoFixture();
    // A controlled picker return lets the test exercise the real editor and
    // native rendering deterministically without touching the user's library.
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(),
      home: HomeIconScreen(platform: TargetPlatform.iOS, pickPhoto: () async => fixture)));
    await tester.pumpAndSettle();
    String? sharedPath;
    Uint8List? sharedPng;
    var calls = 0;
    final temporary = await getTemporaryDirectory();
    final evidence = await Directory('${temporary.path}/home-icon-evidence').create();
    if (!review) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        final arguments = call.arguments as Map;
        expect(arguments['mimeTypes'], ['image/png']);
        expect(arguments['originWidth'], greaterThan(0));
        sharedPath = (arguments['paths'] as List).single as String;
        sharedPng = await File(sharedPath!).readAsBytes();
        return '';
      });
    }
    try {
      await _tap(tester, find.byKey(const Key('homeIconPhoto0')));
      expect(tester.takeException(), isNull);
      expect(tester.widget<FilledButton>(find.byKey(const Key('homeIconPrimary'))).onPressed, isNotNull);
      final screenshot = await binding.takeScreenshot('19-home-icon');
      await File('${evidence.path}/19-home-icon.png').writeAsBytes(screenshot);
      await tester.ensureVisible(find.byKey(const Key('homeIconPrimary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('homeIconPrimary')));
      if (review) debugPrint('Home icon review: inspect Save Image in the native sheet, then dismiss.');
      await tester.pumpAndSettle(const Duration(milliseconds: 200),
        EnginePhase.sendSemanticsUpdate, const Duration(minutes: 2));
      if (!review) {
        expect(calls, 1);
        expect(sharedPng!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final codec = await ui.instantiateImageCodec(sharedPng!);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1024);
        expect(frame.image.height, 1024);
        final pixels = (await frame.image.toByteData())!;
        // Faces on both sides survive the single-photo square crop.
        for (final x in [265, 758]) {
          final offset = (389 * 1024 + x) * 4;
          expect(pixels.getUint8(offset), greaterThan(220));
          expect(pixels.getUint8(offset + 1), greaterThan(150));
        }
        frame.image.dispose();
        codec.dispose();
        await File('${evidence.path}/couple-icon.png').writeAsBytes(sharedPng!);
        expect(await File(sharedPath!).parent.exists(), isFalse);
        expect(find.textContaining('Хадгалах цэсийг хаалаа'), findsOneWidget);
      }
      expect(find.textContaining('Дүрсийг бэлтгэж чадсангүй'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
}
