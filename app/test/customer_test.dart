import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/domain/customer/customer.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/salon/salon_home.dart';
import 'package:craysalon/features/wallet/wallet_controller.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'salon_home_test.dart' show FakeNotifications, FakeShortcut;
import 'support/fake_cray_api.dart';
import 'support/fake_customer_api.dart';
import 'wallet_test.dart' show FakeWalletApi;

/// The customer redesign (Claude Design C1, C5-C10, C12): home, booking in
/// four steps, a booking's detail, visit history and Me.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'cray.shortcut_offered': true}));

  final branding = CachedBranding(
    salonId: '11111111-0000-4000-8000-000000000001',
    displayName: 'Studio Nine Salon',
    version: 3,
    document: publishedBranding(),
  );

  Future<void> pump(WidgetTester tester, FakeCustomerApi api, {bool wallet = false}) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(api),
          sessionProvider.overrideWithValue(api.session),
          initialBrandingProvider.overrideWithValue(branding),
          homeShortcutProvider.overrideWithValue(FakeShortcut(supported: false)),
          salonNotificationsProvider.overrideWithValue(FakeNotifications()),
          if (wallet) walletApiProvider.overrideWithValue(FakeWalletApi()),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder filled(String label) => find.widgetWithText(FilledButton, label);

  bool enabled(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(filled(label)).onPressed != null;

  group('birthday (0113)', () {
    Future<void> openMe(WidgetTester tester) async {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Me')));
      await tester.pumpAndSettle();
    }

    testWidgets('a customer adds their birthday - the day and month, never the year',
        (tester) async {
      final api = FakeCustomerApi();
      await pump(tester, api);
      await openMe(tester);

      expect(find.textContaining('Add it for a birthday treat'), findsOneWidget);
      await tester.tap(find.text('Your birthday'));
      await tester.pumpAndSettle();
      expect(find.textContaining('never the year'), findsOneWidget);

      await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('March').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(api.profile?.birthdayMonth, 3);
      expect(api.profile?.birthdayDay, 16);
      expect(find.text('March 16'), findsOneWidget);
    });

    testWidgets('a child is never asked for a birthday', (tester) async {
      final api = FakeCustomerApi()
        ..profile = const CustomerProfile(name: 'Chotu', phone: '9812344821', isMinor: true);
      await pump(tester, api);
      await openMe(tester);
      expect(find.text('Your birthday'), findsNothing);
    });

    testWidgets('in the birthday month, home shows what to claim at the counter',
        (tester) async {
      final api = FakeCustomerApi()..birthdayOffer = 'a free head massage';
      await pump(tester, api);
      expect(find.text('Happy birthday month!'), findsOneWidget);
      expect(find.text('a free head massage - show this at the counter.'), findsOneWidget);
    });

    testWidgets('and in any other month, nothing', (tester) async {
      await pump(tester, FakeCustomerApi());
      expect(find.text('Happy birthday month!'), findsNothing);
    });
  });

  group('C1 home', () {
    testWidgets('greets by first name, and says when they are due', (tester) async {
      final api = FakeCustomerApi()
        ..due = NextDue(dueOn: DateTime(2026, 10, 14), serviceName: 'Haircut');
      await pump(tester, api);

      expect(find.textContaining(RegExp(r'^Good (morning|afternoon|evening), Asha$')), findsOneWidget);
      expect(find.text('Your next haircut is due around Oct 14'), findsOneWidget);
      expect(find.text('Book now'), findsOneWidget);
    });

    testWidgets('no name on record: a true greeting, never "Hi null"', (tester) async {
      final api = FakeCustomerApi()..profile = const CustomerProfile();
      await pump(tester, api);

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('the balance never appears without its line (DESIGN 6.1)', (tester) async {
      await pump(tester, FakeCustomerApi(), wallet: true);
      // The wallet card sits below the categories, tiles and services now.
      final line = find.text('Usable only at Studio Nine Salon. Cannot be withdrawn as cash.');
      await tester.scrollUntilVisible(line, 300, scrollable: find.byType(Scrollable).first);

      expect(line, findsOneWidget);
      // The balance is in the same card as its line, never apart from it.
      final card = find.ancestor(of: line, matching: find.byType(Card)).first;
      expect(find.descendant(of: card, matching: find.textContaining('₹')), findsWidgets);
    });

    testWidgets('only somebody who never came is told it would be their first visit',
        (tester) async {
      await pump(tester, FakeCustomerApi());
      expect(find.text('Book your first visit'), findsOneWidget);
    });

    testWidgets('a returning customer with no reminder is invited back, not welcomed',
        (tester) async {
      final api = FakeCustomerApi()
        ..visitsList = [
          PastVisit(id: 'v1', completedAt: DateTime(2026, 9, 12), amountPaise: 60000, paid: true),
        ];
      await pump(tester, api);
      expect(find.text('Book your next visit'), findsOneWidget);
      expect(find.text('Book your first visit'), findsNothing);
    });

    testWidgets('no offers card: there is no offers feature behind one', (tester) async {
      await pump(tester, FakeCustomerApi());
      expect(find.text('Offer'), findsNothing);
    });

    testWidgets('four destinations, one thumb away', (tester) async {
      await pump(tester, FakeCustomerApi());
      for (final label in ['Home', 'Book', 'Wallet', 'Me']) {
        expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
            findsOneWidget);
      }
    });
  });

  group('C5-C8 booking', () {
    Future<void> toTimes(WidgetTester tester) async {
      await tester.tap(find.text('Book').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Haircut'));
      await tester.pumpAndSettle();
      await tester.tap(filled('Continue'));
      await tester.pumpAndSettle();
      // Add-ons: skipped, nothing ticked.
      await tester.tap(filled('Continue'));
      await tester.pumpAndSettle();
      // Tomorrow, so no offered time is in the past whenever this runs.
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.tap(find.text('${tomorrow.day}').first);
      await tester.pumpAndSettle();
    }

    testWidgets('nothing is chosen for the customer on open', (tester) async {
      await pump(tester, FakeCustomerApi());
      await tester.tap(find.text('Book').last);
      await tester.pumpAndSettle();

      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(enabled(tester, 'Continue'), isFalse);
      // Grouped by the salon's categories; a retired service is not offered.
      expect(find.text('Hair'), findsOneWidget);
      expect(find.text('Beard'), findsOneWidget);
      expect(find.text('Retired service'), findsNothing);
    });

    testWidgets('add-ons are never pre-ticked', (tester) async {
      await pump(tester, FakeCustomerApi());
      await tester.tap(find.text('Book').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Haircut'));
      await tester.pumpAndSettle();
      await tester.tap(filled('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Head massage'), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsNothing);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    });

    testWidgets('only free times, one button per time; the booking is the customer\'s own',
        (tester) async {
      final api = FakeCustomerApi();
      await pump(tester, api);
      await toTimes(tester);

      // Two stylists free at 10:00 under "Anyone" - one button.
      expect(find.text('10:00 AM'), findsOneWidget);
      expect(find.text('12:00 PM'), findsOneWidget);

      await tester.tap(find.text('10:00 AM'));
      await tester.pumpAndSettle();
      await tester.tap(filled('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Review your booking'), findsOneWidget);
      expect(find.text('Suresh'), findsOneWidget);
      expect(find.text('₹600'), findsOneWidget);
      // Nothing is paid now, and the screen says so.
      expect(find.textContaining('You pay after your visit'), findsOneWidget);

      await tester.tap(filled('Confirm booking'));
      await tester.pumpAndSettle();

      expect(api.bookings, hasLength(1));
      final b = api.bookings.single;
      expect(b['service'], 's-cut');
      expect(b['staff'], 'st-suresh');
      expect(b['addOns'], isEmpty);
      // Never names a customer: the server takes it from the token.
      expect(b['customer'], isNull);
      // Straight from Confirm: the moment, not just the record (21 Oct 2026).
      expect(find.text("You're booked!"), findsOneWidget);
    });

    testWidgets('a time taken meanwhile sends them back to pick again, never double-books',
        (tester) async {
      final api = FakeCustomerApi()..bookErrors.add(const CrayApiException(CrayErrorKind.slotTaken));
      await pump(tester, api);
      await toTimes(tester);
      await tester.tap(find.text('10:00 AM'));
      await tester.pumpAndSettle();
      await tester.tap(filled('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(filled('Confirm booking'));
      await tester.pumpAndSettle();

      expect(find.text('That time was just taken. Please pick another.'), findsOneWidget);
      expect(find.text('Stylist and time'), findsOneWidget);
      expect(enabled(tester, 'Continue'), isFalse, reason: 'the taken time is no longer chosen');

      await tester.tap(find.text('12:00 PM'));
      await tester.pumpAndSettle();
      await tester.tap(filled('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(filled('Confirm booking'));
      await tester.pumpAndSettle();

      expect(api.bookings, hasLength(2));
      expect(api.bookings[1]['action'], isNot(api.bookings[0]['action']),
          reason: 'a different booking is a different action');
    });

    testWidgets('a retry after a dropped connection reuses the SAME action id', (tester) async {
      final api = FakeCustomerApi()..bookErrors.add(const CrayApiException(CrayErrorKind.network));
      await pump(tester, api);
      await toTimes(tester);
      await tester.tap(find.text('10:00 AM'));
      await tester.pumpAndSettle();
      await tester.tap(filled('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(filled('Confirm booking'));
      await tester.pumpAndSettle();

      expect(find.text('Could not book. Check your connection and try again.'), findsOneWidget);

      await tester.tap(filled('Confirm booking'));
      await tester.pumpAndSettle();

      expect(api.bookings, hasLength(2));
      expect(api.bookings[1]['action'], api.bookings[0]['action'],
          reason: 'the server sees one booking, however many times it is sent');
    });
  });

  group('C9 booking detail', () {
    UpcomingBooking inTwoDays() {
      final d = DateTime.now().add(const Duration(days: 2));
      final starts = DateTime(d.year, d.month, d.day, 16, 30);
      return UpcomingBooking(
        id: 'b-9',
        startsAt: starts,
        endsAt: starts.add(const Duration(minutes: 60)),
        status: 'confirmed',
        totalPaise: 75000,
        serviceNames: 'Haircut + Head massage',
        staffName: 'Suresh',
      );
    }

    testWidgets('the next booking is on home, and opens', (tester) async {
      final api = FakeCustomerApi()..upcomingList = [inTwoDays()];
      await pump(tester, api);

      expect(find.text('Your next booking'), findsOneWidget);
      await tester.tap(find.text('Your next booking'));
      await tester.pumpAndSettle();

      expect(find.text('Your booking'), findsOneWidget);
      expect(find.text('Haircut + Head massage'), findsOneWidget);
      expect(find.text('₹750'), findsOneWidget);
      expect(find.text('Booked'), findsOneWidget);
    });

    testWidgets('cancel asks first; "Keep it" cancels nothing', (tester) async {
      final api = FakeCustomerApi()..upcomingList = [inTwoDays()];
      await pump(tester, api);
      await tester.tap(find.text('Your next booking'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this booking?'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(api.cancels, isEmpty);

      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel booking'));
      await tester.pumpAndSettle();

      expect(api.cancels, hasLength(1));
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Cancel booking'), findsNothing, reason: 'nothing left to cancel');
    });
  });

  group('receipts and invoices (0094)', () {
    FakeCustomerApi withDocs() => FakeCustomerApi()
      ..visitsList = [
        PastVisit(
          id: 'v1',
          completedAt: DateTime(2026, 9, 12),
          amountPaise: 45000,
          paid: true,
          serviceNames: 'Haircut',
        ),
      ]
      ..documentList = [
        SalonDocument(
          kind: DocumentKind.taxInvoice,
          number: 'INV/2627/00001',
          issuedAt: DateTime(2026, 9, 12),
          visitId: 'v1',
          totalPaise: 45000,
          taxablePaise: 42857,
          cgstPaise: 1071,
          sgstPaise: 1072,
          gstRateBp: 500,
          gstin: '29ABCDE1234F1Z5',
          walletPaidPaise: 40000,
          bonusPaise: 5000,
          lines: const [DocumentLine(kind: 'service', name: 'Haircut', pricePaise: 45000)],
        ),
        SalonDocument(
          kind: DocumentKind.receipt,
          number: 'RCT/2627/00001',
          issuedAt: DateTime(2026, 9, 1),
          totalPaise: 50000,
          bonusPaise: 5000,
        ),
      ];

    Future<void> openDocs(WidgetTester tester) async {
      await tester.tap(find.text('Me').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receipts and invoices'));
      await tester.pumpAndSettle();
    }

    testWidgets('a top-up is a RECEIPT, and says it is not a tax invoice', (tester) async {
      await pump(tester, withDocs());
      await openDocs(tester);

      await tester.tap(find.text('Receipt'));
      await tester.pumpAndSettle();

      expect(find.text('Number: RCT/2627/00001'), findsOneWidget);
      expect(find.text('This is a receipt for credit added to your wallet. It is not a tax invoice.'),
          findsOneWidget);
      expect(find.text('Bonus credit added'), findsOneWidget);
      expect(find.text('CGST 2.5%'), findsNothing);
    });

    testWidgets('a paid visit opens its tax invoice: GST as issued, to the paisa', (tester) async {
      await pump(tester, withDocs());
      // Past visits live in My bookings now, under the Bookings tab.
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('Bookings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Haircut'));
      await tester.pumpAndSettle();

      expect(find.text('Tax invoice'), findsOneWidget);
      expect(find.text('GSTIN 29ABCDE1234F1Z5'), findsOneWidget);
      expect(find.text('CGST 2.5%'), findsOneWidget);
      expect(find.text('₹10.71'), findsOneWidget);
      expect(find.text('₹10.72'), findsOneWidget);
      expect(find.text('₹428.57'), findsOneWidget);
      // How it was paid, with the bonus apart.
      expect(find.text('Bonus credit'), findsOneWidget);
    });

    testWidgets('no documents yet says when they will come', (tester) async {
      await pump(tester, FakeCustomerApi());
      await openDocs(tester);
      expect(find.textContaining('A receipt appears when you add money'), findsOneWidget);
    });
  });

  group('C10 history and C12 me', () {
    testWidgets('history says paid or not - never a guessed method', (tester) async {
      final api = FakeCustomerApi()
        ..visitsList = [
          PastVisit(
            id: 'v1',
            completedAt: DateTime(2026, 9, 12),
            amountPaise: 60000,
            paid: true,
            serviceNames: 'Haircut',
            staffName: 'Suresh',
          ),
          PastVisit(
            id: 'v2',
            completedAt: DateTime(2026, 8, 14),
            amountPaise: 100000,
            paid: false,
            serviceNames: 'Haircut + Beard trim',
          ),
        ];
      await pump(tester, api);
      // Past visits live in My bookings now, under the Bookings tab.
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('Bookings')));
      await tester.pumpAndSettle();

      expect(find.text('Haircut'), findsOneWidget);
      expect(find.text('with Suresh'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Not paid yet'), findsOneWidget);
      expect(find.text('₹1,000'), findsOneWidget);
    });

    testWidgets('no visits yet: an empty state, not a blank screen', (tester) async {
      await pump(tester, FakeCustomerApi());
      // Past visits live in My bookings now, under the Bookings tab.
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('Bookings')));
      await tester.pumpAndSettle();

      expect(find.text('No bookings yet. Your first one will show here, with everything after it.'),
          findsOneWidget);
    });

    testWidgets('Me shows the number masked, and switches language', (tester) async {
      await pump(tester, FakeCustomerApi());
      await tester.tap(find.text('Me').last);
      await tester.pumpAndSettle();

      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('+91 98xxx x4821'), findsOneWidget);
      expect(find.text('9812344821'), findsNothing);

      await tester.scrollUntilVisible(find.text('App by Crayora'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('App by Crayora'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Language'), -200,
          scrollable: find.byType(Scrollable).first);

      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('हिन्दी').last);
      await tester.pumpAndSettle();

      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('होम')),
          findsOneWidget);
    });
  });
}
