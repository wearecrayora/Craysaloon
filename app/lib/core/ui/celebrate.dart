import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/cray_glass.dart';
import '../theme/motion.dart';

/// A short burst of confetti, once - the "order placed" moment of the food and
/// grocery apps, kept for the two moments here that earn it: a booking made,
/// and a salon joined (decided 21 Oct 2026).
///
/// Within DESIGN 7: it plays once (about 1.6s) and stops, it never touches a
/// money value, it sits behind nothing anyone has to read and takes no taps,
/// and with reduced motion it does not play at all - the success check and the
/// words carry the moment on their own. Painted in code: nothing to download.
///
/// Colours: the salon's own primary and accent, the fixed success green and a
/// neutral - confetti is a moment, not a surface, so the brand may be in it.
class Celebrate extends StatefulWidget {
  const Celebrate({this.particles = 56, this.height = 260, super.key});

  final int particles;
  final double height;

  @override
  State<Celebrate> createState() => _CelebrateState();
}

class _CelebrateState extends State<Celebrate> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final List<_Bit> _bits = _scatter(widget.particles);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Motion.isReduced(context) && !_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static List<_Bit> _scatter(int n) {
    // Seeded: the same burst every time, so it can be looked at in a test.
    final r = math.Random(7);
    return [
      for (var i = 0; i < n; i++)
        _Bit(
          angle: -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 0.9,
          speed: 0.55 + r.nextDouble() * 0.6,
          spin: (r.nextDouble() - 0.5) * 10,
          size: 5 + r.nextDouble() * 5,
          colour: i % 4,
          round: r.nextBool(),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.isReduced(context)) return SizedBox(height: widget.height);
    final scheme = Theme.of(context).colorScheme;
    final colours = [
      scheme.primary,
      scheme.secondary,
      CrayGlass.of(context).success,
      scheme.outline,
    ];
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _ConfettiPainter(_bits, _c.value, colours),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bit {
  const _Bit({
    required this.angle,
    required this.speed,
    required this.spin,
    required this.size,
    required this.colour,
    required this.round,
  });

  final double angle;
  final double speed;
  final double spin;
  final double size;
  final int colour;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t, this.colours);

  final List<_Bit> bits;
  final double t;
  final List<Color> colours;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final origin = Offset(size.width / 2, size.height * 0.55);
    final reach = size.height;
    // Thrown out fast, slowing, then falling - plain projectile motion, which
    // decelerates without ever overshooting.
    for (final b in bits) {
      final v = b.speed * reach * 1.6;
      final dx = math.cos(b.angle) * v * t;
      final dy = math.sin(b.angle) * v * t + 0.9 * reach * t * t;
      final fade = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3);
      final paint = Paint()..color = colours[b.colour].withValues(alpha: fade);
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(b.spin * t);
      if (b.round) {
        canvas.drawCircle(Offset.zero, b.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.5),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
