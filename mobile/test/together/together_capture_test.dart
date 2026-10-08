import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/together/together_controller.dart';
import 'package:hamtdaa/together/together_screen.dart';
import 'package:hamtdaa/ui/theme.dart';
import 'together_fakes.dart';

const _capture = bool.fromEnvironment('CAPTURE_TOGETHER_UI');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture Together fixture screens for visual review', (tester) async {
    await (FontLoader('Nunito')..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final repository = TogetherFakeRepository()
      ..value = stateJson(events: [eventJson(status: 'accepted')]);
    final controller = TogetherController(repository: repository, now: () => today);
    final auth = CloudflareAuthRepository(transport: TogetherTransport(), storage: TogetherStorage());
    addTearDown(controller.dispose);
    addTearDown(auth.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: RepaintBoundary(key: const Key('togetherCapture'),
      child: TogetherScreen(auth: auth, controller: controller))));
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('togetherCapture')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          const output = '/Users/izzy/Downloads/bolzoo/output/together-ui';
          await Directory(output).create(recursive: true);
          await File('$output/$name.png').writeAsBytes(bytes.buffer.asUint8List());
        } finally { image.dispose(); }
      });
    }
    await capture('01-calendar');
    await tester.tap(find.text('Өдрийн асуулт'));
    await tester.pumpAndSettle();
    await capture('02-daily-question');
    repository.value = stateJson(events: [eventJson(status: 'accepted')],
      daily: dailyJson(mine: 'Тэрэлжийн тэр өдөр. Бороо орсон ч хамтдаа алхсан нь хамгийн гоё байсан.',
        partner: 'Чиний инээмсэглэж байсан анхны уулзалтаа хэзээ ч мартдаггүй.', both: true));
    await controller.refresh(quiet: true);
    await tester.pumpAndSettle();
    await capture('03-both-answers');
    await tester.tap(find.text('Хуанли'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('togetherCreate')));
    await tester.tap(find.byKey(const Key('togetherCreate')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('togetherTitle')), 'Кофе уух уу?');
    await tester.enterText(find.byKey(const Key('togetherLocation')), 'Little Heaven');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await capture('04-create-date');
    repository.value = stateJson(paired: false);
    await controller.refresh(quiet: true);
    await tester.pumpAndSettle();
    await capture('05-unpaired');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  }, skip: !_capture);
}
