import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../customer/customer_providers.dart';
import '../dashboard/dashboard_screen.dart';
import '../owner/hours_screens.dart';
import '../referral/referral_screen.dart';
import '../visit/visit_cards.dart';
import '../wallet/wallet_controller.dart';
import 'salon_account.dart';

/// A change made in the console reaches the phone without an app update or a
/// reinstall (decided 13 Oct 2026).
///
/// Everything a salon shows lives on the server, so no update is ever needed -
/// but every read here is a FutureProvider, and a FutureProvider keeps its
/// first answer for as long as the app stays in memory. A price changed in the
/// console used to reach a customer only after they had killed and reopened
/// the app. So every server read the console (or the salon) can change is
/// re-read when the app comes back to the foreground and every few minutes
/// while it is open - see [BrandingRefresh], which drives this alongside the
/// branding.
///
/// Invalidating keeps the old value on screen while the new one loads
/// (`skipLoadingOnRefresh`), so a refresh never blanks a screen, and a failed
/// read leaves the last good answer in place.
///
/// NOT here: the outbox counts (local), and the booking screen's slots - those
/// are auto-disposed, so they are read fresh every time the screen opens.
void refreshServerReads(WidgetRef ref) {
  ref
    // The menu, the team and their hours - customer and owner side.
    ..invalidate(bookableServicesProvider)
    ..invalidate(bookableAddOnsProvider)
    ..invalidate(bookableStaffProvider)
    ..invalidate(servicesProvider)
    ..invalidate(addOnsProvider)
    ..invalidate(staffProvider)
    ..invalidate(shiftsProvider)
    ..invalidate(timeOffProvider)
    // The customer's own picture of the salon.
    ..invalidate(myProfileProvider)
    ..invalidate(nextDueProvider)
    ..invalidate(upcomingProvider)
    ..invalidate(bookingDetailProvider)
    ..invalidate(documentsProvider)
    ..invalidate(historyProvider)
    ..invalidate(referralProvider)
    // Money: the wallet and what a top-up is worth under the salon's rules.
    ..invalidate(walletProvider)
    ..invalidate(topupQuoteProvider)
    ..invalidate(billsProvider)
    ..invalidate(visitsTodayProvider)
    ..invalidate(visitsProvider)
    // The salon itself: its details, features and billing state.
    ..invalidate(salonProfileProvider)
    ..invalidate(salonFeaturesProvider)
    ..invalidate(salonBillingProvider)
    ..invalidate(dashboardProvider);
}
