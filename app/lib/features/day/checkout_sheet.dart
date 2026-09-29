import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../../domain/records/records.dart';
import '../../l10n/app_localizations.dart';
import 'day_controller.dart';

/// Taking the money for a completed visit.
///
/// The one question this sheet exists to answer truthfully is **how much cash
/// do I collect?** With the wallet paying first, that depends on a balance the
/// phone only holds a cached copy of - so the split comes from the server
/// (`checkout_quote`, 0080) and, when it cannot be fetched, the sheet says so
/// and does NOT guess. A guessed split that turned out high would have the
/// server record cash the owner never collected.
///
/// Recording is queued like mark-complete (RULES 9.5: offline records intent,
/// money moves server-side at sync). The row only reads "Paid" once the server
/// says it is.
class CheckoutSheet extends ConsumerStatefulWidget {
  const CheckoutSheet({required this.booking, super.key});

  final BookingRow booking;

  static Future<void> open(BuildContext context, BookingRow booking) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CheckoutSheet(booking: booking),
    );
  }

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  CheckoutQuote? _quote;
  bool _loading = true;
  bool _useWallet = true;
  String _method = 'cash';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final quote = await ref.read(dayControllerProvider.notifier).quote(widget.booking);
    if (!mounted) return;
    setState(() {
      _quote = quote;
      _loading = false;
      // Offline: no quote, so the wallet cannot be checked. Default to the safe
      // choice - collect the full amount - rather than a split nobody verified.
      if (quote == null) _useWallet = false;
    });
  }

  Future<void> _record() async {
    setState(() => _saving = true);
    await ref
        .read(dayControllerProvider.notifier)
        .checkout(widget.booking, useWallet: _useWallet, method: _method);
    if (!mounted) return;
    final l10n = AppL10n.of(context);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.payQueued)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final quote = _quote;

    final String collect;
    if (quote == null) {
      collect = l10n.payCollectAll(rupees(widget.booking.totalPaise));
    } else if (_useWallet && quote.fromWalletPaise > 0) {
      collect = l10n.paySplit(rupees(quote.fromWalletPaise), rupees(quote.fromCounterPaise));
    } else {
      collect = l10n.payCollectAll(rupees(quote.duePaise));
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.paySheetTitle, style: text.titleLarge),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _useWallet,
                    // Without a quote the wallet cannot be used safely - the
                    // switch is off and stays off until there is a connection.
                    onChanged: quote == null ? null : (v) => setState(() => _useWallet = v),
                    title: Text(l10n.payUseWallet),
                  ),
                  if (quote == null) ...[
                    Text(l10n.payNoQuote, style: text.bodyMedium),
                    const SizedBox(height: 12),
                  ],
                  // The instruction, in body size: this is the number the owner
                  // acts on, with a customer standing in front of them.
                  Text(collect, style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures)),
                  const SizedBox(height: 16),
                  Text(l10n.payMethod, style: text.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (value, label) in [
                        ('cash', l10n.payCash),
                        ('upi', l10n.payUpi),
                        ('card', l10n.payCard),
                      ])
                        ChoiceChip(
                          selected: _method == value,
                          onSelected: (_) => setState(() => _method = value),
                          label: Text(label),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    onPressed: _saving ? null : _record,
                    child: Text(_saving ? '…' : l10n.payRecord),
                  ),
                ],
              ),
      ),
    );
  }
}
