// Compile-time Windows/runtime split: production Fluxidi vs local test.
// Never infers or switches API hosts at runtime.

const String kFluxidiRuntimeEnvDefineKey = 'FLUXIDI_RUNTIME_ENV';
const String kFluxidiRuntimeEnvDefine = String.fromEnvironment(
  kFluxidiRuntimeEnvDefineKey,
  defaultValue: '',
);

/// Same dart-define as [kBookingBaseUrlOverride], kept here to avoid
/// importing app_config from session stores.
const String kFluxidiRuntimeBookingBaseUrlOverride = String.fromEnvironment(
  'BOOKING_BASE_URL',
  defaultValue: '',
);
const String kFluxidiRuntimeTrackingBaseUrlOverride = String.fromEnvironment(
  'WORKER_BASE_URL',
  defaultValue: '',
);
const String kFluxidiRuntimeNavigationBaseUrlOverride = String.fromEnvironment(
  'NAVIGATION_WORKER_BASE_URL',
  defaultValue: '',
);

/// Same default as [kPublicBookingBaseUrl]. An unset value is production.
const String kFluxidiRuntimePublicBookingBaseUrl = String.fromEnvironment(
  'PUBLIC_BOOKING_BASE_URL',
  defaultValue: 'https://fluxidi-booking-api.fluxidi.workers.dev',
);

const String kFluxidiProductionBookingHost =
    'fluxidi-booking-api.fluxidi.workers.dev';
const String kFluxidiProductionTrackingHost =
    'fluxidi-tracking-api.fluxidi.workers.dev';
const String kFluxidiProductionNavigationHost =
    'fluxidi-navigation-api.fluxidi.workers.dev';
const String kFluxidiProductionBookingUrl =
    'https://fluxidi-booking-api.fluxidi.workers.dev';
const String kFluxidiProductionTrackingUrl =
    'https://fluxidi-tracking-api.fluxidi.workers.dev';
const String kFluxidiProductionNavigationUrl =
    'https://fluxidi-navigation-api.fluxidi.workers.dev';

/// Named only. These workers are not deployed and must not be created here.
const String kFluxidiStagingBookingHost =
    'fluxidi-booking-api-staging.fluxidi.workers.dev';
const String kFluxidiStagingTrackingHost =
    'fluxidi-tracking-api-staging.fluxidi.workers.dev';
const String kFluxidiStagingNavigationHost =
    'fluxidi-navigation-api-staging.fluxidi.workers.dev';

/// Compile-time only. Never read from a query, deep link, or server flag.
const bool kFluxidiLocalQaCustomerSessionDefine = bool.fromEnvironment(
  'FLUXIDI_LOCAL_QA_CUSTOMER_SESSION',
  defaultValue: false,
);

const String kFluxidiLocalQaAdminTokenDefine = String.fromEnvironment(
  'FLUXIDI_LOCAL_QA_ADMIN_TOKEN',
  defaultValue: '',
);

const String kFluxidiProductionWindowTitle = 'Fluxidi';
const String kFluxidiLocalTestWindowTitle = 'Fluxidi — lokale test';

enum FluxidiRuntimeKind { production, localTest, staging }

bool fluxidiIsLoopbackBookingHost(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme) return false;
  final host = uri.host.toLowerCase();
  return host == '127.0.0.1' || host == 'localhost';
}

FluxidiRuntimeKind resolveFluxidiRuntimeKind({
  String runtimeEnv = kFluxidiRuntimeEnvDefine,
  String bookingBaseUrlOverride = kFluxidiRuntimeBookingBaseUrlOverride,
}) {
  final env = runtimeEnv.trim().toLowerCase();
  if (env == 'local_test' || env == 'local') {
    return FluxidiRuntimeKind.localTest;
  }
  if (env == 'production' || env == 'prod') {
    return FluxidiRuntimeKind.production;
  }
  if (env == 'staging') {
    return FluxidiRuntimeKind.staging;
  }
  if (fluxidiIsLoopbackBookingHost(bookingBaseUrlOverride)) {
    return FluxidiRuntimeKind.localTest;
  }
  return FluxidiRuntimeKind.production;
}

FluxidiRuntimeKind get fluxidiRuntimeKind => resolveFluxidiRuntimeKind();

bool get isFluxidiLocalTestRuntime =>
    fluxidiRuntimeKind == FluxidiRuntimeKind.localTest;

String fluxidiRuntimeStorageDirSuffix({
  FluxidiRuntimeKind? kind,
}) {
  final resolved = kind ?? fluxidiRuntimeKind;
  if (resolved == FluxidiRuntimeKind.localTest) return '_local_test';
  if (resolved == FluxidiRuntimeKind.staging) return '_staging';
  return '';
}

