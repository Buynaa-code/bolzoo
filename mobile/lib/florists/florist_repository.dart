import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

class Florist {
  const Florist({
    required this.id,
    required this.name,
    required this.point,
    required this.distanceMeters,
    this.address,
    this.openingHours,
  });

  final String id;
  final String name;
  final GeoPoint point;
  final double distanceMeters;
  final String? address;
  final String? openingHours;
}

class FloristFailure implements Exception {
  const FloristFailure(this.code);

  final String code;

  String get message => switch (code) {
    'permission_denied' =>
      'Ойролцоох дэлгүүрийг олоход байршлын зөвшөөрөл хэрэгтэй. '
          'Дахин оролдоод зөвшөөрөх эсвэл газрын зургаас газар сонгоорой.',
    'permission_denied_forever' =>
      'Утасны тохиргооноос Нандин мөч аппын байршлын зөвшөөрлийг нээгээрэй.',
    'location_disabled' =>
      'Утасны байршлын үйлчилгээг асаагаад дахин оролдоорой.',
    'location_timeout' =>
      'Байршлыг хараахан олсонгүй. Дахин оролдох эсвэл газрын зургаас газар сонгоорой.',
    'location_unavailable' =>
      'Байршлыг авах боломжгүй байна. Газрын зургаас газар сонгож болно.',
    'network' => 'Холболтоо шалгаад дахин оролдоорой.',
    'busy' => 'Байршлыг шалгаж байна. Түр хүлээгээрэй.',
    _ => 'Дэлгүүрийн мэдээллийг уншиж чадсангүй. Дахин оролдоорой.',
  };
}

abstract class FloristRepository {
  Future<List<Florist>> search(GeoPoint center, {int radiusMeters = 5000});
  void dispose();
}

/// Searches a bundled public OSM catalog on the device. User coordinates are
/// neither transmitted nor persisted. Only parsed public shop data is cached.
class AssetFloristRepository implements FloristRepository {
  AssetFloristRepository({Future<String> Function()? loadCatalog})
    : _loadCatalog = loadCatalog ?? _loadBundledCatalog;

  static const assetPath = 'assets/maps/mongolia_florists.json';
  static const _maxCatalogCharacters = 4 * 1024 * 1024;
  static const _maxElements = 10000;
  final Future<String> Function() _loadCatalog;
  Future<List<_Shop>>? _loading;
  List<_Shop>? _catalog;
  bool _disposed = false;

  static Future<String> _loadBundledCatalog() =>
      rootBundle.loadString(assetPath);

  @override
  Future<List<Florist>> search(
    GeoPoint center, {
    int radiusMeters = 5000,
  }) async {
    _ensureActive();
    if (!center.isValid) {
      throw const FloristFailure('location_unavailable');
    }
    // The UI offers nearby searches only, even if another caller supplies a
    // larger radius. Recalculate distances for every requested center.
    final radius = radiusMeters.clamp(1000, 10000);
    final shops = await _getCatalog();
    _ensureActive();
    final results = <Florist>[];
    for (final shop in shops) {
      final distance = _distanceMeters(center, shop.point);
      if (distance <= radius) {
        results.add(
          Florist(
            id: shop.id,
            name: shop.name,
            point: shop.point,
            address: shop.address,
            openingHours: shop.openingHours,
            distanceMeters: distance,
          ),
        );
      }
    }
    results.sort((a, b) {
      final distance = a.distanceMeters.compareTo(b.distanceMeters);
      return distance == 0 ? a.id.compareTo(b.id) : distance;
    });
    return List.unmodifiable(results);
  }

  Future<List<_Shop>> _getCatalog() async {
    if (_catalog case final catalog?) return catalog;
    final pending = _loading ??= _readCatalog();
    try {
      final catalog = await pending;
      _ensureActive();
      _catalog = catalog;
      return catalog;
    } finally {
      if (identical(_loading, pending)) _loading = null;
    }
  }

