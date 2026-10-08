import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/app_controller.dart';
import '../../ui/theme.dart';
import 'media_files.dart';

String _memoryDate(DateTime value) =>
    '${value.year} оны ${value.month}-р сарын ${value.day}';

Future<void> openMemoryEditor(
  BuildContext context,
  AppController controller, {
  MemoryEntry? memory,
  String? eventId,
  String? placeId,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => _MemoryEditor(
      controller: controller,
      memory: memory,
      eventId: eventId,
      placeId: placeId,
    ),
  ),
);

Future<void> openMemoryDetail(
  BuildContext context,
  AppController controller,
  String memoryId,
) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => _MemoryDetail(controller: controller, memoryId: memoryId),
  ),
);

class MemoriesScreen extends StatelessWidget {
  const MemoriesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final memories = [...controller.data.memories]
        ..sort((a, b) => b.date.compareTo(a.date));
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Дурсамж',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Дурсамж нэмэх',
                        onPressed: () => openMemoryEditor(context, controller),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Жижигхэн мөчүүд. Нандин дурсамжууд.',
                    style: TextStyle(color: AppColors.muted, fontSize: 15),
                  ),
                  const SizedBox(height: 18),
                  const _PrivateCaption(),
                ],
              ),
            ),
          ),
          if (memories.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
                child: _EmptyMemories(
                  onAdd: () => openMemoryEditor(context, controller),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              sliver: SliverList.separated(
                itemCount: memories.length,
                separatorBuilder: (_, _) => const SizedBox(height: 18),
                itemBuilder: (context, index) => _MemoryCard(
                  memory: memories[index],
                  onTap: () =>
                      openMemoryDetail(context, controller, memories[index].id),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _PrivateCaption extends StatelessWidget {
  const _PrivateCaption();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.muted),
      SizedBox(width: 6),
      Expanded(
        child: Text(
          'Зөвхөн танд харагдана',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
    ],
  );
}

class _EmptyMemories extends StatelessWidget {
  const _EmptyMemories({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.blush,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              size: 38,
              color: AppColors.pink,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Эхний дурсамжаа\nхадгалъя',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Дуртай зургаа сонгоод, тэр өдрийн\nхамгийн гоё мөчийг бичээрэй.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.6),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Дурсамж нэмэх'),
          ),
        ],
      ),
    ),
  );
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.memory, required this.onTap});

  final MemoryEntry memory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (memory.photoPath != null)
            AspectRatio(
              aspectRatio: 1.55,
              child: _MemoryPhoto(path: memory.photoPath!),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _memoryDate(memory.date),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  memory.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (memory.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    memory.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _MemoryPhoto extends StatelessWidget {
  const _MemoryPhoto({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Image.file(
    File(path),
    fit: BoxFit.cover,
    width: double.infinity,
    errorBuilder: (context, error, stack) => const ColoredBox(
      color: AppColors.blush,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined, color: AppColors.muted),
              SizedBox(height: 8),
              Text(
                'Зураг нээгдэхгүй байна',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MemoryDetail extends StatefulWidget {
  const _MemoryDetail({required this.controller, required this.memoryId});

  final AppController controller;
  final String memoryId;

  @override
  State<_MemoryDetail> createState() => _MemoryDetailState();
}

class _MemoryDetailState extends State<_MemoryDetail> {
  bool _deleting = false;

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Дурсамжийг устгах уу?'),
        content: const Text(
          'Энэ дурсамж аппын бүртгэлээс устна. Утасны зургийн санд байгаа эх зураг хэвээр үлдэнэ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Болих'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Устгах'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      String? oldPhotoPath;
      for (final memory in widget.controller.data.memories) {
        if (memory.id == widget.memoryId) oldPhotoPath = memory.photoPath;
      }
      await widget.controller.deleteMemory(widget.memoryId);
      await deleteUnusedManagedPhoto(
        oldPhotoPath,
        referencedPaths: () =>
            widget.controller.data.memories.map((memory) => memory.photoPath),
      );
      if (!mounted) return;
      setState(() => _deleting = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Дурсамж устгагдлаа')),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Устгаж чадсангүй. Дахин оролдоорой.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      MemoryEntry? memory;
      for (final entry in widget.controller.data.memories) {
        if (entry.id == widget.memoryId) memory = entry;
      }
      final current = memory;
      return PopScope(
        canPop: !_deleting,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Дурсамж'),
            actions: [
              if (current != null)
                IconButton(
                  tooltip: 'Дурсамж засах',
                  onPressed: _deleting
                      ? null
                      : () => openMemoryEditor(
                          context,
                          widget.controller,
                          memory: current,
                        ),
                  icon: const Icon(Icons.edit_outlined),
                ),
              IconButton(
                tooltip: 'Дурсамж устгах',
                onPressed: current == null || _deleting ? null : _delete,
                icon: _deleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: current == null
              ? const Center(child: Text('Энэ дурсамж байхгүй байна.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                  children: [
                    if (current.photoPath != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _MemoryPhoto(path: current.photoPath!),
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                    Text(
                      _memoryDate(current.date),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      current.title,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                    ),
                    if (current.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 22),
                      SelectableText(
                        current.text,
                        style: const TextStyle(fontSize: 16, height: 1.7),
                      ),
                    ],
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 16),
                    const _PrivateCaption(),
                  ],
                ),
        ),
      );
    },
  );
}

class _MemoryEditor extends StatefulWidget {
  const _MemoryEditor({
    required this.controller,
    this.memory,
    this.eventId,
    this.placeId,
  });

  final AppController controller;
  final MemoryEntry? memory;
  final String? eventId;
  final String? placeId;

  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _title;
  late final TextEditingController _text;
  late final String _initialTitle;
  late final String _initialText;
  late final DateTime _initialDate;
  late DateTime _date;
  XFile? _pickedPhoto;
  bool _removePhoto = false;
  bool _saving = false;
  bool _picking = false;
  bool _allowPop = false;
  bool _askingToClose = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    DateEvent? event;
    if (widget.memory == null && widget.eventId != null) {
      for (final candidate in widget.controller.data.events) {
        if (candidate.id == widget.eventId) event = candidate;
      }
    }
    _initialTitle = widget.memory?.title ?? event?.title ?? '';
    _initialText = widget.memory?.text ?? '';
    _title = TextEditingController(text: _initialTitle);
    _text = TextEditingController(text: _initialText);
    _initialDate = widget.memory?.date ?? event?.startsAt ?? DateTime.now();
    _date = _initialDate;
    _title.addListener(_changed);
    _text.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _dirty =>
      _title.text != _initialTitle ||
      _text.text != _initialText ||
      !DateUtils.isSameDay(_date, _initialDate) ||
      _pickedPhoto != null ||
      (_removePhoto && widget.memory?.photoPath != null);

  String? get _photoPath =>
      _pickedPhoto?.path ?? (_removePhoto ? null : widget.memory?.photoPath);

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _requestClose() async {
    if (_saving || _picking || _askingToClose || _allowPop) return;
    if (_dirty) {
      _askingToClose = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Өөрчлөлтөө орхих уу?'),
          content: const Text('Хадгалаагүй өөрчлөлтүүд алга болно.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Үргэлжлүүлэх'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Орхих'),
            ),
          ],
        ),
      );
      _askingToClose = false;
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _pickPhoto() async {
    if (_picking || _saving) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 88,
        requestFullMetadata: false,
      );
      if (!mounted) return;
      if (photo != null) {
        setState(() {
          _pickedPhoto = photo;
          _removePhoto = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Зураг сонгож чадсангүй. Зургийн хандалтаа шалгаад дахин оролдоорой.';
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Дурсамжийн өдөр',
      cancelText: 'Болих',
      confirmText: 'Сонгох',
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  Future<void> _save() async {
    if (_saving || _picking || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    File? newPhoto;
    try {
      String? photoPath = _removePhoto ? null : widget.memory?.photoPath;
      final picked = _pickedPhoto;
      if (picked != null) {
        final documents =
            widget.controller.storageDirectory ??
            await getApplicationDocumentsDirectory();
        final directory = Directory('${documents.path}/memories_media');
        await directory.create(recursive: true);
        final rawExtension = picked.path.split('.').last.toLowerCase();
        final extension =
            const [
              'jpg',
              'jpeg',
              'png',
              'webp',
              'heic',
              'heif',
            ].contains(rawExtension)
            ? rawExtension
            : 'jpg';
        newPhoto = File('${directory.path}/${newLocalId()}.$extension');
        await picked.saveTo(newPhoto.path);
        photoPath = newPhoto.path;
      }
      await widget.controller.saveMemory(
        MemoryEntry(
          id: widget.memory?.id ?? newLocalId(),
          title: _title.text.trim(),
          date: DateTime(_date.year, _date.month, _date.day),
          text: _text.text.trim(),
          photoPath: photoPath,
          eventId: widget.memory?.eventId ?? widget.eventId,
          placeId: widget.memory?.placeId ?? widget.placeId,
        ),
      );
      await deleteUnusedManagedPhoto(
        widget.memory?.photoPath,
        documentsDirectory: widget.controller.storageDirectory,
        referencedPaths: () =>
            widget.controller.data.memories.map((memory) => memory.photoPath),
      );
      if (!mounted) return;
      setState(() {
        _allowPop = true;
        _saving = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Дурсамж хадгалагдлаа')),
        );
      });
    } catch (_) {
      if (newPhoto != null) {
        try {
          if (await newPhoto.exists()) await newPhoto.delete();
        } catch (_) {
          // A failed cleanup must not hide the actionable save error.
        }
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Хадгалж чадсангүй. Утасны сул зайг шалгаад дахин оролдоорой.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoPath = _photoPath;
    return PopScope(
      canPop: _allowPop || (!_saving && !_picking && !_dirty),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Буцах',
            onPressed: _saving || _picking ? null : _requestClose,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(widget.memory == null ? 'Шинэ дурсамж' : 'Дурсамж засах'),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              if (photoPath != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: AspectRatio(
                    aspectRatio: 1.4,
                    child: _MemoryPhoto(path: photoPath),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _saving || _picking ? null : _pickPhoto,
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Зураг солих'),
                    ),
                    TextButton.icon(
                      onPressed: _saving || _picking
                          ? null
                          : () => setState(() {
                              _pickedPhoto = null;
                              _removePhoto = true;
                            }),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Хасах'),
                    ),
                  ],
                ),
              ] else
                Material(
                  color: AppColors.blush,
                  borderRadius: BorderRadius.circular(26),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _saving || _picking ? null : _pickPhoto,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 35),
                      child: Column(
                        children: [
                          _picking
                              ? const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 34,
                                  color: AppColors.pink,
                                ),
                          const SizedBox(height: 12),
                          const Text(
                            'Зураг нэмэх',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.pink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Зургийн сангаас сонгоно · Заавал биш',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 26),
              TextFormField(
                key: const ValueKey('memoryTitle'),
                controller: _title,
                enabled: !_saving,
                maxLength: 100,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Дурсамжийн нэр',
                  hintText: 'Жишээ нь: Хамтдаа үзсэн нар жаргалт',
                  counterText: '',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Дурсамждаа нэр өгөөрэй.'
                    : null,
              ),
              const SizedBox(height: 18),
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: AppColors.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: _saving ? null : _chooseDate,
                  leading: const Icon(
                    Icons.calendar_today_outlined,
                    size: 21,
                    color: AppColors.pink,
                  ),
                  title: const Text(
                    'Огноо',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  subtitle: Text(
                    _memoryDate(_date),
                    style: const TextStyle(color: AppColors.ink, fontSize: 15),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                key: const ValueKey('memoryText'),
                controller: _text,
                enabled: !_saving,
                minLines: 5,
                maxLines: 12,
                maxLength: 5000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Тэр өдрийн тухай',
                  hintText: 'Санаж үлдмээр мөчөө бичээрэй…',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              const _PrivateCaption(),
              const SizedBox(height: 6),
              const Text(
                'Энэ төхөөрөмж дээр хадгалагдана.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              if (_error != null) ...[
                const SizedBox(height: 18),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                key: const ValueKey('saveMemoryButton'),
                onPressed: _saving || _picking ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.favorite_border_rounded, size: 20),
                label: Text(_saving ? 'Хадгалж байна…' : 'Дурсамжаа хадгалах'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
