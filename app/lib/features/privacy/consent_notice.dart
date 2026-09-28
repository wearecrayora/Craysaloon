import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/external_link.dart';
import '../../domain/join/cray_api.dart';
import '../../l10n/app_localizations.dart';

/// Injected so the notice can be tested without a browser or a dialler, and so
/// iOS runs the same code path (RULES 15b).
final externalLinkProvider =
    Provider<ExternalLink>((ref) => const UrlLauncherExternalLink());

/// The notice, shown **with** the consent request (DPDP s.5).
///
/// Not behind a link, not after the fact, and not a sentence saying consent was
/// given: the Act requires the customer to be told, in plain language and in
/// their own, **what** is collected, **why**, **who** the Data Fiduciary is
/// (the salon, not Crayora), **how to withdraw**, and **who to complain to** -
/// before or at the moment they are asked. A tick-box with no notice is a
/// defect, not a shortcut (RULES 11.6a).
///
/// It appears in two places, deliberately the same widget: on the join screen
/// where consent is first asked for, and on "Your data", where someone goes to
/// change their mind. The second is where most people will actually read it.
class ConsentNotice extends ConsumerWidget {
  const ConsentNotice({
    required this.salonName,
    required this.grievance,
    this.showPolicyLink = true,
    super.key,
  });

  final String salonName;

  /// Null only for a salon activated before a privacy contact was mandatory
  /// (0053). The notice then names Crayora as the way through rather than
  /// inventing a contact, and the console flags the salon.
  final GrievanceContact? grievance;

  final bool showPolicyLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final contact = grievance;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.noticeHeading(salonName), style: text.titleMedium),
            const SizedBox(height: 8),
            _Bullet(l10n.noticeItemPhone),
            _Bullet(l10n.noticeItemVisits),
            _Bullet(l10n.noticeItemOptional),
            const SizedBox(height: 12),
            Text(l10n.noticeFiduciary(salonName), style: text.bodySmall),
            const SizedBox(height: 8),
            Text(l10n.noticeControl, style: text.bodySmall),
            const SizedBox(height: 16),
            Text(l10n.noticeContactHeading, style: text.labelLarge),
            const SizedBox(height: 4),
            if (contact == null)
              Text(l10n.noticeContactNone, style: text.bodySmall)
            else ...[
              Text(contact.name, style: text.bodyMedium),
              // Tappable, because "reachable" is the requirement and retyping an
              // address into a mail app is how a complaint quietly stops being
              // made. The address stays on screen either way.
              if (contact.email case final email? when email.isNotEmpty)
                _LinkLine(label: email, url: Uri(scheme: 'mailto', path: email)),
              if (contact.phone case final phone? when phone.isNotEmpty)
                _LinkLine(label: phone, url: Uri(scheme: 'tel', path: phone)),
            ],
            if (showPolicyLink) ...[
              const SizedBox(height: 12),
              _LinkLine(
                label: l10n.noticePolicyLink,
                url: privacyPolicyUrl,
                style: text.bodyMedium?.copyWith(color: scheme.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// A line that is both readable and openable. If nothing on the device can open
/// it, the failure is said out loud rather than swallowed - the address above it
/// is still the answer.
class _LinkLine extends ConsumerStatefulWidget {
  const _LinkLine({required this.label, required this.url, this.style});

  final String label;
  final Uri url;
  final TextStyle? style;

  @override
  ConsumerState<_LinkLine> createState() => _LinkLineState();
}

class _LinkLineState extends ConsumerState<_LinkLine> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () async {
            final opened = await ref.read(externalLinkProvider).open(widget.url);
            if (mounted) setState(() => _failed = !opened);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(widget.label, style: style),
          ),
        ),
        if (_failed)
          Text(
            AppL10n.of(context).noticeLinkFailed,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
