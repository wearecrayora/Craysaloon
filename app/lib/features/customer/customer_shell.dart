import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/glass.dart';
import '../../l10n/app_localizations.dart';
import 'customer_providers.dart';

/// The customer's shell: Home, Book, Bookings, Wallet, Me (Claude Design
/// C1/C5/C2/C12; Bookings added 21 Oct 2026 - every booking in one place, with
/// a count of the ones still to come, as an order list carries).
///
/// No drawer, like the owner's: the things a customer
/// comes back for are one thumb away. "Your data" is NOT hidden behind Me - it
/// stays on the home app bar too, because a right nobody can find is a right
/// nobody has (DPDP s.6(4)).
class CustomerShell extends ConsumerWidget {
  const CustomerShell({required this.child, super.key});

  final Widget child;

  static const destinations = ['/home', '/book', '/bookings', '/wallet', '/me'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final coming = ref.watch(upcomingProvider).value?.length ?? 0;
    final location = GoRouterState.of(context).matchedLocation;
    final index = destinations.indexOf(location);

    // A plain shell, not a page, so it paints its own mesh behind the bar
    // (same reason as OwnerShell).
    return MeshBackground(
      child: Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index < 0 ? 0 : index,
          onDestinationSelected: (i) => context.go(destinations[i]),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: l10n.navHome,
            ),
            NavigationDestination(
              icon: const Icon(Icons.event_outlined),
              selectedIcon: const Icon(Icons.event),
              label: l10n.navBook,
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: coming > 0,
                label: Text('$coming'),
                child: const Icon(Icons.receipt_long_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: coming > 0,
                label: Text('$coming'),
                child: const Icon(Icons.receipt_long),
              ),
              label: l10n.navBookings,
            ),
            NavigationDestination(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: const Icon(Icons.account_balance_wallet),
              label: l10n.walletTitle,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: l10n.navMe,
            ),
          ],
        ),
      ),
    );
  }
}
