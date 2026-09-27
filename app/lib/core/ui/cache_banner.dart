import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

/// "Shown from this device, last updated …".
///
/// Cached rows are LABELLED, never passed off as live (`ARCHITECTURE.md` 10.2).
/// A list that quietly serves week-old data looks identical to a live one, and
/// the owner finds out it was stale by making a decision on it.
class CacheBanner extends StatelessWidget {
  const CacheBanner({this.refreshedAt, super.key});

  final DateTime? refreshedAt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              refreshedAt == null
                  ? l10n.cachedNeverLoaded
                  : l10n.cachedAsOf(DateFormat.yMMMd().add_jm().format(refreshedAt!)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
