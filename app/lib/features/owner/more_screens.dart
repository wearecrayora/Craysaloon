import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/fine_print.dart';
import '../../core/ui/load_failed.dart';
import '../../app/providers.dart';
import '../../core/format/money.dart';
import '../../core/theme/cray_glass.dart';
import '../../domain/join/cray_api.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/salon_mark.dart';
import '../../domain/salon/salon_account.dart';
import '../../l10n/app_localizations.dart';
import '../salon/salon_account.dart';

/// O-More: everything an owner reaches less often than the day (Claude Design
/// O7-O13). The catalogue and the team are edited here; the salon's rules,
/// hours, billing and profile are SHOWN here and changed by Crayora in the
/// console - there is no owner write path for them, and a form that looked
/// editable but was refused would be worse than a page that says who to ask.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final ownerOrManager = ref.watch(canEditCatalogueProvider);

    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(l10n.moreTitle, style: text.headlineMedium),
          const SizedBox(height: 12),
          _Row(
            Icons.content_cut,
            l10n.catalogueServices,
            l10n.moreServicesSub,
            () => context.push('/catalogue/services'),
          ),
          _Row(
            Icons.add_circle_outline,
            l10n.catalogueAddOns,
            l10n.moreAddOnsSub,
            () => context.push('/catalogue/addons'),
          ),
          _Row(
            Icons.badge_outlined,
            l10n.staffTitle,
            l10n.moreTeamSub,
            () => context.push('/staff'),
          ),
          _Row(
            Icons.rule,
            l10n.rulesTitle,
            l10n.moreRulesSub,
            () => context.push('/more/rules'),
          ),
          _Row(
            Icons.schedule,
            l10n.hoursTitle,
            l10n.moreHoursSub,
            () => context.push('/more/hours'),
          ),
          if (ownerOrManager)
            _Row(
              Icons.receipt_long_outlined,
              l10n.billingTitle,
              l10n.moreBillingSub,
              () => context.push('/more/billing'),
            ),
          _Row(
            Icons.storefront_outlined,
            l10n.profileTitle,
            l10n.moreProfileSub,
            () => context.push('/more/profile'),
          ),
          const SizedBox(height: 24),
          const FinePrint(),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.title, this.subtitle, this.onTap);

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  Text(subtitle, style: text.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// A read-only page: a title, label/value rows, and one line saying who
/// changes it.
class _ReadOnlyPage extends StatelessWidget {
  const _ReadOnlyPage({
    required this.title,
    required this.children,
    required this.footer,
  });

  final String title;
  final List<Widget> children;
  final String footer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(title, style: text.headlineMedium),
          const SizedBox(height: 12),
          ...children,
          const SizedBox(height: 20),
          Text(footer, style: text.bodyMedium),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: text.bodyMedium)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(label, style: Theme.of(context).textTheme.titleLarge),
  );
}

/// Loads the salon profile and hands it to [builder]; says so plainly when it
/// cannot.
class _WithProfile extends ConsumerWidget {
  const _WithProfile({required this.builder});

  final Widget Function(BuildContext context, SalonProfile profile) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(salonProfileProvider);
    // An error is shown the moment there is one - not after Riverpod's
    // background retries run out, which offline is a spinner for ~40 seconds.
    return switch (profile) {
      AsyncData(:final value?) => builder(context, value),
      AsyncData() || AsyncValue(hasError: true) => Scaffold(
        appBar: AppBar(title: const SalonTitle()),
        body: LoadFailed(onRetry: () => ref.invalidate(salonProfileProvider)),
      ),
      _ => Scaffold(
        appBar: AppBar(title: const SalonTitle()),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

int? _paise(Map<String, Object?> rule, String key) =>
    (rule[key] as num?)?.toInt();

/// 500 -> "5%", 1250 -> "12.5%".
String _percent(int bp) =>
    '${(bp / 100).toStringAsFixed(bp % 100 == 0 ? 0 : 1)}%';

/// How long bonus credit lasts: shown to everyone, CHANGED only by the owner
/// (0097). A change applies to bonus given from now on - credit already given
/// keeps the date it was issued with, and the sheet says so before saving.
class _BonusExpiryRow extends ConsumerStatefulWidget {
  const _BonusExpiryRow({required this.days});

  final int days;

  @override
  ConsumerState<_BonusExpiryRow> createState() => _BonusExpiryRowState();
}

class _BonusExpiryRowState extends ConsumerState<_BonusExpiryRow> {
  static const _choices = [30, 60, 90, 180, 365, 0];
  bool _saving = false;

  String _label(AppL10n l10n, int days) =>
      days == 0 ? l10n.rulesNever : l10n.rulesDays(days);

  Future<void> _change() async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.rulesExpiryAsk,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.rulesExpiryNote,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            for (final d in _choices)
              ListTile(
                minTileHeight: 56,
                title: Text(_label(l10n, d)),
                trailing: d == widget.days ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(d),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == widget.days || !mounted) return;
    final api = ref.read(salonAccountApiProvider);
    if (api == null) return;
    setState(() => _saving = true);
    try {
      await api.setBonusExpiry(picked);
      ref.invalidate(salonProfileProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.rulesExpirySaved(_label(l10n, picked)))),
      );
    } on CrayApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.kind == CrayErrorKind.salonUnavailable
                ? l10n.billingReadOnlyOther
                : l10n.rulesSaveFailed,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final owner = ref.watch(sessionProvider)?.appRole == 'owner';

    final row = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(l10n.rulesBonusLasts, style: text.bodyMedium),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              _label(l10n, widget.days),
              textAlign: TextAlign.end,
              style: text.titleMedium,
            ),
          ),
          if (owner) ...[
            const SizedBox(width: 8),
            _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: CrayGlass.of(context).ink,
                  ),
          ],
        ],
      ),
    );

    if (!owner) return row;
    return Semantics(
      button: true,
      label: l10n.rulesExpiryAsk,
      child: Pressable(onTap: _saving ? null : _change, child: row),
    );
  }
}

