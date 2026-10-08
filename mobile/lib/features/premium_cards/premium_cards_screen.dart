import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../cloudflare/cloudflare_auth_repository.dart';
import '../../ui/theme.dart';

/// Card content is returned only after server entitlement verification. It is
/// kept in memory; exporting requires a fresh check for the same login.
class PremiumCardsScreen extends StatefulWidget {
  const PremiumCardsScreen({super.key, required this.auth});
  final CloudflareAuthRepository auth;
  @override
  State<PremiumCardsScreen> createState() => _PremiumCardsScreenState();
}

class _PremiumCardsScreenState extends State<PremiumCardsScreen> {
  final _names = TextEditingController();
  final _message = TextEditingController(text: 'Чамтай өдөр бүр илүү гоё.');
  final _form = GlobalKey<FormState>();
  late final CloudflareCredential? _credential = widget.auth.credential;
  DateTime _date = DateTime.now();
  String _theme = 'rose';
  String? _error;
  Map<String, dynamic>? _card;
  bool _busy = false;

  bool get _current {
    final credential = _credential;
    return mounted && credential != null && widget.auth.accepts(credential);
  }

  @override
  void dispose() {
    _names.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _generate() async {
    if (!_current || _credential == null) throw StateError('session');
    final response = await widget.auth.transport.send(
      'POST',
      '/v1/premium/cards',
      token: _credential.token,
      body: {
        'names': _names.text.trim(),
        'message': _message.text.trim(),
        'date':
            '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
        'theme': _theme,
      },
    );
    if (!_current) throw StateError('session');
    if (response.status == 401) {
      await widget.auth.reject(_credential);
      throw StateError('session');
    }
    if (response.status == 403) throw StateError('plus');
    if (response.status != 200 || response.body['ok'] != true)
      throw StateError('network');
    final card = response.body['card'];
    if (card is! Map<String, dynamic> ||
        card['names'] is! String ||
        card['message'] is! String ||
        card['date'] is! String ||
        card['colors'] is! List ||
        (card['colors'] as List).length != 3 ||
        !(card['colors'] as List).every(
          (c) => c is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(c),
        )) {
      throw StateError('network');
    }
    return card;
  }

  Future<void> _create({bool share = false}) async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final card = await _generate();
      if (!_current) return;
      setState(() => _card = card);
      if (share) {
        final bytes = await renderCoupleCard(card);
        if (!mounted || !_current) return;
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                mimeType: 'image/png',
                name: 'hamtdaa-card.png',
              ),
            ],
            fileNameOverrides: ['hamtdaa-card.png'],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      }
    } catch (error) {
      if (mounted)
        setState(() {
          _card = null;
          _error = error is StateError && error.message == 'plus'
              ? 'Энэ карт Plus багцад багтана. Багцын эрхээ шалгаарай.'
              : 'Карт бүтээж чадсангүй. Нэвтрэлт болон интернэтээ шалгаад дахин оролдоорой.';
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Бидний хосын карт')),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Хоёулангийн жижиг түүх',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Нэр, онцгой өдөр, сэтгэлийн үгээ оруулаад 1080 × 1920 зураг бүтээгээрэй.',
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _names,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: 'Бидний нэр',
                hintText: 'Ану & Тэмүүлэн',
              ),
              validator: (v) =>
                  v?.trim().isNotEmpty == true ? null : 'Нэрээ оруулаарай',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _message,
              maxLength: 160,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Сэтгэлийн үг'),
              validator: (v) => v?.trim().isNotEmpty == true
                  ? null
                  : 'Сэтгэлийн үгээ бичээрэй',
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                '${_date.year}.${_date.month.toString().padLeft(2, '0')}.${_date.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2200),
                      );
                      if (mounted && date != null)
                        setState(() {
                          _date = date;
                          _card = null;
                        });
                    },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final item in const [
                  ('rose', 'Ягаан'),
                  ('sage', 'Ногоон'),
                  ('peach', 'Тоор'),
                ])
                  ChoiceChip(
                    label: Text(item.$2),
                    selected: _theme == item.$1,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _theme = item.$1;
                            _card = null;
                          }),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.pink),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : () => _create(),
              child: Text(_busy ? 'Бүтээж байна…' : 'Картыг харах'),
            ),
            if (_card != null) ...[
              const SizedBox(height: 24),
              AspectRatio(
                aspectRatio: 1080 / 1920,
                child: CustomPaint(painter: CoupleCardPainter(_card!)),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _create(share: true),
                icon: const Icon(Icons.ios_share),
                label: const Text('Зураг хадгалах / хуваалцах'),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Картын бичвэрийг серверт хадгалахгүй. Зураг хадгалах үед өөрийн утасны хуваалцах цэсийг ашиглана.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

Color _color(dynamic hex) =>
    Color(int.parse('FF${(hex as String).substring(1)}', radix: 16));

class CoupleCardPainter extends CustomPainter {
  CoupleCardPainter(this.card);
  final Map<String, dynamic> card;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1080, size.height / 1920);
    final colors = card['colors'] as List;
    final accent = _color(colors[2]);
    final background = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(1080, 1920), [
        _color(colors[0]),
        _color(colors[1]),
      ]);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1080, 1920), background);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(60, 60, 960, 1800),
        const Radius.circular(70),
      ),
      Paint()..color = Colors.white.withValues(alpha: .62),
    );
    void text(
      String value,
      double y,
      double fontSize, {
      FontWeight weight = FontWeight.w500,
      Color? color,
      double width = 800,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: color ?? accent,
            fontSize: fontSize,
            fontWeight: weight,
            height: 1.4,
            fontFamily: 'Arial',
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: width);
      painter.paint(canvas, Offset((1080 - painter.width) / 2, y));
    }

    text('ХАМТДАА', 190, 27, weight: FontWeight.w700);
    final heart = Path()
      ..moveTo(540, 540)
      ..cubicTo(340, 400, 380, 290, 470, 315)
      ..cubicTo(510, 322, 532, 352, 540, 366)
      ..cubicTo(570, 310, 675, 286, 700, 356)
      ..cubicTo(750, 435, 626, 492, 540, 540)
      ..close();
    canvas.drawPath(heart, Paint()..color = accent);
    text(
      card['names'] as String,
      650,
      (card['names'] as String).length > 28 ? 42 : 60,
      weight: FontWeight.w800,
    );
    text(card['date'] as String, 900, 30, color: accent.withValues(alpha: .7));
    text(card['message'] as String, 1090, 44);
    text(
      'Бидний түүх үргэлжилсээр',
      1660,
      27,
      color: accent.withValues(alpha: .7),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(CoupleCardPainter oldDelegate) => oldDelegate.card != card;
}

Future<Uint8List> renderCoupleCard(Map<String, dynamic> card) async {
  final recorder = ui.PictureRecorder();
  CoupleCardPainter(card).paint(Canvas(recorder), const Size(1080, 1920));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1080, 1920);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('render');
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
