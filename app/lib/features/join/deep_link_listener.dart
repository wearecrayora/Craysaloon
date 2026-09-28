import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/join/join_link.dart';
import 'join_controller.dart';

/// Injected so the deep-link path can be driven in tests without a launcher.
final appLinkStreamProvider = Provider<Stream<Uri>>((ref) => AppLinks().uriLinkStream);

/// Feeds a scanned or tapped `join.craysalon.in/s/<code>` link into the join
/// flow.
///
/// A link is a **code**, nothing more: it pre-fills the step the customer would
/// have typed, and the server still resolves the code from scratch. It cannot
/// skip the confirmation screen, so nobody is bound by opening a link
/// (`RULES.md` 4.1 - the salon is named, and agreed to, first).
///
/// Links that arrive once someone is already bound are ignored. A customer of
/// Salon A scanning Salon B's poster must not be walked into a flow that can
/// only end in "already registered".
class DeepLinkListener extends ConsumerStatefulWidget {
  const DeepLinkListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DeepLinkListener> createState() => _DeepLinkListenerState();
}

class _DeepLinkListenerState extends ConsumerState<DeepLinkListener> {
  StreamSubscription<Uri>? _subscription;

  @override
  void initState() {
    super.initState();
    // The stream carries the launch link as well as later ones, so there is no
    // separate "initial link" call to race with it.
    _subscription = ref.read(appLinkStreamProvider).listen(_handle);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handle(Uri uri) {
    final code = JoinLink.parse(uri.toString());
    if (code == null) return;
    final state = ref.read(joinControllerProvider);
    // Mid-flow or finished: leave it alone rather than restarting someone who
    // is halfway through typing a code from the card in their hand.
    if (state.step != JoinStep.code || state.busy) return;
    // A referral code riding on the same link (?r=ABCDEF). Parsed separately,
    // because one failing to parse must never stop somebody joining a salon.
    ref.read(joinControllerProvider.notifier).submitCode(
          code.value,
          referral: JoinLink.referralFrom(uri.toString()),
        );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
