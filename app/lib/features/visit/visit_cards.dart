import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../../core/platform/payment_sheet.dart';
import '../../data/local/outbox.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/visit/visit.dart';
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';
import '../wallet/add_money_screen.dart' show paymentSheetProvider;
import '../wallet/wallet_controller.dart';

final visitApiProvider = Provider<VisitApi?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is VisitApi ? api as VisitApi : null;
});

final visitsTodayProvider = FutureProvider<List<TodayVisit>>((ref) async {
  final api = ref.watch(visitApiProvider);
  if (api == null) return const [];
  return api.visitsToday();
});

final billsProvider = FutureProvider<List<Bill>>((ref) async {
  final api = ref.watch(visitApiProvider);
  if (api == null) return const [];
  return api.bills();
});

/// Today's booking, with the code the customer reads to the stylist.
///
/// The code is shown BIG, because it is read aloud across a salon floor, and
/// only while it can still be used (0084). Nobody else - not the stylist, not
/// the owner - can see it anywhere.
class TodayVisitsCard extends ConsumerWidget {
  const TodayVisitsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final visits = ref.watch(visitsTodayProvider).value ?? const [];
    if (visits.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final v in visits)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.visitToday, style: text.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    '${TimeOfDay.fromDateTime(v.startsAt).format(context)}'
                    '${v.services.isEmpty ? '' : ' · ${v.services}'}',
                    style: text.titleMedium,
                  ),
                  if (v.staff != null) Text(v.staff!, style: text.bodySmall),
                  const SizedBox(height: 12),
                  if (v.inProgress)
                    Text(l10n.visitInProgress, style: text.bodyMedium)
                  else if (v.startCode != null) ...[
                    Text(l10n.visitShowCode, style: text.bodyMedium),
                    const SizedBox(height: 8),
                    Center(
                      child: Semantics(
                        label: l10n.visitCodeSemantics(v.startCode!.split('').join(' ')),
                        // Digit by digit INSTEAD of the number: "four thousand
                        // eight hundred..." is not a code anyone can repeat.
                        excludeSemantics: true,
                        child: Text(
                          v.startCode!,
                          style: text.displaySmall?.copyWith(
                            letterSpacing: 16,
                            fontFeatures: moneyFeatures,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Bills to pay. Each opens the pay sheet.
class BillsCard extends ConsumerWidget {
  const BillsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final bills = ref.watch(billsProvider).value ?? const [];
    if (bills.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in bills)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.billReady, style: text.titleMedium),
                  if (b.services.isNotEmpty) Text(b.services, style: text.bodySmall),
                  const SizedBox(height: 8),
                  Text(
                    rupees(b.duePaise),
                    style: text.headlineSmall?.copyWith(fontFeatures: moneyFeatures),
                  ),
                  if (b.counterRequested) ...[
                    const SizedBox(height: 4),
                    Text(l10n.billCounterSaid, style: text.bodySmall),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => PayBillSheet.open(context, b),
                    child: Text(l10n.billPay),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Paying a bill: the wallet first, as far as it goes; then UPI through
/// Razorpay, or cash at the counter.
///
/// Every amount on this sheet is the SERVER's. The app sends a visit id and
/// never a number (0085). And nothing here can mark a bill paid by itself: the
/// wallet is spent by the server, a UPI payment settles when Razorpay's webhook
/// says so, and cash when STAFF take it (decision of 29 Sep 2026).
class PayBillSheet extends ConsumerStatefulWidget {
  const PayBillSheet({required this.bill, super.key});

  final Bill bill;

  static Future<void> open(BuildContext context, Bill bill) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PayBillSheet(bill: bill),
    );
  }

  @override
  ConsumerState<PayBillSheet> createState() => _PayBillSheetState();
}

class _PayBillSheetState extends ConsumerState<PayBillSheet> {
  late int _due = widget.bill.duePaise;
  bool _busy = false;
  String? _message;

  /// One per intent, reused on retry, so a double tap spends once.
  final String _walletAction = Outbox.newActionId();
  final String _upiAction = Outbox.newActionId();

  void _refreshAll() {
    ref.invalidate(billsProvider);
    ref.invalidate(walletProvider);
  }

  Future<void> _run(Future<void> Function(AppL10n l10n) body) async {
    final l10n = AppL10n.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await body(l10n);
    } on BillException catch (e) {
      if (!mounted) return;
      setState(() => _message = switch (e.problem) {
            BillProblem.alreadyPaid => l10n.billAlreadyPaid,
            BillProblem.paymentsUnavailable => l10n.addMoneyUnavailable,
            BillProblem.notFound || BillProblem.network => l10n.joinOffline,
          });
    } on CrayApiException {
      if (mounted) setState(() => _message = l10n.joinOffline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fromWallet() => _run((l10n) async {
        final left = await ref
            .read(visitApiProvider)!
            .payBillFromWallet(clientActionId: _walletAction, visitId: widget.bill.visitId);
        _refreshAll();
        if (!mounted) return;
        setState(() {
          _due = left;
          _message = left == 0 ? l10n.billPaidFromWallet : l10n.billWalletPartly(rupees(left));
        });
        if (left == 0) Navigator.of(context).pop();
      });

  Future<void> _byUpi() => _run((l10n) async {
        final order = await ref
            .read(visitApiProvider)!
            .startBillPayment(clientActionId: _upiAction, visitId: widget.bill.visitId);
        final salonName = ref.read(resolvedBrandingProvider)?.displayName ?? '';
        final outcome = await ref.read(paymentSheetProvider).open(order, salonName: salonName);
        _refreshAll();
        if (!mounted) return;
        setState(() => _message = switch (outcome) {
              // Never "paid": the bill settles when Razorpay's webhook arrives.
              PaymentOutcome.submitted => l10n.billUpiSent,
              PaymentOutcome.cancelled => l10n.addMoneyCancelled,
              PaymentOutcome.failed => l10n.addMoneyFailed,
              PaymentOutcome.unavailable => l10n.addMoneyCheckoutNotReady,
            });
      });

  Future<void> _atCounter() => _run((l10n) async {
        await ref.read(visitApiProvider)!.requestCounterPayment(widget.bill.visitId);
        _refreshAll();
        if (mounted) setState(() => _message = l10n.billCounterTold);
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final balance = ref.watch(walletProvider).value?.summary.balancePaise ?? 0;
    final fromWallet = balance < _due ? balance : _due;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.billPay, style: text.titleLarge),
            const SizedBox(height: 8),
            Text(l10n.billToPay(rupees(_due)),
                style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures)),
            const SizedBox(height: 16),
            if (fromWallet > 0) ...[
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: _busy ? null : _fromWallet,
                child: Text(l10n.billFromWallet(rupees(fromWallet))),
              ),
              const SizedBox(height: 8),
              if (fromWallet < _due)
                Text(l10n.billWalletCovers(rupees(fromWallet), rupees(_due - fromWallet)),
                    style: text.bodySmall),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: _busy ? null : _byUpi,
              child: Text(l10n.billByUpi(rupees(_due))),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _atCounter,
              child: Text(l10n.billAtCounter),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: text.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
