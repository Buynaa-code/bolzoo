import 'package:flutter/material.dart';

import '../together/together_models.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'wish_controller.dart';
import 'wish_models.dart';

const wishCategories = {
  'home': 'Гэртээ',
  'outdoor': 'Гадаа',
  'food': 'Амттай зүйл',
  'travel': 'Аялал',
  'other': 'Бусад',
};
const wishBudgets = {
  'free': 'Зардалгүй',
  'low': 'Бага төсөв',
  'medium': 'Дунд төсөв',
  'high': 'Тусгай төлөвлөгөө',
};

// Original, evergreen suggestions. No venue prices or availability are implied.
const wishSuggestions = <WishDraft>[
  WishDraft(
    title: 'Хамтдаа пицца хийе',
    note: 'Орцоо хамт сонгоод өөрсдийн жорыг бүтээе.',
    category: 'food',
    budget: 'low',
    location: 'Гэртээ',
  ),
  WishDraft(
    title: 'Утасгүй нэг орой',
    note: 'Дуртай дуугаа тавиад удаан ярилцъя.',
    category: 'home',
  ),
  WishDraft(
    title: 'Кофе, бас яриа',
    note: 'Яаралгүй суух нэг цагийг бид хоёрт.',
    category: 'food',
    budget: 'low',
  ),
  WishDraft(
    title: 'Нар жаргахыг хамт харъя',
    note: 'Тухтай газар сонгоод дулаахан хувцаслая.',
    category: 'outdoor',
  ),
  WishDraft(
    title: 'Гэрийн кино үдэш',
    note: 'Нэг нэг кино санал болгоод хамт сонгоё.',
    category: 'home',
    budget: 'low',
  ),
  WishDraft(
    title: 'Анхны болзоогоо давтъя',
    note: 'Тэр өдрийнхөө хамгийн тод дурсамжийг ярилцъя.',
    category: 'other',
    budget: 'medium',
  ),
  WishDraft(
    title: 'Хөвсгөл рүү хамт аялъя',
    note: 'Боломжит өдөр, зам, төсвөө эхлээд хамт төлөвлөе.',
    category: 'travel',
    budget: 'high',
  ),
  WishDraft(
    title: 'Бие биенийхээ хөргийг зуръя',
    note: 'Гоё зурах албагүй. Хөгжилтэй байхад л болно.',
    category: 'home',
  ),
  WishDraft(
    title: 'Шинэ хоол амталъя',
    note: 'Хоёулаа өмнө нь идэж үзээгүй нэг амт.',
    category: 'food',
    budget: 'medium',
  ),
  WishDraft(
    title: 'Нэг өдрийн жижиг аялал',
    note: 'Ойрхон очих газар сонгоод замын дуугаа бэлдье.',
    category: 'travel',
    budget: 'medium',
  ),
  WishDraft(
    title: 'Өвлийн халуун какао',
    note: 'Цонхны дэргэд тухтай суугаад сайхан мөчөө ярилцъя.',
    category: 'home',
    budget: 'low',
  ),
  WishDraft(
    title: 'Хамтын дууны жагсаалт',
    note: 'Нэг нэг дуу нэмж, яагаад сонгосноо ярилцъя.',
    category: 'home',
  ),
];

IconData _categoryIcon(String category) => switch (category) {
  'home' => Icons.cottage_outlined,
  'outdoor' => Icons.wb_sunny_outlined,
  'food' => Icons.local_cafe_outlined,
  'travel' => Icons.landscape_outlined,
  _ => Icons.auto_awesome_outlined,
};

/// Embedded in TogetherScreen; pair changes recreate this widget and its drafts.
class WishBoard extends StatefulWidget {
  const WishBoard({
    super.key,
    required this.controller,
    required this.onOpenCalendar,
    required this.onAddMemory,
    this.onPaneChanged,
    this.now,
  });
  final WishController controller;
  final Future<void> Function(SharedWish) onOpenCalendar;
  final Future<void> Function(SharedWish) onAddMemory;
  final VoidCallback? onPaneChanged;
  final DateTime Function()? now;
  @override
  State<WishBoard> createState() => WishBoardState();
}

