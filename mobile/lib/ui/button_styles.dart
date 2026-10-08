import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// The Flowertoi pill buttons from assets/flowertoi-ui.css, adapted to touch.
abstract final class FlowertoiButtonStyles {
  static ButtonStyle primary() => FilledButton.styleFrom(
    minimumSize: const Size(48, 54),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
    backgroundColor: Colors.transparent,
    disabledBackgroundColor: const Color(0xFFF0E4EB),
    foregroundColor: Colors.white,
    disabledForegroundColor: const Color(0xFF8A727D),
    elevation: 0,
    textStyle: _textStyle,
    shape: const StadiumBorder(),
  ).copyWith(backgroundBuilder: _primarySurface);

  static ButtonStyle secondary() => OutlinedButton.styleFrom(
    minimumSize: const Size(48, 50),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
    foregroundColor: const Color(0xFFA53167),
    disabledForegroundColor: const Color(0xFF8A727D),
    side: const BorderSide(color: Color(0xFFFFC6E5)),
    textStyle: _textStyle,
    shape: const StadiumBorder(),
  ).copyWith(backgroundBuilder: _secondarySurface);

  static const _textStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 16,
    fontWeight: FontWeight.w800,
  );

  static Widget _primarySurface(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => _surface(context, states, child, primary: true);

  static Widget _secondarySurface(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => _surface(context, states, child, primary: false);

  static Widget _surface(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child, {
    required bool primary,
  }) {
    final button = context.widget;
    final style = button is ButtonStyleButton ? button.style : null;
    // Explicit surfaces are field/occasion selectors or destructive actions.
    // Keep their shape, selection border, and warning color intact.
    if (style?.shape != null ||
        style?.backgroundColor != null ||
        style?.foregroundColor?.resolve(states) ==
            Theme.of(context).colorScheme.error) {
      return child ?? const SizedBox.shrink();
    }
    final disabled = states.contains(WidgetState.disabled);
    final focused = !disabled && states.contains(WidgetState.focused);
    final colors = disabled
        ? const [Color(0xFFF0E4EB), Color(0xFFF0E4EB)]
        : primary
        ? const [
            Color(0xFFFFB1D8),
            Color(0xFFFF75BB),
            Color(0xFFF83C9F),
            Color(0xFFF02B94),
          ]
        : const [Colors.white, Color(0xFFFFF8FC), Color(0xFFFCE5F2)];
    return _PressSurface(
      pressed: states.contains(WidgetState.pressed),
      disabled: disabled,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      baseColor: disabled
          ? const Color(0xFFE4D6DE)
          : primary
          ? const Color(0xFFCE0C71)
          : const Color(0xFFE9B3D0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
            stops: disabled
                ? null
                : primary
                ? const [0, .22, .53, 1]
                : const [0, .45, 1],
          ),
          border: Border.all(
            color: focused
                ? const Color(0xFF8B245B)
                : disabled
                ? const Color(0xFFE4D6DE)
                : primary
                ? const Color(0xFFFF9BCE)
                : const Color(0xFFFFC6E5),
            width: 2,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Visual feedback only: the native button still owns taps, focus and semantics.
/// Raw down events make even a quick tap visible before InkWell's gesture delay.
class _PressSurface extends StatefulWidget {
  const _PressSurface({
    required this.pressed,
    required this.disabled,
    required this.reduceMotion,
    required this.baseColor,
    required this.child,
  });

  final bool pressed, disabled, reduceMotion;
  final Color baseColor;
  final Widget child;

  @override
  State<_PressSurface> createState() => _PressSurfaceState();
}

class _PressSurfaceState extends State<_PressSurface>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 170),
    value: widget.pressed && !widget.disabled ? 1 : 0,
  );
  late final _depth = CurvedAnimation(
    parent: _motion,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutCubic,
  );
  int? _pointer;
  Offset _downPosition = Offset.zero;
  int _transition = 0;

  @override
  void didUpdateWidget(_PressSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disabled) {
      _pointer = null;
      _transition++;
      _motion.value = 0;
    } else if (oldWidget.reduceMotion != widget.reduceMotion) {
      _transition++;
      _motion.value = widget.pressed || _pointer != null ? 1 : 0;
    } else if (oldWidget.pressed != widget.pressed) {
      if (widget.pressed) {
        _press();
      } else if (_pointer == null &&
          (_motion.status == AnimationStatus.forward ||
              _motion.status == AnimationStatus.completed)) {
        _release();
      }
    }
  }

  void _press() {
    if (widget.disabled) return;
    _transition++;
    if (widget.reduceMotion) {
      _motion.value = 1;
    } else {
      _motion.forward();
    }
  }

  void _release({bool cancelled = false}) {
    final transition = ++_transition;
    if (widget.disabled || widget.reduceMotion) {
      _motion.value = 0;
    } else if (cancelled) {
      _motion.reverse();
    } else {
      // Finish the short downstroke even when down/up arrive in one frame.
      // This never waits to run the actual button action.
      _motion.forward().whenCompleteOrCancel(() {
        if (mounted && transition == _transition && _pointer == null) {
          _motion.reverse();
        }
      });
    }
  }

  void _onDown(PointerDownEvent event) {
    if (widget.disabled || _pointer != null ||
        event.buttons & kPrimaryButton == 0) return;
    _pointer = event.pointer;
    _downPosition = event.position;
    _press();
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final size = context.size;
    if ((event.position - _downPosition).distance > kTouchSlop ||
        (size != null && !(Offset.zero & size).contains(event.localPosition))) {
      _pointer = null;
      _release(cancelled: true);
    }
  }

  void _onEnd(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _release(cancelled: event is PointerCancelEvent);
  }

  @override
  void dispose() {
    _transition++;
    _depth.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onEnd,
    onPointerCancel: _onEnd,
    child: AnimatedBuilder(
      animation: _depth,
      child: widget.child,
      builder: (context, child) {
        final travel = 4.5 * _depth.value;
        // All motion stays within a constant layout and stationary tap target.
        return Transform.scale(
          scale: 1 - .015 * _depth.value,
          alignment: Alignment.bottomCenter,
          transformHitTests: false,
          child: Stack(
            // Preserve a stretched button's width for the raised foreground.
            // The default loose fit only expanded the base behind the label.
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                top: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.baseColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: travel, bottom: 5 - travel),
                child: child,
              ),
            ],
          ),
        );
      },
    ),
  );
}
