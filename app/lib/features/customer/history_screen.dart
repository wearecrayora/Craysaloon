import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/salon_mark.dart';
import '../../l10n/app_localizations.dart';
import 'customer_providers.dart';

/// C10 - what the customer had, when, with whom, and what it came to.
///
/// "Paid" or "Not paid yet" rather than the method: the visit knows whether it
/// is settled, and a method guessed from partial records would be a statement
/// about somebody's money that the books do not make.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final ml = MaterialLocalizations.of(context);
    final history = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(historyProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(l10n.historyTitle, style: text.headlineMedium),
            const SizedBox(height: 12),
            switch (history) {
              AsyncData(:final value) when value.isEmpty => _Empty(message: l10n.historyEmpty),
              AsyncData(:final value) => Column(
                  children: [
                    for (final (i, v) in value.indexed)
                      Appear(
                        // A short stagger down the list, capped so a long
                        // history is not a slow one.
                        delay: Duration(milliseconds: 30 * (i < 8 ? i : 8)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Theme.of(context).dividerColor),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(ml.formatMediumDate(v.completedAt), style: text.bodySmall),
                                    if (v.serviceNames.isNotEmpty)
                                      Text(v.serviceNames, style: text.titleMedium),
                                    if (v.staffName != null)
                                      Text(l10n.withStylist(v.staffName!), style: text.bodySmall),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    rupees(v.amountPaise),
                                    style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
                                  ),
                                  Text(
                                    v.paid ? l10n.historyPaid : l10n.historyUnpaid,
                                    style: text.bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              AsyncError() => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.historyFailed, style: text.bodyLarge),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(historyProvider),
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

/// An empty state with one of the salon photos (DESIGN 10) and a way forward.
class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 140,
            child: Image.asset(
              'assets/images/salon_mirrors.jpg',
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