/// O10 - the salon's rules, as the money and the reminders actually apply
/// them: the same keys the ledger and the referral release read.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return _WithProfile(
      builder: (context, p) {
        final every = _paise(p.walletRule, 'topup_paise');
        final bonus = _paise(p.walletRule, 'bonus_paise');
        final minimum = _paise(p.walletRule, 'min_topup_paise');
        final expiry = _paise(p.walletRule, 'bonus_expiry_days');
        final referrer = _paise(p.rewardRule, 'referrer_paise');
        final friend = _paise(p.rewardRule, 'referred_paise');

        return _ReadOnlyPage(
          title: l10n.rulesTitle,
          footer: l10n.rulesFooter,
          children: [
            _Heading(l10n.walletTitle),
            if (bonus != null && every != null && bonus > 0)
              _Field(
                l10n.rulesBonus,
                l10n.rulesBonusValue(rupees(bonus), rupees(every)),
              )
            else
              _Field(l10n.rulesBonus, l10n.rulesNone),
            if (minimum != null)
              _Field(l10n.rulesSmallestTopup, rupees(minimum)),
            // The one rule the OWNER sets, here (RULES 5.3.3). 180 days when
            // never set - the same default the ledger applies (wallet_bonus_for).
            _BonusExpiryRow(days: expiry ?? 180),
            // Paid credit never expires - there is no field for it (RULES 7).
            _Field(l10n.rulesPaidCredit, l10n.rulesNeverExpires),
            if (referrer != null || friend != null) ...[
              _Heading(l10n.referTitle),
              _Field(l10n.rulesReferrer, rupees(referrer ?? 0)),
              _Field(l10n.rulesFriend, rupees(friend ?? 0)),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.rulesReferralWhen,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (p.reminderCycleDays != null) ...[
              _Heading(l10n.rulesReminders),
              _Field(
                l10n.rulesRemindAfter,
                l10n.rulesDays(p.reminderCycleDays!),
              ),
            ],
            if ((p.cancellationPolicy ?? '').trim().isNotEmpty) ...[
              _Heading(l10n.rulesCancellation),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  p.cancellationPolicy!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// O12 - what the salon pays Crayora, and when. Owners and managers only; the
/// server does not send the price to anyone else (0087).
class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final ml = MaterialLocalizations.of(context);
    final billing = ref.watch(salonBillingProvider).value ?? SalonBilling.open;
    final state = switch (billing.state) {
      'active' => l10n.billingActive,
      'grace' => l10n.billingGrace,
      'suspended' => l10n.billingSuspended,
      'purge_due' => l10n.billingClosing,
      _ => l10n.billingUnbilled,
    };

    return _ReadOnlyPage(
      title: l10n.billingTitle,
      footer: l10n.billingFooter,
      children: [
        if (billing.plan != null) _Field(l10n.billingPlan, billing.plan!),
        _Field(l10n.billingStatus, state),
        if (billing.monthlyPricePaise != null)
          _Field(l10n.billingMonthly, rupees(billing.monthlyPricePaise!)),
        if (billing.renewsAt != null)
          _Field(
            l10n.billingPaidUntil,
            ml.formatMediumDate(billing.renewsAt!.toLocal()),
          ),
      ],
    );
  }
}

/// O13 - the salon as its customers see it, and who answers privacy questions.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return _WithProfile(
      builder: (context, p) {
        final privacy = [
          p.grievanceName,
          p.grievanceEmail ?? p.grievancePhone,
        ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');
        return _ReadOnlyPage(
          title: l10n.profileTitle,
          footer: l10n.profileFooter,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SalonMark(size: 56),
              ),
            ),
            _Field(l10n.meName, p.displayName),
            if ((p.legalName ?? '').isNotEmpty)
              _Field(l10n.profileLegalName, p.legalName!),
            if ((p.address ?? '').isNotEmpty)
              _Field(l10n.profileAddress, p.address!),
            if ((p.phone ?? '').isNotEmpty) _Field(l10n.mePhone, p.phone!),
            if ((p.email ?? '').isNotEmpty) _Field(l10n.profileEmail, p.email!),
            _Field(
              'GSTIN',
              p.gstNumber == null
                  ? l10n.profileNoGst
                  : p.gstRateBp == null
                  ? p.gstNumber!
                  : '${p.gstNumber} · ${_percent(p.gstRateBp!)}',
            ),
            if (privacy.isNotEmpty) _Field(l10n.profilePrivacyContact, privacy),
          ],
        );
      },
    );
  }
}
