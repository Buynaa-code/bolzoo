import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../ui/theme.dart';

/// A bundled, offline geographic overview. Geometry comes from Natural Earth;
/// place positions always come from saved WGS84 latitude/longitude coordinates.
class PlacesMap extends StatefulWidget {
  const PlacesMap({
    super.key,
    this.places = const [],
    this.world = false,
    this.selectedId,
    this.onPlaceTap,
    this.onCoordinateTap,
    this.selectedLatitude,
    this.selectedLongitude,
  });

  final List<PlaceEntry> places;
  final bool world;
  final String? selectedId;
  final ValueChanged<PlaceEntry>? onPlaceTap;
  final void Function(double latitude, double longitude)? onCoordinateTap;
  final double? selectedLatitude;
  final double? selectedLongitude;

  @override
  State<PlacesMap> createState() => _PlacesMapState();
}

class _PlacesMapState extends State<PlacesMap> {
  late Future<List<_Country>> _geometry = _load();

  Future<List<_Country>> _load() async {
    final json = jsonDecode(await rootBundle.loadString('assets/maps/natural_earth_countries_110m.geojson')) as Map<String, dynamic>;
    return (json['features'] as List).map((item) {
      final feature = item as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      final polygons = geometry['type'] == 'Polygon' ? [coordinates] : coordinates;
      return _Country(
        (feature['properties'] as Map)['code'] as String,
        [for (final polygon in polygons) [for (final ring in polygon as List) [for (final point in ring as List) Offset((point[0] as num).toDouble(), (point[1] as num).toDouble())]]],
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(26),
    child: ColoredBox(
      color: const Color(0xFFFCF8FA),
      child: FutureBuilder<List<_Country>>(
        future: _geometry,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.map_outlined, color: AppColors.muted),
              const SizedBox(height: 10),
              const Text('Газрын зураг нээгдсэнгүй'),
              TextButton(onPressed: () => setState(() => _geometry = _load()), child: const Text('Дахин оролдох')),
            ]));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          return LayoutBuilder(builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final projection = _Projection(size, widget.world);
            final visible = widget.places.where((place) => place.latitude != null && place.longitude != null && projection.contains(place.latitude!, place.longitude!));
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: widget.onCoordinateTap == null ? null : (details) {
                final coordinate = projection.unproject(details.localPosition);
                if (coordinate != null) widget.onCoordinateTap!(coordinate.dy, coordinate.dx);
              },
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: _CountryPainter(snapshot.data!, projection))),
                if (!widget.world)
                  const Positioned(left: 18, top: 18, child: Text('МОНГОЛ УЛС', style: TextStyle(fontSize: 10, color: AppColors.muted, letterSpacing: 2, fontWeight: FontWeight.w800))),
                for (final place in visible)
                  _pin(projection.project(place.longitude!, place.latitude!), place.name,
                    selected: widget.selectedId == place.id,
                    key: ValueKey('placePin-${place.id}'),
                    onTap: widget.onPlaceTap == null ? null : () => widget.onPlaceTap!(place)),
                if (widget.selectedLatitude != null && widget.selectedLongitude != null && projection.contains(widget.selectedLatitude!, widget.selectedLongitude!))
                  _pin(projection.project(widget.selectedLongitude!, widget.selectedLatitude!), 'Сонгосон цэг', selected: true),
                const Positioned(right: 12, bottom: 10, child: Text('Natural Earth · 1:110m', style: TextStyle(fontSize: 9, color: AppColors.muted))),
              ]),
            );
          });
        },
      ),
    ),
  );

  Widget _pin(Offset position, String name, {bool selected = false, Key? key, VoidCallback? onTap}) => Positioned(
    left: position.dx - 22, top: position.dy - 42,
    child: Semantics(
      label: name,
      button: onTap != null,
      child: Tooltip(
        message: name,
        child: InkResponse(
          key: key,
          onTap: onTap,
          radius: 26,
          child: Icon(Icons.location_on_rounded, size: selected ? 47 : 42, color: selected ? AppColors.ink : AppColors.pink, shadows: const [Shadow(color: Colors.white, blurRadius: 4)]),
        ),
      ),
    ),
  );
}

class _Country {
  const _Country(this.code, this.polygons);
  final String code;
  final List<List<List<Offset>>> polygons;
}

class _Projection {
  _Projection(this.size, this.world);
  final Size size;
  final bool world;
  double get minLon => world ? -180 : 86;
  double get maxLon => world ? 180 : 121;
  double get minLat => world ? -60 : 40;
  double get maxLat => world ? 85 : 54;
  double get latitudeScale => world ? 1 : math.cos(47 * math.pi / 180);
  double get scale => math.min((size.width - 36) / ((maxLon - minLon) * latitudeScale), (size.height - 58) / (maxLat - minLat));
  double get left => (size.width - (maxLon - minLon) * latitudeScale * scale) / 2;
  double get top => (size.height - (maxLat - minLat) * scale) / 2;
  bool contains(double lat, double lon) => lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
  Offset project(double lon, double lat) => Offset(left + (lon - minLon) * latitudeScale * scale, top + (maxLat - lat) * scale);
  Offset? unproject(Offset value) {
    final lon = (value.dx - left) / (latitudeScale * scale) + minLon;
    final lat = maxLat - (value.dy - top) / scale;
    return contains(lat, lon) ? Offset(lon, lat) : null;
  }
}

class _CountryPainter extends CustomPainter {
  const _CountryPainter(this.countries, this.projection);
  final List<_Country> countries;
  final _Projection projection;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final country in countries) {
      if (!projection.world && country.code != 'MNG') continue;
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final polygon in country.polygons) {
        for (final ring in polygon) {
          if (ring.isEmpty) continue;
          final start = projection.project(ring.first.dx, ring.first.dy);
          path.moveTo(start.dx, start.dy);
          for (final point in ring.skip(1)) {
            final p = projection.project(point.dx, point.dy);
            path.lineTo(p.dx, p.dy);
          }
          path.close();
        }
      }
      canvas.drawPath(path, Paint()..color = country.code == 'MNG' ? const Color(0xFFFFE3EF) : const Color(0xFFF1E7ED));
      canvas.drawPath(path, Paint()..color = const Color(0xFFE2CDD7)..style = PaintingStyle.stroke..strokeWidth = projection.world ? .6 : 1.3);
    }
  }

  @override
  bool shouldRepaint(_CountryPainter oldDelegate) => oldDelegate.countries != countries || oldDelegate.projection.world != projection.world || oldDelegate.projection.size != projection.size;
}