  Future<List<_Shop>> _readCatalog() async {
    try {
      final raw = await _loadCatalog();
      if (raw.length > _maxCatalogCharacters) {
        throw const FloristFailure('invalid_response');
      }
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> ||
          json['source'] != 'OpenStreetMap' ||
          json['elements'] is! List ||
          (json['remark'] is String &&
              (json['remark'] as String).trim().isNotEmpty)) {
        throw const FloristFailure('invalid_response');
      }
      final elements = json['elements'] as List;
      if (elements.length > _maxElements) {
        throw const FloristFailure('invalid_response');
      }
      final shops = <String, _Shop>{};
      for (final element in elements) {
        final shop = _parseShop(element);
        if (shop != null) shops.putIfAbsent(shop.id, () => shop);
      }
      // An empty, valid OSM extract is different from an unusable extract.
      if (elements.isNotEmpty && shops.isEmpty) {
        throw const FloristFailure('invalid_response');
      }
      return List.unmodifiable(shops.values);
    } on FloristFailure {
      rethrow;
    } catch (_) {
      // Do not expose source payloads or device location in errors or logs.
      throw const FloristFailure('invalid_response');
    }
  }

  void _ensureActive() {
    if (_disposed) throw StateError('Florist repository disposed');
  }

  @override
  void dispose() {
    _disposed = true;
    _catalog = null;
    _loading = null;
  }
}

class _Shop {
  const _Shop(this.id, this.name, this.point, this.address, this.openingHours);

  final String id;
  final String name;
  final GeoPoint point;
  final String? address;
  final String? openingHours;
}

_Shop? _parseShop(dynamic value) {
  if (value is! Map<String, dynamic>) return null;
  final type = value['type'];
  final id = value['id'];
  final tags = value['tags'];
  if (!const {'node', 'way', 'relation'}.contains(type) ||
      id is! int ||
      id <= 0 ||
      tags is! Map<String, dynamic> ||
      tags['shop'] != 'florist' ||
      const [
        'disused',
        'abandoned',
        'demolished',
      ].any((key) => tags[key] == 'yes' || tags['$key:shop'] == 'florist')) {
    return null;
  }
  final coordinates = type == 'node' ? value : value['center'];
  if (coordinates is! Map<String, dynamic> ||
      coordinates['lat'] is! num ||
      coordinates['lon'] is! num) {
    return null;
  }
  final point = GeoPoint(
    (coordinates['lat'] as num).toDouble(),
    (coordinates['lon'] as num).toDouble(),
  );
  if (!point.isValid) return null;
  final name =
      _text(tags['name:mn'], 120) ??
      _text(tags['name'], 120) ??
      _text(tags['name:en'], 120) ??
      _text(tags['brand'], 120) ??
      'Цэцгийн дэлгүүр';
  final addressParts = [
    _text(tags['addr:street'], 200),
    _text(tags['addr:housenumber'], 40),
    _text(tags['addr:city'], 120),
  ].whereType<String>().toList();
  final address =
      _text(tags['addr:full'], 500) ??
      (addressParts.isEmpty ? null : addressParts.join(', '));
  return _Shop(
    '$type/$id',
    name,
    point,
    address,
    _text(tags['opening_hours'], 300),
  );
}

String? _text(dynamic value, int maxLength) {
  if (value is! String) return null;
  final text = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  if (text.isEmpty) return null;
  return text.length <= maxLength ? text : text.substring(0, maxLength);
}

double _distanceMeters(GeoPoint a, GeoPoint b) {
  const earthRadiusMeters = 6371008.8;
  const radians = math.pi / 180;
  final latDelta = (b.latitude - a.latitude) * radians;
  final lonDelta = (b.longitude - a.longitude) * radians;
  final term =
      math.pow(math.sin(latDelta / 2), 2) +
      math.cos(a.latitude * radians) *
          math.cos(b.latitude * radians) *
          math.pow(math.sin(lonDelta / 2), 2);
  return 2 * earthRadiusMeters * math.asin(math.sqrt(term.clamp(0, 1)));
}
