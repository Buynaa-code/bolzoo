import 'dart:math' as math;
import 'package:flutter/material.dart';

Color bouquetColor(String id) => switch (id) {
  'sage' => const Color(0xFF9EA77C),
  'peach' => const Color(0xFFFFA184),
  _ => const Color(0xFFF17EA9),
};

/// Original vector bouquet: works offline at any screen size, without remote art.
class DigitalBouquet extends StatelessWidget {
  const DigitalBouquet({
    super.key,
    this.templateId = 'letter',
    this.colorId = 'rose',
    this.height = 260,
  });
  final String templateId, colorId;
  final double height;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Дижитал цэцгийн баглаа',
    image: true,
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BouquetPainter(templateId, bouquetColor(colorId)),
      ),
    ),
  );
}

class _BouquetPainter extends CustomPainter {
  const _BouquetPainter(this.template, this.color);
  final String template;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 300, size.height / 320);
    canvas.save();
    canvas.translate(
      (size.width - 300 * scale) / 2,
      (size.height - 320 * scale) / 2,
    );
    canvas.scale(scale);
    final paint = Paint()..isAntiAlias = true;
    final glow = Rect.fromCircle(center: const Offset(150, 150), radius: 132);
    paint.shader = RadialGradient(
      colors: [color.withValues(alpha: .14), color.withValues(alpha: 0)],
    ).createShader(glow);
    canvas.drawOval(glow, paint);
    paint.shader = null;
    if (template == 'letter') {
      final wrap = Path()
        ..moveTo(46, 132)
        ..lineTo(150, 283)
        ..lineTo(256, 132)
        ..quadraticBezierTo(200, 153, 150, 119)
        ..close();
      paint.shader = LinearGradient(
        colors: [
          color.withValues(alpha: .25),
          const Color(0xFFFFFCF8),
          color.withValues(alpha: .45),
        ],
      ).createShader(const Rect.fromLTWH(46, 119, 210, 164));
      canvas.drawPath(wrap, paint);
      paint.shader = null;
    }
    final stems = <Offset>[
      const Offset(91, 89),
      const Offset(123, 65),
      const Offset(168, 59),
      const Offset(210, 87),
      const Offset(70, 135),
      const Offset(111, 124),
      const Offset(155, 107),
      const Offset(201, 132),
      const Offset(233, 151),
      const Offset(91, 170),
      const Offset(147, 154),
      const Offset(182, 178),
    ];
    for (var i = 0; i < stems.length; i++) {
      final flower = stems[i];
      paint
        ..color = const Color(0xFF7E9165)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawPath(
        Path()
          ..moveTo(145 + (i % 4) * 4, 278)
          ..quadraticBezierTo(flower.dx, 185, flower.dx, flower.dy),
        paint,
      );
      paint.style = PaintingStyle.fill;
      final leaf = Offset(flower.dx + (i.isEven ? -12 : 10), flower.dy + 37);
      canvas.save();
      canvas.translate(leaf.dx, leaf.dy);
      canvas.rotate(i.isEven ? -.8 : .8);
      paint.color = i.isEven
          ? const Color(0xFF9EA980)
          : const Color(0xFF6A805E);
      canvas.drawOval(const Rect.fromLTWH(-7, -18, 14, 36), paint);
      canvas.restore();
    }
    for (var i = 0; i < stems.length; i++) {
      final flower = stems[i];
      final isDaisy = template == 'garden' || i % 3 == 1;
      final radius = i % 3 == 0 ? 22.0 : 16.0;
      for (var j = 0; j < (isDaisy ? 9 : 6); j++) {
        final angle = j * math.pi * 2 / (isDaisy ? 9 : 6);
        canvas.save();
        canvas.translate(flower.dx, flower.dy);
        canvas.rotate(angle);
        paint.color = isDaisy
            ? const Color(0xFFFFFCED)
            : Color.lerp(color, Colors.white, j.isEven ? .16 : .4)!;
        canvas.drawOval(
          Rect.fromLTWH(
            -radius * .45,
            -radius * 1.2,
            radius * .9,
            radius * 1.4,
          ),
          paint,
        );
        canvas.restore();
      }
      paint.color = isDaisy ? const Color(0xFFE6BC5C) : color;
      canvas.drawCircle(flower, isDaisy ? 6 : 8, paint);
      paint.color = Colors.white.withValues(alpha: .28);
      canvas.drawCircle(flower.translate(-2, -2), 3, paint);
    }
    if (template == 'bloom') {
      paint.color = Color.lerp(color, Colors.white, .62)!;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          const Rect.fromLTWH(105, 218, 90, 79),
          bottomLeft: const Radius.circular(23),
          bottomRight: const Radius.circular(23),
          topLeft: const Radius.circular(5),
          topRight: const Radius.circular(5),
        ),
        paint,
      );
      paint.color = Colors.white.withValues(alpha: .6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(119, 226, 7, 48),
          const Radius.circular(4),
        ),
        paint,
      );
    } else {
      paint.color = Color.lerp(color, const Color(0xFF95264F), .12)!;
      for (final direction in [-1.0, 1.0]) {
        canvas.save();
        canvas.translate(150, 240);
        canvas.rotate(direction * .4);
        canvas.drawOval(
          Rect.fromLTWH(direction < 0 ? -52 : 0, -12, 52, 24),
          paint,
        );
        final tail = Path()
          ..moveTo(0, 0)
          ..lineTo(direction * 28, 57)
          ..lineTo(direction * 9, 49)
          ..lineTo(direction * 7, 25)
          ..close();
        canvas.drawPath(tail, paint);
        canvas.restore();
      }
      paint.color = color;
      canvas.drawCircle(const Offset(150, 240), 11, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BouquetPainter oldDelegate) =>
      template != oldDelegate.template || color != oldDelegate.color;
}
