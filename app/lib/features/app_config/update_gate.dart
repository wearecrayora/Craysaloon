import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/external_link.dart' show openUpdate;
import '../../core/ui/glass.dart';
import '../../core/ui/salon_mark.dart';
import '../../l10n/app_localizations.dart';
import 'app_config_providers.dart';

/// Below the lowest build the console allows (0119), the app asks for an
/// update and does nothing else - the lever for an app version that must not
/// keep running (a broken release, a changed server contract).
///
/// It never blocks on not knowing: no config yet, or a build number that
/// cannot be read (0), and the app opens as usual.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = appConfig(ref);
    final build = ref.watch(buildNumberProvider).value ?? 0;
    if (build == 0 || config.minBuild <= build) return child;
    return _UpdateRequired(url: config.updateUrl);
  }
}

class _UpdateRequired extends StatelessWidget {
  const _UpdateRequired({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    return MeshBackground(
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Align(alignment: Alignment.centerLeft, child: SalonMark(size: 64)),
                const SizedBox(height: 24),
                Text(l10n.updateRequiredTitle, style: text.headlineMedium),
                const SizedBox(height: 12),
                Text(l10n.updateRequiredBody, style: text.bodyLarge),
                const Spacer(flex: 2),
                FilledButton.icon(
                  onPressed: () => openUpdate(url),
                  icon: const Icon(Icons.system_update_outlined),
                  label: Text(l10n.updateNow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
