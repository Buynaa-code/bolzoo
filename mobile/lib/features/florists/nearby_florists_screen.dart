import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../florists/florist_location.dart';
import '../../florists/florist_repository.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';

/// Location is requested only after an explicit tap. The public shop catalogue
/// is searched on-device; neither the partner nor our API receives this point.
class NearbyFloristsScreen extends StatefulWidget {
  const NearbyFloristsScreen({
    super.key,
    this.repository,
    this.location,
    this.openLink,
    this.tileProvider,
  });
  final FloristRepository? repository;
  final FloristLocation? location;
  final Future<bool> Function(Uri)? openLink;
  final TileProvider? tileProvider;

  @override
  State<NearbyFloristsScreen> createState() => _NearbyFloristsScreenState();
}

class _NearbyFloristsScreenState extends State<NearbyFloristsScreen> {
  late final _repository = widget.repository ?? AssetFloristRepository();
  late final _location = widget.location ?? DeviceFloristLocation();
  final _map = MapController();
  static const _ulaanbaatar = GeoPoint(47.9185, 106.9177);
  GeoPoint? _center;
  List<Florist> _shops = const [];
  FloristFailure? _failure;
  String? _selectedId;
  bool _busy = false;
  bool _deviceCenter = false;
  bool _tileFailed = false;
  int _radius = 5000;
  int _request = 0;

  @override
  void dispose() {
    ++_request;
    if (widget.repository == null) _repository.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (_busy) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final point = await _location.locate();
      if (!mounted || request != _request) return;
      await _load(point, deviceCenter: true, request: request);
    } on FloristFailure catch (failure) {
      if (mounted && request == _request) setState(() => _failure = failure);
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _failure = const FloristFailure('location_unavailable'));
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _search(GeoPoint point, {bool deviceCenter = false}) async {
    if (_busy) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await _load(point, deviceCenter: deviceCenter, request: request);
    } on FloristFailure catch (failure) {
      if (mounted && request == _request) setState(() => _failure = failure);
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _failure = const FloristFailure('invalid_response'));
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _load(
    GeoPoint point, {
    required bool deviceCenter,
    required int request,
  }) async {
    final shops = await _repository.search(point, radiusMeters: _radius);
    if (!mounted || request != _request) return;
    final wasVisible = _center != null;
    setState(() {
      _center = point;
      _deviceCenter = deviceCenter;
      _shops = shops;
      _selectedId = null;
    });
    if (wasVisible) _map.move(LatLng(point.latitude, point.longitude), 13);
  }

  Future<void> _open(Uri uri) async {
    try {
      final opened =
          await (widget.openLink?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Холбоос нээгдсэнгүй. Дахин оролдоорой.')),
      );
    }
  }

