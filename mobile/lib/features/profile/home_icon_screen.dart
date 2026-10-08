import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../ui/components.dart';
import '../../ui/theme.dart';
import 'home_icon_renderer.dart';
import 'home_icon_service.dart';

typedef HomeIconPhotoPicker = Future<Uint8List?> Function();

class HomeIconScreen extends StatefulWidget {
  const HomeIconScreen({super.key, this.pickPhoto,
    this.service = const HomeIconService(), this.platform});
  final HomeIconPhotoPicker? pickPhoto;
  final HomeIconService service;
  final TargetPlatform? platform;

  @override
  State<HomeIconScreen> createState() => _HomeIconScreenState();
}

class _HomeIconScreenState extends State<HomeIconScreen> {
  final _label = TextEditingController(text: 'D-1');
  final _name = TextEditingController(text: 'Хамтдаа');
  final _photos = <ui.Image?>[null, null];
  final _alignments = [Alignment.center, Alignment.center];
  final _zooms = [1.0, 1.0];
  bool _split = false;
  bool _busy = false;
  int _selected = 0;
  String? _status;
  bool _error = false;

  TargetPlatform get _platform => widget.platform ?? defaultTargetPlatform;
  bool get _ready => _photos[0] != null && (!_split || _photos[1] != null)
      && _label.text.trim().isNotEmpty && _name.text.trim().isNotEmpty;

