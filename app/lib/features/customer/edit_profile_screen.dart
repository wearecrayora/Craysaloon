import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cray_glass.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/load_failed.dart';
import '../../core/ui/notice.dart';
import '../../core/ui/salon_mark.dart';
import '../../core/ui/skeleton.dart';
import '../../domain/customer/customer.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/privacy/privacy.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart' show kEnglish, kHindi, kHinglish, localeCode, localeProvider;
import '../join/join_controller.dart' show resolvedBrandingProvider;
import '../privacy/your_data_controller.dart' show privacyApiProvider;
import 'customer_providers.dart';
import '../app_config/app_config_providers.dart' show switchOn;
import '../../core/ui/menu.dart' show Initials;
import 'me_screen.dart' show dayMonthLabel, editBirthday;

/// Edit profile (21 Oct 2026): the customer's name and language are theirs to
/// change here; the birthday is one tap away; the phone number is shown, and
/// changing it is ASKED for (0118).
///
/// Why the number cannot simply be edited: it is how the salon knows it is
/// them - the binding (RULES 4). One number, one salon, and only Crayora moves
/// it, after the salon has confirmed who is asking. So "Change number" raises
/// a correction request with the 30-day clock every other right has, rather
/// than a field that would quietly hand an account to whoever holds the phone.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  TextEditingController? _name;
  Locale? _language;
  bool _busy = false;
  ProfileRefusal? _refusal;
  bool _failed = false;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  bool _dirty(CustomerProfile p) =>
      (_name != null && _name!.text.trim() != (p.name ?? '').trim()) ||
      (_language != null && _language != ref.read(localeProvider));

  Future<void> _save(CustomerProfile p) async {
    final api = ref.read(customerApiProvider);
    if (api == null) return;
    final l10n = AppL10n.of(context);
    final nameChanged = _name!.text.trim() != (p.name ?? '').trim();
    final language = _language;
    setState(() {
      _busy = true;
      _refusal = null;
      _failed = false;
    });
    try {
      final refusal = await api.updateMyProfile(
        name: nameChanged ? _name!.text : null,
        language: language == null ? null : localeCode(language),
      );
      if (!mounted) return;
      if (refusal != null) {
        setState(() {
          _busy = false;
          _refusal = refusal;
        });
        return;
      }
      if (language != null) ref.read(localeProvider.notifier).select(language);
      ref.invalidate(myProfileProvider);
      showNotice(context, l10n.profileSaved);
      if (context.canPop()) context.pop();
    } on CrayApiException {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final profile = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      body: switch (profile) {
        AsyncValue(:final value?, hasValue: true) => _form(context, value),
        AsyncValue(hasError: true) => LoadFailed(
          message: l10n.profileLoadFailed,
          onRetry: () => ref.invalidate(myProfileProvider),
        ),
        AsyncValue(hasValue: true) => LoadFailed(
          message: l10n.profileLoadFailed,
          onRetry: () => ref.invalidate(myProfileProvider),
        ),
        _ => const SkeletonList(rows: 3, padding: EdgeInsets.all(16)),
      },
    );
  }

  Widget _form(BuildContext context, CustomerProfile p) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final salonName = ref.watch(resolvedBrandingProvider)?.displayName ?? l10n.appTitle;
    _name ??= TextEditingController(text: p.name ?? '');
    final language = _language ?? ref.watch(localeProvider);

    final refusalText = switch (_refusal) {
      ProfileRefusal.nameLength => l10n.profileNameLength,
      ProfileRefusal.nameInvalid => l10n.profileNameInvalid,
      ProfileRefusal.erased => l10n.profileErased,
      ProfileRefusal.language => l10n.consentSaveFailed,
      null => _failed ? l10n.consentSaveFailed : null,
    };

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(l10n.meEditProfile, style: text.headlineMedium),
              const SizedBox(height: 16),
              Center(child: Initials(p.initials, size: 80)),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.name],
                maxLength: 60,
                onChanged: (_) => setState(() => _refusal = null),
                decoration: InputDecoration(
                  labelText: l10n.profileNameLabel,
                  hintText: l10n.profileNameHint,
                  helperText: l10n.profileNameHelp(salonName),
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              _PhoneRow(profile: p, salonName: salonName),
              const SizedBox(height: 24),
              Text(l10n.meLanguage, style: text.titleMedium),
              const SizedBox(height: 4),
              Text(l10n.profileLanguageHelp, style: text.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (locale, name) in [
                    (kEnglish, l10n.languageEnglish),
                    (kHindi, l10n.languageHindi),
                    (kHinglish, l10n.languageHinglish),
                  ])
                    ChoiceChip(
                      label: Text(name),
                      selected: language == locale,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) => setState(() => _language = locale),
                    ),
                ],
              ),
              if (!p.isMinor && switchOn(ref, 'birthday')) ...[
                const SizedBox(height: 24),
                Text(l10n.meBirthday, style: text.titleMedium),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => editBirthday(context, ref, p, salonName),
                  icon: const Icon(Icons.cake_outlined),
                  label: Text(
                    p.birthdayMonth == null
                        ? l10n.profileBirthdayAdd
                        : dayMonthLabel(context, p.birthdayMonth!, p.birthdayDay!),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => askForCorrection(context, ref, salonName: salonName),
                icon: const Icon(Icons.edit_note),
                label: Text(l10n.profileOtherCorrection),
              ),
              if (refusalText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(child: Text(refusalText, style: text.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _SaveBar(
          label: _busy ? '…' : l10n.profileSave,
          onPressed: _busy || !_dirty(p) ? null : () => _save(p),
        ),
      ],
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final g = CrayGlass.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: g.bar,
        border: Border(top: BorderSide(color: g.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FilledButton(onPressed: onPressed, child: Text(label)),
        ),
      ),
    );
  }
}

