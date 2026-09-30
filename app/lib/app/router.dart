import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/booking/book_screen.dart';
import '../features/booking/booking_detail_screen.dart';
import '../features/catalogue/catalogue_screens.dart';
import '../features/customer/customer_shell.dart';
import '../features/customer/documents_screen.dart';
import '../features/customer/history_screen.dart';
import '../features/customer/me_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/day/attention_screen.dart';
import '../features/day/day_screen.dart';
import '../features/day/walk_in_screen.dart';
import '../features/join/deep_link_listener.dart';
import '../features/join/join_screen.dart';
import '../features/owner/more_screens.dart';
import '../features/salon/salon_account.dart' show hasFeature;
import '../features/privacy/your_data_screen.dart';
import '../features/referral/referral_screen.dart';
import '../features/wallet/add_money_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../core/ui/glass.dart';
import '../features/salon/salon_home.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';

/// Every route is an explicit [MaterialPage], so the theme's page transitions
/// run - and with them the glass chassis's mesh, which each page paints beneath
/// its transparent scaffold (core/theme/brand_theme.dart). Left to itself,
/// go_router may pick a non-Material page, and the mesh silently never paints.
GoRouterPageBuilder _page(Widget child) =>
    (context, state) => MaterialPage(key: state.pageKey, child: child);

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
      if (session == null ||
          role == 'customer_unbound' ||
          session.salonId == null) {
        if (role == 'platform_admin') return '/console-only';
        return location == '/join' ? null : '/join';
      }

      if (session.isStaff) {
        // The owner's own routes only. '/' means "wherever this role starts".
        const staffRoutes = {
          '/day',
          '/day/walk-in',
          '/attention',
          '/dashboard',
          '/customers',
          '/catalogue/services',
          '/catalogue/addons',
          '/staff',
          '/more',
          '/more/rules',
          '/more/hours',
          '/more/billing',
          '/more/profile',
        };
        return staffRoutes.contains(location) ? null : '/day';
      }

      if (session.isBoundCustomer) {
        // Two destinations, and the second is not optional: "Your data" is
        // where consent is withdrawn and erasure is asked for, and the Act
        // measures withdrawal against how easy consent was (s.6(4)).
        const customerRoutes = {
          '/home',
          '/book',
          '/me',
          '/visits',
          '/documents',
          '/your-data',
          '/wallet',
          '/wallet/add',
          '/refer',
        };
        if (location.startsWith('/booking/')) return null;
        return customerRoutes.contains(location) ? null : '/home';
      }

      return '/join';
    },
    routes: [
      GoRoute(path: '/', pageBuilder: _page(const SizedBox.shrink())),
      GoRoute(
        path: '/join',
        pageBuilder: _page(const DeepLinkListener(child: JoinScreen())),
      ),
      // The customer shell: Home, Book, Wallet, Me (Claude Design C1/C5/C2/C12).
      ShellRoute(
        builder: (context, state, child) => CustomerShell(child: child),
        routes: [
          GoRoute(path: '/home', pageBuilder: _page(const SalonHome())),
          GoRoute(path: '/book', pageBuilder: _page(const BookScreen())),
          GoRoute(path: '/wallet', pageBuilder: _page(const WalletScreen())),
          GoRoute(path: '/me', pageBuilder: _page(const MeScreen())),
        ],
      ),
      GoRoute(path: '/your-data', pageBuilder: _page(const YourDataScreen())),
      GoRoute(path: '/visits', pageBuilder: _page(const HistoryScreen())),
      GoRoute(path: '/documents', pageBuilder: _page(const DocumentsScreen())),
      GoRoute(
        path: '/booking/:id',
        pageBuilder: (context, state) => MaterialPage(
          key: state.pageKey,
          child: BookingDetailScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(path: '/wallet/add', pageBuilder: _page(const AddMoneyScreen())),
      GoRoute(path: '/refer', pageBuilder: _page(const ReferralScreen())),
      GoRoute(path: '/console-only', pageBuilder: _page(const _ConsoleOnly())),

      // The owner shell: one bar, the destinations an owner uses all day.
      ShellRoute(
        // A plain builder, not a page: the shell must survive navigation
        // between its tabs, or the day view is rebuilt - and refreshed twice at
        // once - on every move. It paints its own mesh (see OwnerShell).
        builder: (context, state, child) => OwnerShell(child: child),
        routes: [
          GoRoute(path: '/day', pageBuilder: _page(const DayScreen())),
          GoRoute(
            path: '/day/walk-in',
            pageBuilder: _page(const WalkInScreen()),
          ),
          GoRoute(
            path: '/attention',
            pageBuilder: _page(const AttentionScreen()),
          ),
          GoRoute(
            path: '/dashboard',
            pageBuilder: _page(const DashboardScreen()),
          ),
          GoRoute(
            path: '/customers',
            pageBuilder: _page(const CustomersScreen()),
          ),
          GoRoute(
            path: '/catalogue/services',
            pageBuilder: _page(const ServicesScreen()),
          ),
          GoRoute(
            path: '/catalogue/addons',
            pageBuilder: _page(const AddOnsScreen()),
          ),
          GoRoute(path: '/staff', pageBuilder: _page(const StaffScreen())),
          GoRoute(path: '/more', pageBuilder: _page(const MoreScreen())),
          GoRoute(path: '/more/rules', pageBuilder: _page(const RulesScreen())),
          GoRoute(path: '/more/hours', pageBuilder: _page(const HoursScreen())),
          GoRoute(
            path: '/more/billing',
            pageBuilder: _page(const BillingScreen()),
          ),
          GoRoute(
            path: '/more/profile',
            pageBuilder: _page(const ProfileScreen()),
          ),
        ],
      ),
    ],
  );
});

