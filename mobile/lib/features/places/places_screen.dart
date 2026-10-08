import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_controller.dart';
import '../../ui/theme.dart';
import '../memories/memories_screen.dart';
import 'places_map.dart';

Future<void> openPlaces(BuildContext context, AppController controller) => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => PlacesScreen(controller: controller)));
Future<void> openPlaceDetail(BuildContext context, AppController controller, String placeId) => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => PlaceDetailScreen(controller: controller, placeId: placeId)));
Future<void> openPlaceEditor(BuildContext context, AppController controller, {PlaceEntry? place}) => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => PlaceEditorScreen(controller: controller, place: place)));

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  bool _world = false;
  bool _list = false;
  String? _selected;
  String _query = '';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final places = widget.controller.data.places.where((p) => '${p.name} ${p.address}'.toLowerCase().contains(_query.toLowerCase())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      PlaceEntry? selected;
      for (final place in places) { if (place.id == _selected) selected = place; }
      return Scaffold(
        appBar: AppBar(title: const Text('Очсон газрууд'), actions: [
          IconButton(key: const ValueKey('placesViewToggle'), tooltip: _list ? 'Газрын зураг' : 'Жагсаалт', onPressed: () => setState(() => _list = !_list), icon: Icon(_list ? Icons.map_outlined : Icons.view_list_outlined)),
        ]),
        body: ListView(padding: const EdgeInsets.fromLTRB(22, 12, 22, 100), children: [
          Text('Бидний очсон газрууд', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Нэг газар. Олон нандин мөч.', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 22),
          if (!_list) ...[
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Монгол')), ButtonSegment(value: true, label: Text('Дэлхий'))],
              selected: {_world},
              onSelectionChanged: (value) => setState(() => _world = value.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 18),
            SizedBox(height: 285, child: PlacesMap(
              places: places,
              world: _world,
              selectedId: _selected,
              onPlaceTap: (place) => setState(() => _selected = place.id),
            )),
            const SizedBox(height: 12),
            const Text('Таны хадгалсан координаттай газрууд тэмдэглэгдэнэ.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
            if (selected != null) ...[
              const SizedBox(height: 18),
              _PlaceCard(place: selected, controller: widget.controller),
            ],
          ] else ...[
            TextField(key: const ValueKey('placesSearch'), onChanged: (value) => setState(() => _query = value), decoration: const InputDecoration(hintText: 'Нэр, хаягаар хайх', prefixIcon: Icon(Icons.search_rounded))),
          ],
          const SizedBox(height: 25),
          Row(children: [
            Expanded(child: Text('Хадгалсан газрууд', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            Text('${places.length}', style: const TextStyle(color: AppColors.muted)),
          ]),
          const SizedBox(height: 14),
          if (places.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
              decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(24)),
              child: Column(children: [
                const Icon(Icons.add_location_alt_outlined, color: AppColors.pink, size: 34),
                const SizedBox(height: 15),
                Text(_query.isEmpty ? 'Эхний газраа хадгалъя' : 'Хайлттай тохирох газар алга', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Очсон газрын нэр, координатыг хадгалаад дурсамжтайгаа холбоорой.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
              ]),
            )
          else
            for (final place in places) Padding(padding: const EdgeInsets.only(bottom: 12), child: _PlaceCard(place: place, controller: widget.controller)),
          const SizedBox(height: 12),
          const Text('Энэ төхөөрөмж дээр хадгалагдана.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          key: const ValueKey('placesAddButton'),
          onPressed: () => openPlaceEditor(context, widget.controller),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Газар нэмэх'),
          backgroundColor: AppColors.pink,
          foregroundColor: Colors.white,
        ),
      );
    },
  );
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.controller});
  final PlaceEntry place;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final memories = controller.data.memories.where((m) => m.placeId == place.id).toList();
    final photos = memories.where((m) => m.photoPath != null);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(side: const BorderSide(color: AppColors.line), borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('placeCard-${place.id}'),
        onTap: () => openPlaceDetail(context, controller, place.id),
        child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(15), child: SizedBox(width: 68, height: 72, child: photos.isEmpty ? const ColoredBox(color: AppColors.blush, child: Icon(Icons.landscape_outlined, color: AppColors.pink)) : Image.file(File(photos.first.photoPath!), fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.blush, child: Icon(Icons.image_not_supported_outlined, color: AppColors.muted))))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(place.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text('${memories.length} дурсамж', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            if (place.latitude == null) const Padding(padding: EdgeInsets.only(top: 3), child: Text('Координат нэмээгүй', style: TextStyle(color: AppColors.muted, fontSize: 10))),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ])),
      ),
    );
  }
}

