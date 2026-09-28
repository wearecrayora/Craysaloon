import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/catalogue/catalogue_screens.dart';
import '../features/customers/customers_screen.dart';
import '../features/day/attention_screen.dart';
import '../features/day/day_screen.dart';
import '../features/day/walk_in_screen.dart';
import '../features/join/deep_link_listener.dart';
import '../features/join/join_screen.dart';
import '../features/privacy/your_data_screen.dart';
import '../features/salon/salon_home.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';

/// Routes, and the shell each role gets (`ARCHITECTURE.md` 9.1).
///
/// The shell is chosen from `app_role`, and **the redirect is the whole point**:
/// a route belonging to another role is not hidden, it is unreachable. An
/// unbound customer has exactly one destination - the join screen (§5.5) - and a
/// platform admin has none at all: the console is a different product, and
/// giving an operator a tenant view here would be a tenant view nobody audited.
///
/// Paths match `IMPLEMENTATION.md` §1.2-1.3 so the two cannot drift.
final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final role = session?.appRole;
      final location = state.matchedLocation;

      // Nobody signed in, or signed in with no salon: the join flow, and
      // nothing else exists to navigate to.
      if (session == null || role == 'customer_unbound' || session.salonId == null) {
        if (role == 'platform_admin') return '/console-only';
        return location == '/join' ? null : '/join';
      }

      if (session.isStaff) {
        // The owner's own routes only. '/' means "wherever this role starts".
        const staffRoutes = {
          '/day', '/day/walk-in', '/attention',
          '/customers', '/catalogue/services', '/catalogue/addons', '/staff',
        };
        return staffRoutes.contains(location) ? null : '/day';
      }

      if (session.isBoundCustomer) {
        // Two destinations, and the second is not optional: "Your data" is
        // where consent is withdrawn and erasure is asked for, and the Act
        // measures withdrawal against how easy consent was (s.6(4)).
        const customerRoutes = {'/home', '/your-data'};
        return customerRoutes.contains(location) ? null : '/home';
      }

      return '/join';
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/join',
        builder: (_, _) => const DeepLinkListener(child: JoinScreen()),
      ),
      GoRoute(path: '/home', builder: (_, _) => const SalonHome()),
      GoRoute(path: '/your-data', builder: (_, _) => const YourDataScreen()),
      GoRoute(path: '/console-only', builder: (_, _) => const _ConsoleOnly()),

      // The owner shell: one bar, the destinations an owner uses all day.
      ShellRoute(
        builder: (context, state, child) => OwnerShell(child: child),
        routes: [
          GoRoute(path: '/day', builder: (_, _) => const DayScreen()),
          GoRoute(path: '/day/walk-in', builder: (_, _) => const WalkInScreen()),
          GoRoute(path: '/attention', builder: (_, _) => const AttentionScreen()),
          GoRoute(path: '/customers', builder: (_, _) => const CustomersScreen()),
          GoRoute(path: '/catalogue/services', builder: (_, _) => const ServicesScreen()),
          GoRoute(path: '/catalogue/addons', builder: (_, _) => const AddOnsScreen()),
          GoRoute(path: '/staff', builder: (_, _) => const StaffScreen()),
        ],
      ),
    ],
  );
});

/// The owner's shell. Five destinations, no drawer: a salon owner uses this
/// between customers, with one hand, and a hidden menu is a menu that is not
/// used.
class OwnerShell extends StatelessWidget {
  const OwnerShell({required this.child, super.key});

  final Widget child;

  static const _destinations = [
    '/day',
    '/customers',
    '/catalogue/services',
    '/catalogue/addons',
    '/staff',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    final index = _destinations.indexOf(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(_destinations[i]),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            // The tab is the DAY. Mark-complete is the action on it, not its
            // name - labelling the tab with a verb told the owner to press it.
            label: l10n.dayTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: l10n.customersTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.content_cut_outlined),
            selectedIcon: const Icon(Icons.content_cut),
            label: l10n.catalogueServices,
          ),
          NavigationDestination(
            icon: const Icon(Icons.add_circle_outline),
            selectedIcon: const Icon(Icons.add_circle),
            label: l10n.catalogueAddOns,
          ),
          NavigationDestination(
            icon: const Icon(Icons.badge_outlined),
            selectedIcon: const Icon(Icons.badge),
            label: l10n.staffTitle,
          ),
        ],
      ),
    );
  }
}

/// A Crayora operator who signed into the customer app. They have no tenant, by
/// design (`RULES.md` 6.7), so there is nothing here for them.
class _ConsoleOnly extends StatelessWidget {
  const _ConsoleOnly();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'This account is a Crayora operator account. Salons are managed in the console.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    );
  }
}
