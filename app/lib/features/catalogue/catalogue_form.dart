import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// What the owner typed. Money leaves this form as **integer paise**: the text
/// field collects rupees because that is what a price list is written in, and it
/// is converted once, here, with integer arithmetic (`RULES.md` 5.1.2).
class CatalogueDraft {
  const CatalogueDraft({
    required this.name,
    required this.active,
    this.pricePaise = 0,
    this.minutes = 0,
  });

  final String name;
  final bool active;
  final int pricePaise;
  final int minutes;
}

/// The add/edit sheet for a service, an add-on or a team member.
///
/// One form, three shapes, because three near-identical forms is how two of them
/// end up validating differently. The bounds match the database's own CHECK
/// constraints (5-600 minutes, price >= 0): the app catches a typo early, and
/// the database is still what decides.
class CatalogueForm extends StatefulWidget {
  const CatalogueForm({
    required this.title,
    required this.draft,
    this.showPrice = true,
    this.showMinutes = true,
    this.minutesLabelIsExtra = false,
    super.key,
  });

  final String title;
  final CatalogueDraft draft;
  final bool showPrice;
  final bool showMinutes;

  /// Add-ons add time to a service rather than having their own duration.
  final bool minutesLabelIsExtra;

  static Future<CatalogueDraft?> open(
    BuildContext context, {
    required String title,
    required CatalogueDraft draft,
    bool showPrice = true,
    bool showMinutes = true,
    bool minutesLabelIsExtra = false,
  }) {
    return showModalBottomSheet<CatalogueDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CatalogueForm(
        title: title,
        draft: draft,
        showPrice: showPrice,
        showMinutes: showMinutes,
        minutesLabelIsExtra: minutesLabelIsExtra,
      ),
    );
  }

  @override
  State<CatalogueForm> createState() => _CatalogueFormState();
}

class _CatalogueFormState extends State<CatalogueForm> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _minutes;
  late bool _active;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.draft.name);
    _price = TextEditingController(
      text: widget.draft.pricePaise == 0 ? '' : _rupeesInput(widget.draft.pricePaise),
    );
    _minutes = TextEditingController(
      text: widget.draft.minutes == 0 ? '' : widget.draft.minutes.toString(),
    );
    _active = widget.draft.active;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _minutes.dispose();
    super.dispose();
  }

  /// Paise back into an editable rupee string, without going through a double.
  static String _rupeesInput(int paise) {
    final whole = paise ~/ 100;
    final fraction = paise % 100;
    return fraction == 0 ? '$whole' : '$whole.${fraction.toString().padLeft(2, '0')}';
  }

  /// "400", "400.5", "400.50", "₹400" -> paise. Null when it is not an amount.
  /// Integer arithmetic only: 400.35 must not arrive as 40034.
  static int? _toPaise(String raw) {
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(raw.replaceAll(RegExp('[₹, ]'), ''));
    if (match == null) return null;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return int.parse(match.group(1)!) * 100 + int.parse(fraction);
  }

  void _submit() {
    final l10n = AppL10n.of(context);

    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.formNameRequired);
      return;
    }

    var paise = 0;
    if (widget.showPrice) {
      final parsed = _toPaise(_price.text.trim());
      if (parsed == null) {
        setState(() => _error = l10n.formPriceInvalid);
        return;
      }
      paise = parsed;
    }

    var minutes = 0;
    if (widget.showMinutes) {
      final parsed = int.tryParse(_minutes.text.trim());
      // An add-on may add no time; a service must take some. The database says
      // 5-600 for a service duration, so the form says the same.
      final floor = widget.minutesLabelIsExtra ? 0 : 5;
      if (parsed == null || parsed < floor || parsed > 600) {
        setState(() => _error = l10n.formDurationInvalid);
        return;
      }
      minutes = parsed;
    }

    Navigator.of(context).pop(
      CatalogueDraft(name: name, active: _active, pricePaise: paise, minutes: minutes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return Padding(
      // Above the keyboard, and clear of the home indicator.
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l10n.fieldName),
            ),
            if (widget.showPrice) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(labelText: l10n.fieldPrice),
              ),
            ],
            if (widget.showMinutes) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: widget.minutesLabelIsExtra
                      ? l10n.fieldExtraMinutes
                      : l10n.fieldDuration,
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Hiding is not deleting: past bookings keep their own snapshot of
            // the price and duration (ARCHITECTURE 6.2).
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: Text(l10n.fieldVisible),
              contentPadding: EdgeInsets.zero,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _submit, child: Text(l10n.actionSave)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.actionCancel),
            ),
          ],
        ),
      ),
    );
  }
}
