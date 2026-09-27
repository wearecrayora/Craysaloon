import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/join/cray_api.dart';
import '../../l10n/app_localizations.dart';
import 'join_controller.dart';
import 'qr_scan_sheet.dart';

/// U2-U6, the whole join flow.
///
/// One screen per step, chosen from the controller's state rather than pushed:
/// the steps are a sequence the server governs, not a stack the customer can
/// wander back into. From [JoinStep.confirm] onward the app is already wearing
/// the salon's branding - that is the moment the white-label promise is kept.
class JoinScreen extends ConsumerWidget {
  const JoinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(joinControllerProvider);

    return Scaffold(
      appBar: AppBar(
        // Once the salon is known, the bar carries ITS name and keeps it: this
        // is the salon's app from here on (DESIGN 2.1). The step's own heading
        // lives in the body, so nothing is said twice.
        title: Text(state.salon?.displayName ?? AppL10n.of(context).joinTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: switch (state.step) {
            JoinStep.code => const _CodeStep(),
            JoinStep.confirm => const _ConfirmStep(),
            JoinStep.phone => const _PhoneStep(),
            JoinStep.otp => const _OtpStep(),
            JoinStep.done => const _DoneStep(),
          },
        ),
      ),
    );
  }
}

/// The only place a failure becomes words. `alreadyBound` says a salon, never
/// WHICH salon (`RULES.md` 4.4) - the server does not tell us either.
String? problemText(BuildContext context, JoinProblem problem) {
  final l10n = AppL10n.of(context);
  return switch (problem) {
    JoinProblem.none => null,
    JoinProblem.codeNotFound => l10n.joinCodeInvalid,
    JoinProblem.salonUnavailable => l10n.joinSalonUnavailable,
    JoinProblem.rateLimited => l10n.joinRateLimited,
    JoinProblem.offline => l10n.joinOffline,
    JoinProblem.invalidPhone => l10n.phoneHint,
    JoinProblem.wrongCode => l10n.joinGenericError,
    JoinProblem.otpExpired => l10n.otpExpired,
    JoinProblem.alreadyBound => l10n.joinAlreadyBound,
    JoinProblem.accountConflict => l10n.otpAccountConflict,
    JoinProblem.generic => l10n.joinGenericError,
  };
}

class _Problem extends StatelessWidget {
  const _Problem(this.problem, {this.message});

  final JoinProblem problem;

  /// A more specific sentence than the kind alone can give - "2 tries left".
  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message ?? problemText(context, problem);
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status colours are fixed, never themed (DESIGN 3.1).
          Icon(Icons.error_outline, size: 20, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeStep extends ConsumerStatefulWidget {
  const _CodeStep();

  @override
  ConsumerState<_CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends ConsumerState<_CodeStep> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(joinControllerProvider);

    return ListView(
      children: [
        // Scanning is the fast path; typing is the one that always works. Both
        // are offered, and a refused camera lands back here rather than in a
        // dead end (IMPLEMENTATION U2).
        FilledButton.icon(
          onPressed: state.busy
              ? null
              : () async {
                  final code = await QrScanSheet.open(context);
                  if (code == null || !context.mounted) return;
                  _controller.text = code.value;
                  await ref.read(joinControllerProvider.notifier).submitCode(code.value);
                },
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(l10n.joinScanButton),
        ),
        const SizedBox(height: 24),
        Text(l10n.joinEnterCode, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(hintText: l10n.joinCodeHint),
          // Uppercase as they type: the code is printed in uppercase, and a
          // lowercase echo makes people think they typed it wrong.
          inputFormatters: [_Upper()],
          onSubmitted: (value) =>
              ref.read(joinControllerProvider.notifier).submitCode(value),
        ),
        _Problem(state.problem),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: state.busy
              ? null
              : () => ref.read(joinControllerProvider.notifier).submitCode(_controller.text),
          child: Text(state.busy ? '…' : l10n.joinContinue),
        ),
      ],
    );
  }
}

class _Upper extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) =>
      value.copyWith(text: value.text.toUpperCase());
}

class _ConfirmStep extends ConsumerWidget {
  const _ConfirmStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(joinControllerProvider);
    final salon = state.salon;
    if (salon == null) return const SizedBox.shrink();

