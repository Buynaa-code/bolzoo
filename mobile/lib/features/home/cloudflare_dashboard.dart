import 'package:flutter/material.dart';

import '../../memories/memory_models.dart';
import '../../memories/memory_sticker.dart';
import '../../together/together_models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import 'cloudflare_home_controller.dart';

class CloudflareDashboard extends StatelessWidget {
  const CloudflareDashboard({
    super.key,
    required this.controller,
    required this.onPair,
    required this.onCalendar,
    required this.onMemories,
    required this.onFlorists,
    required this.onDaily,
    required this.onWishes,
    required this.onEvent,
    required this.onMemory,
    this.environmentNotice,
  });

  final CloudflareHomeController controller;
  final VoidCallback onPair,
      onCalendar,
      onMemories,
      onFlorists,
      onDaily,
      onWishes;
  final ValueChanged<TogetherEvent> onEvent;
  final ValueChanged<SharedMemory> onMemory;
  final Widget? environmentNotice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final snapshot = controller.pair;
      final name = snapshot?.profile.displayName ?? '';
      final partner = snapshot?.pair?.partner.displayName ?? '';
      final upcoming =
          controller.calendar?.events
              .where(
                (event) =>
                    event.status != TogetherEventStatus.declined &&
                    !event.startsAt.isBefore(controller.clock().toUtc()),
              )
              .toList() ??
          [];
      upcoming.sort((a, b) => a.startsAt.compareTo(b.startsAt));
      final event = upcoming.firstOrNull;
      final memories = controller.memories?.items.toList() ?? <SharedMemory>[];
      memories.sort((a, b) => b.day.compareTo(a.day));
      final memory = memories.firstOrNull;
      return RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          key: const Key('cloudflareHome'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
          children: [
            if (environmentNotice != null) ...[
              environmentNotice!,
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Сайн уу ♡' : 'Сайн уу, $name ♡',
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
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('cloudflareOpenPair'),
                  tooltip: controller.paired ? 'Бидний холболт' : 'Хосоо урих',
                  onPressed: onPair,
                  icon: CoupleInitials(name: name, partner: partner),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              key: const Key('homeTogetherCard'),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFF5FA), Color(0xFFFDE5F0)],
                ),
              ),
              child: Column(
                children: [
                  const ClipOval(child: HamtdaaMark(size: 66)),
                  const SizedBox(height: 4),
                  Text(
                    controller.paired ? 'Бид хоёр' : 'Хоёулаа хамтдаа эхэлье',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (controller.paired)
                    Text(
                      '${name.isEmpty ? 'Би' : name}  ♡  ${partner.isEmpty ? 'Миний хос' : partner}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.pink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: onPair,
                      icon: const Icon(Icons.favorite_border, size: 18),
                      label: Text(
                        controller.loading
                            ? 'Холболтыг шалгаж байна'
                            : 'Хосоо урих',
                      ),
                    ),
                  const SizedBox(height: 9),
                  const Text(
                    'Жижиг мөч бүр, том түүх ♡',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (controller.error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SoftCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        error,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      TextButton(
                        onPressed: controller.loading
                            ? null
                            : controller.refresh,
                        child: const Text('Дахин шалгах'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Semantics(
              button: true,
              child: InkWell(
                key: const Key('cloudflareOpenTogether'),
                onTap: event == null ? onCalendar : () => onEvent(event),
                borderRadius: BorderRadius.circular(26),
                child: SoftCard(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: AppColors.pink,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Энэ сарын дараагийн болзоо',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              event?.title ?? 'Хэзээ уулзах вэ?',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 19,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              event == null
                                  ? 'Хоёуланд зориулсан цаг төлөвлөе'
                                  : '${shortDate(event.start)} · ${clockText(event.start)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCalendar,
                    icon: const Icon(Icons.send_outlined, size: 19),
                    label: const Text('Урилга'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('cloudflareOpenFlorists'),
                    onPressed: onFlorists,
                    icon: const Icon(Icons.local_florist_outlined, size: 19),
                    label: const Text('Цэцэг'),
                  ),
                ),
              ],
            ),
            SectionLabel(
              'Энэ сарын дурсамж',
              action: TextButton(
                onPressed: onMemories,
                child: const Text('Бүгд ›'),
              ),
            ),
            if (memory == null)
              HomeActionCard(
                icon: Icons.add_photo_alternate_outlined,
                title: controller.memories?.error != null
                    ? 'Дурсамжийг шинэчлэх'
                    : 'Өнөөдрийн мөчөө үлдээе',
                subtitle:
                    controller.memories?.error ?? 'Нэг зураг, бидний нэг түүх.',
                onTap: onMemories,
              )
            else
              InkWell(
                key: const Key('homeLatestMemory'),
                onTap: () => onMemory(memory),
                borderRadius: BorderRadius.circular(26),
                child: SoftCard(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      MemorySticker(
                        bytes: controller.memories?.thumbnails[memory.id],
                        style: memory.sticker,
                        size: 105,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              memory.title.isEmpty
                                  ? 'Бидний дурсамж'
                                  : memory.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              memory.day.replaceAll('-', '.'),
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
            const SectionLabel('Бие биедээ илүү ойр'),
            HomeActionCard(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Өнөөдрийн асуулт',
              subtitle:
                  controller.calendar?.daily?.question ??
                  'Хоёулаа ярилцах нэг асуулт.',
              onTap: onDaily,
            ),
            const SizedBox(height: 12),
            HomeActionCard(
              icon: Icons.auto_awesome_outlined,
              title: 'Бидний хүслүүд',
              subtitle: 'Хамтдаа хийх зүйлсээ цуглуулъя.',
              onTap: onWishes,
            ),
          ],
        ),
      );
    },
  );
}

class CoupleInitials extends StatelessWidget {
  const CoupleInitials({super.key, required this.name, required this.partner});
  final String name, partner;
  Widget _avatar(String text, Color color) => CircleAvatar(
    radius: 22,
    backgroundColor: Colors.white,
    child: CircleAvatar(
      radius: 20,
      backgroundColor: color,
      child: Text(
        text.isEmpty ? '♡' : text.characters.first.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: AppColors.pink,
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 78,
    height: 54,
    child: Stack(
      children: [
        Positioned(left: 0, top: 1, child: _avatar(name, AppColors.blush)),
        Positioned(
          right: 0,
          top: 1,
          child: _avatar(partner, const Color(0xFFF6E9F6)),
        ),
        const Positioned(
          left: 29,
          bottom: 0,
          child: Icon(Icons.favorite_rounded, color: AppColors.pink, size: 22),
        ),
      ],
    ),
  );
}

class HomeActionCard extends StatelessWidget {
  const HomeActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(26),
    child: SoftCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(icon, color: AppColors.pink),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    ),
  );
}
