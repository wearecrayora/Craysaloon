import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/external_link.dart';
import '../../core/platform/otp_autofill.dart';
import '../../core/theme/cray_glass.dart';
import '../../core/theme/motion.dart';
import '../../core/ui/celebrate.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/salon_mark.dart';
import '../../core/ui/success_check.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/privacy/privacy.dart' show kWhatsappOffers;
import '../privacy/consent_notice.dart';
import '../../l10n/app_localizations.dart';
import 'join_controller.dart';
import 'qr_scan_sheet.dart';

/// Reads the one-time code from the SMS, with the customer's tap (Android), or
/// leaves it to the keyboard (iOS). Overridden in tests.
final otpAutofillProvider = Provider<OtpAutofill>(
  (ref) => const MethodChannelOtpAutofill(),
);

/// U2-U6, the whole join flow - which is also how a customer signs back in.
///
/// One screen per step, chosen from the controller's state rather than pushed:
/// the steps are a sequence the server governs, not a stack the customer can
/// wander back into. From [JoinStep.confirm] onward the app is already wearing
/// the salon's branding - that is the moment the white-label promise is kept.
///
/// Redesigned 21 Oct 2026: a progress bar says where you are (salon, number,
/// code), every step's one action is fixed at the bottom in the thumb's reach
/// (DESIGN 4.3), fields say what goes in them before anything is typed, and
/// the code is read from the SMS when the customer allows it.
class JoinScreen extends ConsumerWidget {
  const JoinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(joinControllerProvider);
    final onCode = state.step == JoinStep.code;
    final done = state.step == JoinStep.done;

