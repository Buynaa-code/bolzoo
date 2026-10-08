import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/memories/memories_screen.dart';
import 'package:hamtdaa/features/places/places_map.dart';
import 'package:hamtdaa/features/places/places_screen.dart';
import 'package:hamtdaa/ui/theme.dart';

class _FailingStore implements AppStore {
  _FailingStore(this.data);
  AppData data;
  bool fail = true;
  @override
  Future<AppData> read() async => data;
  @override
  Future<void> write(AppData value) async {
    if (fail) throw StateError('simulated full storage');
    data = AppData.fromJson(jsonDecode(jsonEncode(value.toJson())) as Map<String, dynamic>);
  }
}

void _device(WidgetTester tester, {double scale = 1}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<AppController> _launch(WidgetTester tester, AppStore store, Widget Function(AppController) home) async {
  _device(tester);
  final controller = AppController(store);
  await controller.load();
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: home(controller)));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, value);
  await tester.pump();
}

PlaceEntry _place() => PlaceEntry(id: 'terelj', name: 'Тэрэлж', address: 'Горхи-Тэрэлж', latitude: 47.984, longitude: 107.452, createdAt: DateTime(2026, 9, 1));

void main() {
  testWidgets('month filter uses actual records and can return to all memories', (tester) async {
    final store = MemoryAppStore(AppData(memories: [
      MemoryEntry(id: 'september', title: 'Намрын алхалт', date: DateTime(2026, 9, 20)),
      MemoryEntry(id: 'august', title: 'Зуны аялал', date: DateTime(2026, 8, 10)),
    ]));
    final controller = await _launch(tester, store, (c) => Scaffold(body: MemoriesScreen(controller: c)));
    await _tap(tester, 'memoriesMonthFilter');
    await _tap(tester, 'memoryMonth-2026-8');
    expect(find.text('Зуны аялал'), findsOneWidget);
    expect(find.text('Намрын алхалт'), findsNothing);
    expect(find.text('1 дурсамж'), findsOneWidget);
    await _tap(tester, 'memoriesMonthFilter');
    await _tap(tester, 'memoriesAllMonths');
    expect(find.text('Намрын алхалт'), findsOneWidget);
    expect(controller.data.memories, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('place editor validates paired coordinates and persists a real place', (tester) async {
    final store = MemoryAppStore();
    final controller = await _launch(tester, store, (c) => PlacesScreen(controller: c));
    await _tap(tester, 'placesAddButton');
    await _enter(tester, 'placeName', '  Тэрэлж  ');
    await _enter(tester, 'placeLatitude', '120');
    await _tap(tester, 'savePlaceButton');
    expect(controller.data.places, isEmpty);
    expect(find.text('-90–90 хооронд оруулна уу.'), findsOneWidget);
    await _enter(tester, 'placeLatitude', '47.984');
    await _enter(tester, 'placeLongitude', '107.452');
    await _enter(tester, 'placeNote', '  Дахиад очмоор газар.  ');
    await _tap(tester, 'savePlaceButton');
    expect(controller.data.places, hasLength(1));
    final saved = (await store.read()).places.single;
    expect(saved.name, 'Тэрэлж');
    expect(saved.latitude, 47.984);
    expect(saved.longitude, 107.452);
    expect(saved.note, 'Дахиад очмоор газар.');
    expect(find.byKey(ValueKey('placePin-${saved.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('place detail links existing memory and deletion preserves content', (tester) async {
    final memory = MemoryEntry(id: 'original', title: 'Тэр өдрийн тухай', date: DateTime(2026, 9, 20), text: 'Хадгалсан эх бичвэр', photoPath: '/tmp/preserved-gallery-original.jpg');
    final store = MemoryAppStore(AppData(places: [_place()], memories: [memory]));
    final controller = await _launch(tester, store, (c) => PlacesScreen(controller: c));
    await _tap(tester, 'placeCard-terelj');
    await _tap(tester, 'placeLinkMemoryButton');
    await _tap(tester, 'linkMemory-original');
    expect(controller.data.memories.single.placeId, 'terelj');
    expect(controller.data.memories.single.place, 'Тэрэлж');
    expect(find.byKey(const ValueKey('placeMemory-original')), findsOneWidget);
    await tester.tap(find.byTooltip('Газар устгах'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Устгах'));
    await tester.pumpAndSettle();
    expect(controller.data.places, isEmpty);
    expect(controller.data.memories.single.placeId, isNull);
    expect(controller.data.memories.single.text, memory.text);
    expect(controller.data.memories.single.photoPath, memory.photoPath);
    expect((await store.read()).memories.single.title, memory.title);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new memory from place saves its location and keeps typed note', (tester) async {
    final store = MemoryAppStore(AppData(places: [_place()]));
    final controller = await _launch(tester, store, (c) => PlaceDetailScreen(controller: c, placeId: 'terelj'));
    await _tap(tester, 'placeNewMemoryButton');
    await _enter(tester, 'memoryTitle', 'Нандин мөч');
    await _enter(tester, 'memoryText', 'Хамт байсан болохоор гоё.');
    await _tap(tester, 'saveMemoryButton');
    final saved = controller.data.memories.single;
    expect(saved.placeId, 'terelj');
    expect(saved.place, 'Тэрэлж');
    expect(saved.text, 'Хамт байсан болохоор гоё.');
    expect((await store.read()).memories.single.toJson(), saved.toJson());
    expect(tester.takeException(), isNull);
  });

  testWidgets('heart and comment persist and editing preserves those values', (tester) async {
    final memory = MemoryEntry(id: 'social', title: 'Хөөрхөн өдөр', date: DateTime(2026, 9, 20), text: 'Эх тэмдэглэл');
    final store = MemoryAppStore(AppData(profile: const UserProfile(name: 'Ану'), memories: [memory]));
    final controller = await _launch(tester, store, (c) => Scaffold(body: MemoriesScreen(controller: c)));
    await _tap(tester, 'memoryCard-social');
    await _tap(tester, 'memoryLikeButton');
    await _enter(tester, 'memoryComment', 'Дахиад ингэж алхъя.');
    await _tap(tester, 'memoryCommentSave');
    expect(controller.data.memories.single.likedByMe, isTrue);
    expect(controller.data.memories.single.comments.single.text, 'Дахиад ингэж алхъя.');
    expect(controller.data.memories.single.comments.single.authorName, 'Ану');
    await tester.tap(find.byTooltip('Дурсамж засах'));
    await tester.pumpAndSettle();
    await _enter(tester, 'memoryPlace', 'Хотын цэцэрлэг');
    await _tap(tester, 'saveMemoryButton');
    final saved = (await store.read()).memories.single;
    expect(saved.place, 'Хотын цэцэрлэг');
    expect(saved.text, memory.text);
    expect(saved.likedByMe, isTrue);
    expect(saved.comments, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed place write retains inputs and retry saves once', (tester) async {
    final store = _FailingStore(AppData());
    final controller = await _launch(tester, store, (c) => PlaceEditorScreen(controller: c));
    await _enter(tester, 'placeName', 'Нуурын эрэг');
    await _tap(tester, 'savePlaceButton');
    expect(find.text('Хадгалж чадсангүй. Дахин оролдоорой.'), findsOneWidget);
    expect(controller.data.places, isEmpty);
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('placeName'))).controller!.text, 'Нуурын эрэг');
    store.fail = false;
    await _tap(tester, 'savePlaceButton');
    expect(controller.data.places.single.name, 'Нуурын эрэг');
    expect(store.data.places, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('bundled map has Mongolia geometry and places remain usable at large text', (tester) async {
    final raw = jsonDecode(await rootBundle.loadString('assets/maps/natural_earth_countries_110m.geojson')) as Map<String, dynamic>;
    final mongolia = (raw['features'] as List).cast<Map<String, dynamic>>().singleWhere((f) => (f['properties'] as Map)['code'] == 'MNG');
    final ring = ((mongolia['geometry'] as Map)['coordinates'] as List).first as List;
    final longitudes = ring.map((p) => (p[0] as num).toDouble()).toList()..sort();
    expect(longitudes.first, inInclusiveRange(87, 88));
    expect(longitudes.last, inInclusiveRange(119, 120));
    final store = MemoryAppStore(AppData(places: [_place()]));
    await _launch(tester, store, (c) => PlacesScreen(controller: c));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    await tester.pumpAndSettle();
    expect(find.byType(PlacesMap), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _tap(tester, 'placesViewToggle');
    await _enter(tester, 'placesSearch', 'Хөвсгөл');
    expect(find.text('Хайлттай тохирох газар алга'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
