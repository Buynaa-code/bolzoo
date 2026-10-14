import 'package:flutter/material.dart';
import '../ui/theme.dart';
import '../music/music_repository.dart';
import '../music/music_track.dart';
import '../music/music_widgets.dart';
import 'together_controller.dart';
import 'together_models.dart';

class TogetherEventEditor extends StatefulWidget {
  const TogetherEventEditor({
    super.key,
    required this.controller,
    this.event,
    required this.onSaved,
    this.musicRepository,
  });
  final TogetherController controller;
  final TogetherEvent? event;
  final VoidCallback onSaved;
  final MusicRepository? musicRepository;
  @override
  State<TogetherEventEditor> createState() => _TogetherEventEditorState();
}

class _TogetherEventEditorState extends State<TogetherEventEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _note = TextEditingController(text: widget.event?.note ?? '');
  late final _location = TextEditingController(
    text: widget.event?.location ?? '',
  );
  late DateTime _start =
      widget.event?.start ??
      DateTime.utc(
        widget.controller.selectedDay.year,
        widget.controller.selectedDay.month,
        widget.controller.selectedDay.day,
        18,
      );
  late DateTime _end =
      widget.event?.end ?? _start.add(const Duration(hours: 1));
  late bool _hasEnd = widget.event?.end != null;
  late MusicTrack? _music = widget.event?.music;
  bool _pickingMusic = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickMusic() async {
    final repository = widget.musicRepository;
    if (repository == null || _pickingMusic || !widget.controller.canMutate) {
      return;
    }
    final pair = widget.controller.data?.pairId;
    setState(() => _pickingMusic = true);
    final selected = await Navigator.of(context).push<MusicTrack>(
      MaterialPageRoute(builder: (_) => MusicPicker(repository: repository)),
    );
    if (!mounted) return;
    setState(() {
      _pickingMusic = false;
      if (selected != null &&
          widget.controller.current &&
          widget.controller.data?.pairId == pair &&
          widget.controller.canMutate) {
        _music = selected;
      }
    });
  }

  Future<void> _pickDate(bool end) async {
    final old = end ? _end : _start;
    final value = await showDatePicker(
      context: context,
      initialDate: DateTime(old.year, old.month, old.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: end ? 'Дуусах өдөр' : 'Болзооны өдөр',
      cancelText: 'Болих',
      confirmText: 'Сонгох',
    );
    if (value == null || !mounted) return;
    setState(() {
      final next = DateTime.utc(
        value.year,
        value.month,
        value.day,
        old.hour,
        old.minute,
      );
      if (end) {
        _end = next;
      } else {
        _start = next;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickTime(bool end) async {
    final old = end ? _end : _start;
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: old.hour, minute: old.minute),
      helpText: 'Улаанбаатарын цагаар',
      cancelText: 'Болих',
      confirmText: 'Сонгох',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      final next = DateTime.utc(
        old.year,
        old.month,
        old.day,
        value.hour,
        value.minute,
      );
      if (end) {
        _end = next;
      } else {
        _start = next;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_hasEnd && !_end.isAfter(_start)) {
      setState(() => _error = 'Дуусах цаг эхлэх цагаас хойш байх ёстой.');
      return;
    }
    setState(() => _error = null);
    final event = widget.event;
    final command = widget.controller.command(
      event == null ? 'calendar/create' : 'calendar/update',
      {
        if (event != null) ...{
          'id': event.id,
          'expected_version': event.version,
        },
        'title': _title.text.trim(),
        'note': _note.text.trim(),
        'location': _location.text.trim(),
        'starts_at': togetherUtc(
          _start,
          _start.hour,
          _start.minute,
        ).toIso8601String(),
        'ends_at': _hasEnd
            ? togetherUtc(_end, _end.hour, _end.minute).toIso8601String()
            : null,
        'music': _music?.toJson(),
      },
    );
    if (command != null && await widget.controller.send(command) && mounted) {
      widget.onSaved();
    }
  }

  Widget _when(String label, DateTime value, bool end) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: Key(end ? 'togetherEndDate' : 'togetherStartDate'),
              onPressed: widget.controller.canMutate
                  ? () => _pickDate(end)
                  : null,
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(togetherDay(value)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              key: Key(end ? 'togetherEndTime' : 'togetherStartTime'),
              onPressed: widget.controller.canMutate
                  ? () => _pickTime(end)
                  : null,
              icon: const Icon(Icons.schedule, size: 18),
              label: Text(togetherClock(value)),
            ),
          ),
        ],
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        TextFormField(
          key: const Key('togetherTitle'),
          controller: _title,
          enabled: widget.controller.canMutate,
          maxLength: 120,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Болзооны нэр',
            hintText: 'Жишээ нь: Кофе уух уу?',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Болзооны нэр оруулна уу.'
              : null,
        ),
        const SizedBox(height: 12),
        _when('Өдөр, цаг', _start, false),
        const SizedBox(height: 8),
        const Text(
          'Хоёр утсанд Улаанбаатарын цагаар харагдана.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Дуусах цаг оруулах'),
          value: _hasEnd,
          onChanged: widget.controller.canMutate
              ? (value) => setState(() => _hasEnd = value)
              : null,
        ),
        if (_hasEnd) ...[
          _when('Дуусах өдөр, цаг', _end, true),
          const SizedBox(height: 18),
        ],
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('togetherLocation'),
          controller: _location,
          enabled: widget.controller.canMutate,
          maxLength: 200,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Байршил',
            hintText: 'Хаана уулзах вэ?',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('togetherNote'),
          controller: _note,
          enabled: widget.controller.canMutate,
          minLines: 3,
          maxLines: 8,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: 'Тайлбар',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Урилгын дуу',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Та хоёрт утгатай нэг дуу нэмээрэй. Хос тань урилгаас дарж сонсоно.',
          style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5),
        ),
        if (_music case final music?)
          MusicTrackCard(
            track: music,
            onRemove: widget.controller.canMutate
                ? () => setState(() => _music = null)
                : null,
          ),
        if (widget.musicRepository != null)
          OutlinedButton.icon(
            key: const Key('pickInvitationMusic'),
            onPressed: widget.controller.canMutate && !_pickingMusic
                ? _pickMusic
                : null,
            icon: const Icon(Icons.music_note_outlined),
            label: Text(_music == null ? 'Дуу хайж нэмэх' : 'Дуу солих'),
          ),
        const SizedBox(height: 16),
        const Text(
          'Хоёуланд харагдана. Хос тань зөвшөөрөх эсвэл татгалзах боломжтой. Өөрчилбөл дахин зөвшөөрөл хүлээнэ.',
          style: TextStyle(color: AppColors.muted, height: 1.5),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('togetherSaveEvent'),
          onPressed: widget.controller.canMutate ? _save : null,
          child: const Text('Хадгалах'),
        ),
      ],
    ),
  );
}
