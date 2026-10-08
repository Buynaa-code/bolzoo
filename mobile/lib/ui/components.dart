import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

/// Shared launcher artwork keeps the app identity consistent with the home screen.
class HamtdaaMark extends StatelessWidget {
  const HamtdaaMark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/nandin-moch.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: 'Нандин мөч',
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 24),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -1)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
        ],
      ])),
      ?action,
    ]),
  );
}

class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.color = Colors.white, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(26),
      border: Border.all(color: color == Colors.white ? AppColors.line : Colors.transparent),
    ),
    child: child,
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 12),
    child: Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
      ?action,
    ]),
  );
}

class FlowerMark extends StatelessWidget {
  const FlowerMark({super.key, this.size = 44, this.color = AppColors.pink});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: SizedBox(
    width: size, height: size,
    child: CustomPaint(painter: _FlowerPainter(color)),
  ));
}

class _FlowerPainter extends CustomPainter {
  const _FlowerPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color;
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      canvas.drawCircle(center + Offset(math.cos(angle), math.sin(angle)) * size.width * .235, size.width * .21, paint);
    }
    canvas.drawCircle(center, size.width * .14, Paint()..color = Colors.white.withValues(alpha: .9));
  }
  @override
  bool shouldRepaint(covariant _FlowerPainter oldDelegate) => oldDelegate.color != color;
}

String shortDate(DateTime date) => '${date.month} сарын ${date.day}';
String clockText(DateTime date) => '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

void showSaveError(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('Хадгалж чадсангүй. Дахин оролдоно уу.')),
);
