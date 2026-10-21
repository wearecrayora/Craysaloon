import 'package:flutter/material.dart';

import '../theme/cray_glass.dart';
import 'glass.dart';

/// One thing a person can do, as a tile: an icon in a soft square, its name
/// underneath (decided 21 Oct 2026, "menus you can see").
///
/// This is the action itself, not decoration over a heading (DESIGN 14): the
/// whole tile is the button, at least 88dp tall, and the icon always travels
/// with its label (DESIGN 10). The square wears the salon's soft container
/// colour with its computed ink - the same pair the bottom bar uses for the
/// page you are on - so it is brand on an action, never on a surface.
class ActionTile extends StatelessWidget {
  const ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// A short count or word on the corner - "1" bill to pay. Null for none.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final g = CrayGlass.of(context);

    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: Semantics(
        label: badge == null ? label : '$label, $badge',
        excludeSemantics: true,
        button: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(g.radius + 4),
                      border: Border.all(color: g.line),
                      boxShadow: g.shadows,
                    ),
                    child: Icon(icon, color: scheme.onPrimaryContainer, size: 28),
                  ),
                  if (badge != null)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: _Badge(badge!),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text.labelMedium?.copyWith(color: scheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        // Something is waiting: the fixed status colour, not the brand.
        color: scheme.error,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onError,
        ),
      ),
    );
  }
}

/// A grid of [ActionTile]s, four across - the shortest reach to every option on
/// a phone held in one hand. Shrinks to three on a narrow screen or very large
/// text, so a label never has to squeeze.
class ActionGrid extends StatelessWidget {
  const ActionGrid({required this.tiles, super.key});

  final List<ActionTile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final across = constraints.maxWidth < 340 || scale > 1.3 ? 3 : 4;
        final width = (constraints.maxWidth - 8 * (across - 1)) / across;
        return Wrap(
          spacing: 8,
          runSpacing: 16,
          children: [
            for (final t in tiles) SizedBox(width: width, child: t),
          ],
        );
      },
    );
  }
}

/// A section heading with an optional trailing link ("See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.action, this.onAction, super.key});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: text.titleLarge),
            ),
          ),
          if (action != null)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onAction,
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}
