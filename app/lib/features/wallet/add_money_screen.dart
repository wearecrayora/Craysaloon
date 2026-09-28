import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../../core/platform/payment_sheet.dart';
import '../../data/local/outbox.dart';
import '../../domain/wallet/wallet.dart';
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';
import 'wallet_controller.dart';

final paymentSheetProvider =
    Provider<PaymentSheet>((ref) => const UnavailablePaymentSheet());

/// The amounts offered, in paise. Round numbers a customer would hand over at a
/// counter; the field below them takes anything the salon allows.
const _packs = [50000, 100000, 200000, 500000];

/// C3 — Add Money.
///
/// The disclosure block above the pay button is a **legal requirement, not
/// polish** (RULES 5.3.6, DESIGN 6.2, PHASES: it ships with M7). It states the
/// bonus, the bonus expiry date, that paid credit never expires, that the credit
/// is usable only at this salon, and that it cannot be taken out as cash. Body
/// size. Not collapsed. Not behind a link. Nothing here may be moved into a
/// tooltip to tidy the screen up.
///
/// Every number on it comes from `topup_quote` on the server, which shares its
/// arithmetic with the function that issues the credit - so the screen cannot
/// promise a bonus the ledger would refuse.
class AddMoneyScreen extends ConsumerStatefulWidget {
  const AddMoneyScreen({super.key});

  @override
  ConsumerState<AddMoneyScreen> createState() => _AddMoneyScreenState();
}

class _AddMoneyScreenState extends ConsumerState<AddMoneyScreen> {
  final _controller = TextEditingController();
  int _amountPaise = _packs[1];
  bool _paying = false;
  String? _message;

  /// Created ONCE per intent, not once per attempt: retrying a payment that
  /// timed out must reach the same payment row and the same Razorpay order.
  /// Changing the amount is a different intent, so it clears.
  String? _actionId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _choose(int paise) {
    setState(() {
      _amountPaise = paise;
      _controller.text = (paise ~/ 100).toString();
      _message = null;
      _actionId = null;
    });
  }

  Future<void> _pay(TopupQuote quote, String salonName) async {
    final api = ref.read(walletApiProvider);
    if (api == null || _paying) return;

    setState(() {
      _paying = true;
      _message = null;
    });

    final l10n = AppL10n.of(context);
    try {
      // The action id makes the tap idempotent: a retry reaches the same
      // payment and the same order, never a second way to pay (RULES 9.3).
      final actionId = _actionId ??= Outbox.newActionId();
      final order = await api.startTopup(
        clientActionId: actionId,
        amountPaise: _amountPaise,
      );

      final outcome =
          await ref.read(paymentSheetProvider).open(order, salonName: salonName);

      if (!mounted) return;
      setState(() {
        _message = switch (outcome) {
          // Never "paid". The credit follows Razorpay's webhook, verified
          // against this salon's own secret - not this screen's opinion.
          PaymentOutcome.submitted => l10n.addMoneySubmitted,
          PaymentOutcome.cancelled => l10n.addMoneyCancelled,
          PaymentOutcome.failed => l10n.addMoneyFailed,
          PaymentOutcome.unavailable => l10n.addMoneyCheckoutNotReady,
        };
      });
      if (outcome == PaymentOutcome.submitted) ref.invalidate(walletProvider);
    } on TopupException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = switch (e.problem) {
          TopupProblem.belowMinimum =>
            l10n.addMoneyBelowMinimum(rupees(e.minTopupPaise ?? 0)),
          TopupProblem.invalidAmount => l10n.addMoneyInvalid,
          TopupProblem.paymentsUnavailable => l10n.addMoneyUnavailable,
          TopupProblem.salonUnavailable => l10n.joinSalonUnavailable,
          TopupProblem.network => l10n.joinOffline,
        };
      });
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final salonName = ref.watch(resolvedBrandingProvider)?.displayName ?? '';
    final quote = ref.watch(topupQuoteProvider(_amountPaise));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.addMoneyTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.addMoneyAmount, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pack in _packs)
                  ChoiceChip(
                    selected: _amountPaise == pack,
                    onSelected: (_) => _choose(pack),
                    label: Text(rupees(pack)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(prefixText: '₹ '),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) {
                final rupeesTyped = int.tryParse(value) ?? 0;
                setState(() {
                  _amountPaise = rupeesTyped * 100;
                  _message = null;
                  _actionId = null;
                });
              },
            ),
            const SizedBox(height: 24),

            // ---------------------------------------------------------------
            // The disclosure block. Above the pay button, always visible.
            // ---------------------------------------------------------------
            switch (quote) {
              AsyncData(:final value) =>
                _Disclosure(quote: value, salonName: salonName),
              AsyncError() => Text(l10n.joinOffline,
                  style: Theme.of(context).textTheme.bodyMedium),
              _ => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                ),
            },

            const SizedBox(height: 24),
            FilledButton(
              // Disabled until the server has priced it. A pay button that can
              // be pressed before the disclosure is on screen is a pay button
              // pressed without the disclosure.
              onPressed: _paying || quote.value == null || _amountPaise <= 0
                  ? null
                  : () => _pay(quote.value!, salonName),
              child: Text(_paying ? '…' : l10n.addMoneyPay(rupees(_amountPaise))),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _Disclosure extends StatelessWidget {
  const _Disclosure({required this.quote, required this.salonName});

  final TopupQuote quote;
  final String salonName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    // Body size, not caption (DESIGN 6.2). Small print is how a disclosure
    // becomes a formality.
    final style = Theme.of(context).textTheme.bodyMedium;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.addMoneyDisclosureHeading,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              quote.hasBonus
                  ? l10n.addMoneyBonusYouGet(rupees(quote.bonusPaise))
                  : l10n.addMoneyNoBonus,
              style: style,
            ),
            if (quote.hasBonus && quote.bonusExpiresAt != null) ...[
              const SizedBox(height: 4),
              Text(
                l10n.addMoneyBonusExpires(
                  rupees(quote.bonusPaise),
                  MaterialLocalizations.of(context)
                      .formatShortDate(quote.bonusExpiresAt!),
                ),
                style: style,
              ),
            ],
            const SizedBox(height: 4),
            Text(l10n.addMoneyPaidNeverExpires, style: style),
            const SizedBox(height: 4),
            Text(l10n.walletOnlyAtSalon(salonName), style: style),
            const SizedBox(height: 4),
            Text(l10n.addMoneyNotRefundable, style: style),
          ],
        ),
      ),
    );
  }
}
