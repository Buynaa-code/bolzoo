import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../pair/pair_controller.dart';
import '../../pair/pair_models.dart';
import '../../pair/pair_repository.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';

final pairRouteObserver = RouteObserver<PageRoute<dynamic>>();

/// Give each route a new account-bound repository. This route owns its lifetime.
class PairScreen extends StatefulWidget {
  const PairScreen({
    super.key,
    required this.repository,
    this.onPairChanged,
    this.onConnected,
  });
  final PairRepository repository;

  /// Reports resolved pairing changes and cleared private state to the owner.
  final ValueChanged<PairSnapshot?>? onPairChanged;

  /// Called once when this screen observes a new, server-confirmed connection.
  /// An already-paired account may still open this screen to manage its link.
  final VoidCallback? onConnected;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen>
    with WidgetsBindingObserver, RouteAware {
  late final PairController _controller;
  final _token = TextEditingController();
  final _name = TextEditingController();
  PageRoute<dynamic>? _route;
  bool _routeVisible = true;
  bool _appVisible = true;
  bool _editingName = false;
  bool _changingVisibility = false;
  bool _sawUnpaired = false;
  bool _connectionHandled = false;
  bool _connectionReturnScheduled = false;
  (bool, String?, int?, String?)? _reportedPair;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = PairController(widget.repository);
    _controller.addListener(_pairChanged);
    _appVisible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _controller.setForeground(_appVisible);
  }

  void _pairChanged() {
    final snapshot = _controller.snapshot;
    if (snapshot != null) {
      if (snapshot.pair == null) {
        _sawUnpaired = true;
      } else if (_sawUnpaired) {
        _returnAfterConnection(snapshot.pair!.id);
      }
    }
    // Hiding a private projection is not evidence that the pairing ended.
    // Existing native reminders must survive route changes and backgrounding.
    if (snapshot == null && _changingVisibility) return;
    // Initial loading has no verified pairing to report or invalidate.
    if (snapshot == null && _reportedPair == null) return;
    final pair = snapshot?.pair;
    final next = (
      snapshot != null,
      pair?.id,
      pair?.version,
      pair?.partner.userId,
    );
    if (next == _reportedPair) return;
    _reportedPair = next;
    widget.onPairChanged?.call(snapshot);
  }