String fluxidiRuntimeStateDirName(
  String baseName, {
  FluxidiRuntimeKind? kind,
}) {
  return '$baseName${fluxidiRuntimeStorageDirSuffix(kind: kind)}';
}

String fluxidiWindowTitle({FluxidiRuntimeKind? kind}) {
  final resolved = kind ?? fluxidiRuntimeKind;
  return resolved == FluxidiRuntimeKind.localTest
      ? kFluxidiLocalTestWindowTitle
      : kFluxidiProductionWindowTitle;
}

String get kFluxidiWindowTitle => fluxidiWindowTitle();

String fluxidiEffectiveServiceUrl(String override, String productionFallback) {
  final value = override.trim();
  if (value.isEmpty) return productionFallback;
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

String? fluxidiServiceHost(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty) return null;
  return uri.host.toLowerCase();
}

/// Fail closed when the compiled env and service hosts contradict each other.
/// Does not rewrite any host.
String? fluxidiRuntimeEnvGuardError({
  String runtimeEnv = kFluxidiRuntimeEnvDefine,
  String bookingBaseUrlOverride = kFluxidiRuntimeBookingBaseUrlOverride,
  String trackingBaseUrlOverride = kFluxidiRuntimeTrackingBaseUrlOverride,
  String navigationBaseUrlOverride = kFluxidiRuntimeNavigationBaseUrlOverride,
  String publicBookingBaseUrl = kFluxidiRuntimePublicBookingBaseUrl,
}) {
  final kind = resolveFluxidiRuntimeKind(
    runtimeEnv: runtimeEnv,
    bookingBaseUrlOverride: bookingBaseUrlOverride,
  );
  final loopback = fluxidiIsLoopbackBookingHost(bookingBaseUrlOverride);
  if (kind == FluxidiRuntimeKind.production && loopback) {
    return 'production_runtime_must_not_use_loopback_booking_host';
  }
  if (kind == FluxidiRuntimeKind.localTest && !loopback) {
    return 'local_test_runtime_must_use_loopback_booking_host';
  }
  if (kind == FluxidiRuntimeKind.localTest) return null;
  return fluxidiRuntimeHostIsolationError(
    kind: kind,
    bookingBaseUrl: fluxidiEffectiveServiceUrl(
      bookingBaseUrlOverride,
      kFluxidiProductionBookingUrl,
    ),
    trackingBaseUrl: fluxidiEffectiveServiceUrl(
      trackingBaseUrlOverride,
      kFluxidiProductionTrackingUrl,
    ),
    navigationBaseUrl: fluxidiEffectiveServiceUrl(
      navigationBaseUrlOverride,
      kFluxidiProductionNavigationUrl,
    ),
    publicBookingBaseUrl: publicBookingBaseUrl,
  );
}

String? fluxidiRuntimeHostIsolationError({
  required FluxidiRuntimeKind kind,
  required String bookingBaseUrl,
  required String trackingBaseUrl,
  required String navigationBaseUrl,
  required String publicBookingBaseUrl,
}) {
  final hosts = <String, String>{
    'booking': fluxidiServiceHost(bookingBaseUrl) ?? '',
    'tracking': fluxidiServiceHost(trackingBaseUrl) ?? '',
    'navigation': fluxidiServiceHost(navigationBaseUrl) ?? '',
    'public_booking': fluxidiServiceHost(publicBookingBaseUrl) ?? '',
  };
  const productionHosts = <String>{
    kFluxidiProductionBookingHost,
    kFluxidiProductionTrackingHost,
    kFluxidiProductionNavigationHost,
  };
  const stagingHosts = <String, String>{
    'booking': kFluxidiStagingBookingHost,
    'tracking': kFluxidiStagingTrackingHost,
    'navigation': kFluxidiStagingNavigationHost,
    'public_booking': kFluxidiStagingBookingHost,
  };
  if (kind == FluxidiRuntimeKind.staging) {
    for (final entry in hosts.entries) {
      if (entry.value.isEmpty || productionHosts.contains(entry.value)) {
        return 'staging_runtime_must_not_use_production_host';
      }
      if (entry.value != stagingHosts[entry.key]) {
        return 'staging_runtime_host_mismatch';
      }
    }
    return null;
  }
  for (final host in hosts.values) {
    if (stagingHosts.values.contains(host)) {
      return 'production_runtime_must_not_use_staging_host';
    }
  }
  return null;
}

void assertFluxidiRuntimeEnvGuards() {
  final error = fluxidiRuntimeEnvGuardError();
  if (error != null) {
    throw StateError(error);
  }
}
