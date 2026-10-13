import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/features/florists/nearby_florists_screen.dart';
import 'package:hamtdaa/florists/florist_location.dart';
import 'package:hamtdaa/florists/florist_repository.dart';
import 'package:hamtdaa/ui/theme.dart';

class MemoryTiles extends TileProvider {
  @override
  ImageProvider getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) => MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    ),
  );
}

class FakeLocation implements FloristLocation {
  int calls = 0;
  int settingsCalls = 0;
  FloristFailure? failure;
  Completer<GeoPoint>? pending;
  @override
  Future<GeoPoint> locate() async {
    calls++;
    if (failure case final error?) throw error;
    return pending?.future ?? const GeoPoint(47.9185, 106.9177);
  }

  @override
  Future<bool> openSettings() async {
    settingsCalls++;
    return false;
  }
}

class FakeShops implements FloristRepository {
  final searches = <({GeoPoint point, int radius})>[];
  bool empty = false;
  int failCount = 0;
  @override
  Future<List<Florist>> search(
    GeoPoint center, {
    int radiusMeters = 5000,
  }) async {
    searches.add((point: center, radius: radiusMeters));
    if (failCount > 0) {
      failCount--;
      throw const FloristFailure('invalid_response');
    }
    return empty
        ? []
        : const [
            Florist(
              id: 'node/1',
              name: 'Туршилтын цэцэг',
              point: GeoPoint(47.9200, 106.9180),
              distanceMeters: 180,
              address: 'Туршилтын хаяг',
              openingHours: 'Mo-Su 10:00-19:00',
            ),
          ];
  }

  @override
  void dispose() {}
}

void main() {
  late FakeLocation location;
  late FakeShops shops;
  late List<Uri> links;
  setUp(() {
    location = FakeLocation();
    shops = FakeShops();
    links = [];
  });

  Future<void> render(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: NearbyFloristsScreen(
          repository: shops,
          location: location,
          tileProvider: MemoryTiles(),
          openLink: (uri) async {
            links.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Key key) async {
    final target = find.byKey(key);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'explicit location tap -> flower pin -> shop -> safe directions',
    (tester) async {
      await render(tester);
      expect(location.calls, 0);
      expect(shops.searches, isEmpty);
      expect(find.byType(FlutterMap), findsNothing);
      await tapVisible(tester, const Key('floristsLocate'));
      expect(location.calls, 1);
      expect(shops.searches.single.radius, 5000);
      expect(
        find.byKey(const ValueKey('floristMarker-node/1')),
        findsOneWidget,
      );
      await tapVisible(tester, const ValueKey('floristMarker-node/1'));
      final marker = tester.widget<FloristMarker>(
        find.byKey(const ValueKey('floristMarker-node/1')),
      );
      expect(marker.selected, isTrue);
      await tapVisible(tester, const ValueKey('floristDirections-node/1'));
      expect(links.single.host, 'www.google.com');
      expect(links.single.queryParameters, {
        'api': '1',
        'destination': '47.92,106.918',
      });
      expect(links.single.queryParameters.containsKey('origin'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'denied location can open settings and use manual map without GPS',
    (tester) async {
      location.failure = const FloristFailure('permission_denied_forever');
      await render(tester);
      await tapVisible(tester, const Key('floristsLocate'));
      expect(shops.searches, isEmpty);
      await tester.ensureVisible(find.text('Тохиргоо нээх'));
      await tester.tap(find.text('Тохиргоо нээх'));
      await tester.pumpAndSettle();
      expect(location.settingsCalls, 1);
      await tapVisible(tester, const Key('floristsManual'));
      expect(location.calls, 1);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(shops.searches.single.point.latitude, 47.9185);
      await tapVisible(tester, const Key('floristsSearchMap'));
      expect(shops.searches, hasLength(2));
      expect(location.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty result permits 10km radius and never invents shops', (
    tester,
  ) async {
    shops.empty = true;
    await render(tester);
    await tapVisible(tester, const Key('floristsManual'));
    expect(find.byType(FloristMarker), findsNothing);
    expect(find.textContaining('0 дэлгүүр'), findsOneWidget);
    await tester.ensureVisible(find.text('10 км'));
    await tester.tap(find.text('10 км'));
    await tester.pumpAndSettle();
    expect(shops.searches.last.radius, 10000);
    expect(location.calls, 0);
    expect(find.byType(FloristMarker), findsNothing);
  });

  testWidgets('late location result cannot search after closing page', (
    tester,
  ) async {
    location.pending = Completer<GeoPoint>();
    await render(tester);
    await tester.tap(find.byKey(const Key('floristsLocate')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    location.pending!.complete(const GeoPoint(47, 106));
    await tester.pumpAndSettle();
    expect(shops.searches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bad catalogue shows error then retries manual search', (
    tester,
  ) async {
    shops.failCount = 1;
    await render(tester);
    await tapVisible(tester, const Key('floristsManual'));
    expect(find.byKey(const Key('floristsError')), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
    await tapVisible(tester, const Key('floristsManual'));
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const Key('floristsError')), findsNothing);
  });

  testWidgets('large text remains usable through permission and result flow', (
    tester,
  ) async {
    await render(tester, scale: 2);
    expect(tester.takeException(), isNull);
    await tapVisible(tester, const Key('floristsManual'));
    await tapVisible(tester, const ValueKey('floristDirections-node/1'));
    expect(links, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
