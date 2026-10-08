import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/profile/home_icon_renderer.dart';
import 'package:hamtdaa/features/profile/home_icon_screen.dart';
import 'package:hamtdaa/features/profile/home_icon_service.dart';
import 'package:hamtdaa/features/profile/profile_screen.dart';
import 'package:hamtdaa/ui/theme.dart';
import 'package:share_plus/share_plus.dart';

class _Service extends HomeIconService {
  _Service({this.pinResult = HomeIconPinResult.requested,
    this.shareResult = ShareResultStatus.success, this.fail = false});

  final HomeIconPinResult pinResult;
  final ShareResultStatus shareResult;
  final bool fail;
  int pinCalls = 0;
  int shareCalls = 0;
  Uint8List? png;
  String? name;
  Rect? origin;

  @override
  Future<HomeIconPinResult> pin(Uint8List png, String name) async {
    pinCalls++;
    this.png = png;
    this.name = name;
    if (fail) throw PlatformException(code: 'pin_failed');
    return pinResult;
  }

  @override
  Future<ShareResultStatus> share(Uint8List png, Rect origin) async {
    shareCalls++;
    this.png = png;
    this.origin = origin;
    if (fail) throw PlatformException(code: 'share_failed');
    return shareResult;
  }
}

// Fictional portraits with predictable skin, shirt and background landmarks.
// No user or network photos are needed to verify the rendered composition.
Future<Uint8List> _portrait({
  Color background = const Color(0xFF2563EB),
  Color skin = const Color(0xFFFFD5B5),
  Color shirt = const Color(0xFFEA407A),
  int width = 128,
  int height = 256,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(width / 128, height / 256);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 128, 256), Paint()..color = background);
  canvas.drawCircle(const Offset(64, 72), 30, Paint()..color = skin);
  canvas.drawRect(const Rect.fromLTWH(32, 110, 64, 146), Paint()..color = shirt);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

List<int> _pixel(ByteData pixels, int width, int x, int y) =>
    List.generate(4, (channel) => pixels.getUint8((y * width + x) * 4 + channel));

Future<void> _launch(WidgetTester tester, {
  required HomeIconPhotoPicker picker,
  HomeIconService service = const HomeIconService(),
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: HomeIconScreen(pickPhoto: picker, service: service, platform: platform),
  ));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scroll = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder, 180, scrollable: scroll);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

