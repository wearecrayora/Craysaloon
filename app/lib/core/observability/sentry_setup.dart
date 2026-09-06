import 'package:sentry_flutter/sentry_flutter.dart';

/// Crash and error reporting.
///
/// Two rules shape this file and neither is optional:
///
///   RULES.md 11.3  Never log phone numbers, OTPs, tokens, secrets, or full
///                  payment payloads. Sentry captures breadcrumbs and
///                  exception messages automatically, so scrubbing has to
///                  happen on the way OUT, not at each call site.
///   -              The app must still boot with no DSN configured.
///                  Observability is never a boot dependency.
///
/// The DSN is supplied at build time:
///   flutter build apk --dart-define=SENTRY_DSN=https://...
/// It is a public value - it ships in the client, like the Supabase
/// publishable key - but it is still not committed, so a fork of this public
/// repo cannot report into our project.
const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

/// Set per build so a crash can be traced to a release (PHASES.md M13).
const String buildEnvironment =
    String.fromEnvironment('APP_ENV', defaultValue: 'development');

bool get sentryEnabled => sentryDsn.isNotEmpty;

/// Runs [appRunner] with Sentry when a DSN is configured, and plainly when it
/// is not. Never prevents the app from booting.
Future<void> runWithObservability(Future<void> Function() appRunner) async {
  if (!sentryEnabled) {
    await appRunner();
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = sentryDsn;
      options.environment = buildEnvironment;

      // Never attach IP addresses, usernames or device identifiers. Our users
      // are the salon's customers, and the salon is their Data Fiduciary
      // (PRD 16A.4) - we are not entitled to widen that.
      options.sendDefaultPii = false;

      // Full traces in development, a thin sample in production.
      options.tracesSampleRate = buildEnvironment == 'production' ? 0.1 : 1.0;

      options.beforeSend = _scrubEvent;
      options.beforeBreadcrumb = _scrubBreadcrumb;
    },
    appRunner: appRunner,
  );
}

/// Patterns that must never leave the device.
///
/// Deliberately broad. A false positive costs a redacted string in a stack
/// trace; a false negative puts a customer's phone number in a third-party
/// system. That asymmetry is the whole argument.
final List<RegExp> _sensitive = [
  // Indian mobile numbers, with or without +91 / spaces / hyphens.
  RegExp(r'(\+?91[\s-]?)?[6-9]\d{9}'),
  // Any standalone 4-8 digit run - catches OTPs without assuming a length.
  RegExp(r'\b\d{4,8}\b'),
  // Supabase keys, current and legacy formats.
  RegExp(r'sb_(secret|publishable)_[A-Za-z0-9_-]+'),
  RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
  // Razorpay.
  RegExp(r'rzp_(live|test)_[A-Za-z0-9]+'),
  // Anything shaped like a bearer token.
  RegExp(r'[Bb]earer\s+[A-Za-z0-9._-]{10,}'),
];

/// Visible for testing.
String redactSensitive(String input) {
  var out = input;
  for (final pattern in _sensitive) {
    out = out.replaceAll(pattern, '[redacted]');
  }
  return out;
}

SentryEvent? _scrubEvent(SentryEvent event, Hint hint) {
  final message = event.message;
  if (message != null) {
    event.message = SentryMessage(
      redactSensitive(message.formatted),
      template: message.template,
    );
  }

  // Request bodies, query strings, cookies and headers are the most common
  // leak path. `data` has no setter, so replace the whole request with one
  // built from only the fields that are safe to keep.
  final request = event.request;
  if (request != null) {
    event.request = SentryRequest(
      url: request.url,
      method: request.method,
    );
  }

  // We never send user identity. salon_id alone is enough to triage, and it
  // is not personal data.
  event.user = null;

  final crumbs = event.breadcrumbs;
  if (crumbs != null) {
    for (final crumb in crumbs) {
      _redactBreadcrumb(crumb);
    }
  }

  return event;
}

Breadcrumb? _scrubBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
  if (breadcrumb == null) return null;
  _redactBreadcrumb(breadcrumb);
  return breadcrumb;
}

void _redactBreadcrumb(Breadcrumb crumb) {
  final message = crumb.message;
  if (message != null) {
    crumb.message = redactSensitive(message);
  }
  // Breadcrumb data is arbitrary and frequently carries request payloads.
  crumb.data?.clear();
}
