import 'package:flutter/material.dart';
import '../../data/app_controller.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../ideas/ideas_screen.dart';
import 'flower_screens.dart';
import 'gift_components.dart';
import 'gift_gateway.dart';
import 'invitation_screens.dart';

export 'gift_gateway.dart';
export 'invitation_screens.dart';
export 'flower_screens.dart';

class GiftsScreen extends StatefulWidget {
  const GiftsScreen({super.key, required this.controller, this.gateway});
  final AppController controller;
  final GiftGateway? gateway;
  @override
  State<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends State<GiftsScreen> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(24, 18, 24, 8), child: Row(children: [
      const Text('Bolzoo · ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const Text('Хамтдаа', style: TextStyle(color: AppColors.pink, fontWeight: FontWeight.w800)),
      const Spacer(),
      IconButton(tooltip: 'Болзооны санаанууд', onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => IdeasScreen(controller: widget.controller, gateway: widget.gateway))),
        icon: const Icon(Icons.favorite_border, color: AppColors.pink)),
    ])),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: SegmentedButton<int>(segments: const [
        ButtonSegment(value: 0, label: Text('Урилга'), icon: Icon(Icons.send_outlined)),
        ButtonSegment(value: 1, label: Text('Цэцэг'), icon: Icon(Icons.local_florist_outlined)),
      ], selected: {_tab}, onSelectionChanged: (value) => setState(() => _tab = value.first))),
    Expanded(child: _tab == 0
      ? InvitationsList(controller: widget.controller, gateway: widget.gateway)
      : FlowersHome(controller: widget.controller)),
  ]);
}

class FlowersHome extends StatefulWidget {
  const FlowersHome({super.key, required this.controller});
  final AppController controller;
  @override
  State<FlowersHome> createState() => _FlowersHomeState();
}

class _FlowersHomeState extends State<FlowersHome> {
  String _occasion = 'Зүгээр л';
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.controller,
    builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(24, 4, 24, 28), children: [
      const SizedBox(height: 12),
      const Text('Сэтгэлийн цэцэг', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('Хэн нэгнийг баярлуулах уу?', textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted, fontSize: 16)),
      const SizedBox(height: 12),
      const BouquetArt(templateId: 'letter', colorId: 'rose', height: 290),
      Row(children: [for (final (label, icon) in [
        ('Зүгээр л', Icons.spa_outlined), ('Төрсөн өдөр', Icons.cake_outlined),
        ('Баярлалаа', Icons.card_giftcard_outlined),
      ]) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
        child: OutlinedButton(style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          foregroundColor: _occasion == label ? AppColors.pink : AppColors.ink,
          side: BorderSide(color: _occasion == label ? AppColors.pink : AppColors.line)),
          onPressed: () => setState(() => _occasion = label),
          child: Column(children: [Icon(icon), const SizedBox(height: 7),
            Text(label, style: const TextStyle(fontSize: 11))])))),
      ]),
      const SizedBox(height: 24),
      PinkButton(label: 'Баглаа бүтээх', onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => FlowerEditor(controller: widget.controller, occasion: _occasion)))),
      if (widget.controller.data.gifts.greetings.isNotEmpty) ...[
        const SectionLabel('Миний мэндчилгээнүүд'),
        for (final greeting in widget.controller.data.gifts.greetings.reversed)
          ListTile(contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(backgroundColor: AppColors.blush,
              child: Icon(Icons.local_florist_outlined, color: AppColors.pink)),
            title: Text('${greeting.recipientName}, чамдаа'),
            subtitle: Text(greeting.message, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
              FlowerPreview(controller: widget.controller, greeting: greeting)))),
      ],
    ]));
}
