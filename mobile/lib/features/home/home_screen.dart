import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/app_controller.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../calendar/calendar_screen.dart';
import '../gifts/gifts_screen.dart';
import '../ideas/ideas_screen.dart';
import '../memories/memories_screen.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onTab,
    this.giftGateway,
    this.clock = DateTime.now,
  });
  final AppController controller;
  final ValueChanged<int> onTab;
  final GiftGateway? giftGateway;
  final DateTime Function() clock;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final now = clock();
      final profile = controller.data.profile;
      final upcoming =
          controller.data.events
              .where((event) => !event.startsAt.isBefore(now))
              .toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      final memories = controller.data.memories.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final unread = controller.data.notices
          .where((notice) => !notice.read)
          .length;
      final since = profile.togetherSince;
      final days = since == null
          ? null
          : DateTime.utc(now.year, now.month, now.day)
                    .difference(
                      DateTime.utc(since.year, since.month, since.day),
                    )
                    .inDays +
                1;
      return RefreshIndicator(
        onRefresh: controller.refreshCloud,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 15, 24, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Bolzoo · ',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const TextSpan(
                          text: 'Хамтдаа',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.pink,
                          ),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 21),
                  ),
                ),
                IconButton(
                  key: const Key('homeNotificationsButton'),
                  tooltip: 'Мэдэгдэл',
                  onPressed: () => openNotifications(
                    context,
                    controller: controller,
                    giftGateway: giftGateway,
                  ),
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text('$unread'),
                    child: const Icon(Icons.notifications_none_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 23),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name.isEmpty
                            ? 'Сайн уу ♡'
                            : 'Сайн уу, ${profile.name} ☀',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Өнөөдөр ч бас хамтдаа',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Миний мэдээлэл',
                  onPressed: () => onTab(4),
                  icon: CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.blush,
                    child: Text(
                      profile.name.isEmpty
                          ? '♡'
                          : profile.name.characters.first.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.pink,
                        fontWeight: FontWeight.w900,
                        fontSize: 23,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SoftCard(
              color: AppColors.blush,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
              child: Column(
                children: [
                  const HamtdaaMark(size: 25),
                  const SizedBox(height: 8),
                  const Text(
                    'Хамтдаа',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  if (days != null && days > 0) ...[
                    Text(
                      '$days',
                      key: const Key('togetherDayCount'),
                      style: const TextStyle(
                        fontSize: 63,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        color: AppColors.pink,
                      ),
                    ),
                    const Text(
                      'дахь өдөр',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Бидний өдрүүд',
                      style: TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                        color: AppColors.pink,
                      ),
                    ),
                    TextButton(
                      onPressed: () => onTab(4),
                      child: const Text('Танилцсан өдрөө нэмэх'),
                    ),
                  ],
                  const SizedBox(height: 11),
                  const Text(
                    'Жижиг мөч бүр, том түүх ♡',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              padding: const EdgeInsets.fromLTRB(15, 15, 12, 13),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: AppColors.pink,
                        size: 23,
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Дараагийн болзоо',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              upcoming.isEmpty
                                  ? 'Хэзээ уулзах вэ?'
                                  : upcoming.first.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              upcoming.isEmpty
                                  ? 'Кофе, кино эсвэл зүгээр л хамтдаа.'
                                  : '${shortDate(upcoming.first.startsAt)} · ${clockText(upcoming.first.startsAt)}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('homePlanButton'),
                      onPressed: () => upcoming.isEmpty
                          ? openEventEditor(context, controller)
                          : openEventDetail(
                              context,
                              controller,
                              upcoming.first.id,
                            ),
                      icon: Icon(
                        upcoming.isEmpty
                            ? Icons.add_rounded
                            : Icons.chevron_right,
                        size: 19,
                      ),
                      label: Text(
                        upcoming.isEmpty
                            ? 'Болзоо төлөвлөх'
                            : 'Төлөвлөгөөг харах',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('homeInviteButton'),
                    onPressed: () => openInvitationEditor(
                      context,
                      controller: controller,
                      gateway: giftGateway,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.pink,
                      side: const BorderSide(color: Color(0xFFFFB2D5)),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.send_outlined, size: 20),
                    label: const Text('Урилга'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('homeFlowerButton'),
                    onPressed: () =>
                        openFlowerEditor(context, controller: controller),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.pink,
                      side: const BorderSide(color: Color(0xFFFFB2D5)),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.local_florist_outlined, size: 20),
                    label: const Text('Цэцэг'),
                  ),
                ),
              ],
            ),
            SectionLabel(
              'Сүүлийн дурсамж',
              action: Flexible(
                child: TextButton(
                  onPressed: () => onTab(2),
                  child: const Text('Бүгдийг харах ›'),
                ),
              ),
            ),
            if (memories.isEmpty)
              SoftCard(
                child: Column(
                  children: [
                    const Icon(
                      Icons.photo_outlined,
                      color: AppColors.pink,
                      size: 35,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Хадгалах мөч олон бий',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Анхны зураг, хэдхэн үгнээс эхэлье.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted),
                    ),
                    TextButton(
                      onPressed: () => openMemoryEditor(context, controller),
                      child: const Text('Дурсамж нэмэх →'),
                    ),
                  ],
                ),
              )
            else
              ...memories
                  .take(2)
                  .map(
                    (memory) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SoftCard(
                        padding: const EdgeInsets.all(10),
                        child: InkWell(
                          onTap: () =>
                              openMemoryDetail(context, controller, memory.id),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  width: 105,
                                  height: 100,
                                  child: _MemoryThumbnail(
                                    controller: controller,
                                    memory: memory,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      memory.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${memory.date.year}.${memory.date.month.toString().padLeft(2, '0')}.${memory.date.day.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (memory.place.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on_outlined,
                                            size: 14,
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
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('homeIdeasButton'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      IdeasScreen(controller: controller, gateway: giftGateway),
                ),
              ),
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('Хоёулаа юу хийх вэ?'),
            ),
          ],
        ),
      );
    },
  );
}

class _MemoryThumbnail extends StatelessWidget {
  const _MemoryThumbnail({required this.controller, required this.memory});
  final AppController controller;
  final MemoryEntry memory;
  Widget get _placeholder => const ColoredBox(
    color: AppColors.blush,
    child: Icon(Icons.favorite_border, color: AppColors.pink),
  );
  @override
  Widget build(BuildContext context) {
    final bytes = memory.mediaKey == null
        ? null
        : controller.mediaBytes(memory.mediaKey!);
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder,
      );
    }
    if (memory.photoPath != null) {
      return Image.file(
        File(memory.photoPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder,
      );
    }
    return _placeholder;
  }
}
