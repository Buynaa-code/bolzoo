import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/app_controller.dart';
import '../../notifications/reminders.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../memories/memories_screen.dart';

Future<DateEvent?> openEventEditor(
  BuildContext context,
  AppController controller, {
  DateEvent? event,
  DateTime? initialDate,
}) => Navigator.of(context).push<DateEvent>(
  MaterialPageRoute(
    builder: (_) => _EventEditor(
      controller: controller,
      event: event,
      initialDate: initialDate,
    ),
  ),
);

Future<void> openEventDetail(
  BuildContext context,
  AppController controller,
  String eventId,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => _EventDetail(controller: controller, eventId: eventId),
  ),
);

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _selected;
  late DateTime _month;
  int _filter = 0;
  bool _matches(DateEvent event) => switch (_filter) {
    0 => !widget.controller.isPartnerItem(event.id),
    1 => widget.controller.isPartnerItem(event.id),
    _ => event.shared,
  };

  @override
  void initState() {
    super.initState();
    _selected = localCalendarDay(DateTime.now());
    _month = DateTime(_selected.year, _selected.month);
  }

  void _moveMonth(int offset) {
    setState(() {
      _month = DateTime(_month.year, _month.month + offset);
      final lastDay = DateTime(_month.year, _month.month + 1, 0).day;
      _selected = DateTime(
        _month.year,
        _month.month,
        _selected.day > lastDay ? lastDay : _selected.day,
      );
    });
  }

  Future<void> _addEvent() async {
    final saved = await openEventEditor(
      context,
      widget.controller,
      initialDate: _selected,
    );
    if (!mounted || saved == null) return;
    setState(() {
      _selected = localCalendarDay(saved.startsAt);
      _month = DateTime(_selected.year, _selected.month);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final events =
          widget.controller.data.events
              .where(
                (event) =>
                    _matches(event) && sameDay(event.startsAt, _selected),
              )
              .toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      return ListView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        children: [
          PageHeading(
            'Бидний хуанли',
            subtitle: 'Сайхан өдрүүдээ төлөвлөе.',
            action: IconButton.filledTonal(
              key: const Key('calendarAddEvent'),
              onPressed: _addEvent,
              tooltip: 'Төлөвлөгөө нэмэх',
              icon: const Icon(Icons.add_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in [(0, 'Миний'), (1, 'Хосын'), (2, 'Бидний')])
                  ChoiceChip(
                    key: Key('calendarFilter${entry.$1}'),
                    label: Text(entry.$2),
                    selected: _filter == entry.$1,
                    onSelected: (_) => setState(() => _filter = entry.$1),
                  ),
              ],
            ),
          ),
          if (widget.controller.cloudError != null)
            TextButton.icon(
              onPressed: widget.controller.refreshCloud,
              icon: const Icon(Icons.refresh),
              label: const Text('Дахин шинэчлэх'),
            ),
          SoftCard(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _month.year == 1900 && _month.month == 1
                          ? null
                          : () => _moveMonth(-1),
                      tooltip: 'Өмнөх сар',
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '${_month.year} · ${_month.month} сар',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _month.year == 2100 && _month.month == 12
                          ? null
                          : () => _moveMonth(1),
                      tooltip: 'Дараагийн сар',
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: ['Да', 'Мя', 'Лх', 'Пү', 'Ба', 'Бя', 'Ня']
                      .map(
                        (day) => Expanded(
                          child: Text(
                            day,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                ..._buildWeeks(),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _selected = localCalendarDay(DateTime.now());
                    _month = DateTime(_selected.year, _selected.month);
                  }),
                  icon: const Icon(Icons.today_rounded, size: 17),
                  label: const Text('Өнөөдөр'),
                ),
              ],
            ),
          ),
          SectionLabel(
            shortDate(_selected),
            action: Text(
              '${events.length} төлөвлөгөө',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          if (events.isEmpty)
            SoftCard(
              color: AppColors.blush,
              child: Column(
                children: [
                  const Icon(
                    Icons.event_available_outlined,
                    color: AppColors.pink,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Энэ өдөр чөлөөтэй байна',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Кофе уух уу, эсвэл хамт алхах уу?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _addEvent,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Төлөвлөгөө нэмэх'),
                  ),
                ],
              ),
            ),
          for (final event in events) ...[
            _EventCard(
              event: event,
              onTap: () =>
                  openEventDetail(context, widget.controller, event.id),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: AppColors.muted,
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.controller.cloudAvailable
                      ? 'Хуваалцсан болзоо хосын тань утсанд харагдана'
                      : 'Зөвхөн танд харагдана',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );

  List<Widget> _buildWeeks() {
    final offset = _month.weekday - DateTime.monday;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final weekCount = ((offset + days) / 7).ceil();
    final today = DateTime.now();
    final numberStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontWeight: FontWeight.w800,
      fontSize: 15,
      height: 1.2,
    );
    final numberMetrics = TextPainter(
      text: TextSpan(text: '28', style: numberStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final numberHeight = numberMetrics.height;
    numberMetrics.dispose();
    final cellHeight = math.max(46.0, numberHeight + 14);
    return List.generate(weekCount, (week) {
      return Row(
        children: List.generate(7, (column) {
          final day = week * 7 + column - offset + 1;
          if (day < 1 || day > days) {
            return Expanded(child: SizedBox(height: cellHeight + 4));
          }
          final date = DateTime(_month.year, _month.month, day);
          final selected = sameDay(date, _selected);
          final currentDay = sameDay(date, today);
          final count = widget.controller.data.events
              .where(
                (event) => _matches(event) && sameDay(event.startsAt, date),
              )
              .length;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: '${date.year} оны ${shortDate(date)}, $count төлөвлөгөө',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Material(
                  color: selected ? AppColors.pink : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: currentDay && !selected
                        ? const BorderSide(color: AppColors.pink)
                        : BorderSide.none,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => setState(() => _selected = date),
                    child: SizedBox(
                      height: cellHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: numberHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '$day',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: numberStyle.copyWith(
                                    color: selected
                                        ? Colors.white
                                        : AppColors.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            height: 4,
                            width: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: count == 0
                                  ? Colors.transparent
                                  : selected
                                  ? Colors.white
                                  : AppColors.pink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      );
    });
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});

  final DateEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 58,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.blush,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                clockText(event.startsAt),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.pink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (event.place.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({required this.controller, this.event, this.initialDate});

  final AppController controller;
  final DateEvent? event;
  final DateTime? initialDate;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _place;
  late final TextEditingController _note;
  late final DateTime _originalDate;
  late final String _id;
  late DateTime _date;
  bool _saving = false;
  bool _allowPop = false;
  bool _shared = false;
  int _reminder = 0;

  @override
  void initState() {
    super.initState();
    final day = widget.initialDate ?? DateTime.now();
    _originalDate =
        widget.event?.startsAt ?? DateTime(day.year, day.month, day.day, 18);
    _date = _originalDate;
    _shared = widget.event?.shared ?? false;
    _reminder = widget.event?.reminderMinutes ?? 0;
    _id = widget.event?.id ?? newLocalId();
    _title = TextEditingController(text: widget.event?.title ?? '');
    _place = TextEditingController(text: widget.event?.place ?? '');
    _note = TextEditingController(text: widget.event?.note ?? '');
    for (final controller in [_title, _place, _note]) {
      controller.addListener(_changed);
    }
  }

  bool get _dirty =>
      _title.text != (widget.event?.title ?? '') ||
      _place.text != (widget.event?.place ?? '') ||
      _note.text != (widget.event?.note ?? '') ||
      _date != _originalDate ||
      _shared != (widget.event?.shared ?? false) ||
      _reminder != (widget.event?.reminderMinutes ?? 0);

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final controller in [_title, _place, _note]) {
      controller.removeListener(_changed);
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _close() async {
    if (_saving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Өөрчлөлтийг орхих уу?'),
          content: const Text('Хадгалаагүй мэдээлэл тань алга болно.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Үргэлжлүүлэх'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Орхих'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Өдрөө сонгох',
      cancelText: 'Буцах',
      confirmText: 'Сонгох',
    );
    if (selected == null || !mounted) return;
    setState(
      () => _date = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _date.hour,
        _date.minute,
      ),
    );
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: 'Цагаа сонгох',
      cancelText: 'Буцах',
      confirmText: 'Сонгох',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    setState(
      () => _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        selected.hour,
        selected.minute,
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final event = DateEvent(
      id: _id,
      title: _title.text.trim(),
      startsAt: _date,
      createdAt: widget.event?.createdAt ?? DateTime.now(),
      place: _place.text.trim(),
      note: _note.text.trim(),
      shared: _shared,
      reminderMinutes: _reminder,
      templateId: widget.event?.templateId ?? 'coffee',
    );
    try {
      if (_reminder > 0 &&
          !event.startsAt
              .subtract(Duration(minutes: _reminder))
              .isAfter(DateTime.now())) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Сануулгын цаг өнгөрсөн байна. Өдөр, цагаа өөрчилнө үү.',
            ),
          ),
        );
        return;
      }
      if (_reminder > 0 && !await Reminders.instance.requestPermission()) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Тохиргооноос мэдэгдлийн эрх нээнэ үү, эсвэл сануулгагүй хадгалаарай.',
            ),
          ),
        );
        return;
      }
      await widget.controller.saveEvent(event);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _allowPop = true;
      });
      if (widget.controller.reminderError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.reminderError!)),
        );
      }
      Navigator.of(context).pop(event);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSaveError(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || (!_dirty && !_saving),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.event == null ? 'Шинэ төлөвлөгөө' : 'Төлөвлөгөө засах',
        ),
        leading: IconButton(
          onPressed: _saving ? null : _close,
          tooltip: 'Буцах',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
          children: [
            const Text(
              'Дараагийн сайхан өдөр',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Жижигхэн төлөвлөгөөнөөс гоё дурсамж эхэлдэг.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 26),
            TextFormField(
              key: const Key('eventTitle'),
              controller: _title,
              enabled: !_saving,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Төлөвлөгөөний нэр',
                hintText: 'Хамт кофе уух',
                counterText: '',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Төлөвлөгөөний нэрээ бичээрэй.'
                  : null,
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              key: const Key('eventShared'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Хоёуланд харагдана'),
              subtitle: Text(
                widget.controller.cloudAvailable
                    ? 'Хос тань энэ болзоог хараад зөвшөөрөх боломжтой.'
                    : 'Нэвтэрч хосоороо холбогдсон үед хуваалцана.',
              ),
              value: _shared,
              onChanged: _saving || !widget.controller.cloudAvailable
                  ? null
                  : (v) => setState(() => _shared = v),
            ),
            const SizedBox(height: 18),
            _EditorChoice(
              label: 'Өдөр',
              value: '${_date.year} · ${shortDate(_date)}',
              icon: Icons.calendar_today_outlined,
              onTap: _saving ? null : _pickDate,
            ),
            const SizedBox(height: 12),
            _EditorChoice(
              label: 'Цаг',
              value: clockText(_date),
              icon: Icons.schedule_rounded,
              onTap: _saving ? null : _pickTime,
            ),
            const SizedBox(height: 18),
            TextFormField(
              key: const Key('eventPlace'),
              controller: _place,
              enabled: !_saving,
              maxLength: 240,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Газар · заавал биш',
                hintText: 'Дуртай кафе',
                counterText: '',
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              key: const Key('eventNote'),
              controller: _note,
              enabled: !_saving,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Тэмдэглэл · заавал биш',
                alignLabelWithHint: true,
                hintText: 'Мартахыг хүсэхгүй жижиг зүйлс…',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: const Key('eventReminder'),
              initialValue: _reminder,
              decoration: const InputDecoration(
                labelText: 'Сануулга',
                prefixIcon: Icon(Icons.notifications_none),
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Сануулгагүй')),
                DropdownMenuItem(value: 15, child: Text('15 минутын өмнө')),
                DropdownMenuItem(value: 60, child: Text('1 цагийн өмнө')),
                DropdownMenuItem(value: 1440, child: Text('1 өдрийн өмнө')),
              ],
              onChanged: _saving ? null : (v) => setState(() => _reminder = v!),
            ),
            const SizedBox(height: 12),

            Text(
              _shared
                  ? 'Хосынхоо зөвшөөрлийг хүлээнэ.'
                  : widget.controller.cloudAvailable
                  ? 'Зөвхөн таны бүртгэлд хадгална.'
                  : 'Энэ төхөөрөмжид хадгална.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(22, 12, 22, 16),
        child: FilledButton.icon(
          key: const Key('saveEventButton'),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_saving ? 'Хадгалж байна…' : 'Хадгалах'),
        ),
      ),
    ),
  );
}

