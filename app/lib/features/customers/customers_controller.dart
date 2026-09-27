import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/records_repository.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/records/records.dart';

/// The owner's customer list (screen O4).
///
/// Keyset paging, not page numbers: the cursor is the last row's
/// (lastVisitAt, id), so a customer walking in while the owner scrolls cannot
/// make a row repeat or disappear (ARCHITECTURE 6.8).
class CustomersState {
  const CustomersState({
    this.customers = const [],
    this.search = '',
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.fromCache = false,
    this.refreshedAt,
    this.problem,
  });

  final List<CustomerSummary> customers;
  final String search;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;

  /// True when these rows came from this device rather than the server. The
  /// screen says so; it never passes cached rows off as live.
  final bool fromCache;
  final DateTime? refreshedAt;
  final CrayErrorKind? problem;

  CustomersState copyWith({
    List<CustomerSummary>? customers,
    String? search,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    bool? fromCache,
    DateTime? refreshedAt,
    CrayErrorKind? problem,
    bool clearProblem = false,
  }) {
    return CustomersState(
      customers: customers ?? this.customers,
      search: search ?? this.search,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      fromCache: fromCache ?? this.fromCache,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      problem: clearProblem ? null : (problem ?? this.problem),
    );
  }
}

class CustomersController extends Notifier<CustomersState> {
  CustomerCursor? _cursor;

  @override
  CustomersState build() {
    // Load the first page as soon as the screen asks for the state.
    Future.microtask(refresh);
    return const CustomersState(loading: true);
  }

  RecordsRepository? get _repo => ref.read(recordsRepositoryProvider);

  Future<void> refresh() async {
    final repo = _repo;
    if (repo == null) {
      state = state.copyWith(loading: false);
      return;
    }

    state = state.copyWith(loading: true, clearProblem: true);
    _cursor = null;
    try {
      final result = await repo.customers(search: state.search);
      _cursor = result.value.cursor;
      state = state.copyWith(
        customers: result.value.customers,
        hasMore: result.value.hasMore,
        loading: false,
        fromCache: result.fromCache,
        refreshedAt: result.refreshedAt,
        problem: result.problem,
      );
    } on CrayApiException catch (e) {
      // A failed SEARCH is not served from the cache: a stale search result is
      // worse than an honest "you are offline".
      state = state.copyWith(loading: false, customers: const [], problem: e.kind);
    }
  }

  Future<void> loadMore() async {
    final repo = _repo;
    final cursor = _cursor;
    if (repo == null || cursor == null || state.loadingMore || !state.hasMore) return;

    state = state.copyWith(loadingMore: true, clearProblem: true);
    try {
      final result = await repo.customers(search: state.search, after: cursor);
      _cursor = result.value.cursor;
      state = state.copyWith(
        customers: [...state.customers, ...result.value.customers],
        hasMore: result.value.hasMore,
        loadingMore: false,
      );
    } on CrayApiException catch (e) {
      state = state.copyWith(loadingMore: false, problem: e.kind);
    }
  }

  /// The owner types; the server searches. Debouncing belongs in the widget,
  /// which knows about keystrokes - this just runs the search it is given.
  Future<void> search(String query) async {
    state = state.copyWith(search: query);
    await refresh();
  }
}

final customersControllerProvider =
    NotifierProvider<CustomersController, CustomersState>(CustomersController.new);
