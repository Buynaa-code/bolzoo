import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/gifts/gifts_screen.dart';
import 'package:hamtdaa/features/home/home_screen.dart';
import 'package:hamtdaa/features/ideas/ideas_screen.dart';
import 'package:hamtdaa/ui/theme.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final symbols = FontLoader('NotoSansSymbols2')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSymbols2-Regular.ttf'));
    await symbols.load();
  });
  testWidgets('render native gift design review', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    final now = DateTime(2026, 9, 28, 12);
    final c = AppController(
      MemoryAppStore(
        AppData(
          profile: UserProfile(
            name: 'Ану',
            togetherSince: now.subtract(const Duration(days: 424)),
          ),
          events: [
            DateEvent(
              id: 'preview-event',
              title: 'Кофе уух уу?',
              startsAt: now.add(const Duration(days: 1)),
              createdAt: now,
              place: 'Little Heaven',
            ),
          ],
        ),
      ),
    );
    await c.load();
    final greeting = FlowerGreeting(
      id: 'preview-flower',
      templateId: 'bloom',
      colorId: 'rose',
      occasion: 'Зүгээр л',
      recipientName: 'Ану',
      senderName: 'Тэмүүлэн',
      message: 'Чамтай өдөр бүр илүү гоё.',
      createdAt: now,
    );
    final screens = <String, Widget>{
      'home': Scaffold(
        body: HomeScreen(controller: c, onTab: (_) {}, clock: () => now),
      ),
      'ideas': IdeasScreen(controller: c),
      'flower-editor': FlowerEditor(controller: c),
      'flower-preview': FlowerPreview(controller: c, greeting: greeting),
      'invite-editor': InvitationEditor(controller: c, clock: () => now),
    };
    for (final screen in screens.entries) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: RepaintBoundary(key: const Key('capture'), child: screen.value),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: screen.key);
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile('goldens/legacy/${screen.key}.png'),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
