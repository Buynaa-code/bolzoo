import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/app_controller.dart';
import '../../data/gift_catalog.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import 'gift_components.dart';
import 'gift_export.dart';
import 'gift_gateway.dart';

String newGiftId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String invitationStatus(InvitationState state) => switch (state) {
  InvitationState.draft => 'Ноорог',
  InvitationState.pending => 'Хүлээж байна',
  InvitationState.accepted => 'Зөвшөөрсөн',
  InvitationState.proposed => 'Өөр цаг санал болгосон',
  InvitationState.cancelled => 'Цуцлагдсан',
};

Future<void> openInvitations(
  BuildContext context, {
  required AppController controller,
  GiftGateway? gateway,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Миний урилгууд')),
      body: InvitationsList(controller: controller, gateway: gateway),
    ),
  ),
);

Future<void> openInvitationEditor(
  BuildContext context, {
  required AppController controller,
  GiftGateway? gateway,
  DateIdea? idea,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) =>
        InvitationEditor(controller: controller, gateway: gateway, idea: idea),
  ),
);

bool _hasCurrentInvitation(AppController controller, String id) =>
    controller.hasRemoteItem(id) &&
    controller.data.gifts.invitations.any((invitation) => invitation.id == id);

class InvitationsList extends StatefulWidget {
  const InvitationsList({super.key, required this.controller, this.gateway});
  final AppController controller;
  final GiftGateway? gateway;
  @override
  State<InvitationsList> createState() => _InvitationsListState();
}

