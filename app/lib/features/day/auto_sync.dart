import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart' show outboxProvider;
import '../../data/local/outbox.dart';
import 'day_controller.dart';

/// Sends what the owner did offline when the connection comes back - without
/// them having to open Today or tap anything (RULES 13, PHASES M6).
///
/// No connectivity plugin: a phone that says "connected" may still have no
/// internet, so the honest test is to try. It tries when the app comes back to
/// the foreground, and every 45 seconds while something is waiting - nothing at
/// all while the queue is empty or the app is in the background.
class AutoSync extends ConsumerStatefulWidget {
  const AutoSync({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AutoSync> createState() => _AutoSyncState();
}

class _AutoSyncState extends ConsumerState<AutoSync> with WidgetsBindingObserver {
  static const _every = Duration(seconds: 45);
  Timer? _timer;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_every, (_) => _tryDrain());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tryDrain();
      _timer ??= Timer.periodic(_every, (_) => _tryDrain());
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _tryDrain() async {
    if (_running || !mounted) return;
    final Outbox? outbox = ref.read(outboxProvider);
    if (outbox == null || await outbox.pendingCount() == 0) return;
    _running = true;
    try {
      // refresh() drains first, then re-reads the day - so the list matches
      // what was sent, and the badges follow.
      await ref.read(dayControllerProvider.notifier).refresh();
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
