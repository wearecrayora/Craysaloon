import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/load_failed.dart';
import '../../core/ui/skeleton.dart';
import '../../domain/privacy/privacy.dart';
import '../customer/customer_providers.dart' show myProfileProvider;
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';
import 'consent_notice.dart';
import 'nominee_card.dart';
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
            ? const SkeletonList(padding: EdgeInsets.all(16))
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(yourDataControllerProvider.notifier).load(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (state.message != null) _Message(state.message!),
                    if (state.failed)
                      // Not "everything is off": that would be a false statement
                      // about a legal record. The screen says it could not read
                      // them and offers a retry.
                      // The fixed danger red marks it on the icon; the words
                      // stay in the readable ink - red text on the glass read
                      // 4.4:1, under the 4.5:1 a sentence needs (the sweep).
                      LoadFailed(
                        inline: true,
                        message: l10n.yourDataLoadFailed,
                        onRetry: () => ref
                            .read(yourDataControllerProvider.notifier)
                            .load(),
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
                      // Not offered while WhatsApp is off (0108) - but still
                      // here for anyone who gave it, so they can take it back.
                      if (kWhatsappOffers || (state.consents[ConsentPurpose.whatsapp] ?? false))
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
                    // DPDP s.14: someone to use these rights if the customer
                    // cannot (0112).
                    const NomineeCard(),
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
    // Under 18: offers, reminders and photos cannot be switched on (0110,
    // 0112, DPDP s.9).
    // Switching them OFF is always allowed - withdrawal is never locked.
    final minor = ref.watch(myProfileProvider).value?.isMinor ?? false;
    final childLocked = minor &&
        !granted &&
        (purpose == ConsentPurpose.promotional ||
            purpose == ConsentPurpose.whatsapp ||
            purpose == ConsentPurpose.photos);

    final title = switch (purpose) {
      ConsentPurpose.service => l10n.consentServiceTitle,
      ConsentPurpose.promotional => l10n.consentPromotionalTitle,
      ConsentPurpose.whatsapp => l10n.consentWhatsappTitle,
      _ => l10n.consentPhotosTitle,
    };
    final subtitle = childLocked ? l10n.consentMinorLocked : switch (purpose) {
      ConsentPurpose.service => l10n.consentServiceLocked,
      ConsentPurpose.photos => l10n.consentPhotosSubtitle,
      _ => null,
    };

    return SwitchListTile(
      value: locked ? true : granted,
      // Disabled, not hidden: someone looking for the messages they get should
      // find them here, with the reason, rather than conclude the app forgot.
      onChanged: locked || childLocked || state.busyPurpose == purpose
          ? null
          : (value) => ref
                .read(yourDataControllerProvider.notifier)
                .setConsent(purpose, value),
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
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
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
