import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/florists/florist_repository.dart';

Map<String, Object?> shop(
  int id,
  double latitude,
  double longitude, {
  String type = 'node',
  Map<String, Object?> tags = const {},
}) => {
  'type': type,
  'id': id,
  if (type == 'node') ...{'lat': latitude, 'lon': longitude},
  if (type != 'node') 'center': {'lat': latitude, 'lon': longitude},
  'tags': {'shop': 'florist', 'name': 'Shop $id', ...tags},
};

String catalog(List<Object?> elements) => jsonEncode({
  'source': 'OpenStreetMap',
  'fetchedAt': '2026-10-13',
  'elements': elements,
});

Matcher failure(String code) =>
    isA<FloristFailure>().having((error) => error.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled real Mongolia catalog contains nearby Ulaanbaatar florists',
    () async {
      final repository = AssetFloristRepository();
      addTearDown(repository.dispose);
      final results = await repository.search(
        const GeoPoint(47.9185, 106.9177),
      );
      expect(results, isNotEmpty);
      expect(results.map((shop) => shop.id), contains('node/1732841308'));
      expect(results.first.distanceMeters, lessThan(1000));
      expect(
        results.every(
          (shop) => shop.point.isValid && shop.distanceMeters <= 5000,
        ),
        isTrue,
      );
      expect(
        results.any((shop) => shop.name == 'Flora Цэцгийн дэлгүүр'),
        isTrue,
      );
    },
  );

  test(
    'sorts actual OSM nodes, ways and relations by center distance',
    () async {
      final repository = AssetFloristRepository(
        loadCatalog: () async => catalog([
          shop(3, 47.94, 106.92, type: 'relation'),
          shop(2, 47.93, 106.92, type: 'way'),
          shop(1, 47.92, 106.92),
          shop(4, 48.5, 106.92),
        ]),
      );
      addTearDown(repository.dispose);
      final results = await repository.search(const GeoPoint(47.92, 106.92));
      expect(results.map((shop) => shop.id), ['node/1', 'way/2', 'relation/3']);
      expect(results.first.distanceMeters, 0);
      expect(results[1].distanceMeters, closeTo(1112, 1));
      expect(results[2].distanceMeters, closeTo(2224, 1));
      expect(() => results.clear(), throwsUnsupportedError);
    },
  );

  test(
    'caches only catalog and recalculates distances for another center',
    () async {
      var loads = 0;
      final repository = AssetFloristRepository(
        loadCatalog: () async {
          loads++;
          return catalog([shop(1, 47.92, 106.92), shop(2, 47.94, 106.92)]);
        },
      );
      addTearDown(repository.dispose);
      final first = await repository.search(const GeoPoint(47.92, 106.92));
      final second = await repository.search(const GeoPoint(47.94, 106.92));
      expect(loads, 1);
      expect(first.first.id, 'node/1');
      expect(second.first.id, 'node/2');
      expect(second.first.distanceMeters, 0);
    },
  );

  test('validates elements and deduplicates by OSM type and id', () async {
    final repository = AssetFloristRepository(
      loadCatalog: () async => catalog([
        null,
        shop(1, 47.92, 106.92),
        shop(1, 47.92, 106.92),
        shop(1, 47.92, 106.92, type: 'way'),
        shop(-1, 47.92, 106.92),
        shop(2, 91, 106.92),
        shop(3, 47.92, 181),
        shop(4, 47.92, 106.92, tags: {'shop': 'supermarket'}),
        shop(5, 47.92, 106.92, tags: {'disused': 'yes'}),
        shop(6, 47.92, 106.92, tags: {'abandoned:shop': 'florist'}),
        {
          'type': 'way',
          'id': 9,
          'tags': {'shop': 'florist'},
        },
        {
          'type': 'node',
          'id': 10,
          'lat': '47.92',
          'lon': 106.92,
          'tags': {'shop': 'florist'},
        },
      ]),
    );
    addTearDown(repository.dispose);
    final results = await repository.search(const GeoPoint(47.92, 106.92));
    expect(results.map((shop) => shop.id), ['node/1', 'way/1']);
  });

  test(
    'uses Mongolian names and optional real address/hours without invention',
    () async {
      final repository = AssetFloristRepository(
        loadCatalog: () async => catalog([
          shop(
            1,
            47.92,
            106.92,
            tags: {
              'name:mn': '  Цэцэг\nдэлгүүр ',
              'addr:street': 'Энхтайваны өргөн чөлөө',
              'addr:housenumber': '10',
              'opening_hours': 'Mo-Sa 09:00-18:00',
            },
          ),
          shop(2, 47.921, 106.92, tags: {'name': null}),
        ]),
      );
      addTearDown(repository.dispose);
      final results = await repository.search(const GeoPoint(47.92, 106.92));
      expect(results.first.name, 'Цэцэг дэлгүүр');
      expect(results.first.address, 'Энхтайваны өргөн чөлөө, 10');
      expect(results.first.openingHours, 'Mo-Sa 09:00-18:00');
      expect(results.last.name, 'Цэцгийн дэлгүүр');
      expect(results.last.address, isNull);
      expect(results.last.openingHours, isNull);
    },
  );

  test(
    'bounds nearby search to 1–10km and returns genuine empty results',
    () async {
      final repository = AssetFloristRepository(
        loadCatalog: () async =>
            catalog([shop(1, 0, .005), shop(2, 0, .05), shop(3, 0, .11)]),
      );
      addTearDown(repository.dispose);
      final small = await repository.search(
        const GeoPoint(0, 0),
        radiusMeters: 1,
      );
      final large = await repository.search(
        const GeoPoint(0, 0),
        radiusMeters: 999999,
      );
      final empty = await repository.search(const GeoPoint(47, 107));
      expect(small.map((shop) => shop.id), ['node/1']);
      expect(large.map((shop) => shop.id), ['node/1', 'node/2']);
      expect(empty, isEmpty);
    },
  );

  test('rejects invalid coordinates before reading catalog', () async {
    var loads = 0;
    final repository = AssetFloristRepository(
      loadCatalog: () async {
        loads++;
        return catalog([]);
      },
    );
    addTearDown(repository.dispose);
    for (final center in [
      const GeoPoint(double.nan, 0),
      const GeoPoint(0, double.infinity),
      const GeoPoint(91, 0),
      const GeoPoint(0, -181),
    ]) {
      await expectLater(
        repository.search(center),
        throwsA(failure('location_unavailable')),
      );
    }
    expect(loads, 0);
  });

  test(
    'rejects malformed, partial and oversized catalogs and retries loading',
    () async {
      var input = '{broken';
      final repository = AssetFloristRepository(loadCatalog: () async => input);
      addTearDown(repository.dispose);
      for (final invalid in [
        '{broken',
        '{}',
        '[]',
        jsonEncode({
          'source': 'OpenStreetMap',
          'elements': [],
          'remark': 'timeout',
        }),
        catalog([
          {'type': 'node', 'id': 1},
        ]),
        ' ' * (4 * 1024 * 1024 + 1),
      ]) {
        input = invalid;
        await expectLater(
          repository.search(const GeoPoint(0, 0)),
          throwsA(failure('invalid_response')),
        );
      }
      input = catalog([]);
      expect(await repository.search(const GeoPoint(0, 0)), isEmpty);
    },
  );

  test(
    'shares concurrent loads but keeps each requested center independent',
    () async {
      final loader = Completer<String>();
      var loads = 0;
      final repository = AssetFloristRepository(
        loadCatalog: () {
          loads++;
          return loader.future;
        },
      );
      addTearDown(repository.dispose);
      final first = repository.search(const GeoPoint(0, 0));
      final second = repository.search(const GeoPoint(1, 0));
      loader.complete(catalog([shop(1, 0, 0), shop(2, 1, 0)]));
      expect((await first).single.id, 'node/1');
      expect((await second).single.id, 'node/2');
      expect(loads, 1);
    },
  );

  test('does not return a pending catalog after disposal', () async {
    final loader = Completer<String>();
    final repository = AssetFloristRepository(loadCatalog: () => loader.future);
    final pending = repository.search(const GeoPoint(0, 0));
    repository.dispose();
    loader.complete(catalog([shop(1, 0, 0)]));
    await expectLater(pending, throwsStateError);
    await expectLater(
      repository.search(const GeoPoint(0, 0)),
      throwsStateError,
    );
  });
}
