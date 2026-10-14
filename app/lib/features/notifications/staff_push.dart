import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../salon/salon_home.dart' show salonNotificationsProvider;
import '../day/day_controller.dart';
import '../join/join_controller.dart';
import 'push_registration.dart';

/// Push for the salon's own people (0108): the owner's or manager's phone
/// registers, and hears when a CUSTOMER books, cancels, chooses to pay at the
/// counter, or pays a bill online. Wraps the owner's shell, so it runs once per
/// signed-in session and stops when the session ends.
///
/// When one of those lands while the app is open, the day is re-read - the
/// booking or the payment it announced is on the screen without a pull.
class StaffPush extends ConsumerStatefulWidget {
  const StaffPush({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<StaffPush> createState() => _StaffPushState();
}

class _StaffPushState extends ConsumerState<StaffPush> {
  PushRegistration? _push;

  @override
  void initState() {
    super.initState();
    // After the first frame: the providers this reads are built by then.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final api = ref.read(pushApiProvider);
    if (api == null || !mounted) return;

    // Android files every push under a channel; named for the salon, as the
    // customer's is (ARCHITECTURE 7.4).
    final branding = ref.read(resolvedBrandingProvider);
    if (branding != null) {
      await ref.read(salonNotificationsProvider).ensureChannel(salonName: branding.displayName);
    }
    if (!mounted) return;

    final push = PushRegistration(
      api,
      onArrived: (purpose) {
        if (purpose.startsWith('staff_') && mounted) {
          ref.read(dayControllerProvider.notifier).refresh();
        }
      },
    );
    _push = push;
    await push.start();
  }

  @override
  void dispose() {
    // An ack fired into a disposed ref is a crash in a notification handler.
    _push?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
