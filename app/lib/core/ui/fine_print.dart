import 'package:flutter/material.dart';

import '../../features/privacy/consent_notice.dart' show NoticeLink;
import '../../l10n/app_localizations.dart';
import '../platform/external_link.dart';

/// The published pages - terms, privacy, refunds, who runs the app - and the
/// licences of everything the app is built from, in one place at the foot of
/// Me (customer) and More (salon). The same links the join site carries.
class FinePrint extends StatelessWidget {
  const FinePrint({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final link = text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.primary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.meLegalHeading, style: text.titleSmall),
        const SizedBox(height: 4),
        NoticeLink(label: l10n.linkTerms, url: termsUrl, style: link),
        NoticeLink(
          label: l10n.linkPrivacy,
          url: privacyPolicyUrlFor(Localizations.localeOf(context)),
          style: link,
        ),
        NoticeLink(label: l10n.linkRefunds, url: refundsUrl, style: link),
        NoticeLink(label: l10n.linkAbout, url: aboutUrl, style: link),
        InkWell(
          onTap: () => showLicensePage(context: context, applicationName: l10n.meAppBy),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(l10n.linkLicences, style: link),
          ),
        ),
      ],
    );
  }
}
