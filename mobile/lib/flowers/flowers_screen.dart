import 'dart:async';
import 'package:flutter/material.dart';
import '../cloudflare/cloudflare_auth_repository.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'flower_art.dart';
import 'flower_controller.dart';
import 'flower_models.dart';
import 'flower_repository.dart';

class FlowersScreen extends StatefulWidget {
  const FlowersScreen({
    super.key,
    required this.auth,
    this.controller,
    this.onPair,
  });
  final CloudflareAuthRepository auth;

  /// An injected controller is owned by its caller.
  final FlowersController? controller;
  final VoidCallback? onPair;
  @override
  FlowersScreenState createState() => FlowersScreenState();
}

class FlowersScreenState extends State<FlowersScreen>
    with WidgetsBindingObserver {
  late final FlowersController _controller;
  final _message = TextEditingController();
  final _form = GlobalKey<FormState>();
  int _pane = 0, _revision = 0, _filter = 0;
  String _template = 'letter', _color = 'rose', _occasion = 'Зүгээр л';
  String? _detailId, _seenSentId;
  bool _foreground = true, _discarding = false;
  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        FlowersController(CloudflareFlowersRepository(widget.auth));
    _revision = _controller.privacyRevision;
    _seenSentId = _controller.sentId;
    _controller.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _controller.setVisible(true);
  }

  void _changed() {
    if (!mounted) return;
    if (_revision != _controller.privacyRevision) {
      _revision = _controller.privacyRevision;
      _reset();
    }
    // A write may finish while the app is in the background. A confirmed card
    // must leave the preview then too, so resuming cannot send it a second time.
    if (_controller.sentId != _seenSentId) {
      _seenSentId = _controller.sentId;
      if (_seenSentId != null) {
        _reset();
        _filter = 1;
      }
    }
    setState(() {});
  }

  void _reset() {
    _pane = 0;
    _detailId = null;
    _message.clear();
    _template = 'letter';
    _color = 'rose';
    _occasion = 'Зүгээр л';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _controller.setVisible(_foreground);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.setVisible(false);
    }
    _message.dispose();
    super.dispose();
  }

  Future<bool> requestLeave() async {
    if (_controller.saving || _discarding) return false;
    if (_pane != 1 && _pane != 2) return true;
    _discarding = true;
    final revision = _revision;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Мэндчилгээнээс гарах уу?'),
        content: Text(
          _controller.pending
              ? 'Илгээсэн эсэх нь хараахан батлагдаагүй байна. Дахин оролдоход давхар илгээгдэхгүй.'
              : 'Хадгалаагүй мэндчилгээ арилна.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Үргэлжлүүлэх'),
          ),
          TextButton(
            key: const Key('flowersConfirmLeave'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Гарах'),
          ),
        ],
      ),
    );
    _discarding = false;
    if (!mounted || revision != _revision) return false;
    return leave == true;
  }

  Future<void> _back() async {
    if (_controller.saving) return;
    if (_pane == 2 && !_controller.pending) {
      setState(() => _pane = 1);
      return;
    }
    if (_pane != 0) {
      if (!await requestLeave() || !mounted) return;
      setState(_reset);
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _compose() {
    if (!_controller.canSend) return;
    setState(() {
      _pane = 1;
      _message.text = 'Чамтай өдөр бүр илүү гоё.';
    });
  }

  FlowerDraft get _draft => FlowerDraft(
    templateId: _template,
    colorId: _color,
    occasion: _occasion,
    message: _message.text,
  );
  Future<void> _send() async {
    final revision = _revision;
    final success = _controller.pending
        ? await _controller.retry()
        : await _controller.send(_draft);
    if (!mounted || !_foreground || revision != _revision) return;
    if (success) {
      setState(() {
        _reset();
        _filter = 1;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Цэцгээ илгээлээ ♡')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.snapshot;
    return PopScope(
      canPop: _pane == 0 && !_controller.saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        key: const Key('flowersScreen'),
        appBar: AppBar(
          leading: BackButton(onPressed: _back),
          title: Text(switch (_pane) {
            1 => 'Мэндчилгээ бүтээх',
            2 => 'Мэндчилгээ харах',
            3 => 'Чамд ирсэн цэцэг',
            _ => 'Сэтгэлийн цэцэг',
          }),
          actions: [
            if (_pane == 0)
              IconButton(
                key: const Key('flowersRefresh'),
                tooltip: 'Шинэчлэх',
                onPressed: _controller.loading ? null : _controller.refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        body: !_foreground
            ? const SizedBox.shrink()
            : state == null
            ? _loading()
            : !state.paired
            ? _unpaired()
            : switch (_pane) {
                1 => _editor(),
                2 => _preview(),
                3 => _detail(),
                _ => _home(),
              },
      ),
    );
  }

  Widget _loading() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_controller.loading)
            const CircularProgressIndicator()
          else ...[
            Text(
              _controller.error ?? 'Мэдээллээ шинэчилнэ үү.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _controller.refresh,
              child: const Text('Дахин шалгах'),
            ),
          ],
        ],
      ),
    ),
  );
  Widget _unpaired() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DigitalBouquet(height: 220),
          const Text(
            'Хосдоо жижигхэн баяр бэлэглэе',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Хосоороо холбогдсоныхоо дараа бие биедээ дижитал цэцэг илгээнэ.',
            textAlign: TextAlign.center,
          ),
          if (widget.onPair != null) ...[
            const SizedBox(height: 22),
            FilledButton(
              key: const Key('flowersPair'),
              onPressed: widget.onPair,
              child: const Text('Хосоо холбох'),
            ),
          ],
        ],
      ),
    ),
  );
  Widget _home() {
    final state = _controller.snapshot!;
    final gifts = state.gifts
        .where(
          (g) => _filter == 0
              ? g.recipientId == _controller.actorId
              : g.senderId == _controller.actorId,
        )
        .toList();
    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: ListView(
        key: const Key('flowersInbox'),
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
        children: [
          const Text(
            'Үг бүрт чинь цэцэг нэмье',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          Text(
            '${state.partnerName}-д сэтгэлээ илэрхийлээрэй.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const DigitalBouquet(height: 225),
          FilledButton.icon(
            key: const Key('flowersCompose'),
            onPressed: _controller.canSend ? _compose : null,
            icon: const Icon(Icons.local_florist_outlined),
            label: const Text('Цэцэг бэлэглэх'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Апп дотор очих дижитал мэндчилгээ',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (_controller.pending) ...[
            const SizedBox(height: 16),
            const Text('Илгээлтийн хариуг дахин шалгана уу.'),
            OutlinedButton(
              key: const Key('flowersRetry'),
              onPressed: _controller.saving ? null : _send,
              child: const Text('Илгээлтийг шалгах'),
            ),
          ],
          const SizedBox(height: 24),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Ирсэн цэцэг')),
              ButtonSegment(value: 1, label: Text('Илгээсэн')),
            ],
            selected: {_filter},
            onSelectionChanged: (value) =>
                setState(() => _filter = value.first),
          ),
          const SizedBox(height: 18),
          if (gifts.isEmpty)
            SoftCard(
              color: AppColors.blush,
              child: Text(
                _filter == 0
                    ? 'Чамд ирсэн цэцгүүд энд хадгалагдана ♡'
                    : 'Анхны цэцгээ илгээе ♡',
                textAlign: TextAlign.center,
              ),
            ),
          for (final gift in gifts)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: AppColors.blush,
                child: ListTile(
                  key: Key('flowersGift-${gift.id}'),
                  leading: SizedBox(
                    width: 54,
                    child: DigitalBouquet(
                      templateId: gift.templateId,
                      colorId: gift.colorId,
                      height: 64,
                    ),
                  ),
                  title: Text(
                    _filter == 0
                        ? '${gift.senderName}-ээс ♡'
                        : '${gift.recipientName}-д ♡',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    gift.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() {
                    _detailId = gift.id;
                    _pane = 3;
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _editor() => Form(
    key: _form,
    child: ListView(
      key: const Key('flowersEditor'),
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
      children: [
        const Text(
          'Баглаагаа сонгоорой',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final (id, name) in [
              ('letter', 'Баглаа'),
              ('garden', 'Цэцэрлэг'),
              ('bloom', 'Ваартай'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    key: Key('flowersTemplate-$id'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => setState(() => _template = id),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.blush,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _template == id
                              ? AppColors.pink
                              : AppColors.line,
                          width: 1.5,
                        ),
                      ),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          DigitalBouquet(
                            templateId: id,
                            colorId: _color,
                            height: 105,
                          ),
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Өнгө сонгох',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        Row(
          children: [
            for (final (id, label) in [
              ('rose', 'Ягаан'),
              ('sage', 'Ногоон'),
              ('peach', 'Тоорын өнгө'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 10),
                child: Semantics(
                  label: label,
                  selected: _color == id,
                  child: IconButton(
                    key: Key('flowersColor-$id'),
                    tooltip: label,
                    onPressed: () => setState(() => _color = id),
                    style: IconButton.styleFrom(
                      backgroundColor: bouquetColor(id).withValues(alpha: .25),
                      side: BorderSide(
                        color: _color == id
                            ? AppColors.pink
                            : Colors.transparent,
                      ),
                    ),
                    icon: Icon(
                      _color == id ? Icons.check : Icons.circle,
                      color: bouquetColor(id),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: const Key('flowersOccasion'),
          initialValue: _occasion,
          decoration: const InputDecoration(labelText: 'Ямар учраар'),
          items: flowerOccasions
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (value) {
            if (value != null) setState(() => _occasion = value);
          },
        ),
        const SizedBox(height: 18),
        Text(
          'Хэнд: ${_controller.snapshot!.partnerName}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('flowersMessage'),
          controller: _message,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Сэтгэлийн үг'),
          validator: (value) {
            try {
              _draft.toJson();
              return null;
            } on FlowerFailure {
              return 'Сэтгэлийн үгээ 1–500 тэмдэгтээр бичээрэй.';
            }
          },
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('flowersPreview'),
          onPressed: () {
            if (_form.currentState!.validate()) setState(() => _pane = 2);
          },
          child: const Text('Мэндчилгээ харах →'),
        ),
      ],
    ),
  );
  Widget _preview() => ListView(
    key: const Key('flowersPreviewPage'),
    padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
    children: [
      _card(
        recipient: _controller.snapshot!.partnerName!,
        template: _template,
        color: _color,
        occasion: _occasion,
        message: _message.text.trim(),
      ),
      const SizedBox(height: 22),
      if (_controller.error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            _controller.error!,
            style: const TextStyle(color: AppColors.pink),
          ),
        ),
      FilledButton.icon(
        key: const Key('flowersSend'),
        onPressed: _controller.saving ? null : _send,
        icon: _controller.saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_outlined),
        label: Text(
          _controller.saving
              ? 'Илгээж байна…'
              : _controller.pending
              ? 'Илгээлтийг дахин шалгах'
              : 'Хосдоо илгээх',
        ),
      ),
      const SizedBox(height: 12),
      if (!_controller.pending)
        OutlinedButton(
          onPressed: _controller.saving
              ? null
              : () => setState(() => _pane = 1),
          child: const Text('Засах'),
        ),
    ],
  );
  Widget _detail() {
    final matches = _controller.snapshot!.gifts.where((g) => g.id == _detailId);
    if (matches.isEmpty) {
      return const Center(
        child: Text('Энэ цэцэг харагдах боломжгүй болсон байна.'),
      );
    }
    final gift = matches.first;
    return ListView(
      key: const Key('flowersDetail'),
      padding: const EdgeInsets.all(22),
      children: [
        _card(
          recipient: gift.recipientName,
          sender: gift.senderName,
          template: gift.templateId,
          color: gift.colorId,
          occasion: gift.occasion,
          message: gift.message,
        ),
        const SizedBox(height: 20),
        Text(
          shortDate(gift.createdAt.toUtc().add(const Duration(hours: 8))),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        if (gift.recipientId == _controller.actorId)
          FilledButton(
            onPressed: _controller.canSend ? _compose : null,
            child: const Text('Би ч бас цэцэг бэлэглэе ♡'),
          ),
      ],
    );
  }

  Widget _card({
    required String recipient,
    String? sender,
    required String template,
    required String color,
    required String occasion,
    required String message,
  }) => SoftCard(
    color: const Color(0xFFFFF9FC),
    child: Column(
      children: [
        const SizedBox(height: 8),
        Text(
          '$recipient, чамдаа',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        DigitalBouquet(templateId: template, colorId: color, height: 285),
        Text(
          occasion,
          style: const TextStyle(
            color: AppColors.pink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18),
        ),
        if (sender != null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(),
          ),
          Text(
            '$sender-ээс ♡',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
        const SizedBox(height: 14),
      ],
    ),
  );
}