class WishBoardState extends State<WishBoard> {
  String _filter = 'all', _category = 'all';
  bool _suggestions = false, _creating = false, _discarding = false;
  SharedWish? _planning;
  final _editorKey = GlobalKey<_WishEditorState>();
  WishDraft? _seed;
  WishController get c => widget.controller;
  bool get hasPane => _creating || _planning != null || _suggestions;

  void _change(VoidCallback action) {
    setState(action);
    widget.onPaneChanged?.call();
  }

  Future<void> requestBack() async {
    if (c.saving || _discarding) return;
    if (_creating && _editorKey.currentState?.dirty == true) {
      _discarding = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Хүслээ хадгалахгүй гарах уу?'),
          content: const Text('Бичсэн зүйл тань хадгалагдахгүй.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Үргэлжлүүлэх'),
            ),
            TextButton(
              key: const Key('wishDiscard'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Гарах'),
            ),
          ],
        ),
      );
      _discarding = false;
      if (!mounted || discard != true) return;
    }
    if (mounted) {
      _change(() {
        _creating = false;
        _planning = null;
        _suggestions = false;
        _seed = null;
      });
    }
  }

  void _new([WishDraft? seed]) => _change(() {
    _seed = seed;
    _creating = true;
    _planning = null;
    _suggestions = false;
  });

  Future<void> _delete(SharedWish wish) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Хүслийг устгах уу?'),
        content: const Text(
          'Энэ хүсэл хоёулангийн жагсаалтаас арилна. Товлосон болзоо байвал хуанлид үлдэнэ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Болих'),
          ),
          TextButton(
            key: const Key('wishConfirmDelete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Устгах'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true && c.canMutate) await c.delete(wish);
  }

  Future<void> _retry() async {
    final planId = c.pendingOperation == 'plan' ? c.pendingWishId : null;
    final success = await c.retry();
    if (!mounted || !success) return;
    // A recovered create/plan must not leave a populated form that can duplicate it.
    _change(() {
      _creating = false;
      _planning = null;
      _seed = null;
    });
    final planned = c.items
        .where((wish) => wish.id == planId && wish.eventId != null)
        .firstOrNull;
    if (planned != null) await widget.onOpenCalendar(planned);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      if (!c.current) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Хосын холболтоо шалгаад дахин нээгээрэй.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return Column(
        children: [
          if (c.loading || c.saving)
            const LinearProgressIndicator(minHeight: 2),
          if (c.failure != null || c.notice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
              child: Text(
                c.failure?.message ?? c.notice!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.failure == null
                      ? AppColors.muted
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          if (c.pendingCommand != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OutlinedButton.icon(
                key: const Key('wishRetry'),
                onPressed: c.saving ? null : _retry,
                icon: const Icon(Icons.sync),
                label: const Text('Өмнөх үйлдлийг шалгах'),
              ),
            ),
          if (hasPane)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('wishBack'),
                onPressed: c.saving ? null : requestBack,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Хүслийн жагсаалт'),
              ),
            ),
          Expanded(
            child: _creating
                ? _WishEditor(
                    key: _editorKey,
                    controller: c,
                    seed: _seed,
                    onSaved: () => _change(() {
                      _creating = false;
                      _seed = null;
                    }),
                  )
                : _planning != null
                ? _WishPlanner(
                    key: ValueKey(_planning!.id),
                    controller: c,
                    wish: _planning!,
                    now: widget.now,
                    onSaved: (wish) async {
                      _change(() => _planning = null);
                      await widget.onOpenCalendar(wish);
                    },
                  )
                : _suggestions
                ? _ideas()
                : _list(),
          ),
        ],
      );
    },
  );

  Widget _ideas() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    children: [
      const PageHeading(
        'Нэг санаанаас эхэлье',
        subtitle: 'Таалагдсан санаагаа өөрийнхөөрөө өөрчлөөд хадгалаарай.',
      ),
      for (var i = 0; i < wishSuggestions.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _categoryIcon(wishSuggestions[i].category),
                  color: AppColors.pink,
                ),
                const SizedBox(height: 10),
                Text(
                  wishSuggestions[i].title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  wishSuggestions[i].note,
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: Key('wishSuggestion$i'),
                  onPressed: c.canMutate
                      ? () => _new(wishSuggestions[i])
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Миний хүсэлд нэмэх'),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _list() {
    final visible = c.items
        .where(
          (wish) =>
              (_category == 'all' || wish.category == _category) &&
              switch (_filter) {
                'matched' => wish.isIdea && wish.bothLiked,
                'planned' => wish.isPlanned,
                'done' => wish.isDone,
                _ => !wish.isDone,
              },
        )
        .toList();
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        key: const Key('wishList'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SoftCard(
            color: AppColors.blush,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  color: AppColors.pink,
                  size: 30,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Хоёулаа\nхиймээр зүйлс',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Хүсэл дээрээ зүрх дараарай. Хоёуланд таалагдвал өдөр товлоё.',
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 14),
                Text(
                  '${c.items.where((w) => w.isIdea && w.bothLiked).length} давхацсан хүсэл  ·  ${c.items.where((w) => w.isDone).length} биелсэн',
                  style: const TextStyle(
                    color: AppColors.pink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('wishAdd'),
            onPressed: c.canMutate ? () => _new() : null,
            icon: const Icon(Icons.add),
            label: const Text('Хүсэл нэмэх'),
          ),
          TextButton.icon(
            key: const Key('wishIdeas'),
            onPressed: c.current && !c.saving
                ? () => _change(() => _suggestions = true)
                : null,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Болзооны санаа үзэх'),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in const {
                  'all': 'Хүслүүд',
                  'matched': 'Хоёулаа',
                  'planned': 'Товлосон',
                  'done': 'Биелсэн',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('wishFilter${entry.key}'),
                      label: Text(entry.value),
                      selected: _filter == entry.key,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = entry.key),
                    ),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: PopupMenuButton<String>(
              key: const Key('wishCategoryFilter'),
              initialValue: _category,
              onSelected: (v) => setState(() => _category = v),
              itemBuilder: (_) => [
                for (final e in {'all': 'Бүх төрөл', ...wishCategories}.entries)
                  PopupMenuItem(value: e.key, child: Text(e.value)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      wishCategories[_category] ?? 'Бүх төрөл',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const Icon(Icons.expand_more, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
          if (c.failure != null && c.items.isEmpty && !c.loading)
            OutlinedButton.icon(
              onPressed: c.refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Дахин шалгах'),
            ),
          if (visible.isEmpty && !c.loading && c.failure == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const FlowerMark(size: 48),
                  const SizedBox(height: 16),
                  Text(
                    c.items.isEmpty
                        ? 'Бидний эхний хүсэл юу байх бол?'
                        : 'Энд хараахан хүсэл алга',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.items.isEmpty
                        ? 'Жижигхэн санаа ч сайхан дурсамжийн эхлэл.'
                        : 'Өөр ангиллаа сонгоод үзээрэй.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          for (final wish in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _card(wish),
            ),
        ],
      ),
    );
  }

  Widget _card(SharedWish wish) => SoftCard(
    key: Key('wishCard${wish.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.blush,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_categoryIcon(wish.category), color: AppColors.pink),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                wishCategories[wish.category]!,
                style: const TextStyle(color: AppColors.muted),
              ),
            ),
            if (wish.creatorId == c.actorId)
              IconButton(
                key: Key('wishDelete${wish.id}'),
                tooltip: 'Хүслийг устгах',
                onPressed: c.canMutate ? () => _delete(wish) : null,
                icon: const Icon(Icons.more_horiz),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          wish.title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        if (wish.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            wish.note,
            style: const TextStyle(color: AppColors.muted, height: 1.45),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(
              wishBudgets[wish.budget]!,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            if (wish.location.isNotEmpty)
              Text(
                wish.location,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (wish.isIdea) ...[
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: Key('wishLike${wish.id}'),
                onPressed: c.canMutate
                    ? () => c.like(wish, !wish.myLiked)
                    : null,
                icon: Icon(
                  wish.myLiked ? Icons.favorite : Icons.favorite_border,
                ),
                label: Text(wish.myLiked ? 'Миний хүсэл' : 'Би ч бас'),
              ),
              Text(
                wish.partnerLiked
                    ? 'Хос тань сонгосон'
                    : 'Хосын сонголтыг хүлээе',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          if (wish.bothLiked) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('wishPlan${wish.id}'),
                onPressed: c.canMutate
                    ? () => _change(() => _planning = wish)
                    : null,
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Өдөр товлох'),
              ),
            ),
          ],
        ] else ...[
          Text(
            wish.isDone
                ? 'Бид хамтдаа биелүүлсэн ♡'
                : switch (wish.eventStatus) {
                    'accepted' => 'Хоёулаа тохирсон ♡',
                    'declined' => 'Хос тань татгалзсан',
                    _ => 'Болзооны хариу хүлээж байна',
                  },
            style: const TextStyle(
              color: AppColors.pink,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (wish.eventStartsAt != null) ...[
            const SizedBox(height: 6),
            Text(
              '${togetherDay(togetherTime(wish.eventStartsAt!))} · ${togetherClock(togetherTime(wish.eventStartsAt!))}',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
          if (wish.eventId != null)
            TextButton.icon(
              key: Key('wishCalendar${wish.id}'),
              onPressed: () => widget.onOpenCalendar(wish),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Хуанлид харах'),
            ),
          if (wish.isPlanned &&
              wish.canCompleteAt((widget.now ?? DateTime.now)()))
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: Key('wishComplete${wish.id}'),
                onPressed: c.canMutate ? () => c.complete(wish) : null,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Хамтдаа биелүүлсэн'),
              ),
            ),
          if (wish.isDone && wish.eventStartsAt != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('wishMemory${wish.id}'),
                onPressed: () => widget.onAddMemory(wish),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Дурсамж нэмэх'),
              ),
            ),
        ],
      ],
    ),
  );
}

class _WishEditor extends StatefulWidget {
  const _WishEditor({
    super.key,
    required this.controller,
    required this.onSaved,
    this.seed,
  });
  final WishController controller;
  final WishDraft? seed;
  final VoidCallback onSaved;
  @override
  State<_WishEditor> createState() => _WishEditorState();
}

class _WishEditorState extends State<_WishEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.seed?.title ?? '');
  late final _note = TextEditingController(text: widget.seed?.note ?? '');
  late final _location = TextEditingController(
    text: widget.seed?.location ?? '',
  );
  late String _category = widget.seed?.category ?? 'other',
      _budget = widget.seed?.budget ?? 'free';
  bool get dirty =>
      _title.text.isNotEmpty ||
      _note.text.isNotEmpty ||
      _location.text.isNotEmpty;
  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final saved = await widget.controller.create(
      WishDraft(
        title: _title.text.trim(),
        note: _note.text.trim(),
        location: _location.text.trim(),
        category: _category,
        budget: _budget,
      ),
    );
    if (mounted && saved != null) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      children: [
        const PageHeading(
          'Нэг өдөр хоёулаа…',
          subtitle: 'Таны хүсэл хосод тань ч харагдана.',
        ),
        TextFormField(
          key: const Key('wishTitle'),
          controller: _title,
          enabled: widget.controller.canMutate,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Юу хиймээр байна?',
            hintText: 'Жишээ нь: Хамтдаа пицца хийх',
          ),
          validator: (v) => v == null || v.trim().isEmpty
              ? 'Хүслээ бичээрэй.'
              : togetherTextError(v, 80),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('wishCategory'),
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Төрөл'),
          items: [
            for (final e in wishCategories.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: widget.controller.canMutate
              ? (v) => setState(() => _category = v!)
              : null,
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          key: const Key('wishBudget'),
          initialValue: _budget,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Төсөв'),
          items: [
            for (final e in wishBudgets.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: widget.controller.canMutate
              ? (v) => setState(() => _budget = v!)
              : null,
        ),
        const SizedBox(height: 18),
        TextFormField(
          key: const Key('wishLocation'),
          controller: _location,
          enabled: widget.controller.canMutate,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Хаана? · Заавал биш'),
          validator: (v) => togetherTextError(v, 120),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('wishNote'),
          controller: _note,
          enabled: widget.controller.canMutate,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Бяцхан тайлбар',
            alignLabelWithHint: true,
          ),
          validator: (v) => togetherTextError(v, 500),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('wishSave'),
          onPressed: widget.controller.canMutate ? _save : null,
          child: const Text('Хүслээ хадгалах'),
        ),
      ],
    ),
  );
}

