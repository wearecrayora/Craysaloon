import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/join/join_controller.dart';
import '../theme/cray_glass.dart';

/// The salon's logo in its app bar - or, until there is one, its initials.
///
/// The logo is the published https URL (console upload, served by the join
/// Worker). With no logo, no network, or an image that fails, it falls back to
/// a monogram in the brand's own fill, so the app bar never shows a broken
/// image or a blank square. The fill is `primary` with `onPrimary` - the one
/// pairing the publish gate has already proved legible (DESIGN 3.3).
class SalonMark extends ConsumerWidget {
  const SalonMark({this.size = 32, super.key});

  final double size;

  static String? logoOf(Map<String, Object?> document) {
    final assets = document['assets'];
    final logo = assets is Map ? assets['logo'] : null;
    return logo is String && logo.startsWith('https://') ? logo : null;
  }

  /// "Studio Nine Salon" -> "SN". One word -> its first two letters.
  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(resolvedBrandingProvider);
    final scheme = Theme.of(context).colorScheme;
    final name = branding?.displayName ?? '';
    final logo = branding == null ? null : logoOf(branding.document);
    final radius = BorderRadius.circular(size * 0.28);

    final monogram = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.primary, borderRadius: radius),
      child: Text(
        initials(name),
        style: TextStyle(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.4,
          height: 1,
        ),
      ),
    );

    return Semantics(
      image: true,
      label: name,
      child: ExcludeSemantics(
        child: logo == null
            ? monogram
            : ClipRRect(
                borderRadius: radius,
                child: Image.network(
                  logo,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => monogram,
                  // Appears when ready; no fade on a brand mark.
                  loadingBuilder: (_, child, progress) => progress == null ? child : monogram,
                ),
              ),
      ),
    );
  }
}

/// The app bar title on customer screens: the mark, then the salon's name in
/// its brand ink.
class SalonTitle extends ConsumerWidget {
  const SalonTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(resolvedBrandingProvider)?.displayName ?? '';
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SalonMark(),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: text.titleLarge?.copyWith(color: CrayGlass.of(context).ink),
          ),
        ),
      ],
    );
  }
}