  HomeIconPainter get _painter => HomeIconPainter(
    photos: List.of(_photos), label: _label.text.trim(), split: _split,
    alignments: List.of(_alignments), zooms: List.of(_zooms),
  );

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    for (final photo in _photos) { photo?.dispose(); }
    super.dispose();
  }

  Future<void> _choose(int index) async {
    if (_busy) return;
    setState(() { _busy = true; _status = null; });
    try {
      Uint8List? bytes;
      if (widget.pickPhoto != null) {
        bytes = await widget.pickPhoto!();
      } else {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600,
          imageQuality: 92, requestFullMetadata: false);
        if (file != null) {
          if (await file.length() > 20 * 1024 * 1024) {
            throw const FormatException('Photo too large');
          }
          bytes = await file.readAsBytes();
        }
      }
      if (bytes == null || !mounted) return;
      final photo = await decodeHomeIconPhoto(bytes);
      if (!mounted) { photo.dispose(); return; }
      setState(() {
        _photos[index]?.dispose();
        _photos[index] = photo;
        _alignments[index] = Alignment.center;
        _zooms[index] = 1;
        _selected = index;
      });
    } on PlatformException {
      if (mounted) setState(() { _error = true;
        _status = 'Зураг нээж чадсангүй. Утасны тохиргооноос зургийн эрхээ шалгаад дахин оролдоорой.'; });
    } catch (_) {
      if (mounted) setState(() { _error = true;
        _status = 'Энэ зургийг нээж чадсангүй. Өөр зураг сонгоорой (20 MB хүртэл).'; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export({required bool pin}) async {
    if (_busy || !_ready) return;
    FocusScope.of(context).unfocus();
    final box = context.findRenderObject();
    final origin = box is RenderBox
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    setState(() { _busy = true; _status = null; _error = false; });
    try {
      final png = await renderHomeIconPng(_painter);
      if (!mounted) return;
      String message;
      if (pin) {
        final result = await widget.service.pin(png, _name.text.trim());
        message = switch (result) {
          HomeIconPinResult.requested => 'Нэмэх хүсэлт нээгдлээ. Утасны цэснээс зөвшөөрөөд нүүр дэлгэцээ шалгаарай.',
          HomeIconPinResult.updated => 'Нүүр дэлгэцийн товчлол шинэчлэгдлээ.',
          HomeIconPinResult.unsupported => 'Энэ утас зурагтай товчлол нэмэхийг дэмжихгүй байна. Дүрсээ зургаар хадгалж болно.',
        };
      } else {
        final result = await widget.service.share(png, origin);
        message = result == ShareResultStatus.dismissed
            ? 'Хадгалах цэсийг хаалаа. Хүсвэл дахин нээгээрэй.'
            : 'Дүрс бэлэн. Хадгалсан зургаа нүүр дэлгэцийн товчлолдоо сонгоорой.';
      }
      if (mounted) setState(() => _status = message);
    } catch (_) {
      if (mounted) setState(() { _error = true;
        _status = 'Дүрсийг бэлтгэж чадсангүй. Дахин оролдоорой.'; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ios = _platform == TargetPlatform.iOS;
    final android = _platform == TargetPlatform.android;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Бидний аппын дүрс')),
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            key: const Key('homeIconList'),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              const Text('Нүүр дэлгэцэнд ч\nбид хоёр ♡', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 29, height: 1.2, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              const Text('Хосын зураг, өөрийн бичигтэй дүрс бүтээгээрэй.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 24),
              Center(child: Semantics(
                label: 'Дүрсний урьдчилсан харагдац: ${_label.text}',
                child: Container(
                  width: 200, height: 200,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(44),
                    boxShadow: const [BoxShadow(color: Color(0x24B33A72), blurRadius: 28, offset: Offset(0, 10))]),
                  child: ClipRRect(borderRadius: BorderRadius.circular(44),
                    child: CustomPaint(key: const Key('homeIconPreview'), painter: _painter)),
                ),
              )),
              const SizedBox(height: 12),
              Text(_name.text.trim().isEmpty ? 'Хамтдаа' : _name.text.trim(),
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('Хамтын зураг')),
                  ButtonSegment(value: true, label: Text('Хоёр зураг'))],
                selected: {_split}, showSelectedIcon: false,
                onSelectionChanged: _busy ? null : (value) => setState(() {
                  _split = value.single; _selected = 0; _status = null;
                }),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: OutlinedButton.icon(key: const Key('homeIconPhoto0'),
                  onPressed: _busy ? null : () => _choose(0),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_split ? 'Миний зураг' : 'Зураг сонгох'))),
                if (_split) ...[
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(key: const Key('homeIconPhoto1'),
                    onPressed: _busy ? null : () => _choose(1),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Хосын зураг'))),
                ],
              ]),
              if (_photos[_selected] != null) ...[
                const SizedBox(height: 12),
                ExpansionTile(key: const Key('homeIconCrop'), tilePadding: EdgeInsets.zero,
                  title: const Text('Зургийн байрлал'),
                  children: [
                    if (_split) SegmentedButton<int>(
                      segments: const [ButtonSegment(value: 0, label: Text('Миний')),
                        ButtonSegment(value: 1, label: Text('Хосын'))],
                      selected: {_selected}, showSelectedIcon: false,
                      onSelectionChanged: _busy ? null : (values) => setState(() => _selected = values.single),
                    ),
                    _slider('Томруулах', _zooms[_selected], 1, 3,
                      (value) => _zooms[_selected] = value),
                    _slider('Зүүн · Баруун', _alignments[_selected].x, -1, 1,
                      (value) => _alignments[_selected] = Alignment(value, _alignments[_selected].y)),
                    _slider('Дээш · Доош', _alignments[_selected].y, -1, 1,
                      (value) => _alignments[_selected] = Alignment(_alignments[_selected].x, value)),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              TextField(key: const Key('homeIconLabel'), controller: _label,
                enabled: !_busy, maxLength: 8, textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Дүрсэн дээрх бичиг', hintText: 'D-1'),
                onChanged: (_) => setState(() => _status = null)),
              const Text('Жишээ: D-1, D+425, Бид ♡. Энэ бичиг автоматаар өөрчлөгдөхгүй.',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 16),
              TextField(key: const Key('homeIconName'), controller: _name,
                enabled: !_busy, maxLength: 24,
                decoration: const InputDecoration(labelText: 'Дүрсний доорх нэр'),
                onChanged: (_) => setState(() => _status = null)),
              const SizedBox(height: 12),
              if (_status != null) Padding(padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(liveRegion: true, child: Text(_status!,
                  key: const Key('homeIconStatus'),
                  style: TextStyle(color: _error ? Theme.of(context).colorScheme.error : AppColors.ink)))),
              FilledButton.icon(key: const Key('homeIconPrimary'),
                onPressed: !_ready || _busy ? null : () => _export(pin: android),
                icon: _busy ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(android ? Icons.add_to_home_screen_rounded : Icons.download_rounded),
                label: Text(_busy ? 'Бэлтгэж байна…' : android ? 'Нүүр дэлгэцэд нэмэх' : 'Дүрсийн зургийг хадгалах')),
              if (android) ...[
                const SizedBox(height: 10),
                OutlinedButton(key: const Key('homeIconShare'),
                  onPressed: !_ready || _busy ? null : () => _export(pin: false),
                  child: const Text('Зургаар хадгалах')),
              ],
              const SizedBox(height: 20),
              if (ios) const _IosInstructions()
              else Text(android
                ? 'Хамтдаа аппыг нээдэг шинэ товчлол нэмэгдэнэ. Утасны үндсэн аппын дүрс хэвээр үлдэнэ. Дүрсний хэлбэр утаснаас хамаарна.'
                : 'Зургаа хадгалаад утасныхаа нүүр дэлгэцийн товчлолд ашиглаарай.',
                style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
            ],
          ),
        ))),
      ),
    );
  }

  Widget _slider(String title, double value, double min, double max,
      ValueChanged<double> change) => Column(crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(title, style: const TextStyle(fontSize: 13)),
      Slider(value: value, min: min, max: max,
        onChanged: _busy ? null : (value) => setState(() { change(value); _status = null; }))]);
}

class _IosInstructions extends StatelessWidget {
  const _IosInstructions();

  @override
  Widget build(BuildContext context) => const SoftCard(
    color: AppColors.blush,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('iPhone дээр нэмэх', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
      SizedBox(height: 10),
      Text('1. Дээрх товчийг дарж, цэснээс Save Image сонгоно.\n\n'
        '2. Shortcuts апп → + → Open App үйлдэл нэмээд Хамтдаа аппыг сонгоно.\n\n'
        '3. Details цэс → Add to Home Screen.\n\n'
        '4. Дүрс дээр дарж Choose Photo → хадгалсан зургаа сонгоно. Нэрээ бичээд Add дарна.',
        style: TextStyle(fontSize: 13, height: 1.5)),
      SizedBox(height: 12),
      Text('Энэ нь Хамтдаа аппыг нээх товчлол. Үндсэн аппын дүрс хэвээр үлдэнэ.',
        style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5)),
    ]),
  );
}