class _WishPlanner extends StatefulWidget {
  const _WishPlanner({
    super.key,
    required this.controller,
    required this.wish,
    required this.onSaved,
    this.now,
  });
  final WishController controller;
  final SharedWish wish;
  final Future<void> Function(SharedWish) onSaved;
  final DateTime Function()? now;
  @override
  State<_WishPlanner> createState() => _WishPlannerState();
}

class _WishPlannerState extends State<_WishPlanner> {
  late DateTime _day = togetherTime(
    (widget.now ?? DateTime.now)(),
  ).add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  String? _error;
  Future<void> _date() async {
    final today = togetherTime((widget.now ?? DateTime.now)());
    final value = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(2099, 12, 31),
      helpText: 'Хэзээ хамтдаа хийх вэ?',
      cancelText: 'Болих',
      confirmText: 'Сонгох',
    );
    if (mounted && value != null) setState(() => _day = value);
  }

  Future<void> _clock() async {
    final value = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Улаанбаатарын цагаар',
      cancelText: 'Болих',
      confirmText: 'Сонгох',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (mounted && value != null) setState(() => _time = value);
  }

  Future<void> _save() async {
    final at = togetherUtc(_day, _time.hour, _time.minute);
    if (!at.isAfter((widget.now ?? DateTime.now)().toUtc())) {
      setState(() => _error = 'Ирээдүйн өдөр, цаг сонгоорой.');
      return;
    }
    final current = widget.controller.items
        .where((wish) => wish.id == widget.wish.id)
        .firstOrNull;
    if (current == null || !current.canPlan) {
      setState(
        () => _error =
            'Хүслийн сонголт өөрчлөгдсөн байна. Жагсаалт руу буцаж шалгаарай.',
      );
      return;
    }
    final wish = await widget.controller.plan(current, at);
    if (mounted && wish != null) await widget.onSaved(wish);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
    children: [
      const PageHeading(
        'Хүслээ болзоо болгоё',
        subtitle: 'Хоёуланд таалагдсан. Одоо цагаа тохиръё.',
      ),
      SoftCard(
        color: AppColors.blush,
        child: Text(
          widget.wish.title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        key: const Key('wishPlanDay'),
        onPressed: widget.controller.canMutate ? _date : null,
        icon: const Icon(Icons.calendar_month_outlined),
        label: Text(togetherDay(_day)),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('wishPlanTime'),
        onPressed: widget.controller.canMutate ? _clock : null,
        icon: const Icon(Icons.schedule),
        label: Text(
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Улаанбаатарын цагаар. Болзоо хуанлид нэмэгдэнэ. Хос тань өдөр, цагийг зөвшөөрнө.',
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
      FilledButton.icon(
        key: const Key('wishConfirmPlan'),
        onPressed: widget.controller.canMutate ? _save : null,
        icon: const Icon(Icons.favorite_border),
        label: const Text('Болзоонд урих'),
      ),
    ],
  );
}
