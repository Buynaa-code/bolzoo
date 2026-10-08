import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The same composition is used for the preview and the exported 1024px icon.
class HomeIconPainter extends CustomPainter {
  const HomeIconPainter({
    required this.photos,
    required this.label,
    required this.split,
    this.alignments = const [Alignment.center, Alignment.center],
    this.zooms = const [1, 1],
  });

  final List<ui.Image?> photos;
  final String label;
  final bool split;
  final List<Alignment> alignments;
  final List<double> zooms;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = const Color(0xFFFCE4EF));
    final count = split ? 2 : 1;
    for (var index = 0; index < count; index++) {
      final rect = Rect.fromLTWH(
        size.width * index / count, 0, size.width / count, size.height,
      );
      final photo = photos[index];
      if (photo == null) {
        canvas.drawCircle(rect.center.translate(0, -size.height * .08),
            size.width * .075, Paint()..color = const Color(0xFFEAB8CE));
        canvas.drawOval(Rect.fromCenter(
          center: rect.center.translate(0, size.height * .17),
          width: rect.width * .62, height: size.height * .30,
        ), Paint()..color = const Color(0xFFEAB8CE));
        continue;
      }
      final imageSize = Size(photo.width.toDouble(), photo.height.toDouble());
      final coverScale = math.max(rect.width / imageSize.width, rect.height / imageSize.height);
      final cropSize = Size(rect.width / (coverScale * zooms[index]),
          rect.height / (coverScale * zooms[index]));
      final source = alignments[index].inscribe(cropSize, Offset.zero & imageSize);
      canvas.drawImageRect(photo, source, rect, Paint()..filterQuality = FilterQuality.high);
    }
    if (split) {
      canvas.drawRect(Rect.fromLTWH(size.width / 2 - size.width * .003, 0,
          size.width * .006, size.height), Paint()..color = Colors.white.withValues(alpha: .65));
    }
    canvas.drawRect(bounds, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      stops: [.4, 1], colors: [Colors.transparent, Color(0xCF24131C)],
    ).createShader(bounds));
    final text = TextPainter(
      text: TextSpan(text: label, style: TextStyle(
        fontFamily: 'Nunito', fontWeight: FontWeight.w900,
        color: Colors.white, fontSize: size.width * .215,
        shadows: [Shadow(blurRadius: size.width * .025, color: const Color(0x5524131C))],
      )),
      textDirection: TextDirection.ltr, maxLines: 1,
    )..layout();
    final scale = math.min(1.0, size.width * .7 / math.max(1, text.width));
    canvas.save();
    canvas.translate((size.width - text.width * scale) / 2, size.height * .70);
    canvas.scale(scale);
    text.paint(canvas, Offset.zero);
    canvas.restore();
    text.dispose();
  }

  @override
  bool shouldRepaint(covariant HomeIconPainter oldDelegate) => true;
}

Future<ui.Image> decodeHomeIconPhoto(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('Photo must be at most 20 MiB.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final factor = math.min(1.0, 1600 / math.max(descriptor.width, descriptor.height));
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * factor).round()),
      targetHeight: math.max(1, (descriptor.height * factor).round()),
    );
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<Uint8List> renderHomeIconPng(HomeIconPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1024, 1024));
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(1024, 1024);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not render icon.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    picture.dispose();
  }
}
