import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/cray_glass.dart';
import '../theme/motion.dart';

/// "That worked": a ring that closes and a tick that draws itself, once.
///
/// Painted in code rather than played from a Lottie file: nothing to download
/// or license, crisp at any size, and it follows the theme's success colour.
/// One pass of about half a second on the standard decelerate curve - no
/// bounce, no overshoot (DESIGN 7.1). Under reduced motion it is simply there.
class SuccessCheck extends StatelessWidget {
  const SuccessCheck({this.size = 88, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colour = CrayGlass.of(context).success;
    final reduced = Motion.isReduced(context);
    return Semantics(
      image: true,
      label: MaterialLocalizations.of(context).okButtonLabel,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduced ? 1 : 0, end: 1),
        duration: reduced ? Duration.zero : const Duration(milliseconds: 560),
        curve: Motion.enter,
        builder: (context, t, _) => CustomPaint(
          size: Size.square(size),
          painter: _CheckPainter(t, colour),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.colour);

  final double t;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.07;
    final rect = Offset.zero & size;
    final ring = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // The soft disc fades in under the ring.
    canvas.drawCircle(
      rect.center,
      size.width / 2 - stroke,
      Paint()..color = colour.withValues(alpha: 0.12 * t),
    );

    // The ring closes over the first 60%.
    final ringT = (t / 0.6).clamp(0.0, 1.0);
    canvas.drawArc(
      rect.deflate(stroke),
      -math.pi / 2,
      2 * math.pi * ringT,
      false,
      ring,
    );

    // The tick draws over the rest.
    final tickT = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
    if (tickT <= 0) return;
    final w = size.width;
    final path = Path()
      ..moveTo(w * 0.30, w * 0.52)
      ..lineTo(w * 0.44, w * 0.66)
      ..lineTo(w * 0.71, w * 0.38);
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * tickT), ring);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.colour != colour;
}
