import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/cray_glass.dart';

/// The background behind every screen: a clean warm-grey gradient with soft
/// washes of the salon's own primary (top-left) and accent (right) - its
/// colours in the room, never a coloured page (DESIGN 3.5).
///
/// Nothing floats in it any more: the still life of beauty objects (3.5a) was
/// retired from the app the same day - a busy background competes with the
/// raised surfaces that now carry the depth. Painted as two gradients: no
/// image, nothing to download.
class MeshBackground extends StatelessWidget {
  const MeshBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = CrayGlass.of(context);
    return CustomPaint(
      painter: _MeshPainter(g),
      child: child,
    );
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(this.g);

  final CrayGlass g;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [g.meshTop, g.meshBottom],
        ),
    );

    // Two soft elliptical washes: the brand's primary top-left, its accent
    // from the right, a third of the way down. No shapes, nothing floating.
    void wash(Offset centre, double rx, double ry, Color colour) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(rx, ry);
      canvas.drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            1,
            [colour, colour.withValues(alpha: 0)],
            [0, 0.9],
          ),
      );
      canvas.restore();
    }

    final w = size.width, h = size.height;
    wash(Offset.zero, w * 1.0, h * 0.45, g.primaryGlow);
    wash(Offset(w, h * 0.35), w * 0.8, h * 0.4, g.accentGlow);
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.g != g;
}

/// A raised surface: a solid face a touch lighter at the top, a bright bevel
/// along its edge, a soft shadow down-right and a glow of light up-left - a
/// card you could press (DESIGN 3.5, the tactile chassis).
///
/// [blur] is kept for the few bars drawn over scrolling content; a raised
/// face is opaque, so it is rarely needed.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.blur = false,
    this.radius,
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool blur;
  final double? radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final g = CrayGlass.of(context);
    final r = BorderRadius.circular(radius ?? g.radius);
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        gradient: color == null ? g.face : null,
        borderRadius: r,
        border: Border.all(color: g.line),
        boxShadow: g.shadows,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (!blur) return panel;
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: panel,
      ),
    );
  }
}

/// A recessed well, pressed into the surface: a darker floor with a shadow
/// along its top edge, as light falls into a hollow. For the small squares
/// icons sit in on menus.
class Sunken extends StatelessWidget {
  const Sunken({required this.child, this.size = 40, this.radius = 12, super.key});

  final Widget child;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final g = CrayGlass.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(g.sunken, g.shadow, 0.35)!, g.sunken, g.sunken],
          stops: const [0, 0.35, 1],
        ),
        border: Border.all(color: g.line),
      ),
      child: child,
    );
  }
}

/// A raised key that presses in under the thumb: its face and shadows change
/// in 120ms from raised to pressed, so a tap is felt on the frame it lands.
/// With reduced motion the change is instant, never absent (DESIGN 7.4).
///
/// The tap itself is handled by whatever wraps it (a [Pressable], usually),
/// so the key can sit inside a larger target with its label.
class RaisedKey extends StatelessWidget {
  const RaisedKey({
    required this.child,
    this.pressed = false,
    this.size = 56,
    this.radius,
    super.key,
  });

  final Widget child;
  final bool pressed;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final g = CrayGlass.of(context);
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedContainer(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 120),
      curve: const Cubic(0.2, 0, 0, 1),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: pressed ? g.pressedFace : g.face,
        borderRadius: BorderRadius.circular(radius ?? g.radius + 4),
        border: Border.all(color: g.line),
        boxShadow: pressed ? g.pressedShadows : g.shadows,
      ),
      child: child,
    );
  }
}

/// Press feedback: the target settles slightly under the thumb (120ms, the
/// design's decelerate curve) - so a tap is acknowledged on the frame it lands,
/// even before the network answers. Honours reduced motion (DESIGN.md 7.4):
/// with animations off, the scale is skipped and the tap still works.
///
/// [builder], when given, is told whether the thumb is down - for a raised
/// key that presses in rather than shrinks.
class Pressable extends StatefulWidget {
  const Pressable({
    this.child,
    this.builder,
    this.onTap,
    this.scale = 0.97,
    super.key,
  }) : assert(child != null || builder != null);

  final Widget? child;
  final Widget Function(BuildContext context, bool pressed)? builder;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final content = widget.builder?.call(context, _down) ?? widget.child!;
    final pressable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down && !reduced ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: const Cubic(0.2, 0, 0, 1),
        child: content,
      ),
    );
    if (widget.onTap == null) return pressable;
    // One button, named by what it shows: without the merge a screen reader
    // announced an unnamed "button" and read the text as separate, untappable
    // lines (labeledTapTargetGuideline, the screen sweep).
    return MergeSemantics(child: Semantics(button: true, child: pressable));
  }
}

/// A calm entrance for something that has just appeared - a bill that arrived,
/// a result that came back: fade in and rise 8dp over 220ms (DESIGN.md 7.2,
/// "list insertion"). Not for first paint, and never for money changing value.
class Appear extends StatelessWidget {
  const Appear({required this.child, this.delay = Duration.zero, super.key});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220) + delay,
      curve: Interval(
        delay.inMilliseconds / (220 + delay.inMilliseconds),
        1,
        curve: const Cubic(0.2, 0, 0, 1),
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
