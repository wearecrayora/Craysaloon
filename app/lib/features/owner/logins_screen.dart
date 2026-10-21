import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/load_failed.dart';
import '../../app/providers.dart';
import '../../core/ui/salon_mark.dart';
import '../../core/ui/skeleton.dart';
import '../../core/ui/notice.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/salon/staff_logins.dart';
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';

/// The owner's controls for who can sign in (0106). Null when the signed-in
/// API offers none - a test, or a build without it - and the screen says less.
final staffLoginsApiProvider = Provider<StaffLoginsApi?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is StaffLoginsApi ? api as StaffLoginsApi : null;
});

final staffLoginsProvider = FutureProvider<List<StaffLogin>>((ref) async {
  final api = ref.watch(staffLoginsApiProvider);
  return await api?.staffLogins() ?? const [];
});

/// Only the OWNER manages logins - the database refuses anyone else (0106);
/// the entry is hidden from them too, so nobody meets a button that fails.
final canManageLoginsProvider = Provider<bool>(
  (ref) => ref.watch(sessionProvider)?.appRole == 'owner',
);

String loginRefusalText(AppL10n l10n, LoginRefusal r) => switch (r) {
  LoginRefusal.numberInUse => l10n.loginsNumberInUse,
  LoginRefusal.badPhone => l10n.loginsBadPhone,
  LoginRefusal.nameRequired => l10n.loginsNameRequired,
  LoginRefusal.ownerLogin => l10n.loginsOwnLogin,
  LoginRefusal.salonUnavailable || LoginRefusal.notFound => l10n.loginsFailed,
};

class LoginsScreen extends ConsumerWidget {
  const LoginsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final logins = ref.watch(staffLoginsProvider);

    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(l10n.loginsAdd),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(staffLoginsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Text(l10n.loginsTitle, style: text.headlineMedium),
            const SizedBox(height: 8),
            Text(l10n.loginsIntro, style: text.bodyMedium),
            const SizedBox(height: 16),
            switch (logins) {
              AsyncData(:final value) => Column(
                children: [for (final l in value) _LoginTile(login: l)],
              ),
              AsyncValue(hasError: true) => LoadFailed(
                inline: true,
                onRetry: () => ref.invalidate(staffLoginsProvider),
              ),
              _ => const SkeletonList(rows: 3, padding: EdgeInsets.all(24)),
            },
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final draft = await showModalBottomSheet<_Draft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _AddLoginSheet(),
    );
    if (draft == null) return;
    final api = ref.read(staffLoginsApiProvider);
    if (api == null) return;
    try {
      final r = await api.addStaffLogin(
        name: draft.name,
        phone: draft.phone,
        role: draft.role,
      );
      messenger.notice(
        r.ok ? l10n.loginsAdded(draft.name) : loginRefusalText(l10n, r.refusal!),
        kind: r.ok ? NoticeKind.done : NoticeKind.problem,
      );
      if (r.ok) ref.invalidate(staffLoginsProvider);
    } on CrayApiException {
      messenger.notice(l10n.loginsFailed, kind: NoticeKind.problem);
    }
  }
}

class _LoginTile extends ConsumerWidget {
  const _LoginTile({required this.login});

  final StaffLogin login;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final role = switch (login.role) {
      LoginRole.owner => l10n.loginsRoleOwner,
      LoginRole.manager => l10n.loginsRoleManager,
      LoginRole.staff => l10n.loginsRoleStylist,
    };
    final status = !login.active
        ? l10n.loginsSwitchedOff
        : (login.signedIn ? l10n.loginsCanSignIn : l10n.loginsNotYet);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(login.name, style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '$role · ••••${login.phoneLast4}',
                    style: text.bodyMedium,
                  ),
                  Text(status, style: text.bodySmall),
                ],
              ),
            ),
            if (login.role != LoginRole.owner)
              Semantics(
                label: login.active
                    ? l10n.loginsSwitchOff
                    : l10n.loginsSwitchOn,
                child: Switch(
                  value: login.active,
                  onChanged: (on) => _set(context, ref, on),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, bool on) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(staffLoginsApiProvider);
    if (api == null) return;
    try {
      final r = await api.setStaffLoginActive(login.id, active: on);
      if (!r.ok) {
        messenger.notice(loginRefusalText(l10n, r.refusal!), kind: NoticeKind.problem);
      }
      ref.invalidate(staffLoginsProvider);
    } on CrayApiException {
      messenger.notice(l10n.loginsFailed, kind: NoticeKind.problem);
    }
  }
}

class _Draft {
  const _Draft(this.name, this.phone, this.role);
  final String name;
  final String phone;
  final LoginRole role;
}

class _AddLoginSheet extends StatefulWidget {
  const _AddLoginSheet();

  @override
  State<_AddLoginSheet> createState() => _AddLoginSheetState();
}

class _AddLoginSheetState extends State<_AddLoginSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  LoginRole _role = LoginRole.staff;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.loginsAdd, style: text.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l10n.loginsName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l10n.loginsPhone),
          ),
          const SizedBox(height: 16),
          RadioGroup<LoginRole>(
            groupValue: _role,
            onChanged: (r) => setState(() => _role = r ?? _role),
            child: Column(
              children: [
                RadioListTile<LoginRole>(
                  value: LoginRole.staff,
                  title: Text(l10n.loginsRoleStylist),
                  subtitle: Text(l10n.loginsStylistHint),
                ),
                RadioListTile<LoginRole>(
                  value: LoginRole.manager,
                  title: Text(l10n.loginsRoleManager),
                  subtitle: Text(l10n.loginsManagerHint),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final name = _name.text.trim();
              final phone = _phone.text.trim();
              if (name.isEmpty || phone.isEmpty) return;
              Navigator.of(context).pop(_Draft(name, phone, _role));
            },
            child: Text(l10n.loginsSave),
          ),
        ],
      ),
    );
  }
}
