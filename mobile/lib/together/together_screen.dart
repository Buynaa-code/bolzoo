import 'dart:async';
import 'package:flutter/material.dart';
import '../cloudflare/cloudflare_auth_repository.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import '../memories/memory_controller.dart';
import '../memories/memory_repository.dart';
import '../memories/memory_editor.dart';
import '../memories/memory_detail.dart';
import '../memories/memory_sticker.dart';
import '../memories/memory_models.dart';
import '../wishes/wish_board.dart';
import '../wishes/wish_controller.dart';
import '../wishes/wish_models.dart';
import '../wishes/wish_repository.dart';
import 'together_controller.dart';
import 'together_event_editor.dart';
import 'together_models.dart';
import 'together_repository.dart';
import 'together_reminders.dart';

class TogetherScreen extends StatefulWidget {
  const TogetherScreen({
    super.key,
    required this.auth,
    this.controller,
    this.memories,
    this.memoryPhotoPicker,
    this.wishes,
    this.reminders,
  });
  final CloudflareAuthRepository auth;

  /// Injected controllers are owned by the caller, useful for isolated flow tests.
  final TogetherController? controller;
  final MemoryController? memories;
  final MemoryPhotoPicker? memoryPhotoPicker;
  final WishController? wishes;

  /// The signed-in home owns reminders across calendar route navigation.
  final TogetherReminderCoordinator? reminders;
  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends State<TogetherScreen>
    with WidgetsBindingObserver {
  late final TogetherController _controller;
  MemoryController? _memories;
  WishController? _wishes;
  var _wishBoardKey = GlobalKey<WishBoardState>();
  String? _wishPair;
  final _memoryEditorKey = GlobalKey<MemoryEditorState>();
  TogetherSnapshot? _lastSnapshot;
  String? _memoryId;
  bool _addingMemory = false;
  int _tab = 0;
  String? _eventId, _panePair;
  bool _editing = false, _creating = false, _foreground = true;
  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        TogetherController(
          repository: CloudflareTogetherRepository(widget.auth),
        );
    // Supplying a test/custom calendar also requires its own memory controller;
    // it must not silently create a second live network dependency.
    _memories =
        widget.memories ??
        (widget.controller == null
            ? MemoryController(CloudflareMemoryRepository(widget.auth))
            : null);
    _memories?.addListener(_memoryUpdated);
    _wishes =
        widget.wishes ??
        (widget.controller == null
            ? WishController(CloudflareWishRepository(widget.auth))
            : null);
    _wishes?.addListener(_wishUpdated);
    _controller.addListener(_updated);
    WidgetsBinding.instance.addObserver(this);
    _controller.setVisible(true);
  }

  void _memoryUpdated() {
    if (mounted) setState(() {});
  }

  void _wishUpdated() {
    if (mounted) setState(() {});
  }