// Image decoding and PNG encoding finish on the engine, outside fake time.
// Wait for the UI to finish its operation instead of sleeping a fixed duration.
Future<void> _nativeTap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await _reveal(tester, finder);
  await tester.runAsync(() async {
    await tester.tap(finder);
    await tester.pump();
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (tester.widget<ButtonStyleButton>(finder).onPressed == null) {
      if (DateTime.now().isAfter(deadline)) fail('Operation $key did not finish');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}

Future<bool> _canExport(WidgetTester tester) async {
  final finder = find.byKey(const Key('homeIconPrimary'));
  await _reveal(tester, finder);
  return tester.widget<FilledButton>(finder).onPressed != null;
}

Future<HomeIconPainter> _painter(WidgetTester tester) async {
  final finder = find.byKey(const Key('homeIconPreview'));
  await _reveal(tester, finder);
  return tester.widget<CustomPaint>(finder).painter! as HomeIconPainter;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List firstPhoto;
  late Uint8List secondPhoto;
  setUpAll(() async {
    await (FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
    firstPhoto = await _portrait();
    secondPhoto = await _portrait(background: const Color(0xFFFACC15),
      skin: const Color(0xFFAD7659), shirt: const Color(0xFF16A34A));
  });

  test('1024 PNG preserves both portraits and renders D-1 in its lower region', () async {
    final first = await decodeHomeIconPhoto(firstPhoto);
    final second = await decodeHomeIconPhoto(secondPhoto);
    final png = await renderHomeIconPng(HomeIconPainter(
      photos: [first, second], label: 'D-1', split: true));
    final blankPng = await renderHomeIconPng(HomeIconPainter(
      photos: [first, second], label: '', split: true));
    final image = await _decode(png);
    final blank = await _decode(blankPng);
    try {
      expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect((image.width, image.height), (1024, 1024));
      final pixels = (await image.toByteData())!;
      final baseline = (await blank.toByteData())!;
      expect(_pixel(pixels, 1024, 64, 64), [37, 99, 235, 255]);
      expect(_pixel(pixels, 1024, 576, 64), [250, 204, 21, 255]);
      expect(_pixel(pixels, 1024, 256, 288), [255, 213, 181, 255]);
      expect(_pixel(pixels, 1024, 768, 288), [173, 118, 89, 255]);
      var textPixels = 0;
      for (var y = 700; y < 1000; y++) {
        for (var x = 120; x < 904; x++) {
          final offset = (y * 1024 + x) * 4;
          if (pixels.getUint8(offset) > 235 &&
              pixels.getUint8(offset + 1) > 235 &&
              pixels.getUint8(offset + 2) > 235 &&
              pixels.getUint8(offset) != baseline.getUint8(offset)) {
            textPixels++;
          }
        }
      }
      expect(textPixels, greaterThan(5000));
    } finally {
      image.dispose(); blank.dispose(); first.dispose(); second.dispose();
    }
  });

  test('photo decoder rejects empty, oversized and corrupt images', () async {
    await expectLater(decodeHomeIconPhoto(Uint8List(0)), throwsFormatException);
    await expectLater(decodeHomeIconPhoto(Uint8List(20 * 1024 * 1024 + 1)),
      throwsFormatException);
    await expectLater(decodeHomeIconPhoto(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(anything));
  });

  test('photo decoder caps resolution and preserves its aspect ratio', () async {
    final photo = await decodeHomeIconPhoto(await _portrait(width: 3200, height: 800));
    try { expect((photo.width, photo.height), (1600, 400)); }
    finally { photo.dispose(); }
  });

  testWidgets('one-photo and two-photo modes enforce their own photo requirements', (tester) async {
    var selections = 0;
    await _launch(tester, picker: () async => selections++ == 0 ? firstPhoto : secondPhoto);
    expect(await _canExport(tester), isFalse);
    await _nativeTap(tester, 'homeIconPhoto0');
    expect(await _canExport(tester), isTrue);
    await _tap(tester, find.text('Хоёр зураг'));
    expect(await _canExport(tester), isFalse);
    await _nativeTap(tester, 'homeIconPhoto1');
    expect(await _canExport(tester), isTrue);
    final painter = await _painter(tester);
    expect(painter.split, isTrue);
    expect(painter.photos.every((image) => image != null), isTrue);
    await _tap(tester, find.text('Хамтын зураг'));
    expect(await _canExport(tester), isTrue);
    expect((await _painter(tester)).split, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled or invalid photo picking cannot enable export', (tester) async {
    var selections = 0;
    await _launch(tester, picker: () async => selections++ == 0
      ? null : Uint8List.fromList([1, 2, 3]));
    await _nativeTap(tester, 'homeIconPhoto0');
    expect(await _canExport(tester), isFalse);
    expect(find.byKey(const Key('homeIconStatus')), findsNothing);
    await _nativeTap(tester, 'homeIconPhoto0');
    expect(await _canExport(tester), isFalse);
    expect(find.textContaining('Энэ зургийг нээж чадсангүй'), findsOneWidget);
  });

  testWidgets('label and name edits update preview and required-field validation', (tester) async {
    await _launch(tester, picker: () async => firstPhoto);
    await _nativeTap(tester, 'homeIconPhoto0');
    expect((await _painter(tester)).label, 'D-1');
    final label = find.byKey(const Key('homeIconLabel'));
    await _reveal(tester, label);
    await tester.enterText(label, 'D+425');
    await tester.pump();
    expect((await _painter(tester)).label, 'D+425');
    await _reveal(tester, label);
    await tester.enterText(label, '   ');
    await tester.pump();
    expect(await _canExport(tester), isFalse);
    await _reveal(tester, label);
    await tester.enterText(label, 'D-1');
    final name = find.byKey(const Key('homeIconName'));
    await _reveal(tester, name);
    await tester.enterText(name, '  ');
    await tester.pump();
    expect(await _canExport(tester), isFalse);
    await _reveal(tester, name);
    await tester.enterText(name, 'Бид хоёр');
    await tester.pump();
    expect(await _canExport(tester), isTrue);
  });

  testWidgets('crop controls change only the selected portrait', (tester) async {
    var selections = 0;
    await _launch(tester, picker: () async => selections++ == 0 ? firstPhoto : secondPhoto);
    await _tap(tester, find.text('Хоёр зураг'));
    await _nativeTap(tester, 'homeIconPhoto0');
    await _nativeTap(tester, 'homeIconPhoto1');
    await _tap(tester, find.text('Зургийн байрлал'));
    for (var i = 0; i < 3; i++) {
      final slider = find.byType(Slider).at(i);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.right - 25, rect.center.dy));
      await tester.pumpAndSettle();
    }
    final painter = await _painter(tester);
    expect(painter.zooms.first, 1);
    expect(painter.alignments.first, Alignment.center);
    expect(painter.zooms[1], greaterThan(2.5));
    expect(painter.alignments[1].x, greaterThan(.7));
    expect(painter.alignments[1].y, greaterThan(.7));
  });

  testWidgets('iOS instructions explain Open App and selecting the exported photo', (tester) async {
    await _launch(tester, picker: () async => firstPhoto);
    await _reveal(tester, find.text('iPhone дээр нэмэх'));
    expect(find.textContaining('Shortcuts апп'), findsOneWidget);
    expect(find.textContaining('Open App'), findsOneWidget);
    expect(find.textContaining('Add to Home Screen'), findsOneWidget);
    expect(find.textContaining('Choose Photo'), findsOneWidget);
    expect(find.textContaining('Хамтдаа аппыг сонгоно'), findsOneWidget);
    expect(find.text('Нүүр дэлгэцэд нэмэх'), findsNothing);
  });

  for (final entry in {
    HomeIconPinResult.requested: 'Нэмэх хүсэлт нээгдлээ.',
    HomeIconPinResult.updated: 'Нүүр дэлгэцийн товчлол шинэчлэгдлээ.',
    HomeIconPinResult.unsupported: 'Энэ утас зурагтай товчлол нэмэхийг дэмжихгүй байна.',
  }.entries) {
    testWidgets('Android ${entry.key.name} reports the actual launcher result', (tester) async {
      final service = _Service(pinResult: entry.key);
      await _launch(tester, picker: () async => firstPhoto,
        service: service, platform: TargetPlatform.android);
      await _nativeTap(tester, 'homeIconPhoto0');
      await _nativeTap(tester, 'homeIconPrimary');
      expect(service.pinCalls, 1);
      expect(service.shareCalls, 0);
      expect(service.name, 'Хамтдаа');
      expect(service.png!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(find.textContaining(entry.value), findsOneWidget);
      if (entry.key != HomeIconPinResult.updated) {
        expect(find.text('Нүүр дэлгэцийн товчлол шинэчлэгдлээ.'), findsNothing);
      }
      expect(await _canExport(tester), isTrue);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('${platform.name} export failure shows no successful completion', (tester) async {
      final service = _Service(fail: true);
      await _launch(tester, picker: () async => firstPhoto,
        service: service, platform: platform);
      await _nativeTap(tester, 'homeIconPhoto0');
      await _nativeTap(tester, 'homeIconPrimary');
      expect(find.text('Дүрсийг бэлтгэж чадсангүй. Дахин оролдоорой.'), findsOneWidget);
      expect(find.textContaining('Нэмэх хүсэлт нээгдлээ.'), findsNothing);
      expect(find.textContaining('шинэчлэгдлээ.'), findsNothing);
      expect(find.textContaining('Дүрс бэлэн.'), findsNothing);
      expect(await _canExport(tester), isTrue);
    });
  }

  testWidgets('iOS share cancellation stays distinct from saving', (tester) async {
    final service = _Service(shareResult: ShareResultStatus.dismissed);
    await _launch(tester, picker: () async => firstPhoto, service: service);
    await _nativeTap(tester, 'homeIconPhoto0');
    await _nativeTap(tester, 'homeIconPrimary');
    expect(service.pinCalls, 0);
    expect(service.shareCalls, 1);
    expect(service.origin!.width, greaterThan(0));
    expect(find.textContaining('Хадгалах цэсийг хаалаа.'), findsOneWidget);
    expect(find.textContaining('Дүрс бэлэн.'), findsNothing);
  });

  testWidgets('profile opens the couple-photo icon editor', (tester) async {
    final controller = AppController(MemoryAppStore());
    await controller.load();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(),
      home: Scaffold(body: ProfileScreen(controller: controller))));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('openHomeIconScreen')));
    expect(find.byType(HomeIconScreen), findsOneWidget);
    expect((await _painter(tester)).label, 'D-1');
  });

  group('native service boundaries', () {
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const shares = MethodChannel('dev.fluttercommunity.plus/share');
    const pins = MethodChannel('mn.moch.hamtdaa/home_icon');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('hamtdaa-home-icon-test-');
      messenger.setMockMethodCallHandler(paths, (call) async {
        if (call.method == 'getTemporaryDirectory' || call.method == 'getTemporaryPath') {
          return directory.path;
        }
        throw UnsupportedError(call.method);
      });
    });
    tearDown(() async {
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMethodCallHandler(shares, null);
      messenger.setMockMethodCallHandler(pins, null);
      await directory.delete(recursive: true);
    });

    for (final outcome in ['success', 'cancel', 'failure']) {
      test('share $outcome cleans only its staging and preserves the source', () async {
        final source = await File('${directory.path}/source.png').writeAsBytes(firstPhoto);
        final unrelated = await Directory('${directory.path}/existing-export').create();
        final keep = await File('${unrelated.path}/keep.png').writeAsBytes(secondPhoto);
        String? sharedPath;
        var calls = 0;
        messenger.setMockMethodCallHandler(shares, (call) async {
          expect(call.method, 'share');
          calls++;
          final args = call.arguments as Map;
          sharedPath = (args['paths'] as List).single as String;
          expect(await File(sharedPath!).readAsBytes(), firstPhoto);
          expect(args['mimeTypes'], ['image/png']);
          expect(args['originWidth'], 100);
          expect(args['originHeight'], 40);
          if (outcome == 'failure') throw PlatformException(code: 'share_failed');
          return outcome == 'cancel' ? '' : 'com.apple.UIKit.activity.SaveToCameraRoll';
        });
        final sharing = const HomeIconService().share(firstPhoto, const Rect.fromLTWH(10, 20, 100, 40));
        if (outcome == 'failure') {
          await expectLater(sharing, throwsA(isA<PlatformException>()));
        } else {
          expect(await sharing, outcome == 'cancel' ? ShareResultStatus.dismissed : ShareResultStatus.success);
        }
        expect(calls, 1);
        expect(await File(sharedPath!).exists(), isFalse);
        expect(await File(sharedPath!).parent.exists(), isFalse);
        expect(await source.readAsBytes(), firstPhoto);
        expect(await keep.readAsBytes(), secondPhoto);
      });
    }

    for (final outcome in ['requested', 'updated', 'unsupported', 'unknown']) {
      test('pin maps $outcome without converting an unknown response to success', () async {
        messenger.setMockMethodCallHandler(pins, (call) async {
          expect(call.method, 'pinPhotoIcon');
          final args = call.arguments as Map;
          expect(args['png'], firstPhoto);
          expect(args['label'], 'Бид хоёр');
          return outcome;
        });
        final pinning = const HomeIconService().pin(firstPhoto, 'Бид хоёр');
        if (outcome == 'unknown') {
          await expectLater(pinning, throwsFormatException);
        } else {
          expect(await pinning, HomeIconPinResult.values.byName(outcome));
        }
      });
    }
  });
}
