import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/join/cray_api.dart';
import '../../domain/records/records.dart';
import '../../l10n/app_localizations.dart';
import 'day_controller.dart';

/// Starting a service: the customer reads their code, the stylist types it.
///
/// "Required when possible" (decision of 29 Sep 2026), which means this sheet
/// has two jobs and must never confuse them:
///
///   * when the customer HAS the app and there IS a connection, the code is how
///     a service starts - and a wrong one is answered at once, while they are
///     still standing there;
///   * when it cannot be used - no app, no connection, a code locked by wrong
///     guesses - the stylist starts WITHOUT it. Nobody is turned away. The
///     server records why, and the owner sees every one.
///
/// The code is never shown here and never can be: staff cannot read it (0084).
class StartSheet extends ConsumerStatefulWidget {
  const StartSheet({required this.booking, super.key});

  final BookingRow booking;

  static Future<void> open(BuildContext context, BookingRow booking) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StartSheet(booking: booking),
    );
  }

  @override
  ConsumerState<StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends ConsumerState<StartSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;

  /// Why the "start without the code" option is on offer, if it is.
  _Without? _without;

  @override
  void initState() {
    super.initState();
    // No app, no code to read out: the only way to start is without one.
    if (!widget.booking.customerHasApp) _without = _Without.noApp;
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final l10n = AppL10n.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await ref
          .read(dayControllerProvider.notifier)
          .start(widget.booking, code: _code.text.trim());
      if (!mounted) return;
      if (result.started) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        switch (result.refusal!) {
          case StartRefusal.wrongCode:
            _message = l10n.startWrongCode(result.attemptsLeft ?? 0);
          case StartRefusal.codeLocked:
            _message = l10n.startLocked;
            _without = _Without.locked;
          case StartRefusal.noCodeIssued:
            _message = l10n.startNoCodeIssued;
            _without = _Without.noCodeIssued;
          case StartRefusal.notStartable:
            _message = l10n.startNotStartable;
        }
      });
    } on CrayApiException {
      // No connection: the code cannot be checked. Offer to start without it,
      // and say why, rather than leaving a customer in the chair waiting.
      if (!mounted) return;
      setState(() {
        _message = l10n.startOffline;
        _without = _Without.offline;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startWithout() async {
    setState(() => _busy = true);
    await ref.read(dayControllerProvider.notifier).startWithoutCode(widget.booking);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final without = _without;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.startTitle, style: text.titleLarge),
            const SizedBox(height: 8),
            if (widget.booking.customerHasApp) ...[
              Text(l10n.startAskForCode, style: text.bodyMedium),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: text.headlineMedium?.copyWith(letterSpacing: 12),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: _busy || _code.text.length != 4 ? null : _start,
                child: Text(_busy ? '…' : l10n.startWithCode),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: text.bodyMedium),
            ],
            if (without != null) ...[
              const SizedBox(height: 16),
              Text(
                switch (without) {
                  _Without.noApp => l10n.startNoAppExplained,
                  _ => l10n.startWithoutExplained,
                },
                style: text.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: _busy ? null : _startWithout,
                child: Text(l10n.startWithoutCode),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _Without { noApp, offline, locked, noCodeIssued }
