import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// What a screen shows when its read failed: what happened, in words, and the
/// one thing to do about it. Never a bare "Try again" with no reason, and never
/// text that runs to the edge of the glass.
///
/// [inline] for a section inside a scrolling page (the page already has its
/// gutters); otherwise it centres itself on the whole screen.
class LoadFailed extends StatelessWidget {
  const LoadFailed({
    required this.onRetry,
    this.message,
    this.inline = false,
    super.key,
  });

  final VoidCallback onRetry;
  final String? message;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: inline
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        if (!inline) ...[
          Icon(
            Icons.cloud_off_outlined,
            size: 32,
            color: text.bodySmall?.color,
          ),
          const SizedBox(height: 12),
        ],
        Text(
          message ?? l10n.joinOffline,
          style: text.bodyLarge,
          textAlign: inline ? TextAlign.start : TextAlign.center,
        ),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onRetry, child: Text(l10n.retry)),
      ],
    );
    if (inline) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: body,
      );
    }
    // Scrolls, so at 200% text on a short phone it never clips (the sweep).
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: body,
      ),
    );
  }
}
