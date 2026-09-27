import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/format/money.dart';
import '../../core/ui/cache_banner.dart';
import '../../domain/records/records.dart';
import '../../l10n/app_localizations.dart';
import 'customers_controller.dart';

/// O4 - the customer list. Keyset-paginated, searchable, readable offline.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Next page when the list is close to the end, so the owner never waits at
  /// the bottom. Keyset means "close to the end" is cheap to serve.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      ref.read(customersControllerProvider.notifier).loadMore();
    }
  }

  void _onQueryChanged(String value) {
    // A keystroke is not a query. Waiting a beat turns "Ayesha" into one search
    // instead of six, which matters on salon wi-fi and on the server.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(customersControllerProvider.notifier).search(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(customersControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.customersTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.customersSearchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            if (state.fromCache) CacheBanner(refreshedAt: state.refreshedAt),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(customersControllerProvider.notifier).refresh(),
                child: _body(context, state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, CustomersState state) {
    final l10n = AppL10n.of(context);

    if (state.loading && state.customers.isEmpty) {
      // A skeleton would be a lie about how many rows are coming; this screen
      // has no way to know. Skeletons also never shimmer (DESIGN 11).
      return const Center(child: CircularProgressIndicator());
    }

    if (state.customers.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            state.search.isEmpty
                ? (state.fromCache ? l10n.cachedNeverLoaded : l10n.customersEmpty)
                : l10n.customersNoMatch,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: state.customers.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= state.customers.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: state.loadingMore
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: () =>
                          ref.read(customersControllerProvider.notifier).loadMore(),
                      child: Text(l10n.loadMore),
                    ),
            ),
          );
        }
        return CustomerRow(customer: state.customers[index]);
      },
    );
  }
}

class CustomerRow extends StatelessWidget {
  const CustomerRow({required this.customer, super.key});

  final CustomerSummary customer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;

    final last = customer.lastVisitAt == null
        ? l10n.customerNeverVisited
        : l10n.customerLastVisit(DateFormat.yMMMd().format(customer.lastVisitAt!));

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(customer.name?.trim().isNotEmpty == true
          ? customer.name!
          : (customer.phone ?? '')),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap rather than Row: at 200% text scale these two strings do not
          // fit side by side, and clipping a date is worse than a second line.
          Wrap(
            spacing: 12,
            children: [
              Text(last, style: text.bodySmall),
              Text(l10n.customerVisits(customer.visitCount), style: text.bodySmall),
            ],
          ),
        ],
      ),
      trailing: customer.balancePaise == 0
          ? null
          : Text(
              rupees(customer.balancePaise),
              style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CustomerDetailScreen(customer: customer)),
      ),
    );
  }
}

/// O5 - the customer's record. **Shows a balance and cannot change it**: there
/// is no adjust control here, no endpoint behind one, and no permission that
/// would allow it (`RULES.md` §2, §5.2). Money moves through top-ups, visits and
/// exactly five server-side callers; a screen is not one of them.
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({required this.customer, super.key});

  final CustomerSummary customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final visits = ref.watch(visitsProvider(customer.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name?.trim().isNotEmpty == true
            ? customer.name!
            : (customer.phone ?? l10n.customersTitle)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (customer.phone != null)
              Text(customer.phone!, style: text.bodyLarge?.copyWith(fontFeatures: moneyFeatures)),
            const SizedBox(height: 24),
            Text(l10n.walletBalance, style: text.labelMedium),
            Text(
              rupees(customer.balancePaise),
              // Never animated - a money value that counts up invites the reader
              // to doubt it (DESIGN 11).
              style: text.displaySmall?.copyWith(fontFeatures: moneyFeatures),
            ),
            const SizedBox(height: 4),
            Text(l10n.balanceReadOnly, style: text.bodySmall),
            if (customer.loyaltyPoints > 0) ...[
              const SizedBox(height: 16),
              Text(
                l10n.customerLoyalty('${customer.loyaltyPoints}'),
                style: text.bodyMedium?.copyWith(fontFeatures: moneyFeatures),
              ),
            ],
            const SizedBox(height: 24),
            Text(l10n.customerVisits(customer.visitCount), style: text.titleMedium),
            const SizedBox(height: 8),
            visits.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => Text(l10n.joinOffline, style: text.bodySmall),
              data: (cached) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cached.fromCache) CacheBanner(refreshedAt: cached.refreshedAt),
                  for (final visit in cached.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat.yMMMd().format(visit.completedAt),
                              style: text.bodyMedium,
                            ),
                          ),
                          Text(
                            rupees(visit.finalAmountPaise),
                            style: text.bodyMedium?.copyWith(fontFeatures: moneyFeatures),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
