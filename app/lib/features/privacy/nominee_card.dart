import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/load_failed.dart';
import '../../core/ui/skeleton.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/privacy/privacy.dart';
import '../../l10n/app_localizations.dart';
import 'your_data_controller.dart';

/// Who this customer named to act for them (DPDP s.14, 0112). Read fresh each
/// time Your data opens; nobody but the customer can change it.
final nomineeProvider = FutureProvider.autoDispose<Nominee?>((ref) async {
  final api = ref.watch(privacyApiProvider);
  if (api == null) return null;
  return api.nominee();
});

/// "Someone to act for you": what a nominee can do, who it is, and the way to
/// name, change or remove them - on the same screen as the other rights.
class NomineeCard extends ConsumerWidget {
  const NomineeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final nominee = ref.watch(nomineeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.nomineeHeading, style: text.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.nomineeExplain, style: text.bodySmall),
        const SizedBox(height: 8),
        switch (nominee) {
          AsyncData(:final value) when value == null => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.nomineeNone, style: text.bodyMedium),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _edit(context, ref, null),
                  child: Text(l10n.nomineeAdd),
                ),
              ],
            ),
          AsyncData(:final value?) => Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value.name, style: text.titleSmall),
                    Text(
                      [if (value.relationship != null) value.relationship!, value.maskedPhone]
                          .join(' · '),
                      style: text.bodySmall,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => _edit(context, ref, value),
                          child: Text(l10n.nomineeChange),
                        ),
                        TextButton(
                          onPressed: () async {
                            await ref.read(privacyApiProvider)?.clearNominee();
                            ref.invalidate(nomineeProvider);
                          },
                          child: Text(l10n.nomineeRemove),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          AsyncValue(hasError: true) => LoadFailed(
              inline: true,
              onRetry: () => ref.invalidate(nomineeProvider),
            ),
          _ => const SkeletonList(rows: 3, padding: EdgeInsets.all(16)),
        },
      ],
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Nominee? current) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NomineeSheet(current: current),
    );
    if (saved == true) ref.invalidate(nomineeProvider);
  }
}

class _NomineeSheet extends ConsumerStatefulWidget {
  const _NomineeSheet({required this.current});

  final Nominee? current;

  @override
  ConsumerState<_NomineeSheet> createState() => _NomineeSheetState();
}

class _NomineeSheetState extends ConsumerState<_NomineeSheet> {
  late final _name = TextEditingController(text: widget.current?.name ?? '');
  final _phone = TextEditingController();
  late final _relation = TextEditingController(text: widget.current?.relationship ?? '');
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppL10n.of(context);
    final api = ref.read(privacyApiProvider);
    if (api == null) return;
    if (_name.text.trim().length < 2) {
      setState(() => _problem = l10n.nomineeNameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final refused = await api.setNominee(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        relationship: _relation.text.trim().isEmpty ? null : _relation.text.trim(),
      );
      if (!mounted) return;
      if (refused == null) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _problem = switch (refused) {
            NomineeRefusal.invalidPhone => l10n.nomineeInvalidPhone,
            NomineeRefusal.nameRequired => l10n.nomineeNameRequired,
          });
    } on CrayApiException {
      if (mounted) setState(() => _problem = l10n.consentSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return SafeArea(
      child: Padding(
        // Clear of the keyboard, which covers the bottom of a sheet otherwise.
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.nomineeHeading, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.nomineeName),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(labelText: l10n.nomineePhone, prefixText: '+91 '),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _relation,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.nomineeRelation),
              ),
              if (_problem != null) ...[
                const SizedBox(height: 12),
                Text(_problem!, style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? '…' : l10n.nomineeSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
