import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ui/theme.dart';
import 'memory_models.dart';
import 'memory_photo.dart';
import 'memory_sticker.dart';

typedef MemoryPhotoPicker = Future<Uint8List?> Function();

class MemoryEditor extends StatefulWidget {
  const MemoryEditor({
    super.key,
    required this.day,
    required this.onSave,
    required this.onCancel,
    this.picker,
  });
  final String day;
  final Future<bool> Function(MemoryDraft) onSave;
  final VoidCallback onCancel;
  final MemoryPhotoPicker? picker;

  @override
  State<MemoryEditor> createState() => MemoryEditorState();
}

class MemoryEditorState extends State<MemoryEditor> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _note = TextEditingController();
  MemoryPhoto? _image;
  String _sticker = 'rounded';
  String? _error;
  bool _picking = false, _saving = false, _confirming = false;
  bool get _busy => _picking || _saving;
  bool get _dirty =>
      _image != null || _title.text.isNotEmpty || _note.text.isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _image = null;
    super.dispose();
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      Uint8List? bytes;
      if (widget.picker != null) {
        bytes = await widget.picker!();
      } else {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 2400,
          maxHeight: 2400,
          imageQuality: 92,
          requestFullMetadata: false,
        );
        if (file != null) {
          if (await file.length() > memoryInputByteLimit) {
            throw const MemoryPhotoException(
              '20 MB хүртэл хэмжээтэй зураг сонгоорой.',
            );
          }
          bytes = await file.readAsBytes();
        }
      }
      if (!mounted || bytes == null) return;
      final image = await normalizeMemoryPhoto(bytes);
      if (mounted) setState(() => _image = image);
    } on MemoryPhotoException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Зураг сонгож чадсангүй. Зургийн хандалтаа шалгаад дахин оролдоорой.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_image == null) {
      setState(() => _error = 'Дурсамжийнхаа зургийг сонгоорой.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave(
        MemoryDraft(
          day: widget.day,
          title: _title.text.trim(),
          note: _note.text.trim(),
          sticker: _sticker,
          image: _image!,
        ),
      );
      if (!saved && mounted) {
        setState(
          () => _error =
              'Хадгалж чадсангүй. Зураг, бичвэр тань хэвээр байна. Дахин оролдоорой.',
        );
      }
    } on MemoryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Хадгалж чадсангүй. Холболтоо шалгаад дахин оролдоорой.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> requestCancel() async {
    if (_busy || _confirming) return;
    if (_dirty) {
      _confirming = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Дурсамжаа хадгалахгүй гарах уу?'),
          content: const Text('Сонгосон зураг болон бичвэр хадгалагдахгүй.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Үргэлжлүүлэх'),
            ),
            TextButton(
              key: const Key('memoryDiscard'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Гарах'),
            ),
          ],
        ),
      );
      _confirming = false;
      if (!mounted || discard != true) return;
    }
    widget.onCancel();
  }

  String? _validate(String? value, int limit, {bool required = false}) {
    final text = value?.trim() ?? '';
    if (required && text.isEmpty) return 'Дурсамжийн нэрээ оруулаарай.';
    if (text.length > limit) return '$limit тэмдэгтэд багтаагаарай.';
    if (RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]').hasMatch(text)) {
      return 'Танигдахгүй тэмдэгтээ арилгаарай.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: ListView(
      key: const Key('memoryEditor'),
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
      children: [
        Text(
          widget.day,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: MemorySticker(
            bytes: _image?.photo,
            style: _sticker,
            size: 218,
          ),
        ),
        OutlinedButton.icon(
          key: const Key('memoryChoosePhoto'),
          onPressed: _busy ? null : _pick,
          icon: _picking
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _picking
                ? 'Зургийг бэлтгэж байна…'
                : _image == null
                ? 'Зураг сонгох'
                : 'Зураг солих',
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'rounded',
                icon: Icon(Icons.rounded_corner),
                label: Text('Дугуй хүрээ'),
              ),
              ButtonSegment(
                value: 'polaroid',
                icon: Icon(Icons.photo_outlined),
                label: Text('Полароид'),
              ),
            ],
            selected: {_sticker},
            showSelectedIcon: false,
            onSelectionChanged: _busy
                ? null
                : (values) => setState(() => _sticker = values.single),
          ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          key: const Key('memoryTitle'),
          controller: _title,
          enabled: !_busy,
          maxLength: 80,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Дурсамжийн нэр',
            hintText: 'Өнөөдөр юу хийсэн бэ?',
          ),
          validator: (value) => _validate(value, 80, required: true),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('memoryNote'),
          controller: _note,
          enabled: !_busy,
          minLines: 3,
          maxLines: 7,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: 'Тэр өдрийн тухай',
            hintText: 'Хамгийн гоё мөчөө бичээрэй…',
            alignLabelWithHint: true,
          ),
          validator: (value) => _validate(value, 2000),
        ),
        const SizedBox(height: 8),
        const Text(
          'Энэ зураг, дурсамж хоёуланд тань харагдана.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, height: 1.5),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const Key('memoryEditorError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('memorySave'),
          onPressed: _busy ? null : _save,
          child: _saving
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text('Хадгалж байна…'),
                  ],
                )
              : const Text('Дурсамжаа хадгалах'),
        ),
        const SizedBox(height: 10),
        TextButton(
          key: const Key('memoryCancel'),
          onPressed: _busy ? null : requestCancel,
          child: const Text('Болих'),
        ),
      ],
    ),
  );
}
