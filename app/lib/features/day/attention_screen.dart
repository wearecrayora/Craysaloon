import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../l10n/app_localizations.dart';
import 'day_controller.dart';

/// O3 - **Needs attention**: everything the server refused.
///
/// `RULES.md` 9.6: a rejected offline action surfaces with the reason and a
/// one-tap fix, and is **never silently dropped**. So this screen is not a log.
/// Every row is a piece of work somebody did that did not happen, and it stays
/// here until a person decides: try again, or discard it knowing what it was.
///
/// What is NOT here: anything merely waiting for a connection. That is patience,
/// not a decision, and it is counted on the day view instead.
class AttentionScreen extends ConsumerWidget {
  const AttentionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final rejected = ref.watch(rejectedActionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.needsAttention)),
      body: SafeArea(
        child: rejected.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.joinGenericError),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [Text(l10n.attentionEmpty)],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final row = rows[i];
                return _AttentionTile(
                  op: row.op,
                  reasonKey: attentionReasonKey(row.lastError),
                  at: row.updatedAt,
                  onRetry: () async {
                    final outbox = ref.read(outboxProvider);
                    final repo = ref.read(dayRepositoryProvider);
                    if (outbox == null) return;
                    // The SAME action id is kept: if the server had in fact
                    // applied it, this is recognised as a replay rather than
                    // doing the work twice (RULES 9.3).
                    await outbox.retry(row.clientActionId);
                    await repo?.drain();
                    ref.invalidate(rejectedActionsProvider);
                    ref.invalidate(needsAttentionProvider);
                    ref.invalidate(pendingSyncProvider);
                  },
                  onDiscard: () async {
                    final outbox = ref.read(outboxProvider);
                    if (outbox == null) return;
                    await outbox.discard(row.clientActionId);
                    ref.invalidate(rejectedActionsProvider);
                    ref.invalidate(needsAttentionProvider);
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.op,
    required this.reasonKey,
    required this.at,
    required this.onRetry,
    required this.onDiscard,
  });

  final String op;
  final String reasonKey;
  final DateTime at;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;

    final what = switch (op) {
      'mark_visit_complete' => l10n.attentionOpComplete,
      'create_booking' => l10n.attentionOpBooking,
      'cancel_booking' => l10n.attentionOpCancel,
      _ => op,
    };

    // The row stores an error KIND, never a server message: a Postgres string
    // is not written for the owner of a salon.
    final why = switch (reasonKey) {
      'slot_taken' => l10n.reasonSlotTaken,
      'forbidden' => l10n.reasonForbidden,
      'not_completable' => l10n.reasonNotCompletable,
      'salon_unavailable' => l10n.reasonSalonUnavailable,
      'salon_changed' => l10n.reasonSalonChanged,
      _ => l10n.reasonGeneric,
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(what, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(DateFormat.yMMMd().add_jm().format(at), style: text.bodySmall),
          const SizedBox(height: 8),
          Text(why, style: text.bodyMedium),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onDiscard,
                  child: Text(l10n.attentionDiscard),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
