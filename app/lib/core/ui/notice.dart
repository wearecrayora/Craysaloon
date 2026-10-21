import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/cray_glass.dart';

/// What a notice is saying - which picks its icon. The icon colours are the
/// fixed status colours, never the salon's (DESIGN 3.1).
enum NoticeKind { done, info, problem }

/// A short pop-up at the bottom of the screen: "Saved", "Your bill is ready",
/// "Couldn't reach the salon". Floats above the bottom bar, in the thumb's
/// zone, says one thing, and goes away on its own.
///
/// Never a modal: nothing the person was doing is interrupted (DESIGN 6.8).
/// A screen reader announces it, as a SnackBar always is.
void showNotice(
  BuildContext context,
  String message, {
  NoticeKind kind = NoticeKind.done,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.maybeOf(context)?.notice(
    message,
    kind: kind,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// The same pop-up, from a messenger captured before an `await` - the way a
/// screen must hold it once it may have been closed by the time a call returns.
extension NoticeMessenger on ScaffoldMessengerState {
  void notice(
    String message, {
    NoticeKind kind = NoticeKind.done,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final g = CrayGlass.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, colour) = switch (kind) {
      NoticeKind.done => (Icons.check_circle_rounded, g.success),
      NoticeKind.info => (Icons.notifications_active_outlined, scheme.onSurface),
      NoticeKind.problem => (Icons.error_outline_rounded, scheme.error),
    };
    // A small physical "this happened" on the phones that have it.
    if (kind == NoticeKind.problem) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    this
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              Icon(icon, color: colour),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          action: actionLabel == null
              ? null
              : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
        ),
      );
  }
}
