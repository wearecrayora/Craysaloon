import 'package:flutter/material.dart';

import '../theme/cray_glass.dart';

/// Loading, the way `DESIGN.md` 6.8 and 7.4 ask for it: still blocks in the
/// shape of what is coming, so the page does not jump when it arrives.
///
/// Deliberately static - no sweep, no pulse. A moving gradient across the whole
/// screen is the worst thing to run on a budget phone that is also fetching,
/// and the lint gate refuses one (GATE-4c).
///
/// Screen readers hear one "Loading" for the whole skeleton, not a list of
/// empty boxes.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    this.height = 16,
    this.width,
    this.radius = 8,
    super.key,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A row as a list shows it: a round leading mark, two lines, a trailing value.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({this.leading = true, super.key});

  final bool leading;

  @override
  Widget build(BuildContext context) {
    final g = CrayGlass.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: g.face,
        borderRadius: BorderRadius.circular(g.radius),
        border: Border.all(color: g.line),
      ),
      child: Row(
        children: [
          if (leading) ...[
            const SkeletonBlock(height: 40, width: 40, radius: 20),
            const SizedBox(width: 12),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: SkeletonBlock(height: 16),
                ),
                SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.4,
                  child: SkeletonBlock(height: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonBlock(height: 16, width: 48),
        ],
      ),
    );
  }
}

/// A list still on its way: [rows] skeleton rows, 12dp apart (DESIGN 4.1).
class SkeletonList extends StatelessWidget {
  const SkeletonList({this.rows = 4, this.leading = true, this.padding, super.key});

  final int rows;
  final bool leading;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                SkeletonRow(leading: leading),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A card-sized block, for a card that has not loaded yet.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({this.height = 120, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    final g = CrayGlass.of(context);
    return ExcludeSemantics(
      child: Container(
        height: height,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: g.face,
          borderRadius: BorderRadius.circular(g.radius),
          border: Border.all(color: g.line),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FractionallySizedBox(
              widthFactor: 0.35,
              child: SkeletonBlock(height: 12),
            ),
            SizedBox(height: 12),
            FractionallySizedBox(
              widthFactor: 0.7,
              child: SkeletonBlock(height: 24),
            ),
          ],
        ),
      ),
    );
  }
}
