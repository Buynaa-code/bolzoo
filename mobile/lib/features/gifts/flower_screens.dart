import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../data/app_controller.dart';
import '../../data/gift_catalog.dart';
import '../../ui/theme.dart';
import '../memories/media_files.dart';
import 'gift_components.dart';
import 'gift_export.dart';
import 'invitation_screens.dart' show newGiftId;

Color flowerColor(String id) => switch (id) {
  'sage' => const Color(0xFFB8C19F),
  'peach' => const Color(0xFFFFB29A),
  _ => const Color(0xFFF29EC8),
};

Future<void> openFlowerEditor(
  BuildContext context, {
  required AppController controller,
  String occasion = 'Зүгээр л',
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => FlowerEditor(controller: controller, occasion: occasion),
  ),
);

class BouquetArt extends StatelessWidget {
  const BouquetArt({
    super.key,
    required this.templateId,
    required this.colorId,
    this.height = 300,
  });
  final String templateId, colorId;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: templateId == 'letter'
        ? Image.asset(
            'assets/gifts/bouquet.png',
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.local_florist_outlined,
              size: 90,
              color: AppColors.pink,
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: templateId == 'garden'
                  ? flowerColor(colorId).withValues(alpha: .12)
                  : Colors.transparent,
            ),
            child: Padding(
              padding: EdgeInsets.all(templateId == 'garden' ? 14 : 0),
              child: SvgPicture.asset(
                'assets/gifts/bloom-bouquet.svg',
                theme: SvgTheme(currentColor: flowerColor(colorId)),
                errorBuilder: (_, _, _) => Icon(
                  Icons.local_florist_outlined,
                  size: 90,
                  color: flowerColor(colorId),
                ),
                fit: BoxFit.contain,
              ),
            ),
          ),
  );
}

class FlowerEditor extends StatefulWidget {
  const FlowerEditor({
    super.key,
    required this.controller,
    this.occasion = 'Зүгээр л',
  });
  final AppController controller;
  final String occasion;
  @override
  State<FlowerEditor> createState() => _FlowerEditorState();
}

