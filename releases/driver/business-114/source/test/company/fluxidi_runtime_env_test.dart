import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';

void main() {
  test('explicit production never follows a leftover loopback define', () {
    expect(
      fluxidiRuntimeEnvGuardError(
        runtimeEnv: 'production',
        bookingBaseUrlOverride: 'http://127.0.0.1:8788',
      ),
      'production_runtime_must_not_use_loopback_booking_host',
    );
  });

  test('explicit local_test refuses a production booking host', () {
    expect(
      fluxidiRuntimeEnvGuardError(
        runtimeEnv: 'local_test',
        bookingBaseUrlOverride: 'https://fluxidi-booking-api.fluxidi.workers.dev',
      ),
      'local_test_runtime_must_use_loopback_booking_host',
    );
    expect(
      fluxidiRuntimeEnvGuardError(
        runtimeEnv: 'local_test',
        bookingBaseUrlOverride: '',
      ),
      'local_test_runtime_must_use_loopback_booking_host',
    );
  });

  test('matching hosts keep their storage and window titles apart', () {
    expect(
      resolveFluxidiRuntimeKind(
        runtimeEnv: 'production',
        bookingBaseUrlOverride: '',
      ),
      FluxidiRuntimeKind.production,
    );
    expect(
      resolveFluxidiRuntimeKind(
        runtimeEnv: 'local_test',
        bookingBaseUrlOverride: 'http://127.0.0.1:8788',
      ),
      FluxidiRuntimeKind.localTest,
    );
    expect(
      fluxidiRuntimeStateDirName(
        'company_session',
        kind: FluxidiRuntimeKind.production,
      ),
      'company_session',
    );
    expect(
      fluxidiRuntimeStateDirName(
        'company_session',
        kind: FluxidiRuntimeKind.localTest,
      ),
      'company_session_local_test',
    );
    expect(
      fluxidiWindowTitle(kind: FluxidiRuntimeKind.production),
      'Fluxidi',
    );
    expect(
      fluxidiWindowTitle(kind: FluxidiRuntimeKind.localTest),
      'Fluxidi — lokale test',
    );
    expect(
      fluxidiRuntimeEnvGuardError(
        runtimeEnv: 'production',
        bookingBaseUrlOverride: '',
      ),
      isNull,
    );
    expect(
      fluxidiRuntimeEnvGuardError(
        runtimeEnv: 'local_test',
        bookingBaseUrlOverride: 'http://127.0.0.1:8788',
      ),
      isNull,
    );
  });

  test('staging refuses production hosts and an empty fallback', () {
    expect(
      resolveFluxidiRuntimeKind(
        runtimeEnv: 'staging',
        bookingBaseUrlOverride: '',
      ),
      FluxidiRuntimeKind.staging,
    );
    expect(
      fluxidiRuntimeEnvGuardError(runtimeEnv: 'staging'),
      'staging_runtime_must_not_use_production_host',
    );
    expect(
      fluxidiRuntimeEnvGuardError(
        runtimeEnv: 'staging',
        bookingBaseUrlOverride: 'https://$kFluxidiProductionBookingHost',
        trackingBaseUrlOverride: 'https://$kFluxidiStagingTrackingHost',
        navigationBaseUrlOverride: 'https://$kFluxidiStagingNavigationHost',
        publicBookingBaseUrl: 'https://$kFluxidiStagingBookingHost',
      ),
      'staging_runtime_must_not_use_production_host',
    );
    expect(
      fluxidiRuntimeEnvGuardError(
        runtimeEnv: 'staging',
        bookingBaseUrlOverride: 'https://fluxidi-booking-vat-e2e-test.fluxidi.workers.dev',
        trackingBaseUrlOverride: 'https://$kFluxidiStagingTrackingHost',
        navigationBaseUrlOverride: 'https://$kFluxidiStagingNavigationHost',
        publicBookingBaseUrl: 'https://$kFluxidiStagingBookingHost',
      ),
      'staging_runtime_host_mismatch',
    );
  });

  test('staging accepts only the named staging hosts', () {
    expect(
      fluxidiRuntimeEnvGuardError(
        runtimeEnv: 'staging',
        bookingBaseUrlOverride: 'https://$kFluxidiStagingBookingHost',
        trackingBaseUrlOverride: 'https://$kFluxidiStagingTrackingHost',
        navigationBaseUrlOverride: 'https://$kFluxidiStagingNavigationHost',
        publicBookingBaseUrl: 'https://$kFluxidiStagingBookingHost',
      ),
      isNull,
    );
    expect(
      fluxidiRuntimeStateDirName(
        'company_session',
        kind: FluxidiRuntimeKind.staging,
      ),
      'company_session_staging',
    );
    expect(
      fluxidiWindowTitle(kind: FluxidiRuntimeKind.staging),
      'Fluxidi',
    );
  });

  test('production refuses staging hosts and keeps its own defaults', () {
    expect(
      fluxidiRuntimeEnvGuardError(
        runtimeEnv: 'production',
        bookingBaseUrlOverride: 'https://$kFluxidiStagingBookingHost',
        trackingBaseUrlOverride: 'https://$kFluxidiProductionTrackingHost',
        navigationBaseUrlOverride: 'https://$kFluxidiProductionNavigationHost',
        publicBookingBaseUrl: 'https://$kFluxidiProductionBookingHost',
      ),
      'production_runtime_must_not_use_staging_host',
    );
    expect(
      fluxidiRuntimeEnvGuardError(
        runtimeEnv: '',
        bookingBaseUrlOverride: '',
        trackingBaseUrlOverride: '',
        navigationBaseUrlOverride: '',
        publicBookingBaseUrl: 'https://$kFluxidiProductionBookingHost',
      ),
      isNull,
    );
  });

  test('loopback dart-define without env still isolates local test storage', () {
    expect(
      resolveFluxidiRuntimeKind(
        runtimeEnv: '',
        bookingBaseUrlOverride: 'http://127.0.0.1:8788',
      ),
      FluxidiRuntimeKind.localTest,
    );
    expect(
      resolveFluxidiRuntimeKind(
        runtimeEnv: '',
        bookingBaseUrlOverride: '',
      ),
      FluxidiRuntimeKind.production,
    );
  });
}
