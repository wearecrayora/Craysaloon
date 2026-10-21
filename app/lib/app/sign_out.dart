import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/push/push_setup.dart';
import '../domain/join/cray_api.dart';
import '../core/ui/notice.dart';
import '../features/join/join_controller.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';

/// What stands in the way of signing out, if anything.
enum SignOutBlock { none, unsentWork }

/// Unsent work on this phone - a mark-complete done offline, say. Signing out
/// with it queued would strand it, so it is said first (RULES 9.6: rejected or
/// unsent work is surfaced, never dropped).
Future<SignOutBlock> signOutBlock(WidgetRef ref) async {
  final outbox = ref.read(outboxProvider);
  if (outbox == null) return SignOutBlock.none;
  final pending = await outbox.pending(limit: 1);
  return pending.isEmpty ? SignOutBlock.none : SignOutBlock.unsentWork;
}

/// Signs this device out and leaves nothing of the salon behind on it: the
/// cached rows, the cached branding, the push token. The binding is untouched -
/// signing back in is the salon code and an OTP, into the same salon.
///
/// The session change itself moves the app to the join screen (main.dart).
Future<void> signOut(WidgetRef ref) async {
  final api = ref.read(crayApiProvider);
  await Push.forget();
  await ref.read(brandingStoreProvider).clear();
  await ref.read(cacheDbProvider).wipe();
  ref.read(resolvedBrandingProvider.notifier).clear();
  ref.invalidate(joinControllerProvider);
  if (api is SessionApi) await (api as SessionApi).signOut();
}

/// Sign out, behind a confirm sheet (DESIGN 4.3: never a one-tap surprise).
/// It ends this phone's session only; signing back in is the salon code and an
/// OTP, into the same salon.
class SignOutButton extends ConsumerWidget {
  const SignOutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
      onPressed: () => _confirm(context, ref),
      icon: const Icon(Icons.logout),
      label: Text(l10n.signOut),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    if (await signOutBlock(ref) == SignOutBlock.unsentWork) {
      if (context.mounted) showNotice(context, l10n.signOutUnsent, kind: NoticeKind.problem);
      return;
    }
    if (!context.mounted) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.signOutTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(l10n.signOutBody, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.signOut),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
              ),
            ],
          ),
        ),
      ),
    );
    if (go == true) await signOut(ref);
  }
}