class _FlowerEditorState extends State<FlowerEditor> {
  final _form = GlobalKey<FormState>();
  final _recipient = TextEditingController();
  late final TextEditingController _sender, _message;
  String _template = 'letter', _color = 'rose';
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _sender = TextEditingController(text: widget.controller.data.profile.name);
    _message = TextEditingController(
      text: switch (widget.occasion) {
        'Төрсөн өдөр' => 'Төрсөн өдрийн мэнд! Чиний бүх хүсэл биелээсэй.',
        'Баярлалаа' =>
          'Хажууд минь байдагт баярлалаа. Чамтай бүх зүйл илүү гоё.',
        _ => 'Чамтай өдөр бүр илүү гоё.',
      },
    );
  }

  @override
  void dispose() {
    _recipient.dispose();
    _sender.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final greeting = FlowerGreeting(
      id: newGiftId(),
      templateId: _template,
      colorId: _color,
      occasion: widget.occasion,
      recipientName: _recipient.text.trim(),
      senderName: _sender.text.trim(),
      message: _message.text.trim(),
      createdAt: DateTime.now(),
    );
    try {
      await widget.controller.saveGreeting(greeting);
      if (mounted) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => FlowerPreview(
              controller: widget.controller,
              greeting: greeting,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Мэндчилгээгээ хадгалж чадсангүй. Дахин оролдоорой.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Мэндчилгээ бүтээх')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 32),
        children: [
          Row(
            children: [
              for (final (id, label) in [
                ('letter', 'Захидал'),
                ('garden', 'Цэцэрлэг'),
                ('bloom', 'Баглаа'),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      key: Key('flower-template-$id'),
                      onTap: () => setState(() => _template = id),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCF6F8),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _template == id
                                ? AppColors.pink
                                : AppColors.line,
                            width: _template == id ? 2 : 1,
                          ),
                        ),
                        padding: const EdgeInsets.all(5),
                        child: Column(
                          children: [
                            BouquetArt(
                              templateId: id,
                              colorId: _color,
                              height: 108,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 11),
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
          const SizedBox(height: 10),
          Row(
            children: [
              for (final id in flowerColors)
                Padding(
                  padding: const EdgeInsets.only(right: 15),
                  child: Semantics(
                    label: switch (id) {
                      'sage' => 'Ногоон',
                      'peach' => 'Тоорын өнгө',
                      _ => 'Ягаан',
                    },
                    selected: _color == id,
                    button: true,
                    child: InkWell(
                      key: Key('flower-color-$id'),
                      borderRadius: BorderRadius.circular(30),
                      onTap: () => setState(() => _color = id),
                      child: Container(
                        width: 48,
                        height: 48,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == id
                                ? AppColors.pink
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: flowerColor(id),
                          ),
                          child: _color == id
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 25),
          GiftField(
            label: 'Хэнд',
            controller: _recipient,
            maxLength: 40,
            fieldKey: const Key('flowerRecipient'),
          ),
          GiftField(
            label: 'Хэнээс',
            controller: _sender,
            maxLength: 40,
            fieldKey: const Key('flowerSender'),
          ),
          GiftField(
            label: 'Сэтгэлийн үг',
            controller: _message,
            maxLength: 300,
            lines: 4,
            fieldKey: const Key('flowerMessage'),
          ),
          if (_error != null) GiftNotice(_error!, error: true),
          PinkButton(
            label: 'Мэндчилгээгээ харах',
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    ),
  );
}

class FlowerCard extends StatelessWidget {
  const FlowerCard({super.key, required this.greeting});
  final FlowerGreeting greeting;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(
        color: flowerColor(greeting.colorId).withValues(alpha: .5),
      ),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          flowerColor(greeting.colorId).withValues(alpha: .09),
          Colors.white,
        ],
      ),
    ),
    child: Column(
      children: [
        Text(
          '${greeting.recipientName}, чамдаа',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        BouquetArt(
          templateId: greeting.templateId,
          colorId: greeting.colorId,
          height: 295,
        ),
        const SizedBox(height: 18),
        Text(
          greeting.message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, height: 1.6),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18, horizontal: 50),
          child: Divider(),
        ),
        Text(
          '${greeting.senderName}гээс ♡',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class FlowerPreview extends StatefulWidget {
  const FlowerPreview({
    super.key,
    required this.controller,
    required this.greeting,
    this.captureImage,
    this.shareImage,
  });
  final AppController controller;
  final FlowerGreeting greeting;
  // Native export is injectable so tests exercise the data flow without OS sheets.
  final Future<String> Function(GlobalKey key)? captureImage;
  final Future<void> Function(GlobalKey key, BuildContext context)? shareImage;
  @override
  State<FlowerPreview> createState() => _FlowerPreviewState();
}

class _FlowerPreviewState extends State<FlowerPreview> {
  final _capture = GlobalKey();
  bool _busy = false;
  String? _error;
  bool get _saved => widget.controller.data.memories.any(
    (memory) =>
        memory.id ==
        (widget.greeting.memoryId ?? 'flower_${widget.greeting.id}'),
  );
  Future<void> _saveMemory() async {
    if (_busy || _saved) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? path;
    bool committed = false;
    try {
      path =
          await (widget.captureImage?.call(_capture) ??
              captureGiftPng(
                _capture,
                permanent: true,
                documentsDirectory: widget.controller.storageDirectory,
              ));
      final greeting = widget.greeting;
      await widget.controller.saveMemory(
        MemoryEntry(
          id: greeting.memoryId ?? 'flower_${greeting.id}',
          title: '${greeting.recipientName}, чамдаа',
          date: greeting.createdAt,
          text: '${greeting.message}\n\n${greeting.senderName}гээс ♡',
          photoPath: path,
        ),
      );
      committed = true;
      await widget.controller.saveGreeting(
        greeting.copyWith(
          memoryId: greeting.memoryId ?? 'flower_${greeting.id}',
        ),
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (path != null && !committed) {
        await deleteUnusedManagedPhoto(
          path,
          documentsDirectory: widget.controller.storageDirectory,
          referencedPaths: () =>
              widget.controller.data.memories.map((memory) => memory.photoPath),
        );
      }
      if (mounted) {
        setState(() => _error = 'Хадгалж чадсангүй. Дахин оролдоорой.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.shareImage != null) {
        await widget.shareImage!(_capture, context);
      } else {
        await shareGiftPng(
          _capture,
          context,
          title: '${widget.greeting.recipientName}, чамдаа',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Зураг бэлдэж чадсангүй. Дахин оролдоорой.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Мэндчилгээ харах')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 32),
      children: [
        RepaintBoundary(
          key: _capture,
          child: FlowerCard(greeting: widget.greeting),
        ),
        const SizedBox(height: 22),
        PinkButton(
          label: _saved ? 'Дурсамжид хадгалсан' : 'Дурсамждаа хадгалах',
          busy: _busy,
          icon: _saved ? Icons.check_rounded : Icons.arrow_forward_rounded,
          onPressed: _busy || _saved ? null : _saveMemory,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _share,
          icon: const Icon(Icons.ios_share),
          label: const Text('Зураг татах / хуваалцах'),
        ),
        const GiftNotice(
          'Зургаа хадгалах эсвэл илгээх аппыг нээгдэх цонхноос сонгоорой.',
        ),
        if (_error != null) GiftNotice(_error!, error: true),
      ],
    ),
  );
}
