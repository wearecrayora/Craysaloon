import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/money.dart';
import '../../domain/wallet/wallet.dart';
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';
import 'wallet_controller.dart';

/// C2 — the wallet.
///
/// Two rules from `DESIGN.md` 6.1-6.2 shape it: **never show a balance alone**
/// (it always carries "usable only at this salon, not withdrawable as cash"),
/// and **never animate a money value**. The number appears; it does not count
/// up. A balance that moves is a balance somebody watches instead of trusts.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final salonName = ref.watch(resolvedBrandingProvider)?.displayName ?? '';
    final view = ref.watch(walletProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.walletTitle)),
      body: SafeArea(
        child: switch (view) {
          AsyncData(:final value) => RefreshIndicator(
              onRefresh: () async => ref.invalidate(walletProvider),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _BalanceCard(summary: value.summary, salonName: salonName),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.push('/wallet/add'),
                    child: Text(l10n.walletAddMoney),
                  ),
                  const SizedBox(height: 32),
                  Text(l10n.walletHistoryHeading,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (value.history.isEmpty)
                    Text(l10n.walletHistoryEmpty,
                        style: Theme.of(context).textTheme.bodyMedium)
                  else
                    for (final entry in value.history) _EntryRow(entry),
                ],
              ),
            ),
          // Money is never served stale. Offline, this says so (RULES 5).
          AsyncError() => _Failed(onRetry: () => ref.invalidate(walletProvider)),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary, required this.salonName});

  final WalletSummary summary;
  final String salonName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.walletBalance, style: text.labelLarge),
            const SizedBox(height: 4),
            Text(
              rupees(summary.balancePaise),
              // Tabular figures, and no animation, ever (DESIGN 6.1).
              style: text.headlineMedium?.copyWith(fontFeatures: moneyFeatures),
            ),
            const SizedBox(height: 8),
            // A balance is never shown alone.
            Text(l10n.walletOnlyAtSalon(salonName), style: text.bodySmall),
            const SizedBox(height: 16),
            // Paid and bonus, separately: the summary is one number, the detail
            // is honest (DESIGN 6.2).
            _Line(label: l10n.walletPaidLabel, paise: summary.paidPaise),
            _Line(label: l10n.walletBonusLabel, paise: summary.bonusPaise),
            Text(l10n.addMoneyPaidNeverExpires, style: text.bodySmall),
            if (summary.nextBonusExpiry case final expiry?
                when summary.nextBonusPaise > 0) ...[
              const SizedBox(height: 4),
              Text(
                l10n.walletBonusExpiryNote(
                  rupees(summary.nextBonusPaise),
                  MaterialLocalizations.of(context).formatShortDate(expiry),
                ),
                style: text.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.paise});

  final String label;
  final int paise;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // At 200% text scale a fixed pair overflows, and the thing that gets
          // clipped is the amount (DESIGN 13). The label yields; the money does
          // not.
          Flexible(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(rupees(paise), style: style?.copyWith(fontFeatures: moneyFeatures)),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow(this.entry);

  final WalletEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final label = switch (entry.kind) {
      'credit_topup' => l10n.entryTopUp,
      'credit_bonus' => l10n.entryBonus,
      'debit_spend' => l10n.entrySpend,
      'debit_expiry' => l10n.entryExpiry,
      'credit_reversal' => l10n.entryReversal,
      'credit_referral' => l10n.entryReferral,
      _ => l10n.entryCorrection,
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        entry.reason ??
            MaterialLocalizations.of(context).formatShortDate(entry.createdAt),
        style: text.bodySmall,
      ),
      trailing: Text(
        // The sign is the ledger's, shown as it is stored. A debit that reads
        // as a positive number is how a statement stops being checkable.
        '${entry.amountPaise > 0 ? '+' : ''}${rupees(entry.amountPaise)}',
        style: text.bodyMedium?.copyWith(fontFeatures: moneyFeatures),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.joinOffline, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}