    return Scaffold(
      // The code step is Crayora-neutral and carries its own hero. From the
      // confirmation on, the bar carries the SALON's mark and name and keeps
      // them: this is the salon's app from here (DESIGN 2.1). The step's own
      // heading lives in the body, so nothing is said twice.
      appBar: onCode
          ? null
          : AppBar(
              title: const SalonTitle(),
              automaticallyImplyLeading: false,
              leading: done
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      onPressed: () => ref.read(joinControllerProvider.notifier).back(),
                    ),
            ),
      body: SafeArea(
        top: !onCode,
        child: PopScope(
          // The system back gesture walks back through the steps too.
          canPop: onCode || done,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) ref.read(joinControllerProvider.notifier).back();
          },
          // Steps cross-fade with a short rise (DESIGN 7.2); with reduced
          // motion, a 100ms fade.
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.standard),
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: Motion.isReduced(context)
                  ? child
                  : SlideTransition(
                      position: Tween(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
            ),
            child: KeyedSubtree(
              key: ValueKey(state.step),
              child: switch (state.step) {
                JoinStep.code => const _CodeStep(),
                JoinStep.confirm => const _ConfirmStep(),
                JoinStep.phone => const _PhoneStep(),
                JoinStep.otp => const _OtpStep(),
                JoinStep.done => const _DoneStep(),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A step's frame: where you are, what to read and fill in (scrolling), and
/// the step's actions fixed at the bottom, above the keyboard when it is up.
class _StepFrame extends StatelessWidget {
  const _StepFrame({
    required this.children,
    required this.actions,
    this.progress,
    this.padded = true,
  });

  final List<Widget> children;
  final List<Widget> actions;
  final int? progress;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final g = CrayGlass.of(context);
    return Column(
      children: [
        if (progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _JoinProgress(at: progress!),
          ),
        Expanded(
          child: ListView(
            padding: padded
                ? const EdgeInsets.fromLTRB(16, 8, 16, 24)
                : const EdgeInsets.only(bottom: 24),
            children: children,
          ),
        ),
        // The bar the actions sit on: glass, with the hairline above it, so
        // the list visibly scrolls underneath.
        DecoratedBox(
          decoration: BoxDecoration(
            color: g.bar,
            border: Border(top: BorderSide(color: g.line)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: actions,
            ),
          ),
        ),
      ],
    );
  }
}

/// Salon · Number · Code: three bars, filled up to where you are, each named.
class _JoinProgress extends StatelessWidget {
  const _JoinProgress({required this.at});

  final int at;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final labels = [l10n.joinStepSalon, l10n.joinStepNumber, l10n.joinStepCode];
    return Semantics(
      label: l10n.bookStep(at + 1, labels.length),
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: Motion.of(context, Motion.standard),
                    curve: Motion.enter,
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= at ? scheme.primary : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      color: i == at ? scheme.onSurface : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The text under a field that says what to put in it - shown before anything
/// is typed, so nobody has to guess the format and be told off afterwards.
class _Guide extends StatelessWidget {
  const _Guide(this.text, {this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: style?.color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

/// A salon photo - a salon space, never a person (DESIGN 10) - optionally
/// fading into the mesh. Used where the salon is not yet, or only just, known;
/// the salon's own photos replace it when it has some.
class _Photo extends StatelessWidget {
  const _Photo({
    required this.asset,
    required this.height,
    this.fade = true,
    this.radius,
  });

  final String asset;
  final double height;
  final bool fade;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    Widget image = Image.asset(
      asset,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    );
    if (fade) {
      // An alpha mask, not a colour overlay: it fades into whatever mesh is
      // behind, in either mode, without naming a colour.
      image = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.55, 1],
        ).createShader(rect),
        child: image,
      );
    }
    if (radius != null) {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(radius!),
        child: image,
      );
    }
    return image;
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
    JoinProblem.ageRequired => l10n.joinAgeRequired,
    JoinProblem.guardianRequired => l10n.joinGuardianRequired,
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
            // Red on the icon, readable ink on the words (contrast, the sweep).
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
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

  Future<void> _scan() async {
    final code = await QrScanSheet.open(context);
    if (code == null || !mounted) return;
    _controller.text = code.value;
    await ref.read(joinControllerProvider.notifier).submitCode(code.value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(joinControllerProvider);
    final text = Theme.of(context).textTheme;
    final notifier = ref.read(joinControllerProvider.notifier);

    return _StepFrame(
      padded: false,
      actions: [
        FilledButton(
          onPressed: state.busy ? null : () => notifier.submitCode(_controller.text),
          child: Text(state.busy ? '…' : l10n.joinContinue),
        ),
      ],
      children: [
        const _Photo(asset: 'assets/images/salon_bright.jpg', height: 220),
        _gutter(Appear(child: Text(l10n.joinTitle, style: text.headlineMedium))),
        const SizedBox(height: 8),
        _gutter(Text(l10n.joinIntro, style: text.bodyMedium)),
        const SizedBox(height: 24),
        // Scanning is the fast path; typing is the one that always works. Both
        // are offered, and a refused camera lands back here rather than in a
        // dead end (IMPLEMENTATION U2).
        _gutter(
          _BigChoice(
            icon: Icons.qr_code_scanner_rounded,
            title: l10n.joinScanButton,
            subtitle: l10n.joinScanSub,
            onTap: state.busy ? null : _scan,
          ),
        ),
        const SizedBox(height: 24),
        _gutter(_OrDivider(l10n.joinEnterCode)),
        const SizedBox(height: 16),
        _gutter(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.go,
                decoration: InputDecoration(
                  hintText: l10n.joinCodeHint,
                  prefixIcon: const Icon(Icons.storefront_outlined),
                ),
                // Uppercase as they type: the code is printed in uppercase, and
                // a lowercase echo makes people think they typed it wrong.
                inputFormatters: [_Upper()],
                onSubmitted: notifier.submitCode,
              ),
              _Guide(l10n.joinCodeGuide),
              _Problem(state.problem),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _gutter(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );
}

/// The large, obvious choice: an icon in a soft square, a title, one line on
/// what it does. The whole card is the button.
class _BigChoice extends StatelessWidget {
  const _BigChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final g = CrayGlass.of(context);
    return Pressable(
      onTap: onTap,
      child: GlassPanel(
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(g.radius),
              ),
              child: Icon(icon, size: 32, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  const SizedBox(height: 4),
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

class _OrDivider extends StatelessWidget {
  const _OrDivider(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        // Flexible: in Hindi, or at large text, the words wrap rather than
        // push the lines off the screen.
        Flexible(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _ConfirmStep extends ConsumerWidget {
  const _ConfirmStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(joinControllerProvider);
    final salon = state.salon;
    if (salon == null) return const SizedBox.shrink();
    final notifier = ref.read(joinControllerProvider.notifier);

    return _StepFrame(
      progress: 0,
      actions: [
        FilledButton(onPressed: notifier.confirmSalon, child: Text(l10n.joinContinue)),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: notifier.backToCode,
          child: Text(l10n.joinNotThisSalon),
        ),
      ],
      children: [
        const _Photo(
          asset: 'assets/images/salon_mirrors.jpg',
          height: 140,
          fade: false,
          radius: 20,
        ),
        const SizedBox(height: 20),
        // The salon's own mark, the moment it is known: this is where the app
        // becomes theirs.
        const Appear(
          child: Align(alignment: Alignment.centerLeft, child: SalonMark(size: 72)),
        ),
        const SizedBox(height: 16),
        Text(l10n.joinConfirmTitle(salon.displayName), style: text.headlineMedium),
        const SizedBox(height: 16),
        // What the app does for them - only what exists (no unsupported claims).
        _Perk(icon: Icons.event_available_outlined, text: l10n.joinPerkBook),
        _Perk(icon: Icons.account_balance_wallet_outlined, text: l10n.joinPerkWallet),
        _Perk(icon: Icons.notifications_active_outlined, text: l10n.joinPerkRemind),
        const SizedBox(height: 16),
        // The licensing boundary, said plainly before anyone commits: credit is
        // redeemable only at the issuing salon (RULES 2).
        Text(l10n.joinConfirmBody, style: text.bodyMedium),
      ],
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurface),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _PhoneStep extends ConsumerStatefulWidget {
  const _PhoneStep();

  @override
  ConsumerState<_PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends ConsumerState<_PhoneStep> {
  late final _controller = TextEditingController(
    text: ref.read(joinControllerProvider).phone,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(joinControllerProvider);
    final notifier = ref.read(joinControllerProvider.notifier);

    return _StepFrame(
      progress: 1,
      actions: [
        FilledButton(
          onPressed: state.busy ? null : () => notifier.submitPhone(_controller.text),
          child: Text(state.busy ? '…' : l10n.joinStart),
        ),
      ],
      children: [
        Text(l10n.phoneTitle, style: text.headlineSmall),
        const SizedBox(height: 4),
        Text(l10n.phoneSub, style: text.bodyMedium),
        const SizedBox(height: 16),
        // The notice comes FIRST, then the number and the boxes together:
        // consent without notice is not consent (DPDP s.5, RULES 11.6a), and a
        // notice wedged between the field and the button is a wall someone
        // scrolls past twice. It names the salon as the Data Fiduciary and
        // carries the salon's own privacy contact, which the pre-auth lookup
        // published for exactly this moment - nobody has an account yet.
        ConsentNotice(
          salonName: state.salon?.displayName ?? '',
          grievance: state.salon?.grievance,
        ),
        const SizedBox(height: 16),
        // Age, before anything is sent (0110, DPDP s.9). Nothing pre-selected:
        // the person says which, and under 18 brings a parent or guardian in.
        const _AgeQuestion(),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          // NOT autofocused, unlike the code and OTP fields. Focus scrolls the
          // field into view, which would carry the customer straight past the
          // notice above it - and a notice nobody is shown is not a notice
          // (DPDP s.5). They tap the field when they have read enough.
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          decoration: InputDecoration(
            hintText: l10n.phoneHint,
            prefixIcon: const Icon(Icons.smartphone_outlined),
            prefixText: '+91 ',
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          onSubmitted: notifier.submitPhone,
        ),
        _Guide(l10n.phoneGuide, icon: Icons.sms_outlined),
        const SizedBox(height: 16),
        // Service messages ARE the service: they are stated, not asked for.
        // Marketing is asked for, separately, and starts off (RULES 11).
        Text(l10n.phoneServiceNote, style: text.bodySmall),
        // A child is never asked (DPDP s.9) - the box is not offered at all.
        if (state.adult != false)
          CheckboxListTile(
            value: state.promotional,
            onChanged: (v) => notifier.setPromotional(v ?? false),
            title: Text(l10n.phoneConsentPromotional),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l10n.joinMinorNoOffers, style: text.bodySmall),
          ),
        // WhatsApp offers are not asked for while the paid channels are off
        // (0108): consent to a channel nothing uses is consent for nothing.
        if (kWhatsappOffers && state.adult != false)
          CheckboxListTile(
            value: state.whatsapp,
            onChanged: state.promotional ? (v) => notifier.setWhatsapp(v ?? false) : null,
            title: Text(l10n.phoneConsentWhatsapp),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        _Problem(state.problem),
        const SizedBox(height: 8),
        Text(l10n.joinTermsLine, style: text.bodySmall),
        NoticeLink(
          label: l10n.linkTerms,
          url: sitePageFor('terms', Localizations.localeOf(context)),
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

  /// Whether the code came from the SMS - said on screen, so a code that
  /// appears by itself is never a mystery.
  bool _filledFromSms = false;
  late final OtpAutofill _autofill = ref.read(otpAutofillProvider);

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _listenForSms();
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

  /// Android asks the customer before the app may read the SMS; if they allow
  /// it, the code is filled in and checked at once. Declined, or on iOS, they
  /// type it (or tap the keyboard's suggestion) exactly as before.
  Future<void> _listenForSms() async {
    final code = await _autofill.listen();
    if (code == null || !mounted || _controller.text.length == 6) return;
    _controller.text = code;
    setState(() => _filledFromSms = true);
    await _submit(code);
  }

  Future<void> _submit(String code) async {
    if (ref.read(joinControllerProvider).busy) return;
    await ref.read(joinControllerProvider.notifier).submitOtp(code);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _autofill.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(joinControllerProvider);
    final notifier = ref.read(joinControllerProvider.notifier);

    // A wrong code with attempts left says how many; the generic text would
    // leave someone guessing whether the app or the code is broken.
    final attemptsMessage =
        state.problem == JoinProblem.wrongCode && state.attemptsLeft != null
        ? l10n.otpWrongCode('${state.attemptsLeft}')
        : null;

    return _StepFrame(
      progress: 2,
      actions: [
        FilledButton(
          onPressed: state.busy || _left == 0 ? null : () => _submit(_controller.text),
          child: Text(state.busy ? '…' : l10n.otpVerify),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: state.busy
              ? null
              : () async {
                  _controller.clear();
                  setState(() => _filledFromSms = false);
                  await notifier.resend();
                  if (!mounted) return;
                  _startCountdown();
                  unawaited(_listenForSms());
                },
          icon: const Icon(Icons.refresh),
          label: Text(l10n.otpResend),
        ),
      ],
      children: [
        Text(l10n.otpTitle, style: text.headlineSmall),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(child: Text(l10n.otpSentTo(_masked(state.phone)), style: text.bodyMedium)),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: state.busy ? null : notifier.back,
              child: Text(l10n.otpChangeNumber),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _OtpBoxes(
          controller: _controller,
          error: state.problem == JoinProblem.wrongCode,
          label: l10n.otpTitle,
          onChanged: (_) => setState(() => _filledFromSms = false),
          onComplete: _submit,
        ),
        const SizedBox(height: 8),
        _Guide(
          _filledFromSms ? l10n.otpFilledFromSms : l10n.otpWaitingForSms,
          icon: _filledFromSms ? Icons.mark_email_read_outlined : Icons.sms_outlined,
        ),
        if (_left > 0)
          _Guide(l10n.otpExpiresIn(_left), icon: Icons.timer_outlined)
        else
          _Guide(l10n.otpExpired, icon: Icons.timer_off_outlined),
        _Problem(state.problem, message: attemptsMessage),
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

/// Six boxes, one digit each - the code as people see it in the SMS. One real
/// text field sits over them, invisible, so typing, pasting, the keyboard's
/// own code suggestion (iOS) and a screen reader all work as on any field;
/// the boxes only draw what it holds. When the sixth digit lands, it is sent.
class _OtpBoxes extends StatefulWidget {
  const _OtpBoxes({
    required this.controller,
    required this.onComplete,
    required this.onChanged,
    required this.label,
    this.error = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onComplete;
  final ValueChanged<String> onChanged;
  final String label;
  final bool error;

  static const length = 6;

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_redraw);
    _focus.addListener(_redraw);
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_redraw);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final g = CrayGlass.of(context);
    final value = widget.controller.text;
    final digit = text.headlineSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final box = math.min(
          56.0,
          (constraints.maxWidth - gap * (_OtpBoxes.length - 1)) / _OtpBoxes.length,
        );
        final height = math.max(56.0, MediaQuery.textScalerOf(context).scale(32) + 16);
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < _OtpBoxes.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    AnimatedContainer(
                      duration: Motion.of(context, Motion.micro),
                      width: box,
                      height: height,
                      alignment: Alignment.center,
                      // Each digit sits in a recessed well.
                      decoration: BoxDecoration(
                        color: g.sunken,
                        borderRadius: BorderRadius.circular(g.radius),
                        border: Border.all(
                          color: widget.error
                              ? scheme.error
                              : _focus.hasFocus && i == value.length
                              ? g.ink
                              : i < value.length
                              ? scheme.outline
                              : g.line,
                          width: _focus.hasFocus && i == value.length ? 2 : 1,
                        ),
                      ),
                      child: Text(i < value.length ? value[i] : '', style: digit),
                    ),
                  ],
                ],
              ),
              Positioned.fill(
                child: Semantics(
                  label: widget.label,
                  child: Opacity(
                    opacity: 0,
                    alwaysIncludeSemantics: true,
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      autofocus: true,
                      showCursor: false,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      // iOS offers the code from Messages on the keyboard; some
                      // Android keyboards do the same.
                      autofillHints: const [AutofillHints.oneTimeCode],
                      decoration: const InputDecoration.collapsed(hintText: null),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(_OtpBoxes.length),
                      ],
                      onChanged: (v) {
                        widget.onChanged(v);
                        if (v.length == _OtpBoxes.length) {
                          HapticFeedback.selectionClick();
                          widget.onComplete(v);
                        }
                      },
                      onSubmitted: widget.onComplete,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DoneStep extends ConsumerWidget {
  const _DoneStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(joinControllerProvider);
    final salon = state.salon;

    return _StepFrame(
      actions: [
        FilledButton(
          // Into the salon's app. The session is already live; this only lets
          // the router show the home it has been waiting to show (router.dart).
          onPressed: () {
            ref.invalidate(joinControllerProvider);
            GoRouter.maybeOf(context)?.go('/');
          },
          child: Text(l10n.joinedContinue),
        ),
      ],
      children: [
        const SizedBox(height: 32),
        // Start-aligned like every other screen: centred body text is one of
        // the tells DESIGN 14 names.
        const Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(left: 0, right: 0, top: -64, child: Celebrate(height: 240)),
            Align(alignment: Alignment.centerLeft, child: SuccessCheck(size: 80)),
          ],
        ),
        const SizedBox(height: 24),
        Text(l10n.joinedTitle(salon?.displayName ?? ''), style: text.headlineMedium),
        const SizedBox(height: 12),
        Text(
          state.outcome == LoginOutcome.staff ? l10n.joinedStaff : l10n.joinedBody,
          style: text.bodyLarge,
        ),
      ],
    );
  }
}

class _Upper extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue old,
    TextEditingValue value,
  ) => value.copyWith(text: value.text.toUpperCase());
}


/// "How old are you?" - 18 or older, or under 18 with a parent or guardian who
/// gives their name and agrees (0110).
class _AgeQuestion extends ConsumerWidget {
  const _AgeQuestion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(joinControllerProvider);
    final notifier = ref.read(joinControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.joinAgeQuestion, style: text.titleSmall),
        RadioGroup<bool>(
          groupValue: state.adult,
          onChanged: (v) {
            if (v != null) notifier.setAdult(v);
          },
          child: Column(
            children: [
              RadioListTile<bool>(
                value: true,
                title: Text(l10n.joinAgeAdult),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<bool>(
                value: false,
                title: Text(l10n.joinAgeMinor),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        if (state.adult == false) ...[
          const SizedBox(height: 4),
          Text(l10n.joinGuardianIntro, style: text.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l10n.joinGuardianName),
            onChanged: notifier.setGuardianName,
          ),
          CheckboxListTile(
            value: state.guardianConfirms,
            onChanged: (v) => notifier.setGuardianConfirms(v ?? false),
            title: Text(l10n.joinGuardianConfirm(state.salon?.displayName ?? '')),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ],
    );
  }
}
