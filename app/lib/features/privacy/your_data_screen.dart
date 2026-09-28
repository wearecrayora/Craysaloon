import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/privacy/privacy.dart';
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';
import 'consent_notice.dart';
import 'your_data_controller.dart';

/// One screen for every right the DPDP Act gives a customer.
///
/// The Act's test for withdrawal is that it must be **as easy as consent was**
/// (s.6(4)). Consent was four taps on the join screen, so withdrawal is one tap
/// here - no email to find, no form, no "contact us to unsubscribe". Access
/// (s.11), erasure (s.12(3)) and grievance (s.13) are buttons on the same
/// screen, each showing the date it was asked and the date an answer is due,
/// because an obligation with a visible clock is the one that gets met.
///
/// It is reachable from the customer's home screen. Not in a settings menu
/// three levels down: a right nobody can find is a right nobody has.
class YourDataScreen extends ConsumerWidget {
  const YourDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(yourDataControllerProvider);
    final branding = ref.watch(resolvedBrandingProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.yourDataTitle)),
      body: SafeArea(
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => ref.read(yourDataControllerProvider.notifier).load(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (state.message != null) _Message(state.message!),
                    if (state.failed)
                      // Not "everything is off": that would be a false statement
                      // about a legal record. The screen says it could not read
                      // them and offers a retry.
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          l10n.consentSaveFailed,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      )
                    else ...[
                      Text(
                        l10n.yourDataConsentsHeading,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const _ConsentRow(
                        purpose: ConsentPurpose.service,
                        locked: true,
                      ),
                      const _ConsentRow(purpose: ConsentPurpose.promotional),
                      const _ConsentRow(purpose: ConsentPurpose.whatsapp),
                      const _ConsentRow(purpose: ConsentPurpose.photos),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      l10n.yourDataRightsHeading,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const _RightTile(kind: 'access'),
                    const _RightTile(kind: 'grievance'),
                    // Erasure asks first, and says what erasure actually does
                    // before it happens rather than after (RULES 11.8).
                    const _RightTile(kind: 'erasure', confirm: true),
                    const SizedBox(height: 24),
                    Text(
                      l10n.yourDataFiduciaryHeading,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ConsentNotice(
                      salonName: branding?.displayName ?? '',
                      grievance: branding?.grievance,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.message);

  final YourDataMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = switch (message) {
      YourDataMessage.serviceRequired => l10n.consentServiceLocked,
      YourDataMessage.saveFailed => l10n.consentSaveFailed,
      YourDataMessage.requestSent => l10n.rightAskedThanks,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _ConsentRow extends ConsumerWidget {
  const _ConsentRow({required this.purpose, this.locked = false});

  final String purpose;

  /// `service_communication` is the service itself. Shown, explained, and not
  /// offered as a switch - the way out is erasure, which is on this screen.
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(yourDataControllerProvider);
    final granted = state.consents[purpose] ?? false;

    final title = switch (purpose) {
      ConsentPurpose.service => l10n.consentServiceTitle,
      ConsentPurpose.promotional => l10n.consentPromotionalTitle,
      ConsentPurpose.whatsapp => l10n.consentWhatsappTitle,
      _ => l10n.consentPhotosTitle,
    };
    final subtitle = switch (purpose) {
      ConsentPurpose.service => l10n.consentServiceLocked,
      ConsentPurpose.photos => l10n.consentPhotosSubtitle,
      _ => null,
    };

    return SwitchListTile(
      value: locked ? true : granted,
      // Disabled, not hidden: someone looking for the messages they get should
      // find them here, with the reason, rather than conclude the app forgot.
      onChanged: locked || state.busyPurpose == purpose
          ? null
          : (value) =>
              ref.read(yourDataControllerProvider.notifier).setConsent(purpose, value),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _RightTile extends ConsumerWidget {
  const _RightTile({required this.kind, this.confirm = false});

  final String kind;
  final bool confirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(yourDataControllerProvider);
    final existing = state.openRequest(kind);

    final title = switch (kind) {
      'access' => l10n.rightAccessTitle,
      'erasure' => l10n.rightErasureTitle,
      _ => l10n.rightGrievanceTitle,
    };

    // Already asked: the tile stops being a button and starts being a receipt.
    // Offering it again would invite a queue of duplicates the salon then has
    // to work through, and tell the customer nothing about their first request.
    if (existing != null) {
      final asked = _date(context, existing.requestedAt);
      final due = _date(context, existing.dueAt);
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(
          existing.outcome != null
              ? l10n.rightAnswered(existing.outcome!)
              : l10n.rightAsked(asked, due),
        ),
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: state.busyPurpose == kind
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: state.busyPurpose == kind
          ? null
          : () async {
              if (confirm && !await _confirmed(context)) return;
              await ref.read(yourDataControllerProvider.notifier).request(kind);
            },
    );
  }

  Future<bool> _confirmed(BuildContext context) async {
    final l10n = AppL10n.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.erasureConfirmTitle),
        content: Text(l10n.erasureConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.erasureConfirmAction),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  static String _date(BuildContext context, DateTime when) =>
      MaterialLocalizations.of(context).formatShortDate(when);
}
