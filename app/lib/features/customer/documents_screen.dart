import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/salon_mark.dart';
import '../../domain/customer/customer.dart';
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';
import 'customer_providers.dart';

/// The customer's receipts and invoices (0094).
///
/// A top-up shows as a RECEIPT, and says in words that it is not a tax invoice
/// (RULES 11.12); a paid visit shows as a tax invoice or a bill of supply,
/// whichever the salon issued. The app formats what the database issued and
/// computes nothing - not a paisa of the tax.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final ml = MaterialLocalizations.of(context);
    final docs = ref.watch(documentsProvider);

    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(documentsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(l10n.docsTitle, style: text.headlineMedium),
            const SizedBox(height: 12),
            switch (docs) {
              AsyncData(:final value) when value.isEmpty => Text(
                l10n.docsEmpty,
                style: text.bodyLarge,
              ),
              AsyncData(:final value) => Column(
                children: [
                  for (final (i, d) in value.indexed)
                    Appear(
                      delay: Duration(milliseconds: 30 * (i < 8 ? i : 8)),
                      child: Pressable(
                        onTap: () => DocumentSheet.open(context, d),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 56),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                d.isReceipt
                                    ? Icons.receipt_long_outlined
                                    : Icons.description_outlined,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _title(l10n, d.kind),
                                      style: text.titleMedium,
                                    ),
                                    Text(
                                      '${d.number} · ${ml.formatMediumDate(d.issuedAt)}',
                                      style: text.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                rupees(d.totalPaise),
                                style: text.titleMedium?.copyWith(
                                  fontFeatures: moneyFeatures,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              AsyncError() => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.docsFailed, style: text.bodyLarge),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(documentsProvider),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
              _ => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }
}

String _title(AppL10n l10n, DocumentKind kind) => switch (kind) {
  DocumentKind.receipt => l10n.docReceipt,
  DocumentKind.taxInvoice => l10n.docTaxInvoice,
  DocumentKind.billOfSupply => l10n.docBillOfSupply,
};

/// One document, in full.
class DocumentSheet extends ConsumerWidget {
  const DocumentSheet(this.doc, {super.key});

  final SalonDocument doc;

  static Future<void> open(BuildContext context, SalonDocument doc) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DocumentSheet(doc),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final ml = MaterialLocalizations.of(context);
    final salon = ref.watch(resolvedBrandingProvider)?.displayName ?? '';
    final d = doc;
    String rate(int bp) =>
        '${(bp / 200).toStringAsFixed(bp % 200 == 0 ? 0 : 1)}%';

    Widget row(String label, int paise, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong ? text.titleMedium : text.bodyMedium,
            ),
          ),
          Text(
            rupees(paise),
            style: (strong ? text.titleMedium : text.bodyMedium)?.copyWith(
              fontFeatures: moneyFeatures,
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(_title(l10n, d.kind), style: text.headlineSmall),
            const SizedBox(height: 4),
            Text(salon, style: text.titleMedium),
            if (d.gstin != null)
              Text(l10n.docGstin(d.gstin!), style: text.bodySmall),
            const SizedBox(height: 12),
            Text('${l10n.docNumber}: ${d.number}', style: text.bodyMedium),
            Text(
              '${l10n.docDate}: ${ml.formatMediumDate(d.issuedAt)}',
              style: text.bodyMedium,
            ),
            const Divider(height: 32),
            if (d.isReceipt) ...[
              row(l10n.docAmountPaid, d.totalPaise, strong: true),
              if (d.bonusPaise > 0) row(l10n.docBonusAdded, d.bonusPaise),
              const SizedBox(height: 12),
              // RULES 11.12, said on the document itself.
              Text(l10n.docReceiptNote, style: text.bodyMedium),
              const SizedBox(height: 8),
              Text(l10n.walletOnlyAtSalon(salon), style: text.bodySmall),
            ] else ...[
              for (final line in d.lines)
                row(
                  line.kind == 'adjustment'
                      ? l10n.docAdjustment
                      : (line.name ?? ''),
                  line.pricePaise,
                ),
              const Divider(height: 24),
              if (d.kind == DocumentKind.taxInvoice && d.gstRateBp != null) ...[
                row(l10n.docTaxable, d.taxablePaise),
                row(l10n.docCgst(rate(d.gstRateBp!)), d.cgstPaise),
                row(l10n.docSgst(rate(d.gstRateBp!)), d.sgstPaise),
              ],
              row(l10n.docTotal, d.totalPaise, strong: true),
              if (d.kind == DocumentKind.billOfSupply)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l10n.docNoGst, style: text.bodySmall),
                ),
              const SizedBox(height: 16),
              Text(l10n.docPaidWith, style: text.titleSmall),
              if (d.walletPaidPaise > 0)
                row(l10n.docPaidWallet, d.walletPaidPaise),
              if (d.bonusPaise > 0) row(l10n.docPaidBonus, d.bonusPaise),
              if (d.otherPaise > 0) row(l10n.docPaidOther, d.otherPaise),
            ],
          ],
        ),
      ),
    );
  }
}
