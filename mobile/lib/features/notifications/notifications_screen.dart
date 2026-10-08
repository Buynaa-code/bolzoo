import 'package:flutter/material.dart';
import '../../data/app_controller.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../calendar/calendar_screen.dart';
import '../gifts/gifts_screen.dart';
import '../memories/memories_screen.dart';
import '../places/places_screen.dart';

Future<void> openNotifications(BuildContext context, {required AppController controller,
    GiftGateway? giftGateway}) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NotificationsScreen(controller: controller, giftGateway: giftGateway)));

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.controller, this.giftGateway});
  final AppController controller;
  final GiftGateway? giftGateway;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String? _opening;
  Future<void> _open(AppNotice notice) async {
    if (_opening != null) return;
    setState(() => _opening = notice.id);
    try {
      await widget.controller.markNoticeRead(notice.id);
      if (!mounted) return;
      final data = widget.controller.data;
      switch (notice.kind) {
        case 'event':
          if (data.events.any((event) => event.id == notice.sourceId)) {
            await openEventDetail(context, widget.controller, notice.sourceId); return;
          }
        case 'memory':
          if (data.memories.any((memory) => memory.id == notice.sourceId)) {
            await openMemoryDetail(context, widget.controller, notice.sourceId); return;
          }
        case 'place':
          if (data.places.any((place) => place.id == notice.sourceId)) {
            await openPlaceDetail(context, widget.controller, notice.sourceId); return;
          }
        case 'greeting':
          final matches = data.gifts.greetings.where((item) => item.id == notice.sourceId);
          if (matches.isNotEmpty) {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
              FlowerPreview(controller: widget.controller, greeting: matches.first))); return;
          }
        case 'invitation':
          final gateway = widget.giftGateway;
          final candidates = gateway == null ? data.gifts.invitations : await gateway.list();
          if (!mounted) return;
          final matches = candidates.where((item) => item.id == notice.sourceId);
          if (matches.isNotEmpty) {
            final invitation = matches.first;
            final received = gateway != null && invitation.creatorId != gateway.currentUserId &&
              invitation.recipientId == gateway.currentUserId;
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => received
              ? InvitationRecipientScreen(controller: widget.controller, gateway: gateway, invitation: invitation)
              : InvitationPreview(controller: widget.controller, gateway: gateway, invitation: invitation))); return;
          }
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Энэ мэдээлэл устсан эсвэл хуваалцах эрх нь дууссан байна.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Мэдээллийг нээж чадсангүй. Дахин оролдоорой.')));
    } finally { if (mounted) setState(() => _opening = null); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Мэдэгдэл')),
    body: ListenableBuilder(listenable: widget.controller, builder: (context, _) {
      final notices = widget.controller.data.notices.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return RefreshIndicator(onRefresh: widget.controller.refreshCloud, child: ListView(
        physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(24, 15, 24, 32), children: [
        if (notices.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 100), child: Column(children: [
          Icon(Icons.notifications_none_rounded, size: 48, color: AppColors.pink), SizedBox(height: 18),
          Text('Одоогоор мэдэгдэл алга', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          SizedBox(height: 8), Text('Шинэ урилга, хамтын дурсамж энд харагдана.', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.6)),
        ])),
        for (final notice in notices) Column(children: [
          InkWell(key: Key('notice-${notice.id}'), borderRadius: BorderRadius.circular(18),
            onTap: _opening == null ? () => _open(notice) : null,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Row(crossAxisAlignment: CrossAxisAlignment.start,
              children: [CircleAvatar(radius: 21, backgroundColor: AppColors.blush, child: _opening == notice.id
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(switch (notice.kind) { 'memory' => Icons.photo_outlined, 'invitation' => Icons.send_outlined,
                  'event' => Icons.calendar_today_outlined, 'place' => Icons.location_on_outlined,
                  _ => Icons.card_giftcard_outlined }, color: AppColors.pink, size: 22)),
                const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(notice.title, style: TextStyle(fontWeight: notice.read ? FontWeight.w700 : FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 8), Text(notice.body, style: const TextStyle(color: AppColors.muted, height: 1.6, fontSize: 13)),
                  const SizedBox(height: 8), Text(_noticeTime(notice.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ])),
                if (!notice.read) const Padding(padding: EdgeInsets.only(left: 7, top: 6), child: SizedBox(width: 6, height: 6,
                  child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.pink)))),
              ]))), const Divider(height: 1),
        ]),
      ]));
    }));
}

String _noticeTime(DateTime createdAt) {
  final now = DateTime.now();
  if (sameDay(now, createdAt)) return clockText(createdAt);
  if (sameDay(now.subtract(const Duration(days: 1)), createdAt)) return 'Өчигдөр';
  return '${shortDate(createdAt)} · ${clockText(createdAt)}';
}