/// The number, shown and locked, with the way to change it.
class _PhoneRow extends ConsumerWidget {
  const _PhoneRow({required this.profile, required this.salonName});

  final CustomerProfile profile;
  final String salonName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.mePhone, style: text.bodySmall),
                Text(profile.maskedPhone ?? '—', style: text.titleMedium),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => askForCorrection(
              context,
              ref,
              salonName: salonName,
              phone: true,
            ),
            child: Text(l10n.profileChangeNumber),
          ),
        ],
      ),
    );
  }
}

/// Asking for a correction (DPDP s.12): a short sheet that says what happens
/// next, an optional line of detail, and one button. A request already open
/// is shown as asked, with its due date - never asked twice.
Future<void> askForCorrection(
  BuildContext context,
  WidgetRef ref, {
  required String salonName,
  bool phone = false,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CorrectionSheet(salonName: salonName, phone: phone),
  );
  if (sent == true && context.mounted) {
    showNotice(context, AppL10n.of(context).rightAskedThanks);
  }
}

class _CorrectionSheet extends ConsumerStatefulWidget {
  const _CorrectionSheet({required this.salonName, required this.phone});

  final String salonName;
  final bool phone;

  @override
  ConsumerState<_CorrectionSheet> createState() => _CorrectionSheetState();
}

class _CorrectionSheetState extends ConsumerState<_CorrectionSheet> {
  final _detail = TextEditingController();
  bool _busy = false;
  bool _failed = false;
  DataRightRequest? _open;

  @override
  void initState() {
    super.initState();
    _loadOpen();
  }

  Future<void> _loadOpen() async {
    final api = ref.read(privacyApiProvider);
    if (api == null) return;
    try {
      final mine = await api.myRequests();
      final open = mine.where((r) => r.kind == 'correction' && r.isOpen).firstOrNull;
      if (mounted && open != null) setState(() => _open = open);
    } on CrayApiException {
      // Shown as askable; the server returns the open one if there is one.
    }
  }

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final api = ref.read(privacyApiProvider);
    if (api == null) return;
    final l10n = AppL10n.of(context);
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final detail = _detail.text.trim();
      await api.requestRight(
        'correction',
        detail: [
          if (widget.phone) l10n.profileNumberRequestPrefix,
          if (detail.isNotEmpty) detail,
        ].join(' - '),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on CrayApiException {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final open = _open;
    final ml = MaterialLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.phone ? l10n.profileChangeNumberTitle : l10n.profileOtherCorrection,
                style: text.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                widget.phone
                    ? l10n.profileChangeNumberBody(widget.salonName)
                    : l10n.profileCorrectionBody(widget.salonName),
                style: text.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (open != null)
                Text(
                  l10n.rightAsked(ml.formatMediumDate(open.requestedAt), ml.formatMediumDate(open.dueAt)),
                  style: text.bodyMedium,
                )
              else ...[
                TextField(
                  controller: _detail,
                  maxLength: 200,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l10n.profileCorrectionDetail,
                    hintText: widget.phone
                        ? l10n.profileNumberDetailHint
                        : l10n.profileCorrectionDetailHint,
                  ),
                ),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(l10n.consentSaveFailed, style: text.bodyMedium),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  child: Text(_busy ? '…' : l10n.profileCorrectionSend),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(ml.closeButtonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
