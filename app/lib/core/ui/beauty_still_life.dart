import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../theme/still_life_palette.dart';

/// A still life of beauty objects in frosted glass, painted into the mesh
/// behind every screen (decided 14 Oct 2026, DESIGN.md 3.5a).
///
/// Lipstick, a brush, nail polish, perfume, scissors and a mascara wand -
/// drawn as translucent glass: a faint fill, a hairline edge and
/// a highlight, the way a frosted object catches the light. They sit at the
/// EDGES of the screen, partly cropped, so the middle - where people read - is
/// left to the content.
///
/// The rules that keep it quiet:
///  * **Neutral, never brand-tinted.** Ink in light mode, white in dark; the
///    salon's colour reaches the background only through the mesh glows.
///  * **Faint.** Fill under 6% and an edge under 13% - text over it still
///    clears 4.5:1, asserted by the screen sweep on every screen.
///  * **Still.** Nothing moves: a background that animates competes with the
///    content and costs a budget phone its battery.
///  * Vector, painted in one pass - no image to download, nothing to cache.
void paintBeautyStillLife(Canvas canvas, Size size, {required bool dark}) {
  final w = size.width;
  final h = size.height;
  if (w <= 0 || h <= 0) return;

  final base = dark ? StillLifePalette.inkDark : StillLifePalette.inkLight;
  final fillAlpha = dark ? 0.04 : 0.028;
  final edgeAlpha = dark ? 0.10 : 0.07;
  final shineAlpha = dark ? 0.14 : 0.5;
  // One unit is a fraction of the shorter side, so phones and tablets get
  // objects of the same visual weight.
  final u = math.min(w, h);

  void place(
    void Function(_Glass g) draw, {
    required double x,
    required double y,
    required double height,
    required double turnDegrees,
  }) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(turnDegrees * math.pi / 180);
    canvas.scale(height);
    draw(_Glass(canvas, base, fillAlpha, edgeAlpha, shineAlpha, 1 / height));
    canvas.restore();
  }

  // Corners and edges only, small enough to read as texture rather than as
  // pictures, each partly cropped by the screen edge. Six objects - more, and
  // an empty screen starts to look like wallpaper (design review 14 Oct 2026).
  place(_perfume, x: w - u * 0.07, y: h * 0.07, height: u * 0.26, turnDegrees: 14);
  place(_brush, x: w + u * 0.03, y: h * 0.46, height: u * 0.50, turnDegrees: 24);
  place(_mascara, x: u * 0.03, y: h * 0.34, height: u * 0.28, turnDegrees: 16);
  place(_lipstick, x: u * 0.08, y: h * 0.80, height: u * 0.26, turnDegrees: -22);
  place(_scissors, x: w * 0.46, y: h - u * 0.20, height: u * 0.22, turnDegrees: -28);
  place(_polish, x: w - u * 0.10, y: h * 0.86, height: u * 0.20, turnDegrees: 10);
}

/// Paints one glass shape: a faint fill graded top-left to bottom-right, a
/// hairline edge, and a highlight along the upper-left of the object.
class _Glass {
  _Glass(this.canvas, this.base, this.fillAlpha, this.edgeAlpha, this.shineAlpha, this.px);

  final Canvas canvas;
  final Color base;
  final double fillAlpha;
  final double edgeAlpha;
  final double shineAlpha;

  /// One screen pixel, in this object's unit space - keeps hairlines hairline.
  final double px;

  void shape(Path p, {double weight = 1}) {
    final b = p.getBounds();
    canvas.drawPath(
      p,
      Paint()
        ..shader = ui.Gradient.linear(b.topLeft, b.bottomRight, [
          base.withValues(alpha: fillAlpha * 1.5 * weight),
          base.withValues(alpha: fillAlpha * 0.6 * weight),
        ]),
    );
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px * 1.2
        ..color = base.withValues(alpha: edgeAlpha * weight),
    );
  }

  void line(Path p, {double width = 1.2}) {
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px * width
        ..strokeCap = StrokeCap.round
        ..color = base.withValues(alpha: edgeAlpha),
    );
  }

  /// The catch-light: a soft white stroke, strongest in its middle.
  void shine(Offset a, Offset b) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = px * 3
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(a, b, [
          StillLifePalette.shine.withValues(alpha: 0),
          StillLifePalette.shine.withValues(alpha: shineAlpha),
          StillLifePalette.shine.withValues(alpha: 0),
        ], [0, 0.5, 1]),
    );
  }
}

Path _rrect(double l, double t, double r, double b, double radius) =>
    Path()..addRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(radius)));

// Each object is drawn in a unit box: x from about -0.25 to 0.25, y from 0
// (top) to 1 (bottom), origin at its top centre.

