import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/glass.dart';
import '../../l10n/app_localizations.dart';

/// The customer's shell: Home, Book, Wallet, Me (Claude Design C1/C5/C2/C12).
///
/// Four destinations and no drawer, like the owner's: the things a customer
/// comes back for are one thumb away. "Your data" is NOT hidden behind Me - it
/// stays on the home app bar too, because a right nobody can find is a right
/// nobody has (DPDP s.6(4)).
class CustomerShell extends StatelessWidget {
  const CustomerShell({required this.child, super.key});

  final Widget child;

  static const destinations = ['/home', '/book', '/wallet', '/me'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
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