    return ListView(
      children: [
        Text(
          l10n.joinConfirmTitle(salon.displayName),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        // The licensing boundary, said plainly before anyone commits: credit is
        // redeemable only at the issuing salon (RULES 2).
        Text(l10n.joinConfirmBody, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => ref.read(joinControllerProvider.notifier).confirmSalon(),
          child: Text(l10n.joinContinue),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => ref.read(joinControllerProvider.notifier).backToCode(),
          child: Text(l10n.joinNotThisSalon),
        ),
      ],
    );
  }
}

class _PhoneStep extends ConsumerStatefulWidget {
  const _PhoneStep();

  @override
  ConsumerState<_PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends ConsumerState<_PhoneStep> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(joinControllerProvider);
    final notifier = ref.read(joinControllerProvider.notifier);

    return ListView(
      children: [
        Text(l10n.phoneTitle, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(hintText: l10n.phoneHint),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          onSubmitted: (value) => notifier.submitPhone(value),
        ),
        const SizedBox(height: 16),
        // Service messages ARE the service: they are stated, not asked for.
        // Marketing is asked for, separately, and starts off (RULES 11).
        Text(l10n.phoneServiceNote, style: Theme.of(context).textTheme.bodySmall),
        CheckboxListTile(
          value: state.promotional,
          onChanged: (v) => notifier.setPromotional(v ?? false),
          title: Text(l10n.phoneConsentPromotional),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          value: state.whatsapp,
          onChanged: (v) => notifier.setWhatsapp(v ?? false),
          title: Text(l10n.phoneConsentWhatsapp),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        _Problem(state.problem),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: state.busy ? null : () => notifier.submitPhone(_controller.text),
          child: Text(state.busy ? '…' : l10n.joinStart),
        ),
      ],
    );
  }
}

class _OtpStep extends ConsumerStatefulWidget {
  const _OtpStep();

  @override
  ConsumerState<_OtpStep> createState() => _OtpStepState();
}

class _OtpStepState extends ConsumerState<_OtpStep> {
  final _controller = TextEditingController();
  Timer? _tick;
  int _left = 0;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  /// Message Central's code lives about a minute, and the app must show THEIR
  /// number rather than assume one (ADR-36). When it runs out the offer is a
  /// resend, never "type it again".
  void _startCountdown() {
    _left = ref.read(joinControllerProvider).challenge?.expiresIn ?? 0;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(joinControllerProvider);
    final notifier = ref.read(joinControllerProvider.notifier);

    // A wrong code with attempts left says how many; the generic text would
    // leave someone guessing whether the app or the code is broken.
    final attemptsMessage = state.problem == JoinProblem.wrongCode && state.attemptsLeft != null
        ? l10n.otpWrongCode('${state.attemptsLeft}')
        : null;

    return ListView(
      children: [
        Text(l10n.otpTitle, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          l10n.otpSentTo(_masked(state.phone)),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.go,
          // Android autofills the code from the SMS when the format matches.
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          onSubmitted: (value) => notifier.submitOtp(value),
        ),
        const SizedBox(height: 8),
        if (_left > 0)
          Text(l10n.otpExpiresIn(_left), style: Theme.of(context).textTheme.bodySmall),
        _Problem(state.problem, message: attemptsMessage),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: state.busy || _left == 0
              ? null
              : () => notifier.submitOtp(_controller.text),
          child: Text(state.busy ? '…' : l10n.joinContinue),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: state.busy
              ? null
              : () async {
                  _controller.clear();
                  await notifier.resend();
                  if (mounted) _startCountdown();
                },
          child: Text(l10n.otpResend),
        ),
      ],
    );
  }

  /// The number is shown back partly hidden: someone else may be looking at the
  /// screen, and the customer knows their own number.
  static String _masked(String phone) {
    if (phone.length < 4) return phone;
    return '•••••• ${phone.substring(phone.length - 4)}';
  }
}

class _DoneStep extends ConsumerWidget {
  const _DoneStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(joinControllerProvider);
    final salon = state.salon;

    return ListView(
      children: [
        Text(
          l10n.joinedTitle(salon?.displayName ?? ''),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          state.outcome == LoginOutcome.staff ? l10n.joinedStaff : l10n.joinedBody,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
