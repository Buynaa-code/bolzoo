import 'package:flutter/material.dart';
import '../../data/gift_catalog.dart';
import '../../ui/theme.dart';

class PinkButton extends StatelessWidget {
  const PinkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool busy;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: onPressed == null
            ? [const Color(0xFFE8D3DD), const Color(0xFFE8D3DD)]
            : [const Color(0xFFFA73B4), AppColors.pink],
      ),
      borderRadius: BorderRadius.circular(40),
      boxShadow: onPressed == null
          ? null
          : [
              BoxShadow(
                color: AppColors.pink.withValues(alpha: .15),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
    ),
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        minimumSize: const Size(double.infinity, 54),
      ),
      onPressed: busy ? null : onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          else ...[
            Flexible(child: Text(label, textAlign: TextAlign.center)),
            const SizedBox(width: 14),
            Icon(icon, size: 21),
          ],
        ],
      ),
    ),
  );
}

class IdeaArtwork extends StatelessWidget {
  const IdeaArtwork(this.idea, {super.key, this.height = 200});
  final DateIdea idea;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: idea.image.isEmpty
        ? Container(
            height: height,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF3B1B35), Color(0xFFAF3D69)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.movie_outlined,
                size: 70,
                color: Color(0xFFFFDFEA),
              ),
            ),
          )
        : Image.asset(
            idea.image,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              height: height,
              color: AppColors.blush,
              child: const Center(
                child: Icon(
                  Icons.favorite_outline,
                  color: AppColors.pink,
                  size: 50,
                ),
              ),
            ),
          ),
  );
}

class GiftField extends StatelessWidget {
  const GiftField({
    super.key,
    required this.label,
    required this.controller,
    this.maxLength = 80,
    this.lines = 1,
    this.hint,
    this.fieldKey,
  });
  final String label;
  final TextEditingController controller;
  final int maxLength, lines;
  final String? hint;
  final Key? fieldKey;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextFormField(
          key: fieldKey,
          controller: controller,
          maxLength: maxLength,
          maxLines: lines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: hint,
            counterText: lines == 1 ? '' : null,
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? '$label оруулна уу.'
              : null,
        ),
      ],
    ),
  );
}

class GiftNotice extends StatelessWidget {
  const GiftNotice(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: error ? const Color(0xFFB3261E) : AppColors.muted,
        fontSize: 12,
        height: 1.5,
      ),
    ),
  );
}
