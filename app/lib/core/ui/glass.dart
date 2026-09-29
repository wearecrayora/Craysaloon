import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/cray_glass.dart';

/// The soft colour mesh behind every screen (Claude Design, 29 Sep 2026).
///
/// A warm base wash with three glows from the salon's own primary and accent -
/// top-left, top-right and bottom - so each salon's app carries its colour
/// without a single surface being painted with the brand (DESIGN.md 3.5).
/// Painted once per frame as gradients: no image, nothing to download.
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

    void glow(Offset centre, double rx, double ry, Color colour, double stop) {
      // An elliptical glow: a radial gradient in a unit circle, scaled.
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
            [0, stop],
          ),
      );
      canvas.restore();
    }

    final w = size.width, h = size.height;
    glow(Offset(0, 0), w * 0.9, h * 0.55, g.primaryGlow, 0.62);
    glow(Offset(w, h * 0.22), w * 0.8, h * 0.45, g.accentGlow, 0.60);
    glow(Offset(w * 0.3, h), w * 1.1, h * 0.6, g.primaryLow, 0.70);
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.g != g;
}

/// A frosted-glass panel: translucent fill, a bright hairline, a soft shadow.
///
/// [blur] adds a real backdrop blur. It is off by default: blur is expensive on
/// the budget phones this app runs on, and over the mesh a translucent card
/// already reads as glass. Bars and sheets - a few per screen - turn it on.
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
        color: color ?? g.card,
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

/// Press feedback: the target settles slightly under the thumb (120ms, the
/// design's decelerate curve) - so a tap is acknowledged on the frame it lands,
/// even before the network answers. Honours reduced motion (DESIGN.md 7.4):
/// with animations off, the scale is skipped and the tap still works.
class Pressable extends StatefulWidget {
  const Pressable({required this.child, this.onTap, this.scale = 0.97, super.key});

  final Widget child;
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down && !reduced ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: const Cubic(0.2, 0, 0, 1),
        child: widget.child,
      ),
    );
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
