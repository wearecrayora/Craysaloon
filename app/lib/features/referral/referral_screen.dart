import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/join/join_code.dart';
import '../../domain/join/join_link.dart';
import '../../domain/referral/referral.dart';
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';

final referralApiProvider = Provider<ReferralApi?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is ReferralApi ? api as ReferralApi : null;
});

final referralProvider = FutureProvider<ReferralSummary>((ref) async {
  final api = ref.watch(referralApiProvider);
  if (api == null) throw const CrayApiException(CrayErrorKind.server);
  return api.referralSummary();
});

/// C11 — Refer & Earn.
///
/// The only screen that asks the customer to do something for the salon, which
/// is exactly why it has to be honest about when the reward arrives: **after
/// the friend's first completed, paid visit** (RULES 10). A screen that implies
/// "share and get ₹100" earns a complaint the first time somebody shares and
/// gets nothing, and the complaint is correct.
class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final salonName = ref.watch(resolvedBrandingProvider)?.displayName ?? '';
    final summary = ref.watch(referralProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.referTitle)),
      body: SafeArea(
        child: switch (summary) {
          AsyncData(:final value) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(referralProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l10n.referHeadline(
                    rupees(value.referredPaise),
                    rupees(value.referrerPaise),
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                // The condition, stated before the code. Not in small print
                // underneath it.
                Text(
                  l10n.referHowItWorks(salonName),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                _CodeCard(code: value.code, salonName: salonName),
                const SizedBox(height: 24),
                Text(
                  l10n.referWaiting(value.pending),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  value.rewarded == 0
                      ? l10n.referEarnedNone
                      : l10n.referEarned(
                          value.rewarded,
                          rupees(value.earnedPaise),
                        ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                // Referral credit is still credit: it never appears without
                // the two sentences that travel with every balance.
                Text(
                  l10n.referNotCash(salonName),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 32),
                const _ClaimCard(),
                const SizedBox(height: 32),
              ],
            ),
          ),
          AsyncError() => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.joinOffline),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(referralProvider),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _CodeCard extends ConsumerStatefulWidget {
  const _CodeCard({required this.code, required this.salonName});

  final String code;
  final String salonName;

  @override
  ConsumerState<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends ConsumerState<_CodeCard> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final salonCode = ref.watch(joinControllerProvider).code;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.referYourCode,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            SelectableText(
              widget.code,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                // A code that is read aloud and typed by somebody else.
                letterSpacing: 4,
                fontFeatures: moneyFeatures,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              // Not a Row: a Row here hands the button unbounded width inside
              // the card and the layout asserts.
              child: OutlinedButton.icon(
                onPressed: () async {
                  // The LINK, not the bare code: a friend who taps it lands on
                  // the salon with the code already attached, and never has to
                  // type six characters correctly.
                  // Empty until the join flow has run in this process: the
                  // salon code is not persisted, so a returning customer who
                  // has not re-entered it shares the bare code instead of a
                  // link. Both work; the link is just kinder.
                  final parsed = salonCode.isEmpty
                      ? null
                      : JoinCode.tryParse(salonCode);
                  final text = parsed == null
                      ? widget.code
                      : JoinLink.shareLink(parsed, widget.code);
                  await Clipboard.setData(ClipboardData(text: text));
                  if (mounted) setState(() => _copied = true);
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(_copied ? l10n.referCopied : l10n.referCopy),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClaimCard extends ConsumerStatefulWidget {
  const _ClaimCard();

  @override
  ConsumerState<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends ConsumerState<_ClaimCard> {
  final _controller = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final api = ref.read(referralApiProvider);
    if (api == null || _busy) return;
    final l10n = AppL10n.of(context);

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final refusal = await api.claimReferral(
        _controller.text.trim().toUpperCase(),
      );
      if (!mounted) return;
      setState(() {
        _message = switch (refusal) {
          null => l10n.referClaimed,
          ClaimRefusal.unknownCode => l10n.referClaimUnknown,
          ClaimRefusal.selfReferral => l10n.referClaimSelf,
          ClaimRefusal.alreadyReferred => l10n.referClaimAlready,
          ClaimRefusal.notNewCustomer => l10n.referClaimNotNew,
        };
      });
      if (refusal == null) ref.invalidate(referralProvider);
    } on CrayApiException {
      if (mounted) setState(() => _message = l10n.joinOffline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.referClaimTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(hintText: l10n.referClaimHint),
              inputFormatters: [
                LengthLimitingTextInputFormatter(6),
                TextInputFormatter.withFunction(
                  (_, value) => value.copyWith(text: value.text.toUpperCase()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _claim,
              child: Text(_busy ? '…' : l10n.referClaimAction),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
