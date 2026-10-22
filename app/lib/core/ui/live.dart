import 'package:flutter/material.dart';

import '../theme/cray_glass.dart';
import '../theme/motion.dart';

/// The "live" dot of a delivery tracker: a solid dot with a ring that swells
/// and fades - "this is happening now". For a booking that is today.
///
/// It pings three times when it appears and then rests, solid: a ring that
/// pulses forever competes with everything else on the screen and costs a
/// budget phone its battery (DESIGN 7.4). With reduced motion it is simply
/// the dot.
class LiveDot extends StatefulWidget {
  const LiveDot({this.size = 10, this.colour, super.key});

  final double size;
  final Color? colour;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  int _pings = 0;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && ++_pings < 3) _c.forward(from: 0);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Motion.isReduced(context) && _pings == 0 && !_c.isAnimating) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour = widget.colour ?? CrayGlass.of(context).success;
    final s = widget.size;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: s * 2.4,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Motion.enter.transform(_c.value);
            return Stack(
              alignment: Alignment.center,
              children: [
                if (_c.isAnimating)
                  Container(
                    width: s * (1 + 1.4 * t),
                    height: s * (1 + 1.4 * t),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colour.withValues(alpha: 0.35 * (1 - t)),
                    ),
                  ),
                Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A step tracker, as a food app shows an order's journey: the steps done are
/// filled, the current one is live, the rest are waiting. Each is a word, never
/// colour alone (DESIGN 3.4); the line between steps fills as it moves on.
class StepTracker extends StatelessWidget {
  const StepTracker({required this.steps, required this.current, super.key});

  final List<String> steps;

  /// Index of the step happening now. Steps before it are done; equal to the
  /// number of steps, everything is done.
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final g = CrayGlass.of(context);
    return Semantics(
      label: current < steps.length
          ? '${steps[current]} (${current + 1}/${steps.length})'
          : steps.last,
      excludeSemantics: true,
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 24,
                    child: Column(
                      children: [
                        if (i == current)
                          LiveDot(size: 10, colour: g.success)
                        else
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              i < current ? Icons.check_circle : Icons.circle_outlined,
                              size: 16,
                              color: i < current ? g.success : scheme.outline,
                            ),
                          ),
                        if (i < steps.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              constraints: const BoxConstraints(minHeight: 16),
                              color: i < current ? g.success : scheme.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        steps[i],
                        style: (i == current ? text.titleMedium : text.bodyMedium)?.copyWith(
                          color: i > current ? text.bodySmall?.color : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