  void _updated() {
    if (!mounted) return;
    if (_panePair != null && _panePair != _controller.data?.pairId) {
      _eventId = _panePair = null;
      _creating = _editing = _addingMemory = false;
      _memoryId = null;
    }
    final snapshot = _controller.data;
    final changed = !identical(snapshot, _lastSnapshot);
    _lastSnapshot = snapshot;
    if (changed) widget.reminders?.observe(snapshot);
    final wishPair = _controller.paired ? snapshot?.pairId : null;
    if (_wishPair != wishPair) {
      _wishPair = wishPair;
      _wishBoardKey = GlobalKey<WishBoardState>();
    }
    final wishesBound = _wishes?.pairId == wishPair;
    _wishes?.bind(wishPair);
    if (_foreground && wishesBound && changed) unawaited(_wishes?.refresh());
    if (_foreground) {
      final pair = _controller.paired ? snapshot?.pairId : null;
      final month = pair == null ? null : togetherMonth(_controller.month);
      final bound = _memories?.pairId == pair && _memories?.month == month;
      _memories?.bind(pair, month);
      if (bound && changed) unawaited(_memories?.refresh());
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _controller.setVisible(_foreground);
    _memories?.setVisible(_foreground);
    _wishes?.setVisible(_foreground);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_updated);
    _memories?.removeListener(_memoryUpdated);
    _wishes?.removeListener(_wishUpdated);
    if (widget.memories == null) _memories?.dispose();
    if (widget.wishes == null) _wishes?.dispose();
    _controller.setVisible(false);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  bool get _inPane =>
      _eventId != null ||
      _creating ||
      _addingMemory ||
      _memoryId != null ||
      (_tab == 2 && _wishBoardKey.currentState?.hasPane == true);
  void _back() {
    if (_tab == 2 && _wishBoardKey.currentState?.hasPane == true) {
      unawaited(_wishBoardKey.currentState!.requestBack());
      return;
    }
    if (_addingMemory && _memoryEditorKey.currentState != null) {
      unawaited(_memoryEditorKey.currentState!.requestCancel());
      return;
    }
    _closePane();
  }

  void _closePane() {
    if (_inPane) {
      setState(() {
        _eventId = _panePair = null;
        _creating = _editing = _addingMemory = false;
        _memoryId = null;
      });
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _create() => setState(() {
    _panePair = _controller.data!.pairId;
    _creating = true;
    _editing = false;
    _eventId = null;
  });
  void _open(TogetherEvent event) => setState(() {
    _panePair = _controller.data!.pairId;
    _eventId = event.id;
    _creating = _editing = false;
  });

  Future<void> _wishCalendar(SharedWish wish, {bool memory = false}) async {
    if (!_controller.paired ||
        wish.pairId != _controller.data?.pairId ||
        wish.eventStartsAt == null) {
      return;
    }
    final day = togetherTime(wish.eventStartsAt!);
    final delta =
        (day.year - _controller.month.year) * 12 +
        day.month -
        _controller.month.month;
    if (delta != 0) {
      await _controller.browseMonth(delta);
    } else {
      await _controller.refresh();
    }
    if (!mounted ||
        !_foreground ||
        !_controller.paired ||
        wish.pairId != _controller.data?.pairId) {
      return;
    }
    _controller.selectDay(day);
    setState(() {
      _tab = 0;
      _panePair = wish.pairId;
      _creating = _editing = false;
      _memoryId = null;
      _addingMemory = memory && _memories != null;
      _eventId = _addingMemory
          ? null
          : (_controller.event(wish.eventId ?? '')?.id);
    });
  }

  void _showReminders() {
    final reminders = widget.reminders;
    if (reminders == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: AnimatedBuilder(
            animation: reminders,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Болзооны сануулга',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  key: const Key('togetherRemindersEnabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Энэ утсанд сануулах'),
                  value: reminders.enabled,
                  onChanged:
                      reminders.supported &&
                          !reminders.busy &&
                          reminders.pairId != null &&
                          reminders.pairId == _controller.data?.pairId
                      ? reminders.setEnabled
                      : null,
                ),
                const Text(
                  'Ойрын 60 хоногт болох, хоёулаа зөвшөөрсөн 60 хүртэлх болзоог нэг цагийн өмнө сануулна. Нэг цаг хүрэхгүй хугацаа үлдсэн бол эхлэхэд нь сануулна. Түгжээтэй дэлгэцэд нэр, газар, тэмдэглэл харагдахгүй.',
                  style: TextStyle(height: 1.5),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Сонголт зөвхөн таны энэ хосын холболтод үйлчилнэ. Апп нээлттэй, интернеттэй үед өөрчлөлт шинэчлэгдэнэ. Апп хаалттай байхад хос тань болзоог өөрчилж эсвэл холболтыг салгавал өмнөх сануулга дараа нээх хүртэл үлдэж болно.',
                  style: TextStyle(height: 1.5, color: AppColors.muted),
                ),
                if (!reminders.supported)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Сануулга iPhone болон Android утсанд ажиллана.',
                    ),
                  ),
                if (reminders.message case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(message),
                  ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Хаах'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_inPane,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          _addingMemory
              ? 'Дурсамж нэмэх'
              : _memoryId != null
              ? 'Бидний дурсамж'
              : _creating
              ? 'Болзоо нэмэх'
              : _editing
              ? 'Болзоо засах'
              : _eventId != null
              ? 'Бидний болзоо'
              : 'Бид хоёр',
        ),
        leading: IconButton(
          onPressed: _back,
          tooltip: 'Буцах',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          if (widget.reminders != null && !_inPane)
            IconButton(
              key: const Key('togetherReminders'),
              onPressed: _showReminders,
              tooltip: 'Сануулга',
              icon: const Icon(Icons.notifications_outlined),
            ),
          if (!_inPane)
            IconButton(
              onPressed: _controller.loading || _controller.saving
                  ? null
                  : _controller.refresh,
              tooltip: 'Шинэчлэх',
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Visibility(
          visible: _foreground,
          // The gallery temporarily backgrounds the app. Retain only an unsaved
          // local editor; shared photos/details are removed while hidden.
          maintainState: _addingMemory || _tab == 2,
          child: Column(
            children: [
              if (_controller.failure case final failure?)
                _Feedback(text: failure.message, error: true),
              if (_controller.pendingCommand != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Хадгалсан эсэхийг баталгаажуулж чадсангүй. Өмнөх үйлдлээ дахин шалгаарай.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      OutlinedButton.icon(
                        key: const Key('togetherRetry'),
                        onPressed: _controller.saving || _controller.loading
                            ? null
                            : _controller.retry,
                        icon: const Icon(Icons.sync),
                        label: const Text('Өмнөх үйлдлийг дахин шалгах'),
                      ),
                    ],
                  ),
                ),
              if (_controller.loading || _controller.saving)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _body() {
    if (!_controller.current) {
      return const _Empty(
        icon: Icons.lock_outline,
        title: 'Дахин нэвтрээрэй',
        message: 'Таны өмнөх мэдээллийг хаалаа.',
      );
    }
    if (_controller.data == null) {
      return _Empty(
        icon: Icons.cloud_outlined,
        title: _controller.loading
            ? 'Мэдээллийг шалгаж байна'
            : 'Мэдээлэл хараахан ирээгүй',
        message: 'Холболтоо шалгаад дахин оролдоорой.',
        action: _controller.loading
            ? null
            : OutlinedButton(
                onPressed: _controller.refresh,
                child: const Text('Дахин шалгах'),
              ),
      );
    }
    if (!_controller.paired) {
      return _Empty(
        icon: Icons.favorite_border,
        title: 'Хосоороо холбогдоорой',
        message:
            'Хоёр тал зөвшөөрч холбогдсоны дараа хуанли болон өдөр тутмын асуултаа хамт ашиглана.',
        action: OutlinedButton(onPressed: _back, child: const Text('Буцах')),
      );
    }
    if (_addingMemory && _memories != null) {
      return MemoryEditor(
        key: _memoryEditorKey,
        day: togetherDay(_controller.selectedDay),
        picker: widget.memoryPhotoPicker,
        onCancel: _closePane,
        onSave: (draft) async {
          final saved = await _memories!.save(draft);
          if (saved && mounted) _closePane();
          if (!saved && _memories!.failure != null) throw _memories!.failure!;
          return saved;
        },
      );
    }
    if (_memoryId != null && _memories != null) {
      final matching = _memories!.items.where((m) => m.id == _memoryId);
      if (matching.isEmpty) {
        return _Empty(
          icon: Icons.photo_outlined,
          title: 'Дурсамж олдсонгүй',
          message: 'Хуанли руу буцаж шинэ мэдээллийг хараарай.',
          action: OutlinedButton(onPressed: _back, child: const Text('Буцах')),
        );
      }
      final memory = matching.first;
      return MemoryDetail(
        key: ValueKey('memory:$_panePair:${memory.id}'),
        memory: memory,
        loadPhoto: () => _memories!.photo(memory),
        canDelete: memory.creatorId == _memories!.repository.actorId,
        onDelete: () => _memories!.delete(memory),
        onClose: _back,
      );
    }
    if (_creating || _editing) {
      final event = _eventId == null ? null : _controller.event(_eventId!);
      if (_editing && event == null) return _missing();
      if (_editing && event!.creatorId != _controller.actorId) {
        return _missing();
      }
      return TogetherEventEditor(
        key: ValueKey(
          'editor:${_controller.data!.pairId}:${event?.id}:${event?.version}',
        ),
        controller: _controller,
        event: event,
        onSaved: () {
          if (mounted) {
            setState(() {
              _creating = _editing = false;
              _eventId = null;
            });
          }
        },
      );
    }
    if (_eventId != null) {
      final event = _controller.event(_eventId!);
      return event == null
          ? _missing()
          : _EventDetail(
              controller: _controller,
              event: event,
              onEdit: () => setState(() => _editing = true),
              onDeleted: _back,
            );
    }
    return Column(
      children: [
        if (!(_tab == 2 && _wishBoardKey.currentState?.hasPane == true))
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                direction: MediaQuery.textScalerOf(context).scale(14) > 19
                    ? Axis.vertical
                    : Axis.horizontal,
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: const Text('Хуанли'),
                    icon: _wishes == null
                        ? const Icon(Icons.calendar_month_outlined)
                        : null,
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(_wishes == null ? 'Өдрийн асуулт' : 'Асуулт'),
                    icon: _wishes == null
                        ? const Icon(Icons.chat_bubble_outline)
                        : null,
                  ),
                  if (_wishes != null)
                    const ButtonSegment(value: 2, label: Text('Хүслүүд')),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (values) =>
                    setState(() => _tab = values.single),
              ),
            ),
          ),
        Expanded(
          child: _tab == 0
              ? TogetherCalendar(
                  controller: _controller,
                  memories: _memories,
                  onCreate: _create,
                  onOpen: _open,
                  onAddMemory: _memories == null
                      ? null
                      : () => setState(() {
                          _panePair = _controller.data!.pairId;
                          _addingMemory = true;
                        }),
                  onOpenMemory: (memory) => setState(() {
                    _panePair = memory.pairId;
                    _memoryId = memory.id;
                  }),
                )
              : _tab == 2 && _wishes != null
              ? WishBoard(
                  key: _wishBoardKey,
                  controller: _wishes!,
                  onPaneChanged: () {
                    if (mounted) setState(() {});
                  },
                  onOpenCalendar: _wishCalendar,
                  onAddMemory: (wish) => _wishCalendar(wish, memory: true),
                )
              : _Daily(
                  key: ValueKey(
                    'daily:${_controller.data!.pairId}:${_controller.data!.daily?.questionId}',
                  ),
                  controller: _controller,
                ),
        ),
      ],
    );
  }

  Widget _missing() => _Empty(
    icon: Icons.event_busy_outlined,
    title: 'Болзоо өөрчлөгдсөн байна',
    message: 'Хуанли руу буцаж шинэ мэдээллийг хараарай.',
    action: OutlinedButton(
      onPressed: _back,
      child: const Text('Хуанли руу буцах'),
    ),
  );
}

class TogetherCalendar extends StatefulWidget {
  const TogetherCalendar({
    super.key,
    required this.controller,
    this.memories,
    required this.onCreate,
    required this.onOpen,
    this.onAddMemory,
    this.onOpenMemory,
  });
  final TogetherController controller;
  final MemoryController? memories;
  final VoidCallback onCreate;
  final VoidCallback? onAddMemory;
  final ValueChanged<TogetherEvent> onOpen;
  final ValueChanged<SharedMemory>? onOpenMemory;
  @override
  State<TogetherCalendar> createState() => _TogetherCalendarState();
}

class _TogetherCalendarState extends State<TogetherCalendar> {
  bool _showPhotos = true;
  Future<void> _today() async {
    final now = togetherTime(DateTime.now().toUtc());
    final delta =
        (now.year - widget.controller.month.year) * 12 +
        now.month -
        widget.controller.month.month;
    if (delta != 0) await widget.controller.browseMonth(delta);
    if (mounted) widget.controller.selectDay(now);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller, memories = widget.memories;
    final month = controller.month;
    final days = DateTime.utc(month.year, month.month + 1, 0).day;
    final offset = month.weekday - 1;
    final cells = ((days + offset) / 7).ceil() * 7;
    final today = togetherDay(togetherTime(DateTime.now().toUtc()));
    final selectedMemories =
        memories?.onDay(togetherDay(controller.selectedDay)) ??
        <SharedMemory>[];
    return ListView(
      key: const Key('togetherCalendar'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('togetherPreviousMonth'),
              onPressed: controller.loading || controller.saving
                  ? null
                  : () => controller.browseMonth(-1),
              tooltip: 'Өмнөх сар',
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${month.year} · ${month.month} сар',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              key: const Key('togetherNextMonth'),
              onPressed: controller.loading || controller.saving
                  ? null
                  : () => controller.browseMonth(1),
              tooltip: 'Дараах сар',
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('calendarToday'),
                  onPressed: controller.loading || controller.saving
                      ? null
                      : _today,
                  child: const Text('Өнөөдөр'),
                ),
              ),
            ),
            if (memories != null) ...[
              const Text('Зураг', style: TextStyle(color: AppColors.muted)),
              Switch.adaptive(
                key: const Key('calendarPhotoToggle'),
                value: _showPhotos,
                onChanged: (value) => setState(() => _showPhotos = value),
              ),
            ],
          ],
        ),
        Row(
          children: [
            for (final day in ['Да', 'Мя', 'Лх', 'Пү', 'Ба', 'Бя', 'Ня'])
              Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: _showPhotos && memories != null ? 85 : 49,
          ),
          itemBuilder: (context, index) {
            final number = index - offset + 1;
            if (number < 1 || number > days) return const SizedBox.shrink();
            final day = DateTime.utc(month.year, month.month, number),
                key = togetherDay(
                  DateTime.utc(month.year, month.month, number),
                );
            final selected = togetherDay(controller.selectedDay) == key;
            final marked = controller.data!.events.any(
              (event) => event.occursOn(day),
            );
            final photos = memories?.onDay(key) ?? <SharedMemory>[];
            final cover = photos.isEmpty ? null : photos.first;
            return Semantics(
              selected: selected,
              button: true,
              label:
                  '${month.month} сарын $number${marked ? ', болзоотой' : ''}${photos.isNotEmpty ? ', ${photos.length} дурсамжтай' : ''}',
              child: InkWell(
                key: Key('togetherDay$number'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => controller.selectDay(day),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.blush : null,
                    borderRadius: BorderRadius.circular(14),
                    border: selected ? Border.all(color: AppColors.pink) : null,
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$number',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected || key == today
                              ? FontWeight.w900
                              : FontWeight.w600,
                          color: selected || key == today
                              ? AppColors.pink
                              : AppColors.ink,
                        ),
                      ),
                      if (_showPhotos && memories != null)
                        Expanded(
                          child: cover == null
                              ? Center(
                                  child: Icon(
                                    marked ? Icons.favorite : Icons.circle,
                                    size: marked ? 15 : 3,
                                    color: marked
                                        ? AppColors.pink
                                        : AppColors.line,
                                  ),
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) => Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      MemorySticker(
                                        bytes: memories.thumbnails[cover.id],
                                        style: cover.sticker,
                                        size: constraints.maxWidth
                                            .clamp(0, 54)
                                            .toDouble(),
                                      ),
                                      if (photos.length > 1)
                                        Positioned(
                                          right: 1,
                                          bottom: 3,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.ink,
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              '+${photos.length - 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                        )
                      else ...[
                        const SizedBox(height: 3),
                        Icon(
                          marked ? Icons.favorite : Icons.circle,
                          size: marked ? 9 : 4,
                          color: marked || photos.isNotEmpty
                              ? AppColors.pink
                              : Colors.transparent,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Улаанбаатарын цагаар',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: Text(
                '${controller.selectedDay.month} сарын ${controller.selectedDay.day}',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (widget.onAddMemory != null)
              IconButton(
                key: const Key('calendarAddMemory'),
                tooltip: 'Зурагтай дурсамж нэмэх',
                onPressed: memories?.current == true
                    ? widget.onAddMemory
                    : null,
                icon: const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: AppColors.pink,
                ),
              ),
          ],
        ),
        if (memories?.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                Text(
                  memories!.error!,
                  style: const TextStyle(color: AppColors.muted),
                ),
                TextButton(
                  onPressed: memories.loading ? null : memories.refresh,
                  child: const Text('Зургийг дахин шалгах'),
                ),
              ],
            ),
          ),
        for (final memory in selectedMemories)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SoftCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                key: Key('calendarMemory${memory.id}'),
                leading: MemorySticker(
                  bytes: memories?.thumbnails[memory.id],
                  style: memory.sticker,
                  size: 54,
                ),
                title: Text(
                  memory.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: memory.note.isEmpty
                    ? null
                    : Text(
                        memory.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onOpenMemory?.call(memory),
              ),
            ),
          ),
        if (controller.selectedEvents.isEmpty && selectedMemories.isEmpty)
          const SoftCard(
            color: AppColors.blush,
            child: Text(
              'Энэ өдөр юу хийсэн бэ? Зургаа нэмээд нандин мөчөө хадгалаарай.',
              style: TextStyle(height: 1.6),
            ),
          ),
        for (final event in controller.selectedEvents)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SoftCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                key: Key('togetherEvent${event.id}'),
                onTap: () => widget.onOpen(event),
                leading: Text(
                  togetherClock(event.start),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.pink,
                  ),
                ),
                title: Text(
                  event.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${event.location.isEmpty ? '' : '${event.location} · '}${event.status.label}',
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ),
        const SizedBox(height: 18),
        if (widget.onAddMemory != null) ...[
          FilledButton.icon(
            key: const Key('calendarSaveDay'),
            onPressed: memories?.current == true ? widget.onAddMemory : null,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Энэ өдрийг хадгалъя'),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          key: const Key('togetherCreate'),
          onPressed: controller.canMutate ? widget.onCreate : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Болзоо нэмэх'),
        ),
      ],
    );
  }
}

