import 'package:flutter/material.dart';

import '../../data/app_controller.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.controller});

  final AppController controller;

  void _edit(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileEditor(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final data = controller.data;
      final profile = data.profile;
      final since = profile.togetherSince;
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          const PageHeading(
            'Бидний орон зай',
            subtitle: 'Өөртөө хадгалах нандин бүхэн.',
          ),
          SoftCard(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.blush,
                    shape: BoxShape.circle,
                  ),
                  child: const HamtdaaMark(size: 45),
                ),
                const SizedBox(height: 15),
                Text(
                  profile.name.isEmpty ? 'Таны орон зай' : profile.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 25,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Өдөр бүр багахан хайр',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  key: const Key('profileEditButton'),
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Мэдээллээ засах'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            color: AppColors.blush,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.favorite_border_rounded,
                      color: AppColors.pink,
                      size: 20,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Бидний эхэлсэн өдөр',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (since == null) ...[
                  const Text(
                    'Дурсах өдөртэй болоорой',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Хамтдаа эхэлсэн өдрөө нэмээд\nөнгөрүүлсэн хоногоо тоолоорой.',
                    style: TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => _edit(context),
                    icon: const Icon(Icons.add_rounded, size: 19),
                    label: const Text('Өдөр нэмэх'),
                  ),
                ] else ...[
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${_daysTogether(since)}',
                          style: const TextStyle(
                            color: AppColors.pink,
                            fontSize: 50,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const TextSpan(
                          text: '  хоног',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${since.year} оны ${shortDate(since)} · эхэлсэн өдөр',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SectionLabel('Миний цуглуулга'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CollectionCount(
                  count: data.events.length,
                  label: 'Төлөвлөгөө',
                  icon: Icons.calendar_month_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CollectionCount(
                  count: data.memories.length,
                  label: 'Дурсамж',
                  icon: Icons.photo_library_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SoftCard(
            color: Color(0xFFFAF7F9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 19,
                      color: AppColors.muted,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Зөвхөн танд харагдана',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'Зураг, тэмдэглэл энэ төхөөрөмжид хадгалагдана. '
                  'Аппыг устгавал мэдээлэл устана.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Center(
            child: Text(
              'Хамтдаа · 0.1.0',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      );
    },
  );
}

class _CollectionCount extends StatelessWidget {
  const _CollectionCount({
    required this.count,
    required this.label,
    required this.icon,
  });

  final int count;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 23, color: AppColors.pink),
        const SizedBox(height: 16),
        Text(
          '$count',
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      ],
    ),
  );
}

// UTC calendar components avoid daylight-saving and timezone-offset differences.
// The first calendar day is counted as day one.
int _daysTogether(DateTime since) {
  final today = DateTime.now();
  return DateTime.utc(today.year, today.month, today.day)
          .difference(DateTime.utc(since.year, since.month, since.day))
          .inDays +
      1;
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.controller});

  final AppController controller;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  final _formKey = GlobalKey<FormState>();
  late final UserProfile _initial;
  late final TextEditingController _name;
  DateTime? _since;
  bool _saving = false;
  bool _choosingDate = false;
  bool _allowPop = false;
  bool _askingToClose = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initial = widget.controller.data.profile;
    _name = TextEditingController(text: _initial.name)..addListener(_changed);
    _since = _initial.togetherSince;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _dirty =>
      _name.text != _initial.name ||
      !DateUtils.isSameDay(_since, _initial.togetherSince);

  bool get _busy => _saving || _choosingDate;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _requestClose() async {
    if (_busy || _askingToClose || _allowPop) return;
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

  Future<void> _chooseDate() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _choosingDate = true);
    final today = localCalendarDay(DateTime.now());
    final firstDate = DateTime(1900);
    var initialDate = _since ?? today;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(today)) initialDate = today;
    try {
      final selected = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: today,
        helpText: 'Бидний эхэлсэн өдөр',
        cancelText: 'Болих',
        confirmText: 'Сонгох',
        fieldLabelText: 'Огноо',
        fieldHintText: 'Сар/өдөр/он',
        errorFormatText: 'Огноогоо зөв бичээрэй.',
        errorInvalidText: 'Өнөөдрөөс өмнөх өдөр сонгоорой.',
      );
      if (selected != null && mounted) {
        setState(() {
          _since = localCalendarDay(selected);
          _error = null;
        });
      }
    } finally {
      if (mounted) setState(() => _choosingDate = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.updateProfile(
        UserProfile(name: _name.text.trim(), togetherSince: _since),
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
          const SnackBar(content: Text('Мэдээлэл хадгалагдлаа')),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Өөрчлөлт хадгалагдсангүй. Дахин оролдоорой.';
      });
      showSaveError(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final since = _since;
    return PopScope(
      canPop: _allowPop || (!_busy && !_dirty),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Буцах',
            onPressed: _busy ? null : _requestClose,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Миний мэдээлэл'),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const Center(child: HamtdaaMark(size: 58)),
              const SizedBox(height: 22),
              const Text(
                'Танд зориулсан орон зай',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Өөрийн нэр, дурсах өдрөө нэмээрэй.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 34),
              TextFormField(
                key: const Key('profileNameField'),
                controller: _name,
                enabled: !_busy,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Таны нэр',
                  hintText: 'Жишээ нь: Ану',
                  counterText: '',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Нэрээ оруулаарай.';
                  }
                  if (value.trim().characters.length > 40) {
                    return 'Нэр 40 тэмдэгтээс уртгүй байна.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Бидний эхэлсэн өдөр',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Заавал биш · Хамтдаа өнгөрүүлсэн хоногийг тоолно.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Material(
                color: AppColors.blush,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  key: const Key('profileDateField'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 5,
                  ),
                  onTap: _busy ? null : _chooseDate,
                  leading: const Icon(
                    Icons.calendar_today_outlined,
                    color: AppColors.pink,
                    size: 23,
                  ),
                  title: Text(
                    since == null
                        ? 'Өдрөө сонгох'
                        : '${since.year} оны ${shortDate(since)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
              if (since != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const Key('profileRemoveDateButton'),
                    onPressed: _busy ? null : () => setState(() => _since = null),
                    icon: const Icon(Icons.close_rounded, size: 17),
                    label: const Text('Өдрийг хасах'),
                  ),
                ),
              const SizedBox(height: 28),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Энэ мэдээлэл зөвхөн таны төхөөрөмжид хадгалагдана.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 20),
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
              const SizedBox(height: 32),
              FilledButton.icon(
                key: const Key('profileSaveButton'),
                onPressed: _busy ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 20),
                label: Text(_saving ? 'Хадгалж байна…' : 'Хадгалах'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