/// The owner's shell: Today, Customers, Dashboard, More (Claude Design O1-O13).
/// No drawer: a salon owner uses this between customers, with one hand, and a
/// hidden menu is a menu that is not used. The catalogue and the team moved
/// under More - they are set up once and tweaked, not used all day.
///
/// Dashboard is a tab only for someone who may open it: owner_dashboard refuses
/// anyone else, and only a plan that carries it (0087).
class OwnerShell extends ConsumerWidget {
  const OwnerShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    final dashboard =
        ref.watch(canEditCatalogueProvider) && hasFeature(ref, 'dashboard');

    final tabs = [
      (
        path: '/day',
        dest: NavigationDestination(
          icon: const Icon(Icons.today_outlined),
          selectedIcon: const Icon(Icons.today),
          // The tab is the DAY. Mark-complete is the action on it, not its
          // name - labelling the tab with a verb told the owner to press it.
          label: l10n.dayTitle,
        ),
      ),
      (
        path: '/customers',
        dest: NavigationDestination(
          icon: const Icon(Icons.people_outline),
          selectedIcon: const Icon(Icons.people),
          label: l10n.customersTitle,
        ),
      ),
      if (dashboard)
        (
          path: '/dashboard',
          dest: NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            label: l10n.dashTitle,
          ),
        ),
      (
        path: '/more',
        dest: NavigationDestination(
          icon: const Icon(Icons.more_horiz),
          selectedIcon: const Icon(Icons.more_horiz),
          label: l10n.moreTitle,
        ),
      ),
    ];

    // Where a screen belongs: the walk-in and Needs attention are part of the
    // day; the catalogue, the team and the read-only pages live under More.
    final section = switch (location) {
      final l when l.startsWith('/day') || l == '/attention' => '/day',
      final l
          when l.startsWith('/catalogue') ||
              l == '/staff' ||
              l.startsWith('/more') =>
        '/more',
      final l => l,
    };
    final index = tabs.indexWhere((t) => t.path == section);

    // The shell paints its own mesh: it is not a page, so the per-page mesh
    // (core/theme/brand_theme.dart) never reaches the bar at the bottom.
    return MeshBackground(
      child: Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index < 0 ? 0 : index,
          onDestinationSelected: (i) => context.go(tabs[i].path),
          destinations: [for (final t in tabs) t.dest],
        ),
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