  Future<void> _settings() async {
    try {
      if (await _location.openSettings() || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Утасны тохиргооноос байршлын зөвшөөрлөө шалгаарай.'),
        ),
      );
    }
  }

  void _select(Florist shop) {
    setState(() => _selectedId = shop.id);
    _map.move(LatLng(shop.point.latitude, shop.point.longitude), 15);
  }

  @override
  Widget build(BuildContext context) {
    final center = _center;
    final selected = _shops.where((shop) => shop.id == _selectedId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Цэцэг ойрхон 🌷')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              key: const Key('nearbyFloristsScreen'),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                const Text(
                  'Жижигхэн бэлэг,\nтомхон инээмсэглэл.',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Ойролцоох цэцгийн дэлгүүрээ олоод, хайртай хүнээ баярлуулаарай.',
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 20),
                if (center == null) ...[
                  SoftCard(
                    color: const Color(0xFFFFF2F8),
                    child: Column(
                      children: [
                        const FlowerMark(size: 72),
                        const SizedBox(height: 16),
                        const Text(
                          'Танд ойрхон цэцэг',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Байршлаа зөвшөөрвөл 5 км доторх бүртгэлтэй дэлгүүрүүдийг харуулна. Эсвэл газрын зураг дээр цэг сонгоорой.',
                          textAlign: TextAlign.center,
                          style: TextStyle(height: 1.5),
                        ),
                        const SizedBox(height: 18),
                        _locationButton(),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('floristsManual'),
                          onPressed: _busy ? null : () => _search(_ulaanbaatar),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Газрын зураг дээр сонгох'),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: LinearProgressIndicator(key: Key('floristsLoading')),
                  ),
                if (_failure case final failure?) ...[
                  const SizedBox(height: 12),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(failure.message, key: const Key('floristsError')),
                        if (failure.code == 'permission_denied_forever' ||
                            failure.code == 'location_disabled')
                          TextButton(
                            onPressed: _settings,
                            child: const Text('Тохиргоо нээх'),
                          ),
                        if (center != null)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _search(
                                    center,
                                    deviceCenter: _deviceCenter,
                                  ),
                            child: const Text('Дахин оролдох'),
                          ),
                      ],
                    ),
                  ),
                ],
                if (center != null) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final radius in [5000, 10000])
                        ChoiceChip(
                          label: Text('${radius ~/ 1000} км'),
                          selected: _radius == radius,
                          onSelected: _busy
                              ? null
                              : (_) {
                                  setState(() => _radius = radius);
                                  _search(center, deviceCenter: _deviceCenter);
                                },
                        ),
                      TextButton.icon(
                        key: const Key('floristsLocateAgain'),
                        onPressed: _busy ? null : _locate,
                        icon: const Icon(Icons.my_location, size: 18),
                        label: const Text('Миний ойролцоо'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      height: 330,
                      child: FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          keepAlive: true,
                          initialCenter: LatLng(
                            center.latitude,
                            center.longitude,
                          ),
                          initialZoom: 13,
                          minZoom: 4,
                          maxZoom: 18,
                          backgroundColor: const Color(0xFFF6F1EB),
                          interactionOptions: const InteractionOptions(
                            flags:
                                InteractiveFlag.all & ~InteractiveFlag.rotate,
                          ),
                          onTap: (_, point) => _search(
                            GeoPoint(point.latitude, point.longitude),
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'mn.moch.hamtdaa',
                            maxNativeZoom: 19,
                            tileProvider: widget.tileProvider,
                            errorTileCallback: (_, _, _) {
                              if (_tileFailed) return;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) setState(() => _tileFailed = true);
                              });
                            },
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(
                                  center.latitude,
                                  center.longitude,
                                ),
                                width: 26,
                                height: 26,
                                child: Tooltip(
                                  message: _deviceCenter
                                      ? 'Таны ойролцоо'
                                      : 'Хайлтын цэг',
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6A8CEB),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 4,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x336A8CEB),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              for (final shop in _shops)
                                Marker(
                                  point: LatLng(
                                    shop.point.latitude,
                                    shop.point.longitude,
                                  ),
                                  width: 56,
                                  height: 64,
                                  alignment: Alignment.topCenter,
                                  child: FloristMarker(
                                    key: ValueKey('floristMarker-${shop.id}'),
                                    name: shop.name,
                                    selected: _selectedId == shop.id,
                                    onTap: () => _select(shop),
                                  ),
                                ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: ColoredBox(
                              color: Colors.white,
                              child: TextButton(
                                key: const Key('floristsAttribution'),
                                onPressed: () => _open(
                                  Uri.parse(
                                    'https://www.openstreetmap.org/copyright',
                                  ),
                                ),
                                child: const Text(
                                  '© OpenStreetMap contributors',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_tileFailed)
                    const Text(
                      'Газрын зургийн зарим хэсэг ачаалсангүй. Интернэтээ шалгаарай. Доорх дэлгүүрийн жагсаалт ашиглах боломжтой.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  OutlinedButton.icon(
                    key: const Key('floristsSearchMap'),
                    onPressed: _busy
                        ? null
                        : () {
                            final point = _map.camera.center;
                            _search(GeoPoint(point.latitude, point.longitude));
                          },
                    icon: const Icon(Icons.search),
                    label: const Text('Энэ хэсгээс хайх'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _deviceCenter
                        ? 'Таны ойролцоо · ${_shops.length} дэлгүүр'
                        : 'Сонгосон цэгийн ойролцоо · ${_shops.length} дэлгүүр',
                    key: const Key('floristsResultCount'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Зай нь шулуун шугамаар тооцсон ойролцоо утга.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  if (selected != null) _shopCard(selected, selected: true),
                  if (_shops.isEmpty)
                    const SoftCard(
                      child: Text(
                        'Энэ хэсэгт бүртгэлтэй дэлгүүр олдсонгүй. 10 км болгож томруулах эсвэл газрын зураг дээр өөр цэг сонгоорой.',
                      ),
                    ),
                  for (final shop in _shops)
                    if (shop.id != _selectedId) _shopCard(shop),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Монгол дахь OpenStreetMap-ийн цэцгийн дэлгүүрийн бүртгэл · 2026.10.13. Бүх дэлгүүр багтаагүй байж болно. Ажиллах цаг, хаягаа очихын өмнө шалгаарай.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Байршлыг энэ дэлгэцэд л ашиглана; хостой тань хуваалцахгүй. Газрын зураг нээхэд үзэж буй бүс OpenStreetMap-д, «Чиглэл» дарахад дэлгүүрийн байршил Google Maps-д дамжина.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _locationButton() => FilledButton.icon(
    key: const Key('floristsLocate'),
    onPressed: _busy ? null : _locate,
    icon: const Icon(Icons.near_me_outlined),
    label: const Text('Ойролцоох дэлгүүр олох'),
  );

  Widget _shopCard(Florist shop, {bool selected = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SoftCard(
      color: selected ? const Color(0xFFFFF0F7) : Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: ValueKey('floristShop-${shop.id}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => _select(shop),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const FlowerMark(size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      shop.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    shop.distanceMeters < 1000
                        ? '${shop.distanceMeters.round()} м'
                        : '${(shop.distanceMeters / 1000).toStringAsFixed(1)} км',
                    style: const TextStyle(
                      color: AppColors.pink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (shop.address case final address?)
            Text(address, style: const TextStyle(color: AppColors.muted)),
          if (shop.openingHours case final hours?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Бүртгэл дэх цаг: $hours',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: ValueKey('floristDirections-${shop.id}'),
              onPressed: () => _open(
                Uri.https('www.google.com', '/maps/dir/', {
                  'api': '1',
                  'destination':
                      '${shop.point.latitude},${shop.point.longitude}',
                }),
              ),
              icon: const Icon(Icons.directions_outlined, size: 20),
              label: const Text('Чиглэл'),
            ),
          ),
        ],
      ),
    ),
  );
}

class FloristMarker extends StatelessWidget {
  const FloristMarker({
    super.key,
    required this.name,
    required this.onTap,
    this.selected = false,
  });
  final String name;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$name, цэцгийн дэлгүүр',
    button: true,
    selected: selected,
    child: Tooltip(
      message: name,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              bottom: 2,
              child: Icon(
                Icons.arrow_drop_down,
                size: 36,
                color: selected ? AppColors.ink : AppColors.pink,
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFFDEEE) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.ink : AppColors.pink,
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33B52972),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: FlowerMark(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
