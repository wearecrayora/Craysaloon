import 'package:flutter/material.dart';

/// The motion tokens of `DESIGN.md` 7.1, in one place, so a screen asks for
/// "standard" rather than inventing 180ms.
///
/// No bounce, no elastic, no overshoot - the two curves below are the only
/// curves the app uses, and both settle without passing their target.
abstract final class Motion {
  static const micro = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 220);
  static const large = Duration(milliseconds: 280);

  /// What reduced motion falls back to: a short fade, never nothing - a state
  /// change with no acknowledgement reads as a failed tap (7.4).
  static const reduced = Duration(milliseconds: 100);

  static const enter = Cubic(0.2, 0, 0, 1);
  static const exit = Cubic(0.3, 0, 1, 1);

  /// Exits are always faster than entrances (×0.8).
  static Duration exitOf(Duration d) => d * 0.8;

  static bool isReduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or the reduced-motion fade when the person asked for less motion.
  static Duration of(BuildContext context, Duration d) =>
      isReduced(context) ? reduced : d;
}

/// The page transition (`DESIGN.md` 7.1 "large"): the new page fades in while
/// rising from a short way to the right, and the page beneath recedes a little
/// and dims. A sense of going forward - not a slide across the whole screen,
/// and no zoom, which on a budget phone costs a frame on the first paint.
///
/// Reduced motion: a 100ms cross-fade, nothing moves.
class CrayPageTransitionsBuilder extends PageTransitionsBuilder {
  const CrayPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Motion.large;

  @override
  Duration get reverseTransitionDuration => Motion.exitOf(Motion.large);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.isReduced(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final enter = CurvedAnimation(
      parent: animation,
      curve: Motion.enter,
      reverseCurve: Motion.exit,
    );
    final under = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Motion.enter,
      reverseCurve: Motion.exit,
    );
    return SlideTransition(
      position: Tween(
        begin: Offset.zero,
        end: const Offset(-0.04, 0),
      ).animate(under),
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.6).animate(under),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(enter),
          child: FadeTransition(opacity: enter, child: child),
        ),
      ),
    );
  }
}