class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({super.key, required this.controller, required this.placeId});
  final AppController controller;
  final String placeId;
  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  bool _busy = false;

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Газрыг устгах уу?'),
      content: const Text('Холбогдсон дурсамж, зураг хэвээр үлдэнэ.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Болих')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Устгах'))],
    ));
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.controller.deletePlace(widget.placeId);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) { setState(() => _busy = false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Устгаж чадсангүй. Дахин оролдоорой.'))); }
    }
  }

  Future<void> _linkMemory(PlaceEntry place) async {
    final memory = await showModalBottomSheet<MemoryEntry>(context: context, showDragHandle: true, builder: (context) {
      final candidates = widget.controller.data.memories.where((m) => m.placeId != place.id).toList()..sort((a, b) => b.date.compareTo(a.date));
      return SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), children: [
        const Padding(padding: EdgeInsets.all(10), child: Text('Дурсамж сонгох', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        if (candidates.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Холбох дурсамж алга. Шинэ дурсамж нэмээрэй.')),
        for (final entry in candidates) ListTile(key: ValueKey('linkMemory-${entry.id}'), title: Text(entry.title), subtitle: Text(entry.place.isEmpty ? '${entry.date.year}.${entry.date.month}.${entry.date.day}' : 'Одоогийн газар: ${entry.place}'), trailing: const Icon(Icons.add_link_rounded), onTap: () => Navigator.pop(context, entry)),
      ]));
    });
    if (memory == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.controller.saveMemory(memory.copyWith(place: place.name, placeId: place.id));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дурсамжийг холбож чадсангүй. Дахин оролдоорой.')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _openMap(PlaceEntry place) async {
    try {
      final uri = Uri.https('www.openstreetmap.org', '/', {'mlat': '${place.latitude}', 'mlon': '${place.longitude}' }).replace(fragment: 'map=15/${place.latitude}/${place.longitude}');
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) throw StateError('map unavailable');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Газрын зургийг нээж чадсангүй.')));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.controller, builder: (context, _) {
    PlaceEntry? place;
    for (final entry in widget.controller.data.places) { if (entry.id == widget.placeId) place = entry; }
    final current = place;
    final memories = widget.controller.data.memories.where((m) => m.placeId == widget.placeId).toList()..sort((a,b) => b.date.compareTo(a.date));
    return Scaffold(
      appBar: AppBar(title: const Text('Газар'), actions: [
        IconButton(tooltip: 'Газар засах', onPressed: current == null || _busy ? null : () => openPlaceEditor(context, widget.controller, place: current), icon: const Icon(Icons.edit_outlined)),
        IconButton(tooltip: 'Газар устгах', onPressed: current == null || _busy ? null : _delete, icon: const Icon(Icons.delete_outline_rounded)),
      ]),
      body: current == null ? const Center(child: Text('Энэ газар байхгүй байна.')) : ListView(padding: const EdgeInsets.fromLTRB(22, 12, 22, 36), children: [
        if (current.latitude != null && current.longitude != null) ...[
          SizedBox(height: 235, child: PlacesMap(places: [current], selectedId: current.id, world: current.latitude! < 40 || current.latitude! > 54 || current.longitude! < 86 || current.longitude! > 121)),
          const SizedBox(height: 22),
        ],
        Text(current.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        if (current.address.isNotEmpty) ...[const SizedBox(height: 9), Text(current.address, style: const TextStyle(color: AppColors.muted, height: 1.5))],
        if (current.latitude != null) ...[
          const SizedBox(height: 10),
          Text('${current.latitude!.toStringAsFixed(5)}, ${current.longitude!.toStringAsFixed(5)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _openMap(current), icon: const Icon(Icons.open_in_new_rounded, size: 15), label: const Text('Газрын зургаар нээх'))),
        ],
        if (current.note.isNotEmpty) ...[const SizedBox(height: 18), SelectableText(current.note, style: const TextStyle(height: 1.6))],
        const SizedBox(height: 24),
        Row(children: [Expanded(child: Text('${memories.length} дурсамж', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))), IconButton(key: const ValueKey('placeLinkMemoryButton'), tooltip: 'Дурсамж холбох', onPressed: _busy ? null : () => _linkMemory(current), icon: const Icon(Icons.add_link_rounded, color: AppColors.pink))]),
        const SizedBox(height: 12),
        if (memories.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('Энэ газартай дурсамжаа холбоорой.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))),
        for (final memory in memories) Card(elevation: 0, color: AppColors.blush, margin: const EdgeInsets.only(bottom: 10), child: ListTile(key: ValueKey('placeMemory-${memory.id}'), title: Text(memory.title), subtitle: Text('${memory.date.year}.${memory.date.month}.${memory.date.day}'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => openMemoryDetail(context, widget.controller, memory.id))),
        const SizedBox(height: 20),
        FilledButton.icon(key: const ValueKey('placeNewMemoryButton'), onPressed: _busy ? null : () => openMemoryEditor(context, widget.controller, placeId: current.id), icon: const Icon(Icons.add_rounded), label: const Text('Дурсамж нэмэх')),
        const SizedBox(height: 18),
        const Text('Энэ төхөөрөмж дээр хадгалагдана.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 11)),
      ]),
    );
  });
}

class PlaceEditorScreen extends StatefulWidget {
  const PlaceEditorScreen({super.key, required this.controller, this.place});
  final AppController controller;
  final PlaceEntry? place;
  @override
  State<PlaceEditorScreen> createState() => _PlaceEditorScreenState();
}

class _PlaceEditorScreenState extends State<PlaceEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.place?.name ?? '');
  late final _address = TextEditingController(text: widget.place?.address ?? '');
  late final _note = TextEditingController(text: widget.place?.note ?? '');
  late final _latitude = TextEditingController(text: widget.place?.latitude?.toString() ?? '');
  late final _longitude = TextEditingController(text: widget.place?.longitude?.toString() ?? '');
  bool _saving = false;
  bool _allowPop = false;
  String? _error;

  @override
  void dispose() { for (final c in [_name, _address, _note, _latitude, _longitude]) { c.dispose(); } super.dispose(); }

  bool get _dirty => _name.text != (widget.place?.name ?? '') || _address.text != (widget.place?.address ?? '') || _note.text != (widget.place?.note ?? '') || _latitude.text != (widget.place?.latitude?.toString() ?? '') || _longitude.text != (widget.place?.longitude?.toString() ?? '');

  Future<void> _close() async {
    if (_saving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Өөрчлөлтөө орхих уу?'), content: const Text('Хадгалаагүй өөрчлөлтүүд алга болно.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Үргэлжлүүлэх')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Орхих'))]));
      if (discard != true || !mounted) return;
    }
    if (mounted) { setState(() => _allowPop = true); WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context); }); }
  }

  Future<void> _pickCoordinate() async {
    var world = false;
    var lat = double.tryParse(_latitude.text);
    var lon = double.tryParse(_longitude.text);
    final result = await showModalBottomSheet<(double, double)>(context: context, isScrollControlled: true, showDragHandle: true, builder: (context) => StatefulBuilder(builder: (context, update) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Газрын байршлыг сонгох', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('Монгол')), ButtonSegment(value: true, label: Text('Дэлхий'))], selected: {world}, onSelectionChanged: (value) => update(() => world = value.first)),
      const SizedBox(height: 14),
      SizedBox(height: 280, child: PlacesMap(world: world, selectedLatitude: lat, selectedLongitude: lon, onCoordinateTap: (a, b) => update(() {lat = a; lon = b;}))),
      const SizedBox(height: 12),
      const Text('Зураг дээр товшино уу. Улсын тойм зураг тул нарийн координатыг дараа нь засаж болно.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 16),
      FilledButton(onPressed: lat == null || lon == null ? null : () => Navigator.pop(context, (lat!, lon!)), child: const Text('Энэ цэгийг сонгох')),
    ])))));
    if (result != null && mounted) setState(() { _latitude.text = result.$1.toStringAsFixed(5); _longitude.text = result.$2.toStringAsFixed(5); });
  }

  String? _coordinateError(String? value, bool latitude) {
    final other = latitude ? _longitude.text : _latitude.text;
    if ((value ?? '').trim().isEmpty) return other.trim().isEmpty ? null : 'Хоёр координатыг оруулна уу.';
    final parsed = double.tryParse(value!.trim());
    final limit = latitude ? 90 : 180;
    return parsed == null || !parsed.isFinite || parsed < -limit || parsed > limit ? '-$limit–$limit хооронд оруулна уу.' : null;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _saving = true; _error = null; });
    try {
      await widget.controller.savePlace(PlaceEntry(id: widget.place?.id ?? newLocalId(), name: _name.text.trim(), address: _address.text.trim(), note: _note.text.trim(), latitude: double.tryParse(_latitude.text.trim()), longitude: double.tryParse(_longitude.text.trim()), category: widget.place?.category ?? 'other', createdAt: widget.place?.createdAt ?? DateTime.now()));
      if (!mounted) return;
      setState(() { _saving = false; _allowPop = true; });
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context); });
    } catch (_) { if (mounted) setState(() { _saving = false; _error = 'Хадгалж чадсангүй. Дахин оролдоорой.'; }); }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || (!_saving && !_dirty),
    onPopInvokedWithResult: (didPop, _) { if (!didPop) _close(); },
    child: Scaffold(
      appBar: AppBar(leading: IconButton(tooltip: 'Буцах', onPressed: _saving ? null : _close, icon: const Icon(Icons.arrow_back_rounded)), title: Text(widget.place == null ? 'Газар нэмэх' : 'Газар засах')),
      body: Form(key: _form, onChanged: () => setState(() {}), child: ListView(padding: const EdgeInsets.fromLTRB(22, 12, 22, 36), children: [
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(25)), child: const Column(children: [Icon(Icons.add_location_alt_outlined, color: AppColors.pink, size: 36), SizedBox(height: 12), Text('Санаж үлдмээр газар', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))])),
        const SizedBox(height: 24),
        TextFormField(key: const ValueKey('placeName'), controller: _name, enabled: !_saving, maxLength: 120, decoration: const InputDecoration(labelText: 'Газрын нэр', counterText: ''), validator: (value) => value == null || value.trim().isEmpty ? 'Газрын нэрээ бичээрэй.' : null),
        const SizedBox(height: 16),
        TextFormField(key: const ValueKey('placeAddress'), controller: _address, enabled: !_saving, maxLength: 300, decoration: const InputDecoration(labelText: 'Хаяг, байршлын тайлбар', counterText: '')),
        const SizedBox(height: 16),
        OutlinedButton.icon(key: const ValueKey('placePickCoordinate'), onPressed: _saving ? null : _pickCoordinate, icon: const Icon(Icons.map_outlined), label: const Text('Газрын зураг дээр сонгох')),
        const SizedBox(height: 16),
        TextFormField(key: const ValueKey('placeLatitude'), controller: _latitude, enabled: !_saving, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Өргөрөг', hintText: 'Жишээ: 47.9185'), validator: (value) => _coordinateError(value, true)),
        const SizedBox(height: 16),
        TextFormField(key: const ValueKey('placeLongitude'), controller: _longitude, enabled: !_saving, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Уртраг', hintText: 'Жишээ: 106.9177'), validator: (value) => _coordinateError(value, false)),
        const SizedBox(height: 12),
        const Text('Координат заавал биш. Нэмсэн үед газрын зурагт тэмдэглэнэ.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 18),
        TextFormField(key: const ValueKey('placeNote'), controller: _note, enabled: !_saving, minLines: 3, maxLines: 6, maxLength: 3000, decoration: const InputDecoration(labelText: 'Тэмдэглэл', alignLabelWithHint: true)),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 18),
        FilledButton.icon(key: const ValueKey('savePlaceButton'), onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded), label: Text(_saving ? 'Хадгалж байна…' : 'Газраа хадгалах')),
      ])),
    ),
  );
}
