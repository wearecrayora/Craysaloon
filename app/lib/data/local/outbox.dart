import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../domain/join/cray_api.dart';
import 'cache_db.dart';

/// The queue of work the owner has done and the server has not yet accepted.
///
/// `ARCHITECTURE.md` 10.2 and `RULES.md` 9: capture works offline, money and
/// binding never do. The three operations here are captures - complete a visit,
/// book a walk-in, cancel - and each carries a `client_action_id` generated once
/// and reused for every retry, so the server can recognise a replay and answer
/// with the original result instead of doing the work twice (RULES 9.3).
///
/// Two rules this class exists to keep:
///
/// 1. **Nothing is dropped.** A server refusal moves a row to `rejected` with
///    the reason, for "Needs attention" to show and the owner to fix (RULES
///    9.6). It is never deleted quietly, and never retried forever in the hope
///    it starts working.
/// 2. **Order is preserved per entity.** Rows drain oldest first, so "book the
///    walk-in, then complete it" replays in that order rather than arriving
///    backwards and failing for a reason nobody can read.
class Outbox {
  Outbox(this.db);

  final CacheDb db;

  static final _random = Random.secure();

  /// A v4 uuid, generated on the device. It is the idempotency key, so it must
  /// be created ONCE per intent - not once per attempt.
  static String newActionId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
        '-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<String> enqueue({
    required String salonId,
    required String op,
    required Map<String, Object?> payload,
    String? actionId,
  }) async {
    final id = actionId ?? newActionId();
    final now = DateTime.now();
    await db.into(db.outboxActions).insert(
          OutboxActionsCompanion.insert(
            clientActionId: id,
            salonId: salonId,
            op: op,
            payload: jsonEncode(payload),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// Oldest first. `syncing` rows are included: a row left in that state is one
  /// the app died in the middle of, and the server's idempotency makes retrying
  /// it safe - which is the entire reason the key exists.
  Future<List<OutboxAction>> pending({int limit = 50}) {
    return (db.select(db.outboxActions)
          ..where((t) => t.status.isIn(['pending', 'syncing']))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<List<OutboxAction>> rejected() {
    return (db.select(db.outboxActions)
          ..where((t) => t.status.equals('rejected'))
          ..orderBy([(t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)]))
        .get();
  }

  /// How many pieces of work are still unsent - what the day view shows so the
  /// owner knows their tap is not lost.
  ///
  /// A plain read, not a live query. The only thing that changes these counts is
  /// this app acting, so the screen refreshes them when it acts; a live Drift
  /// stream would add a subscription (and a pending timer) for an event that
  /// cannot happen behind the user's back.
  Future<int> pendingCount() async => (await pending(limit: 1000)).length;

  Future<int> rejectedCount() async => (await rejected()).length;

  Future<void> markSyncing(String actionId) => _set(actionId, status: 'syncing', bumpAttempt: true);

  /// The server accepted it. The row stays, applied, as the record that this
  /// device's intent became a fact - and is cleared by [purgeApplied] later.
  Future<void> markApplied(String actionId) => _set(actionId, status: 'applied');

  /// The server said no, for a reason that will not change by asking again:
  /// the slot is taken, the booking is already completed, the account cannot.
  Future<void> markRejected(String actionId, String reason) =>
      _set(actionId, status: 'rejected', error: reason);

  /// The server could not be reached. Back to pending - this is not a refusal,
  /// and it must not look like one in "Needs attention".
  Future<void> markUnreachable(String actionId, String reason) =>
      _set(actionId, status: 'pending', error: reason);

  /// Retry from "Needs attention": the owner fixed whatever it was. The SAME
  /// action id is kept, so if the server had in fact applied it, the retry is
  /// recognised as a replay instead of doing it twice.
  Future<void> retry(String actionId) => _set(actionId, status: 'pending', clearError: true);

  /// The owner chose to discard it. Only ever from "Needs attention", where they
  /// have seen what it was - never automatically.
  Future<void> discard(String actionId) =>
      (db.delete(db.outboxActions)..where((t) => t.clientActionId.equals(actionId))).go();

  Future<int> purgeApplied({Duration olderThan = const Duration(days: 7)}) {
    final cutoff = DateTime.now().subtract(olderThan);
    return (db.delete(db.outboxActions)
          ..where((t) => t.status.equals('applied') & t.updatedAt.isSmallerThanValue(cutoff)))
        .go();
  }

  Future<void> _set(
    String actionId, {
    required String status,
    String? error,
    bool bumpAttempt = false,
    bool clearError = false,
  }) async {
    final row = await (db.select(db.outboxActions)
          ..where((t) => t.clientActionId.equals(actionId)))
        .getSingleOrNull();
    if (row == null) return;

    await (db.update(db.outboxActions)..where((t) => t.clientActionId.equals(actionId)))
        .write(OutboxActionsCompanion(
      status: Value(status),
      attempts: Value(bumpAttempt ? row.attempts + 1 : row.attempts),
      lastError: clearError ? const Value(null) : Value(error ?? row.lastError),
      updatedAt: Value(DateTime.now()),
    ));
  }
}

/// Turns a server answer into the outbox's three outcomes.
///
/// The distinction that matters: **unreachable is not refused.** A network
/// failure goes back to pending and is retried; a policy or a state saying no
/// goes to "Needs attention" and waits for a person. Treating the first as the
/// second fills the inbox with noise; treating the second as the first retries
/// forever and never tells anyone.
OutboxOutcome outcomeFor(CrayErrorKind kind) => switch (kind) {
      CrayErrorKind.network => OutboxOutcome.unreachable,
      CrayErrorKind.rateLimited => OutboxOutcome.unreachable,
      CrayErrorKind.server => OutboxOutcome.unreachable,
      _ => OutboxOutcome.rejected,
    };

enum OutboxOutcome { applied, rejected, unreachable }