void _lipstick(_Glass g) {
  // Case, metal band, then the slanted bullet.
  g.shape(_rrect(-0.16, 0.48, 0.16, 1.0, 0.04));
  g.shape(_rrect(-0.13, 0.36, 0.13, 0.48, 0.02), weight: 1.3);
  g.shape(
    Path()
      ..moveTo(-0.10, 0.36)
      ..lineTo(-0.10, 0.10)
      ..quadraticBezierTo(-0.06, 0.02, 0.10, 0.0)
      ..lineTo(0.10, 0.36)
      ..close(),
    weight: 1.4,
  );
  g.shine(const Offset(-0.11, 0.55), const Offset(-0.11, 0.95));
}

void _brush(_Glass g) {
  // A fan of bristles, the ferrule, a long tapering handle.
  g.shape(
    Path()
      ..moveTo(-0.03, 0.30)
      ..quadraticBezierTo(-0.20, 0.14, -0.11, 0.0)
      ..quadraticBezierTo(0.0, -0.05, 0.11, 0.0)
      ..quadraticBezierTo(0.20, 0.14, 0.03, 0.30)
      ..close(),
    weight: 1.3,
  );
  g.shape(_rrect(-0.045, 0.30, 0.045, 0.42, 0.015), weight: 1.4);
  g.shape(
    Path()
      ..moveTo(-0.04, 0.42)
      ..lineTo(0.04, 0.42)
      ..lineTo(0.018, 1.0)
      ..quadraticBezierTo(0.0, 1.02, -0.018, 1.0)
      ..close(),
  );
  for (final dx in [-0.06, 0.0, 0.06]) {
    g.line(Path()
      ..moveTo(dx * 0.4, 0.28)
      ..lineTo(dx, 0.04));
  }
  g.shine(const Offset(-0.02, 0.48), const Offset(-0.008, 0.9));
}

void _polish(_Glass g) {
  // A tall cap on a rounded glass bottle.
  g.shape(_rrect(-0.07, 0.0, 0.07, 0.42, 0.03), weight: 1.4);
  g.shape(_rrect(-0.10, 0.40, 0.10, 0.48, 0.02), weight: 1.2);
  g.shape(_rrect(-0.22, 0.48, 0.22, 1.0, 0.10));
  g.shine(const Offset(-0.15, 0.58), const Offset(-0.15, 0.90));
}

void _perfume(_Glass g) {
  // A round cap, a short neck, a faceted body.
  g.shape(Path()..addOval(Rect.fromCircle(center: const Offset(0, 0.10), radius: 0.10)), weight: 1.3);
  g.shape(_rrect(-0.05, 0.19, 0.05, 0.30, 0.01), weight: 1.4);
  g.shape(
    Path()
      ..moveTo(-0.20, 0.30)
      ..lineTo(0.20, 0.30)
      ..lineTo(0.28, 0.48)
      ..lineTo(0.28, 0.92)
      ..quadraticBezierTo(0.28, 1.0, 0.20, 1.0)
      ..lineTo(-0.20, 1.0)
      ..quadraticBezierTo(-0.28, 1.0, -0.28, 0.92)
      ..lineTo(-0.28, 0.48)
      ..close(),
  );
  g.line(Path()
    ..moveTo(-0.28, 0.48)
    ..lineTo(0.28, 0.48));
  g.shine(const Offset(-0.20, 0.54), const Offset(-0.20, 0.92));
}

void _scissors(_Glass g) {
  // Two finger rings and two crossed blades.
  g.shape(Path()..addOval(Rect.fromCircle(center: const Offset(-0.13, 0.82), radius: 0.12)));
  g.shape(Path()..addOval(Rect.fromCircle(center: const Offset(0.13, 0.82), radius: 0.12)));
  g.shape(
    Path()
      ..moveTo(-0.07, 0.72)
      ..lineTo(0.06, 0.0)
      ..lineTo(0.10, 0.04)
      ..lineTo(0.0, 0.70)
      ..close(),
    weight: 1.3,
  );
  g.shape(
    Path()
      ..moveTo(0.07, 0.72)
      ..lineTo(-0.06, 0.0)
      ..lineTo(-0.10, 0.04)
      ..lineTo(0.0, 0.70)
      ..close(),
    weight: 1.3,
  );
  g.shape(Path()..addOval(Rect.fromCircle(center: const Offset(0, 0.58), radius: 0.02)), weight: 2);
}

void _mascara(_Glass g) {
  // A slim tube and its cap, the wand's bristles at the tip.
  g.shape(_rrect(-0.06, 0.0, 0.06, 0.44, 0.03), weight: 1.3);
  g.shape(_rrect(-0.07, 0.44, 0.07, 1.0, 0.035));
  g.line(Path()
    ..moveTo(-0.07, 0.44)
    ..lineTo(0.07, 0.44));
  g.shine(const Offset(-0.035, 0.52), const Offset(-0.035, 0.94));
}