class _InvitationsListState extends State<InvitationsList> {
  bool _past = false, _loading = false;
  String? _error;
  List<DateInvitation> _remote = [];
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_purgeUnavailable);
    _refresh();
  }

  void _purgeUnavailable() {
    if (!widget.controller.cloudAvailable) return;
    final safe = _remote
        .where((item) => widget.controller.hasRemoteItem(item.id))
        .toList();
    if (safe.length != _remote.length && mounted) {
      setState(() => _remote = safe);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_purgeUnavailable);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InvitationsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_purgeUnavailable);
      widget.controller.addListener(_purgeUnavailable);
    }
    if (widget.gateway != oldWidget.gateway) {
      _remote = [];
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_loading || widget.gateway == null) return;
    final gateway = widget.gateway!;
    final epoch = widget.controller.cloudEpoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await gateway.list();
      if (mounted &&
          widget.gateway == gateway &&
          widget.controller.cloudEpoch == epoch) {
        setState(
          () => _remote = widget.controller.cloudAvailable
              ? values
                    .where((item) => widget.controller.hasRemoteItem(item.id))
                    .toList()
              : values,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _remote = [];
          _error =
              'Урилгуудыг шинэчилж чадсангүй. Доош татаж дахин оролдоорой.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(DateInvitation invitation) async {
    final recipient =
        widget.gateway != null &&
        invitation.state != InvitationState.draft &&
        invitation.creatorId != widget.gateway!.currentUserId &&
        invitation.recipientId == widget.gateway!.currentUserId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => recipient
            ? InvitationRecipientScreen(
                controller: widget.controller,
                gateway: widget.gateway!,
                invitation: invitation,
              )
            : InvitationPreview(
                controller: widget.controller,
                gateway: widget.gateway,
                invitation: invitation,
              ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final byId = {
        for (final item in widget.controller.data.gifts.invitations)
          if (item.state == InvitationState.draft) item.id: item,
        for (final item
            in widget.controller.cloudAvailable
                ? widget.controller.data.gifts.invitations.where(
                    (item) => widget.controller.hasRemoteItem(item.id),
                  )
                : _remote)
          item.id: item,
      };
      final items =
          byId.values
              .where(
                (item) =>
                    _past ==
                    (item.state == InvitationState.cancelled ||
                        item.startsAt.isBefore(DateTime.now())),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            const PageHeading('Миний урилгууд'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Идэвхтэй')),
                ButtonSegment(value: true, label: Text('Өнгөрсөн')),
              ],
              selected: {_past},
              onSelectionChanged: (value) =>
                  setState(() => _past = value.first),
            ),
            const SizedBox(height: 18),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) GiftNotice(_error!, error: true),
            if (items.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.mail_outline, color: AppColors.pink, size: 45),
                    SizedBox(height: 16),
                    Text(
                      'Урилгаа эндээс эхлүүлээрэй.',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Өдөр, газар, сэтгэлийн хэдэн үг.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            for (final invitation in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: SoftCard(
                  padding: const EdgeInsets.all(12),
                  child: InkWell(
                    onTap: () => _open(invitation),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 76,
                          child: IdeaArtwork(
                            ideaFor(invitation.templateId),
                            height: 94,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                invitation.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '${shortDate(invitation.startsAt)} · ${clockText(invitation.startsAt)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                invitation.place,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                invitationStatus(invitation.state),
                                style: TextStyle(
                                  color:
                                      invitation.state ==
                                          InvitationState.accepted
                                      ? const Color(0xFF37844A)
                                      : AppColors.pink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            PinkButton(
              label: 'Шинэ урилга',
              onPressed: () async {
                await openInvitationEditor(
                  context,
                  controller: widget.controller,
                  gateway: widget.gateway,
                );
                if (mounted) await _refresh();
              },
            ),
          ],
        ),
      );
    },
  );
}

class InvitationEditor extends StatefulWidget {
  const InvitationEditor({
    super.key,
    required this.controller,
    this.gateway,
    this.idea,
    this.existing,
    this.clock = DateTime.now,
  });
  final AppController controller;
  final GiftGateway? gateway;
  final DateIdea? idea;
  final DateInvitation? existing;
  final DateTime Function() clock;
  @override
  State<InvitationEditor> createState() => _InvitationEditorState();
}

class _InvitationEditorState extends State<InvitationEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _recipient,
      _sender,
      _title,
      _place,
      _message;
  late String _template;
  late DateTime _startsAt;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final prior = widget.existing;
    final idea = widget.idea ?? ideaFor(prior?.templateId ?? 'coffee');
    _template = prior?.templateId ?? idea.id;
    _recipient = TextEditingController(text: prior?.recipientName ?? '');
    _sender = TextEditingController(
      text: prior?.senderName ?? widget.controller.data.profile.name,
    );
    _title = TextEditingController(text: prior?.title ?? idea.invitationTitle);
    _place = TextEditingController(text: prior?.place ?? '');
    _message = TextEditingController(text: prior?.message ?? idea.description);
    final tomorrow = widget.clock().add(const Duration(days: 1));
    _startsAt =
        prior?.startsAt ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 16);
  }

  @override
  void dispose() {
    for (final c in [_recipient, _sender, _title, _place, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = widget.clock();
    final day = await showDatePicker(
      context: context,
      initialDate: _startsAt.isBefore(now) ? now : _startsAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (day != null && mounted) {
      setState(
        () => _startsAt = DateTime(
          day.year,
          day.month,
          day.day,
          _startsAt.hour,
          _startsAt.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (time != null && mounted) {
      setState(
        () => _startsAt = DateTime(
          _startsAt.year,
          _startsAt.month,
          _startsAt.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_startsAt.isAfter(widget.clock())) {
      setState(() => _error = 'Болзох өдрөө ирээдүйд сонгоно уу.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final invitation = DateInvitation(
      id: widget.existing?.id ?? newGiftId(),
      templateId: _template,
      title: _title.text.trim(),
      recipientName: _recipient.text.trim(),
      senderName: _sender.text.trim(),
      startsAt: _startsAt,
      createdAt: widget.existing?.createdAt ?? widget.clock(),
      place: _place.text.trim(),
      message: _message.text.trim(),
      creatorId: widget.gateway?.currentUserId,
    );
    try {
      await widget.controller.saveInvitation(invitation);
      if (mounted) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => InvitationPreview(
              controller: widget.controller,
              gateway: widget.gateway,
              invitation: invitation,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Урилгаа хадгалж чадсангүй. Дахин оролдоорой.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Болзоонд урья')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          const Text(
            'Загвар сонгох',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 125 + MediaQuery.textScalerOf(context).scale(24),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: dateIdeas.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final idea = dateIdeas[index];
                return SizedBox(
                  width: 100,
                  child: InkWell(
                    key: Key('invite-template-${idea.id}'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() {
                      final previous = ideaFor(_template);
                      _template = idea.id;
                      if (_title.text == previous.invitationTitle) {
                        _title.text = idea.invitationTitle;
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: _template == idea.id
                              ? AppColors.pink
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          IdeaArtwork(idea, height: 85),
                          const SizedBox(height: 6),
                          Text(
                            idea.placeType,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          GiftField(
            label: 'Хэнд',
            controller: _recipient,
            maxLength: 40,
            fieldKey: const Key('inviteRecipient'),
          ),
          GiftField(
            label: 'Хэнээс',
            controller: _sender,
            maxLength: 40,
            fieldKey: const Key('inviteSender'),
          ),
          GiftField(
            label: 'Урилгын нэр',
            controller: _title,
            maxLength: 100,
            fieldKey: const Key('inviteTitle'),
          ),
          const Text('Хэзээ', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 19),
                  label: Text(
                    '${_startsAt.year}.${_startsAt.month.toString().padLeft(2, '0')}.${_startsAt.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule, size: 19),
                label: Text(clockText(_startsAt)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          GiftField(
            label: 'Хаана',
            controller: _place,
            maxLength: 140,
            hint: 'Газрын нэр, хаяг',
            fieldKey: const Key('invitePlace'),
          ),
          GiftField(
            label: 'Сэтгэлийн үг',
            controller: _message,
            maxLength: 500,
            lines: 3,
            fieldKey: const Key('inviteMessage'),
          ),
          if (_error != null) GiftNotice(_error!, error: true),
          PinkButton(
            label: 'Урилгаа харах',
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    ),
  );
}

class InvitationCard extends StatelessWidget {
  const InvitationCard({super.key, required this.invitation});
  final DateInvitation invitation;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      children: [
        const Icon(Icons.favorite_border, color: AppColors.pink, size: 32),
        const SizedBox(height: 17),
        Text(
          '${invitation.recipientName},\n${invitation.title}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 22),
        IdeaArtwork(ideaFor(invitation.templateId), height: 210),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today_outlined, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${shortDate(invitation.startsAt)} · ${clockText(invitation.startsAt)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on_outlined, size: 21),
            const SizedBox(width: 8),
            Flexible(
              child: Text(invitation.place, textAlign: TextAlign.center),
            ),
          ],
        ),
        if (invitation.message.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            invitation.message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.6),
          ),
        ],
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 14),
        Text(
          '${invitation.senderName}гээс ♡',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class InvitationPreview extends StatefulWidget {
  const InvitationPreview({
    super.key,
    required this.controller,
    required this.invitation,
    this.gateway,
  });
  final AppController controller;
  final DateInvitation invitation;
  final GiftGateway? gateway;
  @override
  State<InvitationPreview> createState() => _InvitationPreviewState();
}

class _InvitationPreviewState extends State<InvitationPreview> {
  final _capture = GlobalKey();
  late DateInvitation _invitation;
  String? _error, _commandId;
  bool _busy = false, _lostAccess = false;
  @override
  void initState() {
    super.initState();
    _invitation = widget.invitation;
    _lostAccess =
        _invitation.state != InvitationState.draft &&
        widget.controller.cloudAvailable &&
        !_hasCurrentInvitation(widget.controller, _invitation.id);
    widget.controller.addListener(_refreshFromController);
  }

  void _refreshFromController() {
    if (!widget.controller.cloudAvailable || !mounted) return;
    if (_invitation.state != InvitationState.draft &&
        !_hasCurrentInvitation(widget.controller, _invitation.id)) {
      setState(() {
        _lostAccess = true;
        _error = null;
        _commandId = null;
      });
      return;
    }
    if (_lostAccess) return;
    final values = widget.controller.data.gifts.invitations.where(
      (item) => item.id == _invitation.id && item.version > _invitation.version,
    );
    if (values.isNotEmpty) {
      setState(() {
        _invitation = values.first;
        _commandId = null;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshFromController);
    super.dispose();
  }

  Future<void> _publish() async {
    if (_busy ||
        _lostAccess ||
        widget.gateway == null ||
        _invitation.state != InvitationState.draft) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _commandId ??= newGiftId();
    final epoch = widget.controller.cloudEpoch;
    try {
      final saved = await widget.gateway!.publish(
        _invitation,
        commandId: _commandId!,
      );
      if (!mounted || _lostAccess || widget.controller.cloudEpoch != epoch) {
        return;
      }
      setState(() {
        _invitation = saved;
        _commandId = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is GiftGatewayException
              ? error.message
              : 'Илгээж чадсангүй. Дахин оролдоорой.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy || _lostAccess) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await shareGiftPng(_capture, context, title: _invitation.title);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Зураг бэлдэж чадсангүй. Дахин оролдоорой.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmProposal() async {
    final gateway = widget.gateway;
    if (_busy ||
        _lostAccess ||
        gateway == null ||
        _invitation.creatorId != gateway.currentUserId) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _commandId ??= newGiftId();
    final epoch = widget.controller.cloudEpoch;
    try {
      final saved = await gateway.respond(
        _invitation,
        response: InvitationResponse.accept,
        commandId: _commandId!,
      );
      if (!mounted || _lostAccess || widget.controller.cloudEpoch != epoch) {
        return;
      }
      setState(() {
        _invitation = saved;
        _commandId = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is GiftGatewayException
              ? error.message
              : 'Хариуг хадгалж чадсангүй. Дахин оролдоорой.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Урилга бэлэн')),
    body: _lostAccess
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Энэ урилгыг харах эрх дууссан байна.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              RepaintBoundary(
                key: _capture,
                child: InvitationCard(invitation: _invitation),
              ),
              const SizedBox(height: 22),
              if (_invitation.state == InvitationState.draft) ...[
                PinkButton(
                  label: 'Хосдоо илгээх',
                  busy: _busy,
                  onPressed: widget.gateway == null || _busy ? null : _publish,
                  icon: Icons.send_outlined,
                ),
                GiftNotice(
                  widget.gateway == null
                      ? 'Хосдоо илгээхийн тулд нэвтэрч, хосын холбоогоо баталгаажуулаарай.'
                      : 'Баталгаажсан хосын тань аппд урилга очно. Зөвшөөрөх хүртэл болзоо баталгаажаагүй байна.',
                ),
              ] else
                GiftNotice(invitationStatus(_invitation.state)),
              if (_invitation.state == InvitationState.proposed &&
                  _invitation.proposedAt != null) ...[
                Text(
                  'Санал болгосон цаг: ${shortDate(_invitation.proposedAt!)} · ${clockText(_invitation.proposedAt!)}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                PinkButton(
                  label: 'Энэ цагийг зөвшөөрөх',
                  busy: _busy,
                  onPressed: _busy ? null : _confirmProposal,
                ),
                const SizedBox(height: 14),
              ],
              OutlinedButton.icon(
                onPressed: _busy ? null : _share,
                icon: const Icon(Icons.ios_share),
                label: const Text('Зургаар хуваалцах'),
              ),
              if (_invitation.state == InvitationState.draft) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => InvitationEditor(
                              controller: widget.controller,
                              gateway: widget.gateway,
                              existing: _invitation,
                            ),
                          ),
                        ),
                  child: const Text('Засах'),
                ),
              ],
              const GiftNotice(
                'Зургаар хуваалцах нь урилгын хариуг автоматаар бүртгэхгүй.',
              ),
              if (_error != null) GiftNotice(_error!, error: true),
            ],
          ),
  );
}

class InvitationRecipientScreen extends StatefulWidget {
  const InvitationRecipientScreen({
    super.key,
    required this.controller,
    required this.gateway,
    required this.invitation,
  });
  final AppController controller;
  final GiftGateway gateway;
  final DateInvitation invitation;
  @override
  State<InvitationRecipientScreen> createState() =>
      _InvitationRecipientScreenState();
}

class _InvitationRecipientScreenState extends State<InvitationRecipientScreen> {
  late DateInvitation _invitation;
  bool _busy = false, _lostAccess = false;
  String? _error, _commandId;
  InvitationResponse? _pendingResponse;
  DateTime? _pendingTime;
  @override
  void initState() {
    super.initState();
    _invitation = widget.invitation;
    widget.controller.addListener(_checkAccess);
    _lostAccess =
        widget.controller.cloudAvailable &&
        (!widget.controller.isPartnerItem(_invitation.id) ||
            !_hasCurrentInvitation(widget.controller, _invitation.id));
  }

  void _checkAccess() {
    if (!mounted || !widget.controller.cloudAvailable) return;
    if (!widget.controller.isPartnerItem(_invitation.id) ||
        !_hasCurrentInvitation(widget.controller, _invitation.id)) {
      setState(() {
        _lostAccess = true;
        _pendingTime = null;
        _error = null;
      });
      return;
    }
    if (_lostAccess) return;
    final values = widget.controller.data.gifts.invitations.where(
      (item) => item.id == _invitation.id && item.version > _invitation.version,
    );
    if (values.isNotEmpty) {
      setState(() {
        _invitation = values.first;
        _pendingResponse = null;
        _pendingTime = null;
        _commandId = null;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_checkAccess);
    super.dispose();
  }

  bool get _canRespond =>
      !_lostAccess &&
      _invitation.state == InvitationState.pending &&
      _invitation.creatorId != widget.gateway.currentUserId &&
      _invitation.recipientId == widget.gateway.currentUserId;
  Future<void> _respond(
    InvitationResponse response, {
    DateTime? proposedAt,
  }) async {
    if (_busy || !_canRespond) return;
    if (_pendingResponse != null &&
        (_pendingResponse != response || _pendingTime != proposedAt)) {
      setState(
        () => _error =
            'Өмнөх хариуг шалгаж байна. Ижил хариугаар дахин оролдоорой.',
      );
      return;
    }
    _pendingResponse = response;
    _pendingTime = proposedAt;
    _commandId ??= newGiftId();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.respond(
        _invitation,
        response: response,
        commandId: _commandId!,
        proposedAt: proposedAt,
      );
      if (!mounted || _lostAccess) return;
      setState(() => _invitation = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is GiftGatewayException
              ? error.message
              : 'Хариуг илгээж чадсангүй. Дахин оролдоорой.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose() async {
    if (_pendingTime != null) {
      await _respond(InvitationResponse.propose, proposedAt: _pendingTime);
      return;
    }
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _invitation.startsAt.isBefore(now)
          ? now
          : _invitation.startsAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (day == null || !mounted || _lostAccess) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_invitation.startsAt),
    );
    if (time == null || !mounted || _lostAccess) return;
    final proposed = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    if (!proposed.isAfter(DateTime.now())) {
      setState(() => _error = 'Ирээдүйд болох цаг сонгоно уу.');
      return;
    }
    await _respond(InvitationResponse.propose, proposedAt: proposed);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Танд урилга ирлээ')),
    body: _lostAccess
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    color: AppColors.pink,
                    size: 40,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Энэ урилгыг харах эрх дууссан байна.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Буцах'),
                  ),
                ],
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              Text(
                '${_invitation.senderName} чамайг\nболзоонд урьжээ',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 24),
              InvitationCard(invitation: _invitation),
              const SizedBox(height: 26),
              if (_canRespond) ...[
                PinkButton(
                  label: 'Тэгье ♡',
                  busy: _busy,
                  onPressed: _busy
                      ? null
                      : () => _respond(InvitationResponse.accept),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _propose,
                  child: const Text('Өөр цаг санал болгох'),
                ),
              ] else
                GiftNotice(
                  _invitation.state == InvitationState.draft ||
                          _invitation.creatorId == widget.gateway.currentUserId
                      ? 'Энэ нь таны урьдчилан харах дэлгэц. Хүлээн авагч л хариу өгнө.'
                      : invitationStatus(_invitation.state),
                ),
              if (_error != null) GiftNotice(_error!, error: true),
            ],
          ),
  );
}