class _EventDetail extends StatelessWidget {
  const _EventDetail({
    required this.controller,
    required this.event,
    required this.onEdit,
    required this.onDeleted,
  });
  final TogetherController controller;
  final TogetherEvent event;
  final VoidCallback onEdit, onDeleted;
  Future<void> _respond(String response) async {
    final command = controller.command('calendar/respond', {
      'id': event.id,
      'expected_version': event.version,
      'response': response,
    });
    if (command != null) await controller.send(command);
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Болзоог устгах уу?'),
        content: const Text('Хоёр хүний хуанлиас энэ болзоо хасагдана.'),
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
    if (confirmed != true || !context.mounted) return;
    final command = controller.command('calendar/delete', {
      'id': event.id,
      'expected_version': event.version,
    });
    if (command != null && await controller.send(command)) onDeleted();
  }

  @override
  Widget build(BuildContext context) {
    final own = event.creatorId == controller.actorId;
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        SoftCard(
          color: AppColors.blush,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.favorite_border_rounded,
                color: AppColors.pink,
                size: 34,
              ),
              const SizedBox(height: 16),
              Text(
                event.title,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                event.status.label,
                style: const TextStyle(
                  color: AppColors.pink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _DetailLine(
          Icons.calendar_month_outlined,
          '${togetherDay(event.start)} · ${togetherClock(event.start)}',
        ),
        if (event.end case final end?)
          _DetailLine(
            Icons.schedule,
            'Дуусах: ${togetherDay(end)} · ${togetherClock(end)}',
          ),
        const Padding(
          padding: EdgeInsets.only(left: 36, bottom: 12),
          child: Text(
            'Улаанбаатарын цагаар',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
        if (event.location.isNotEmpty)
          _DetailLine(Icons.place_outlined, event.location),
        if (event.note.isNotEmpty) _DetailLine(Icons.notes_rounded, event.note),
        const SizedBox(height: 14),
        Text(
          own
              ? 'Таны төлөвлөсөн болзоо'
              : '${controller.data?.partnerName?.isNotEmpty == true ? controller.data!.partnerName : 'Хос тань'} төлөвлөсөн болзоо',
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 24),
        if (own) ...[
          FilledButton.icon(
            key: const Key('togetherEdit'),
            onPressed: controller.canMutate ? onEdit : null,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Болзоог засах'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('togetherDelete'),
            onPressed: controller.canMutate ? () => _delete(context) : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Болзоог устгах'),
          ),
        ] else ...[
          FilledButton.icon(
            key: const Key('togetherAccept'),
            onPressed:
                controller.canMutate &&
                    event.status != TogetherEventStatus.accepted
                ? () => _respond('accepted')
                : null,
            icon: const Icon(Icons.favorite_border),
            label: const Text('Тэгье, хамт явъя'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('togetherDecline'),
            onPressed:
                controller.canMutate &&
                    event.status != TogetherEventStatus.declined
                ? () => _respond('declined')
                : null,
            child: const Text('Энэ удаа боломжгүй'),
          ),
        ],
      ],
    );
  }
}

class _Daily extends StatefulWidget {
  const _Daily({super.key, required this.controller});
  final TogetherController controller;
  @override
  State<_Daily> createState() => _DailyState();
}

class _DailyState extends State<_Daily> {
  final _answer = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _submit(TogetherDaily daily) async {
    if (!_form.currentState!.validate()) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Хариултаа илгээх үү?'),
        content: const Text(
          'Илгээсний дараа хариултыг өөрчлөх боломжгүй. Хоёулаа хариулахад хариултууд нээгдэнэ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Болих'),
          ),
          TextButton(
            key: const Key('togetherConfirmAnswer'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Илгээх'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final command = widget.controller.command('daily/answer', {
      'question_id': daily.questionId,
      'answer': _answer.text.trim(),
    });
    if (command != null && await widget.controller.send(command) && mounted) {
      _answer.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final daily = controller.data!.daily;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const Key('togetherDaily'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
        children: [
          if (daily == null)
            const SoftCard(
              color: AppColors.blush,
              child: Text(
                'Өнөөдрийн асуулт хараахан бэлэн болоогүй байна. Түр хүлээгээд дахин шалгаарай.',
              ),
            )
          else ...[
            SoftCard(
              color: AppColors.blush,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    daily.day,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: AppColors.pink,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    daily.question,
                    key: const Key('togetherQuestion'),
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Өдөр бүр нэг асуулт. Хоёулаа хариулсны дараа нээгдэнэ.',
                    style: TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (daily.myAnswer == null)
              Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      key: const Key('togetherAnswer'),
                      controller: _answer,
                      enabled: controller.canMutate,
                      minLines: 4,
                      maxLines: 8,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'Миний хариулт',
                        alignLabelWithHint: true,
                        hintText: 'Сэтгэлд орсон үгээ бичээрэй…',
                      ),
                      validator: (text) => text == null || text.trim().isEmpty
                          ? 'Хариултаа бичээрэй.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('togetherSubmitAnswer'),
                        onPressed: controller.canMutate
                            ? () => _submit(daily)
                            : null,
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Хариултаа илгээх'),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              _AnswerCard(label: 'Миний хариулт', answer: daily.myAnswer!),
              const SizedBox(height: 12),
              if (daily.bothAnswered)
                _AnswerCard(
                  label: controller.data?.partnerName?.isNotEmpty == true
                      ? controller.data!.partnerName!
                      : 'Хосын хариулт',
                  answer: daily.partnerAnswer!,
                )
              else
                const SoftCard(
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, color: AppColors.pink),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Хосын хариултыг хүлээж байна. Хоёулаа хариулмагц энд нээгдэнэ.',
                          style: TextStyle(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
          const SizedBox(height: 28),
          OutlinedButton.icon(
            key: const Key('togetherHistory'),
            onPressed: controller.loadingHistory
                ? null
                : () => controller.loadHistory(),
            icon: const Icon(Icons.history_rounded),
            label: const Text('Өмнөх хариултууд'),
          ),
          if (controller.loadingHistory)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (controller.historyLoaded && controller.history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Өмнөх хариулт одоогоор алга.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          for (final entry in controller.history)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.day,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.question,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Би: ${entry.myAnswer ?? 'Хариулаагүй'}',
                      style: const TextStyle(height: 1.5),
                    ),
                    if (entry.bothAnswered) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Хос: ${entry.partnerAnswer}',
                        style: const TextStyle(height: 1.5),
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Хоёулаа хариулаагүй тул хосын хариулт нээгдэхгүй.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (controller.nextBeforeDay != null)
            TextButton(
              onPressed: controller.loadingHistory
                  ? null
                  : () => controller.loadHistory(more: true),
              child: const Text('Өмнөх өдрүүд'),
            ),
        ],
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.label, required this.answer});
  final String label, answer;
  @override
  Widget build(BuildContext context) => SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.pink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(answer, style: const TextStyle(fontSize: 17, height: 1.6)),
      ],
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: AppColors.pink),
        const SizedBox(width: 14),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 16, height: 1.5)),
        ),
      ],
    ),
  );
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.text, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        height: 1.4,
        color: error ? Theme.of(context).colorScheme.error : AppColors.muted,
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: AppColors.pink),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.6),
          ),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    ),
  );
}
