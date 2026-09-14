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

const String kFluxidiProductionWindowTitle = 'Fluxidi';
const String kFluxidiLocalTestWindowTitle = 'Fluxidi — lokale test';

enum FluxidiRuntimeKind { production, localTest }

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
  return resolved == FluxidiRuntimeKind.localTest ? '_local_test' : '';
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

/// Fail closed when the compiled env and booking host contradict each other.
/// Does not rewrite either host.
String? fluxidiRuntimeEnvGuardError({
  String runtimeEnv = kFluxidiRuntimeEnvDefine,
  String bookingBaseUrlOverride = kFluxidiRuntimeBookingBaseUrlOverride,
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
  return null;
}

void assertFluxidiRuntimeEnvGuards() {
  final error = fluxidiRuntimeEnvGuardError();
  if (error != null) {
    throw StateError(error);
  }
}
