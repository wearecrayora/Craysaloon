import '../../core/ui/service_icon.dart';
import '../../l10n/app_localizations.dart';

/// A kind of service, as the customer reads it.
String kindLabel(AppL10n l10n, ServiceKind kind) => switch (kind) {
  ServiceKind.hair || ServiceKind.styling => l10n.kindHair,
  ServiceKind.beard => l10n.kindBeard,
  ServiceKind.nails => l10n.kindNails,
  ServiceKind.facial => l10n.kindFacial,
  ServiceKind.spa => l10n.kindSpa,
  ServiceKind.makeup => l10n.kindMakeup,
  ServiceKind.colour => l10n.kindColour,
  ServiceKind.wax => l10n.kindWax,
  ServiceKind.other => l10n.kindOther,
};
