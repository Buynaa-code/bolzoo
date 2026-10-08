import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';

class MemorySticker extends StatelessWidget {
  const MemorySticker({
    super.key,
    required this.bytes,
    required this.style,
    required this.size,
  });
  final Uint8List? bytes;
  final String style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final polaroid = style == 'polaroid';
    final inset = size * (polaroid ? .1 : .05);
    return Semantics(
      image: bytes != null,
      label: 'Дурсамжийн зураг',
      child: SizedBox.square(
        dimension: size,
        child: ClipRect(
          child: Padding(
            padding: EdgeInsets.all(inset),
            child: Transform.rotate(
              angle: polaroid ? -.07 : .035,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(
                    polaroid ? size * .035 : size * .2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: .14),
                      blurRadius: size * .04,
                      offset: Offset(0, size * .02),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    size * .045,
                    size * .045,
                    size * .045,
                    size * (polaroid ? .16 : .045),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          polaroid ? size * .015 : size * .15,
                        ),
                        child: bytes == null
                            ? _placeholder()
                            : Image.memory(
                                bytes!,
                                fit: BoxFit.cover,
                                cacheWidth: 320,
                                frameBuilder: (context, child, frame, loaded) =>
                                    frame == null ? _placeholder() : child,
                                errorBuilder: (_, _, _) => _placeholder(),
                              ),
                      ),
                      Positioned(
                        right: size * .02,
                        bottom: size * .015,
                        child: Icon(
                          Icons.favorite_rounded,
                          size: size * .19,
                          color: AppColors.pink,
                          shadows: const [
                            Shadow(color: Colors.white, blurRadius: 3),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => ColoredBox(
    color: AppColors.blush,
    child: Center(
      child: Icon(
        Icons.photo_outlined,
        color: AppColors.muted,
        size: size * .3,
      ),
    ),
  );
}