  void _returnAfterConnection(String pairId) {
    if (widget.onConnected == null ||
        _connectionHandled ||
        _connectionReturnScheduled ||
        !_appVisible ||
        !_routeVisible) {
      return;
    }
    _connectionReturnScheduled = true;
    // Both the confirm response and the other person's polling refresh arrive
    // through this listener. Finish the frame before changing the route stack.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectionReturnScheduled = false;
      if (!mounted ||
          !_appVisible ||
          !_routeVisible ||
          !_controller.authorized ||
          _controller.snapshot?.pair?.id != pairId ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _connectionHandled = true;
      widget.onConnected?.call();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      pairRouteObserver.unsubscribe(this);
      _route = route;
      pairRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _visibilityChanged();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _visibilityChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    _visibilityChanged();
  }

  void _visibilityChanged() {
    if (!_appVisible || !_routeVisible) _token.clear();
    _changingVisibility = true;
    try {
      _controller.setForeground(_appVisible && _routeVisible);
    } finally {
      _changingVisibility = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pairRouteObserver.unsubscribe(this);
    _controller.removeListener(_pairChanged);
    _controller.dispose();
    widget.repository.dispose();
    _token.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Болих'),
            ),
            FilledButton(
              key: const Key('pairDialogConfirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _create({bool rotate = false}) async {
    if (rotate &&
        !await _confirm(
          title: 'Шинэ урилга үүсгэх үү?',
          body: 'Өмнөх код болон түүнд ирсэн хүсэлт хүчингүй болно.',
          action: 'Шинэ код үүсгэх',
        )) {
      return;
    }
    if (mounted) await _controller.createInvitation();
  }

  Future<void> _accept(PairInvitation invitation) async {
    final name = invitation.requester?.displayName;
    if (name == null) return;
    final approved = await _confirm(
      title: '$name-тай холбогдох уу?',
      body:
          'Энэ нь хэрэглэгчийн өөрөө оруулсан нэр. '
          'Урилгаа өгсөн хүн мөн эсэхийг өөрөөр нь баталгаажуулаарай. '
          'Зөвшөөрвөл та хоёр хосоор холбогдоно.',
      action: 'Зөвшөөрч холбогдох',
    );
    if (mounted && approved) await _controller.confirm(invitation);
  }

  Future<void> _unlink(ActivePair pair) async {
    final approved = await _confirm(
      title: 'Хосын холболтоо салгах уу?',
      body:
          '${pair.partner.displayName}-тай хийсэн холболт хоёр талд цуцлагдана. '
          'Энэ холбооны зурагтай дурсамжууд болон хамтын хүслүүд бүрмөсөн устах тул хэрэгтэй мэдээллээ '
          'эхлээд Мэдээллийн хуулбар авах хэсгээс татаж аваарай. '
          'Дахин холбогдохдоо хоёулаа шинэ урилгыг зөвшөөрнө.',
      action: 'Холболт салгах',
    );
    if (mounted && approved) await _controller.unlink(pair);
  }

  Future<void> _copy(String token) async {
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Код хуулагдлаа. Зөвхөн холбогдох хүндээ өгөөрэй.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final snapshot = _controller.snapshot;
      final pair = snapshot?.pair;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Хосоор холбогдох'),
          actions: [
            IconButton(
              key: const Key('pairRefresh'),
              tooltip: 'Шинэчлэх',
              onPressed:
                  _controller.busy ||
                      _controller.loading ||
                      !_controller.authorized
                  ? null
                  : _controller.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _controller.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const Center(child: HamtdaaMark(size: 56)),
              const SizedBox(height: 20),
              Text(
                pair == null
                    ? 'Хоёулаа зөвшөөрөөд, хамтдаа'
                    : 'Та хоёр холбогдлоо',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '1. Нэг нь код үүсгээд нөгөөдөө илгээнэ.\n'
                '2. Нөгөө нь кодыг шалгаж, хүсэлт илгээнэ.\n'
                '3. Код илгээсэн хүн хүсэлтийг зөвшөөрнө.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 26),
              if (_controller.busy || _controller.loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_controller.failure != null) ...[
                _message(_controller.failure!.message, error: true),
                if (_controller.canRetry)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: FilledButton(
                      key: const Key('pairRetry'),
                      onPressed: _controller.retry,
                      child: const Text('Ижил хүсэлтийг дахин илгээх'),
                    ),
                  ),
                const SizedBox(height: 18),
              ],
              if (_controller.notice != null) ...[
                _message(_controller.notice!),
                const SizedBox(height: 18),
              ],
              if (snapshot == null && !_controller.loading && !_controller.busy)
                SoftCard(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.cloud_off_outlined,
                        color: AppColors.muted,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Холболтын төлөвийг серверээс баталгаажуулсны дараа харуулна.',
                        textAlign: TextAlign.center,
                      ),
                      if (_controller.authorized) ...[
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _controller.refresh,
                          child: const Text('Дахин шалгах'),
                        ),
                      ],
                    ],
                  ),
                ),
              if (snapshot != null) ...[
                _profile(snapshot.profile),
                const SizedBox(height: 18),
                if (pair != null)
                  _active(pair)
                else ...[
                  for (final invitation in snapshot.invitations)
                    if (invitation.isOpen || invitation.isPending)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: _invitation(invitation),
                      ),
                  if (snapshot.invitations.every(
                    (i) => !i.isPending && !i.isOpen,
                  ))
                    _createCard(),
                  if (!snapshot.invitations.any((i) => i.isPending)) ...[
                    const SizedBox(height: 18),
                    _joinCard(),
                  ],
                ],
                const SizedBox(height: 24),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Холбогдсоны дараа хуваалцахаар сонгосон болзоо, '
                        'дурсамж, зураг тань хоёуланд харагдана. '
                        'Хувийн тэмдэглэл зөвхөн танд үлдэнэ.',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _message(String text, {bool error = false}) => Semantics(
    liveRegion: true,
    child: SoftCard(
      color: error ? const Color(0xFFFFF5F1) : AppColors.blush,
      padding: const EdgeInsets.all(16),
      child: Text(text, style: const TextStyle(height: 1.5)),
    ),
  );

  Widget _profile(PairProfile profile) => SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.person_outline_rounded, color: AppColors.pink),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Хосод харагдах миний нэр',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              key: const Key('pairEditName'),
              tooltip: 'Нэрээ засах',
              onPressed: !_controller.canAct
                  ? null
                  : () => setState(() {
                      _name.text = profile.displayName;
                      _editingName = !_editingName;
                    }),
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
          ],
        ),
        if (_editingName) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('pairNameField'),
            controller: _name,
            enabled: _controller.canAct,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Таны нэр'),
          ),
          FilledButton(
            key: const Key('pairSaveName'),
            onPressed: !_controller.canAct
                ? null
                : () async {
                    await _controller.updateName(_name.text);
                    if (mounted && _controller.failure == null) {
                      setState(() => _editingName = false);
                    }
                  },
            child: const Text('Нэрээ хадгалах'),
          ),
        ] else
          Text(
            profile.displayName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
        const SizedBox(height: 8),
        const Text(
          'Энэ нэр серверт хадгалагдаж, урилга болон хүсэлтэд харагдана.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    ),
  );

  Widget _createCard() => SoftCard(
    color: AppColors.blush,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Хайртай хүнээ урих',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        const Text(
          '24 цаг хүчинтэй код үүсгээд өөрөө дамжуулна. '
          'Түүний хүсэлт ирэхэд нэрийг нь харж эцэслэн зөвшөөрнө.',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('pairCreate'),
          onPressed: _controller.canAct ? () => _create() : null,
          icon: const Icon(Icons.favorite_border_rounded),
          label: const Text('Урилгын код үүсгэх'),
        ),
      ],
    ),
  );

  Widget _invitation(PairInvitation invitation) {
    final token = _controller.tokenFor(invitation);
    final expires = invitation.expiresAt.toLocal();
    if (invitation.isCreator && invitation.isOpen) {
      return SoftCard(
        color: AppColors.blush,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Таны урилга бэлэн',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (token != null) ...[
              const Text('Кодыг зөвхөн холбогдох хүндээ дамжуулаарай.'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  token,
                  key: const Key('pairIssuedToken'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('pairCopyToken'),
                onPressed: () => _copy(token),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Код хуулах'),
              ),
            ] else
              const Text(
                'Кодыг энэ төхөөрөмжид хадгалдаггүй. Өмнө нь хуулсан код хүчинтэй хэвээр. '
                'Код хэрэгтэй бол шинэ урилга үүсгээрэй.',
                style: TextStyle(height: 1.5),
              ),
            const SizedBox(height: 12),
            Text(
              '${shortDate(expires)}, ${clockText(expires)} хүртэл',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: _controller.canAct
                      ? () => _create(rotate: true)
                      : null,
                  child: const Text('Шинэ код'),
                ),
                TextButton(
                  key: const Key('pairRevoke'),
                  onPressed: _controller.canAct
                      ? () => _controller.close(invitation, 'revoke')
                      : null,
                  child: const Text('Урилгыг цуцлах'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (invitation.isCreator && invitation.requester != null) {
      return SoftCard(
        color: AppColors.blush,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Танд хүсэлт ирлээ',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Text(
              invitation.requester!.displayName,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Энэ хүн тантай холбогдохыг зөвшөөрсөн. '
              'Нэр нь хэрэглэгчийн өөрөө оруулсан мэдээлэл тул урилгаа өгсөн хүн мөн эсэхийг шалгаарай.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('pairConfirm'),
              onPressed: _controller.canAct ? () => _accept(invitation) : null,
              child: const Text('Энэ хүнтэй холбогдох'),
            ),
            TextButton(
              key: const Key('pairDecline'),
              onPressed: _controller.canAct
                  ? () => _controller.close(invitation, 'decline')
                  : null,
              child: const Text('Татгалзах'),
            ),
          ],
        ),
      );
    }
    return SoftCard(
      color: AppColors.blush,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded, color: AppColors.pink),
          const SizedBox(height: 12),
          const Text(
            'Зөвшөөрлийг хүлээж байна',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            '${invitation.creator.displayName} таны нэрийг харж баталгаажуулсны дараа холбогдоно.',
            style: const TextStyle(height: 1.5),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('pairCancel'),
            onPressed: _controller.canAct
                ? () => _controller.close(invitation, 'cancel')
                : null,
            child: const Text('Хүсэлтээ цуцлах'),
          ),
        ],
      ),
    );
  }

  Widget _joinCard() {
    final preview = _controller.preview;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Урилга авсан уу?',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          const Text(
            'Хоёулаа өөр өөр имэйлээр нэвтэрсэн байх ёстой. '
            'Кодыг шалгасны дараа нэрийг нь нягтлаад хүсэлтээ илгээнэ.',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (preview == null) ...[
            TextField(
              key: const Key('pairTokenField'),
              controller: _token,
              enabled: _controller.canAct,
              autocorrect: false,
              enableSuggestions: false,
              // Validate the complete paste after trimming outer whitespace;
              // a length formatter would silently cut off part of the code.
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Урилгын код',
                hintText: 'Хуулсан кодоо энд оруулна',
                counterText: '',
              ),
              onSubmitted: (_) => _preview(),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              key: const Key('pairPreview'),
              onPressed: _controller.canAct ? _preview : null,
              child: const Text('Урилгыг шалгах'),
            ),
          ] else ...[
            Text(
              preview.creator.displayName,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            const Text(
              'Энэ нь хэрэглэгчийн өөрөө оруулсан нэр. '
              'Таньдаг хүн мөн бол хүсэлтээ илгээгээрэй. Нөгөө хүн дараа нь таныг зөвшөөрнө.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('pairRequest'),
              onPressed: _controller.canAct ? _controller.requestPair : null,
              child: const Text('Зөвшөөрч хүсэлт илгээх'),
            ),
            TextButton(
              onPressed: _controller.busy ? null : _controller.cancelPreview,
              child: const Text('Болих'),
            ),
          ],
        ],
      ),
    );
  }

  void _preview() {
    final input = _token.text;
    _token.clear();
    unawaited(_controller.previewToken(input));
  }

  Widget _active(ActivePair pair) => SoftCard(
    color: AppColors.blush,
    child: Column(
      children: [
        const Icon(Icons.favorite_rounded, color: AppColors.pink, size: 36),
        const SizedBox(height: 16),
        Text(
          pair.partner.displayName,
          key: const Key('pairPartnerName'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          'Хоёр тал зөвшөөрсөн холболт',
          style: TextStyle(color: AppColors.muted),
        ),
        if (widget.onConnected != null && Navigator.of(context).canPop()) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('pairGoHome'),
            onPressed: _controller.busy
                ? null
                : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.home_outlined),
            label: const Text('Нүүр хуудас руу'),
          ),
        ],
        const SizedBox(height: 20),
        OutlinedButton(
          key: const Key('pairUnlink'),
          onPressed: _controller.canAct ? () => _unlink(pair) : null,
          child: const Text('Холболтоо салгах'),
        ),
      ],
    ),
  );
}
