import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'memory_models.dart';

class MemoryDetail extends StatefulWidget {
  const MemoryDetail({
    super.key,
    required this.memory,
    required this.loadPhoto,
    required this.canDelete,
    required this.onDelete,
    required this.onClose,
  });
  final SharedMemory memory;
  final Future<Uint8List> Function() loadPhoto;
  final bool canDelete;
  final Future<bool> Function() onDelete;
  final VoidCallback onClose;

  @override
  State<MemoryDetail> createState() => _MemoryDetailState();
}

class _MemoryDetailState extends State<MemoryDetail> {
  Uint8List? _photo;
  String? _photoError, _deleteError;
  bool _loading = true,
      _deleting = false,
      _confirming = false,
      _deleted = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MemoryDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memory.id != widget.memory.id ||
        oldWidget.memory.pairId != widget.memory.pairId ||
        oldWidget.memory.version != widget.memory.version) {
      _photo = null;
      _deleteError = null;
      _deleted = false;
      _load();
    }
  }

  @override
  void dispose() {
    _request++;
    _photo = null;
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _photoError = null;
      _photo = null;
    });
    try {
      final photo = await widget.loadPhoto();
      if (photo.isEmpty) throw const MemoryFailure('unavailable');
      if (mounted && request == _request) setState(() => _photo = photo);
    } on MemoryFailure catch (error) {
      if (mounted && request == _request) {
        setState(() => _photoError = error.message);
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(
          () => _photoError = 'Зургийг нээж чадсангүй. Дахин оролдоорой.',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    if (!widget.canDelete || _deleting || _confirming) return;
    _confirming = true;
    final memory = widget.memory;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Дурсамжийг устгах уу?'),
        content: const Text(
          'Зураг болон бичвэр хоёулангийн тань хуанлиас устна.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Болих'),
          ),
          TextButton(
            key: const Key('memoryConfirmDelete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Устгах'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (!mounted ||
        confirmed != true ||
        !widget.canDelete ||
        memory.id != widget.memory.id ||
        memory.pairId != widget.memory.pairId) {
      return;
    }
    setState(() {
      _deleting = true;
      _deleteError = null;
    });
    try {
      final deleted = await widget.onDelete();
      if (!mounted ||
          memory.id != widget.memory.id ||
          memory.pairId != widget.memory.pairId ||
          memory.version != widget.memory.version) {
        return;
      }
      if (deleted) {
        _request++;
        _photo = null;
        _deleted = true;
        widget.onClose();
      } else {
        setState(() => _deleteError = 'Устгаж чадсангүй. Дахин оролдоорой.');
      }
    } on MemoryFailure catch (error) {
      if (mounted) setState(() => _deleteError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _deleteError =
              'Устгаж чадсангүй. Холболтоо шалгаад дахин оролдоорой.',
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _retry(String message) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.muted,
        size: 36,
      ),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('memoryPhotoRetry'),
        onPressed: _deleting ? null : _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Дахин нээх'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => _deleted
      ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Дурсамж устлаа.'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: widget.onClose,
                child: const Text('Хуанли руу буцах'),
              ),
            ],
          ),
        )
      : ListView(
          key: const Key('memoryDetail'),
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          children: [
            Text(
              widget.memory.day,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: ColoredBox(
                color: AppColors.blush,
                child: _loading
                    ? const SizedBox(
                        height: 280,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _photoError != null
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: _retry(_photoError!),
                      )
                    : Image.memory(
                        _photo!,
                        key: const Key('memoryFullPhoto'),
                        fit: BoxFit.contain,
                        semanticLabel: widget.memory.title,
                        errorBuilder: (_, _, _) => Padding(
                          padding: const EdgeInsets.all(28),
                          child: _retry(
                            'Зургийг нээж чадсангүй. Дахин оролдоорой.',
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.memory.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            if (widget.memory.note.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(
                widget.memory.note,
                style: const TextStyle(fontSize: 16, height: 1.65),
              ),
            ],
            if (_deleteError != null)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _deleteError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 28),
            OutlinedButton(
              key: const Key('memoryClose'),
              onPressed: _deleting ? null : widget.onClose,
              child: const Text('Хуанли руу буцах'),
            ),
            if (widget.canDelete) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                key: const Key('memoryDelete'),
                onPressed: _deleting ? null : _delete,
                icon: _deleting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                label: Text(_deleting ? 'Устгаж байна…' : 'Дурсамжийг устгах'),
              ),
            ],
          ],
        );
}
