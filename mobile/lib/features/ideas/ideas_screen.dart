import 'package:flutter/material.dart';
import '../../data/app_controller.dart';
import '../../data/gift_catalog.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../gifts/gift_components.dart';
import '../gifts/gift_gateway.dart';
import '../gifts/invitation_screens.dart';

class IdeasScreen extends StatefulWidget {
  const IdeasScreen({super.key, required this.controller, this.gateway});
  final AppController controller;
  final GiftGateway? gateway;
  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends State<IdeasScreen> {
  String _category = 'Бүгд';
  String _query = '';
  bool _favorites = false;
  Future<void> _favorite(String id) async {
    try { await widget.controller.toggleFavoriteIdea(id); }
    catch (_) { if (mounted) showSaveError(context); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Болзооны санаанууд'), actions: [
      IconButton(tooltip: 'Хадгалсан санаанууд', onPressed: () => setState(() => _favorites = !_favorites),
        icon: Icon(_favorites ? Icons.favorite : Icons.favorite_border, color: AppColors.pink)),
    ]),
    body: ListenableBuilder(listenable: widget.controller, builder: (context, _) {
      final saved = widget.controller.data.gifts.favoriteIdeaIds;
      final ideas = dateIdeas.where((idea) => (_category == 'Бүгд' || idea.category == _category) &&
        (!_favorites || saved.contains(idea.id)) &&
        '${idea.title} ${idea.description} ${idea.placeType}'.toLowerCase().contains(_query.toLowerCase())).toList();
      return ListView(padding: const EdgeInsets.fromLTRB(24, 6, 24, 28), children: [
        const PageHeading('Хоёулаа юу хийх вэ?'),
        TextField(key: const Key('ideaSearch'), decoration: const InputDecoration(
          hintText: 'Санаа хайх', prefixIcon: Icon(Icons.search)),
          onChanged: (value) => setState(() => _query = value.trim())),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: [for (final category in ['Бүгд', 'Дотор', 'Гадаа'])
          ChoiceChip(label: Text(category), selected: _category == category,
            onSelected: (_) => setState(() => _category = category))]),
        const SizedBox(height: 18),
        if (ideas.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(child: Text('Тохирох санаа олдсонгүй.', style: TextStyle(color: AppColors.muted)))),
        for (final idea in ideas) Padding(padding: const EdgeInsets.only(bottom: 20),
          child: SoftCard(padding: const EdgeInsets.all(10), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              InkWell(borderRadius: BorderRadius.circular(20),
                onTap: () => _open(idea), child: IdeaArtwork(idea)),
              Positioned(top: 8, right: 8, child: IconButton.filledTonal(
                key: Key('favorite-${idea.id}'), tooltip: 'Санааг хадгалах',
                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .93)),
                onPressed: () => _favorite(idea.id),
                icon: Icon(saved.contains(idea.id) ? Icons.favorite : Icons.favorite_border,
                  color: AppColors.pink))),
            ]),
            InkWell(onTap: () => _open(idea), child: Padding(padding: const EdgeInsets.all(7),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(idea.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5), Text(idea.description, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 12), IdeaMetadata(idea),
              ]))),
          ]))),
      ]);
    }),
  );
  void _open(DateIdea idea) => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => IdeaDetailScreen(idea: idea, controller: widget.controller, gateway: widget.gateway)));
}

class IdeaMetadata extends StatelessWidget {
  const IdeaMetadata(this.idea, {super.key});
  final DateIdea idea;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 18, runSpacing: 5, children: [
    Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.schedule, size: 17),
      const SizedBox(width: 5), Text(idea.duration)]),
    Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.location_on_outlined, size: 17),
      const SizedBox(width: 5), Text(idea.placeType)]),
  ]);
}

class IdeaDetailScreen extends StatelessWidget {
  const IdeaDetailScreen({super.key, required this.idea, required this.controller, this.gateway});
  final DateIdea idea;
  final AppController controller;
  final GiftGateway? gateway;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Санааны дэлгэрэнгүй')),
    body: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 32), children: [
      IdeaArtwork(idea, height: 245), const SizedBox(height: 20),
      Text(idea.title, style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8), Text(idea.description, style: const TextStyle(color: AppColors.muted, fontSize: 16)),
      const SizedBox(height: 20), IdeaMetadata(idea), const SizedBox(height: 20), const Divider(),
      for (var i = 0; i < idea.steps.length; i++) Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(backgroundColor: AppColors.blush,
            child: Text('${i + 1}', style: const TextStyle(color: AppColors.pink, fontWeight: FontWeight.w900))),
          const SizedBox(width: 16), Expanded(child: Text(idea.steps[i],
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.6))),
        ])),
      const SizedBox(height: 12),
      PinkButton(label: 'Урилга бүтээх', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InvitationEditor(controller: controller, gateway: gateway, idea: idea)))),
    ]),
  );
}
