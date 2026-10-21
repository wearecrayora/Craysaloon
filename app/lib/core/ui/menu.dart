import 'package:flutter/material.dart';

import 'glass.dart';

/// A round mark with someone's initials - the salon's soft container, its
/// computed ink. A person icon when there is no name yet.
class Initials extends StatelessWidget {
  const Initials(this.initials, {this.size = 48, super.key});

  final String? initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = (size >= 64
            ? Theme.of(context).textTheme.headlineSmall
            : Theme.of(context).textTheme.titleMedium)
        ?.copyWith(color: scheme.onPrimaryContainer);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
        child: initials == null
            ? Icon(Icons.person_outline, color: scheme.onPrimaryContainer, size: size / 2)
            : Text(initials!, style: style, maxLines: 1),
      ),
    );
  }
}

/// A labelled group of menu rows on one glass card.
class MenuSection extends StatelessWidget {
  const MenuSection({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1, indent: 64));
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(children: rows),
        ),
      ],
    );
  }
}

/// One menu row: its icon in a small soft square, a title, one line on what
/// is behind it, a chevron. The whole row is the target (56dp+).
class MenuRow extends StatelessWidget {
  const MenuRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    if (subtitle != null) Text(subtitle!, style: text.bodySmall),
                  ],
                ),
              ),
              trailing ?? const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

