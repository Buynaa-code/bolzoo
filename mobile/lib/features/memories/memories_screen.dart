import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/app_controller.dart';
import '../../ui/theme.dart';
import '../places/places_screen.dart';
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

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  DateTime? _month;

  Future<void> _chooseMonth(List<MemoryEntry> memories) async {
    final months =
        memories
            .map((m) => DateTime(m.date.year, m.date.month))
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final selection = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Дурсамжийн сар',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              key: const ValueKey('memoriesAllMonths'),
              title: const Text('Бүх дурсамж'),
              trailing: _month == null
                  ? const Icon(Icons.check_rounded, color: AppColors.pink)
                  : null,
              onTap: () => Navigator.pop(context, DateTime(1)),
            ),
            for (final month in months)
              ListTile(
                key: ValueKey('memoryMonth-${month.year}-${month.month}'),
                title: Text('${month.year} · ${month.month}-р сар'),
                trailing: _month == month
                    ? const Icon(Icons.check_rounded, color: AppColors.pink)
                    : null,
                onTap: () => Navigator.pop(context, month),
              ),
          ],
        ),
      ),
    );
    if (selection != null && mounted) {
      setState(() => _month = selection.year == 1 ? null : selection);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final all = [...widget.controller.data.memories]
        ..sort((a, b) => b.date.compareTo(a.date));
      final memories = all
          .where(
            (m) =>
                _month == null ||
                (m.date.year == _month!.year && m.date.month == _month!.month),
          )
          .toList();
      final width = MediaQuery.sizeOf(context).width;
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Бидний дурсамж',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('memoriesPlacesButton'),
                        tooltip: 'Очсон газрууд',
                        onPressed: () => openPlaces(context, widget.controller),
                        icon: const Icon(Icons.map_outlined),
                      ),
                      IconButton.filledTonal(
                        key: const ValueKey('memoriesAddButton'),
                        tooltip: 'Дурсамж нэмэх',
                        onPressed: () =>
                            openMemoryEditor(context, widget.controller),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Жижигхэн мөчүүд. Нандин дурсамжууд.',
                    style: TextStyle(color: AppColors.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Flexible(
                        child: OutlinedButton.icon(
                          key: const ValueKey('memoriesMonthFilter'),
                          onPressed: () => _chooseMonth(all),
                          icon: const Icon(
                            Icons.calendar_month_outlined,
                            size: 17,
                          ),
                          label: Text(
                            _month == null
                                ? 'Бүх сар'
                                : '${_month!.year} · ${_month!.month}-р сар',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${memories.length} дурсамж',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _PrivateCaption(mixed: all.any((memory) => memory.shared)),
                ],
              ),
            ),
          ),
          if (memories.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
                child: _month == null
                    ? _EmptyMemories(
                        onAdd: () =>
                            openMemoryEditor(context, widget.controller),
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library_outlined,
                              size: 40,
                              color: AppColors.muted,
                            ),
                            const SizedBox(height: 16),
                            const Text('Энэ сард дурсамж алга'),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () => setState(() => _month = null),
                              child: const Text('Бүх дурсамжийг харах'),
                            ),
                          ],
                        ),
                      ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: width >= 650 ? 3 : 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                  mainAxisExtent:
                      (width - 58) / (width >= 650 ? 3 : 2) + 100 * scale,
                ),
                itemCount: memories.length,
                itemBuilder: (context, index) => _MemoryCard(
                  memory: memories[index],
                  controller: widget.controller,
                  onTap: () => openMemoryDetail(
                    context,
                    widget.controller,
                    memories[index].id,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _PrivateCaption extends StatelessWidget {
  const _PrivateCaption({this.shared = false, this.mixed = false});
  final bool shared;
  final bool mixed;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        shared || mixed
            ? Icons.people_outline_rounded
            : Icons.lock_outline_rounded,
        size: 14,
        color: AppColors.muted,
      ),
      SizedBox(width: 6),
      Expanded(
        child: Text(
          mixed
              ? 'Хувийн болон хуваалцсан дурсамжууд'
              : shared
              ? 'Хостойгоо хуваалцсан'
              : 'Зөвхөн танд харагдана',
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
  const _MemoryCard({
    required this.memory,
    required this.controller,
    required this.onTap,
  });
  final AppController controller;
  final MemoryEntry memory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('memoryCard-${memory.id}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (memory.photoPath != null || memory.mediaKey != null)
                    _MemoryPhoto(
                      path: controller.isPartnerItem(memory.id)
                          ? null
                          : memory.photoPath,
                      mediaKey: memory.mediaKey,
                      controller: controller,
                    )
                  else
                    const ColoredBox(
                      color: AppColors.blush,
                      child: Center(
                        child: Icon(
                          Icons.auto_stories_outlined,
                          size: 38,
                          color: AppColors.pink,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .94),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        child: Text(
                          '${memory.date.month}.${memory.date.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 11),
          Text(
            memory.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 5),
          if (memory.place.isNotEmpty)
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 13,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    memory.place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            )
          else
            Text(
              '${memory.date.year} оны ${memory.date.month}-р сар',
              maxLines: 1,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
        ],
      ),
    ),
  );
}

class _MemoryPhoto extends StatelessWidget {
  const _MemoryPhoto({this.path, this.mediaKey, this.controller});
  final String? path;
  final String? mediaKey;
  final AppController? controller;

  Widget _unavailable({bool remote = false}) => ColoredBox(
    color: AppColors.blush,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.image_not_supported_outlined,
              color: AppColors.muted,
            ),
            const SizedBox(height: 8),
            Text(
              remote ? 'Зураг татагдаагүй байна' : 'Зураг нээгдэхгүй байна',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            if (remote && controller != null)
              TextButton(
                onPressed: () async {
                  try {
                    await controller!.refreshCloud();
                  } catch (_) {}
                },
                child: const Text('Дахин татах'),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final local = path;
    if (local != null) {
      return Image.file(
        File(local),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => _unavailable(),
      );
    }
    final key = mediaKey;
    final bytes = key == null ? null : controller?.mediaBytes(key);
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => _unavailable(remote: true),
      );
    }
    return _unavailable(remote: key != null);
  }
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
  bool _socialBusy = false;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _like() async {
    if (_socialBusy) return;
    setState(() => _socialBusy = true);
    try {
      await widget.controller.toggleMemoryLike(widget.memoryId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Хадгалж чадсангүй. Дахин оролдоорой.')),
        );
      }
    } finally {
      if (mounted) setState(() => _socialBusy = false);
    }
  }

  Future<void> _addComment() async {
    if (_socialBusy || _comment.text.trim().isEmpty) return;
    setState(() => _socialBusy = true);
    try {
      await widget.controller.addMemoryComment(
        widget.memoryId,
        _comment.text.trim(),
      );
      if (mounted) {
        _comment.clear();
        FocusScope.of(context).unfocus();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сэтгэгдэл хадгалагдсангүй. Дахин оролдоорой.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _socialBusy = false);
    }
  }

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
        documentsDirectory: widget.controller.storageDirectory,
        referencedPaths: () =>
            widget.controller.data.memories.map((memory) => memory.photoPath),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Дурсамж устгагдлаа')));
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
              if (current != null && widget.controller.canEdit(current.id))
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
              if (current != null && widget.controller.canEdit(current.id))
                IconButton(
                  tooltip: 'Дурсамж устгах',
                  onPressed: _deleting ? null : _delete,
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
                    if (current.photoPath != null ||
                        current.mediaKey != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _MemoryPhoto(
                            path: widget.controller.isPartnerItem(current.id)
                                ? null
                                : current.photoPath,
                            mediaKey: current.mediaKey,
                            controller: widget.controller,
                          ),
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
                    if (current.place.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      InkWell(
                        key: const ValueKey('memoryPlaceLink'),
                        onTap: current.placeId == null
                            ? null
                            : () => openPlaceDetail(
                                context,
                                widget.controller,
                                current.placeId!,
                              ),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.place_outlined,
                                color: AppColors.pink,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  current.place,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                              if (current.placeId != null)
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.muted,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (current.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 22),
                      SelectableText(
                        current.text,
                        style: const TextStyle(fontSize: 16, height: 1.7),
                      ),
                    ],
                    const SizedBox(height: 25),
                    Row(
                      children: [
                        IconButton(
                          key: const ValueKey('memoryLikeButton'),
                          tooltip: current.likedByMe
                              ? 'Таалагдсаныг болих'
                              : 'Таалагдлаа',
                          onPressed: _socialBusy ? null : _like,
                          icon: Icon(
                            current.likedByMe
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: AppColors.pink,
                          ),
                        ),
                        Text(
                          '${current.likeCount} таалагдсан',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 18,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${current.comments.length}',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 14),
                    const Text(
                      'Сэтгэгдэл',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      current.shared
                          ? 'Хуваалцсан дурсамжийн сэтгэгдлүүд.'
                          : widget.controller.cloudAvailable
                          ? 'Таны бүртгэлийн сэтгэгдлүүд.'
                          : 'Энэ төхөөрөмж дээр хадгалсан сэтгэгдлүүд.',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                    for (final comment in current.comments)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CircleAvatar(
                              radius: 17,
                              backgroundColor: AppColors.blush,
                              child: Icon(
                                Icons.person_outline_rounded,
                                size: 19,
                                color: AppColors.pink,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    comment.authorName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    comment.text,
                                    style: const TextStyle(height: 1.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                    TextField(
                      key: const ValueKey('memoryComment'),
                      controller: _comment,
                      enabled: !_socialBusy,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        hintText: 'Сэтгэгдлээ үлдээгээрэй…',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const ValueKey('memoryCommentSave'),
                        onPressed: _socialBusy ? null : _addComment,
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Хадгалах'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _PrivateCaption(shared: current.shared),
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
  late final TextEditingController _place;
  late final String _initialPlace;
  String? _placeId;
  String? _initialPlaceId;
  late bool _shared;
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
    _shared = widget.memory?.shared ?? false;
    _placeId = widget.memory?.placeId ?? widget.placeId;
    PlaceEntry? savedPlace;
    for (final entry in widget.controller.data.places) {
      if (entry.id == _placeId) savedPlace = entry;
    }
    if (savedPlace == null) _placeId = null;
    _initialPlaceId = _placeId;
    _initialPlace =
        widget.memory?.place ?? savedPlace?.name ?? event?.place ?? '';
    _place = TextEditingController(text: _initialPlace);
    _place.addListener(_changed);
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
      _place.text != _initialPlace ||
      _placeId != _initialPlaceId ||
      _shared != (widget.memory?.shared ?? false) ||
      !DateUtils.isSameDay(_date, _initialDate) ||
      _pickedPhoto != null ||
      (_removePhoto && widget.memory?.photoPath != null);

  String? get _photoPath =>
      _pickedPhoto?.path ?? (_removePhoto ? null : widget.memory?.photoPath);

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    _place.dispose();
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
      final base =
          widget.memory ??
          MemoryEntry(
            id: newLocalId(),
            title: _title.text.trim(),
            date: _date,
            eventId: widget.eventId,
          );
      await widget.controller.saveMemory(
        base.copyWith(
          title: _title.text.trim(),
          date: DateTime(_date.year, _date.month, _date.day),
          text: _text.text.trim(),
          photoPath: photoPath,
          mediaKey: _removePhoto || picked != null ? null : base.mediaKey,
          shared: _shared,
          place: _place.text.trim(),
          placeId: widget.controller.data.places.any((p) => p.id == _placeId)
              ? _placeId
              : null,
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
      final messenger = ScaffoldMessenger.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
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
        _error = widget.controller.cloudAvailable
            ? 'Хадгалж чадсангүй. Холболт болон зургийн төрлийг шалгаад дахин оролдоорой.'
            : 'Хадгалж чадсангүй. Утасны сул зайг шалгаад дахин оролдоорой.';
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
              if (photoPath != null ||
                  (!_removePhoto && widget.memory?.mediaKey != null)) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: AspectRatio(
                    aspectRatio: 1.4,
                    child: _MemoryPhoto(
                      path: photoPath,
                      mediaKey: _removePhoto ? null : widget.memory?.mediaKey,
                      controller: widget.controller,
                    ),
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
                key: const ValueKey('memoryPlace'),
                controller: _place,
                enabled: !_saving,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Байршил',
                  hintText: 'Тэр өдөр хаана байсан бэ?',
                  counterText: '',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
                onChanged: (_) {
                  if (_placeId != null) setState(() => _placeId = null);
                },
              ),
              if (widget.controller.data.places.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: ValueKey('memorySavedPlace-${_placeId ?? 'none'}'),
                  initialValue: _placeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Хадгалсан газартай холбох',
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Холбохгүй')),
                    for (final place in widget.controller.data.places)
                      DropdownMenuItem(
                        value: place.id,
                        child: Text(
                          place.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _placeId = value == null || value.isEmpty
                              ? null
                              : value;
                          if (_placeId != null) {
                            _place.text = widget.controller.data.places
                                .firstWhere((p) => p.id == _placeId)
                                .name;
                          }
                        }),
                ),
              ],
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
                  hintText: 'Юугаараа онцгой байв?',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              SwitchListTile.adaptive(
                key: const ValueKey('memorySharedSwitch'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Хоёуланд харагдана',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  widget.controller.cloudAvailable
                      ? 'Хуваалцсан дурсамжийг хос тань харна.'
                      : 'Хуваалцахын тулд бүртгэлээрээ нэвтрээрэй.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                value: _shared,
                onChanged: _saving || !widget.controller.cloudAvailable
                    ? null
                    : (value) => setState(() => _shared = value),
              ),
              const SizedBox(height: 12),
              _PrivateCaption(shared: _shared),
              const SizedBox(height: 6),
              Text(
                _shared
                    ? 'Сервер хадгалсны дараа хосод харагдана.'
                    : widget.controller.cloudAvailable
                    ? 'Таны бүртгэлд хадгалагдана.'
                    : 'Энэ төхөөрөмж дээр хадгалагдана.',
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
