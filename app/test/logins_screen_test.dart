import 'package:craysalon/app/providers.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/salon/staff_logins.dart';
import 'package:craysalon/features/owner/logins_screen.dart';
import 'package:craysalon/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0106: the owner adds and switches off their own staff's logins, and every
/// refusal is a sentence they can act on - none names another salon.
class FakeLogins implements StaffLoginsApi {
  final List<StaffLogin> logins = [
    const StaffLogin(id: 'u-owner', role: LoginRole.owner, name: 'Sunita Rao', phoneLast4: '4821', active: true, signedIn: true),
    const StaffLogin(id: 'u-priya', role: LoginRole.staff, name: 'Priya', phoneLast4: '1051', active: true, signedIn: false),
  ];
  LoginRefusal? refuseAdd;
  final List<(String, bool)> switched = [];

  @override
  Future<List<StaffLogin>> staffLogins() async => List.of(logins);

  @override
  Future<LoginOutcomeResult> addStaffLogin({required String name, required String phone, required LoginRole role}) async {
    if (refuseAdd != null) return LoginOutcomeResult.refused(refuseAdd!);
    logins.add(StaffLogin(id: 'u-new', role: role, name: name, phoneLast4: phone.substring(phone.length - 4), active: true, signedIn: false));
    return const LoginOutcomeResult.ok();
  }

  @override
  Future<LoginOutcomeResult> setStaffLoginActive(String id, {required bool active}) async {
    switched.add((id, active));
    final i = logins.indexWhere((l) => l.id == id);
    final l = logins[i];
    logins[i] = StaffLogin(id: l.id, role: l.role, name: l.name, phoneLast4: l.phoneLast4, active: active, signedIn: l.signedIn);
    return const LoginOutcomeResult.ok();
  }
}

void main() {
  Future<void> pump(WidgetTester tester, FakeLogins api) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(
          const AppSession(appRole: 'owner', salonId: '11111111-0000-4000-8000-000000000001'),
        ),
        staffLoginsApiProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: LoginsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> addPerson(WidgetTester tester, String name, String phone) async {
    await tester.tap(find.text('Add a login'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), name);
    await tester.enterText(find.widgetWithText(TextField, 'Their mobile number'), phone);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
  }

  testWidgets('the owner sees who can sign in - numbers by their last four only', (tester) async {
    await pump(tester, FakeLogins());
    expect(find.text('Who can sign in'), findsOneWidget);
    expect(find.text('Sunita Rao'), findsOneWidget);
    expect(find.textContaining('••••1051'), findsOneWidget);
    expect(find.text('Not signed in yet'), findsOneWidget);
  });

  testWidgets('and adds a stylist, who then appears', (tester) async {
    final api = FakeLogins();
    await pump(tester, api);
    await addPerson(tester, 'Ravi', '9810501061');
    expect(find.text('Ravi can now sign in'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
  });

  testWidgets('a number already in use says so - and names no salon', (tester) async {
    final api = FakeLogins()..refuseAdd = LoginRefusal.numberInUse;
    await pump(tester, api);
    await addPerson(tester, 'Ravi', '9810501061');
    expect(find.textContaining('already signs in to a salon'), findsOneWidget);
  });

  testWidgets('a stylist who leaves is switched off; the owner has no switch', (tester) async {
    final api = FakeLogins();
    await pump(tester, api);
    expect(find.byType(Switch), findsOneWidget, reason: 'one switch: Priya\'s, never the owner\'s');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(api.switched, [('u-priya', false)]);
    expect(find.text('Switched off'), findsOneWidget);
  });
}