class _EditorChoice extends StatelessWidget {
  const _EditorChoice({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.all(18),
    ),
    child: Row(
      children: [
        Icon(icon, size: 21, color: AppColors.pink),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: AppColors.muted)),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.right)),
      ],
    ),
  );
}

class _EventDetail extends StatefulWidget {
  const _EventDetail({required this.controller, required this.eventId});
  final AppController controller;
  final String eventId;

  @override
  State<_EventDetail> createState() => _EventDetailState();
}

class _EventDetailState extends State<_EventDetail> {
  bool _deleting = false;
  Future<void> _respond(bool accept) async {
    if (_deleting) return;
    DateTime? proposed;
    if (!accept) {
      final day = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime(2100),
      );
      if (day == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 18, minute: 0),
      );
      if (time == null || !mounted) return;
      proposed = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      if (!proposed.isAfter(DateTime.now())) return;
    }
    setState(() => _deleting = true);
    try {
      await widget.controller.respondToEvent(
        widget.eventId,
        accept: accept,
        proposedAt: proposed,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _delete(DateEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Төлөвлөгөөг устгах уу?'),
        content: const Text(
          'Энэ төлөвлөгөө хуанлиас арилна. Холбосон дурсамжууд тань үлдэнэ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Буцах'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Устгах'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.controller.deleteEvent(event.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showSaveError(context);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      DateEvent? current;
      for (final event in widget.controller.data.events) {
        if (event.id == widget.eventId) {
          current = event;
          break;
        }
      }
      final event = current;
      if (event == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Төлөвлөгөө')),
          body: const Center(child: Text('Энэ төлөвлөгөө байхгүй байна.')),
        );
      }
      final consent = widget.controller.consentState(event.id);
      final proposedAt = widget.controller.proposedEventTime(event.id);
      final partner = widget.controller.isPartnerItem(event.id);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Төлөвлөгөө'),
          actions: [
            if (widget.controller.canEdit(event.id) &&
                !widget.controller.isInvitationEvent(event.id))
              IconButton(
                onPressed: _deleting
                    ? null
                    : () => openEventEditor(
                        context,
                        widget.controller,
                        event: event,
                      ),
                tooltip: 'Төлөвлөгөө засах',
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                event.templateId == 'walk'
                    ? 'assets/gifts/walk.jpg'
                    : 'assets/gifts/coffee.jpg',
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 220,
                  child: ColoredBox(
                    color: AppColors.blush,
                    child: Center(
                      child: Icon(
                        Icons.favorite_border_rounded,
                        size: 56,
                        color: AppColors.pink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Болзооны загвар зураг',
              style: TextStyle(fontSize: 10, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            SoftCard(
              color: AppColors.blush,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.favorite_border_rounded,
                    color: AppColors.pink,
                    size: 32,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${event.startsAt.year} · ${shortDate(event.startsAt)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    clockText(event.startsAt),
                    style: const TextStyle(
                      color: AppColors.pink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            if (event.place.isNotEmpty) ...[
              const SectionLabel('Уулзах газар'),
              SoftCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: AppColors.pink,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        event.place,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (event.note.isNotEmpty) ...[
              const SectionLabel('Тэмдэглэл'),
              SoftCard(
                child: Text(
                  event.note,
                  style: const TextStyle(fontSize: 16, height: 1.55),
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _deleting
                  ? null
                  : () => openMemoryEditor(
                      context,
                      widget.controller,
                      eventId: event.id,
                    ),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Дурсамж нэмэх'),
            ),
            const SizedBox(height: 16),
            Text(
              event.shared
                  ? switch (consent) {
                      'accepted' => 'Хоёулаа тохирсон ♡',
                      'proposed' => 'Өөр цаг санал болгосон',
                      _ => 'Хосын зөвшөөрлийг хүлээж байна',
                    }
                  : 'Зөвхөн танд харагдана',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            if (event.shared && consent == 'proposed') ...[
              const SizedBox(height: 12),
              SoftCard(
                key: const Key('eventProposalCard'),
                color: AppColors.blush,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Санал болгосон цаг',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      proposedAt == null
                          ? 'Санал болгосон цагийг ачаалж чадсангүй. Дахин шинэчилнэ үү.'
                          : '${proposedAt.year} · ${shortDate(proposedAt)} · ${clockText(proposedAt)}',
                      key: const Key('eventProposedTime'),
                      style: const TextStyle(
                        color: AppColors.pink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (event.shared &&
                ((partner && consent == 'pending') ||
                    (!partner && consent == 'proposed' && proposedAt != null)))
              FilledButton(
                key: const Key('eventAcceptButton'),
                onPressed: _deleting ? null : () => _respond(true),
                child: Text(
                  consent == 'proposed'
                      ? 'Санал болгосон цагийг зөвшөөрөх ♡'
                      : 'Зөвшөөрөх ♡',
                ),
              ),
            if (event.shared && partner)
              TextButton(
                onPressed: _deleting ? null : () => _respond(false),
                child: const Text('Өөр цаг санал болгох'),
              ),
            const SizedBox(height: 24),
            if (widget.controller.canEdit(event.id) &&
                !widget.controller.isInvitationEvent(event.id))
              TextButton.icon(
                onPressed: _deleting ? null : () => _delete(event),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                label: Text(_deleting ? 'Устгаж байна…' : 'Төлөвлөгөө устгах'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.muted,
                  minimumSize: const Size(48, 48),
                ),
              ),
          ],
        ),
      );
    },
  );
}
