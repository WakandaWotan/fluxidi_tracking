import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';

void main() {
  test('production default booking URL stays on the production worker', () {
    expect(
      appConfig.bookingBaseUrl.contains('fluxidi-booking-api.fluxidi.workers.dev'),
      isTrue,
    );
    expect(kFluxidiE2eBuild, isFalse);
    expect(kFluxidiE2eTestToken, isEmpty);
  });

  test('release/production build fails when a test endpoint or token is supplied', () {
    expect(
      fluxidiBookingEndpointGuardError(
        e2eBuild: false,
        bookingBaseUrl: 'https://fluxidi-booking-vat-e2e-test.example.workers.dev',
        e2eToken: '',
      ),
      'production_build_must_not_use_e2e_endpoint',
    );
    expect(
      fluxidiBookingEndpointGuardError(
        e2eBuild: false,
        bookingBaseUrl: 'https://fluxidi-booking-api.fluxidi.workers.dev',
        e2eToken: 'secret-token',
      ),
      'production_build_must_not_include_e2e_token',
    );
  });

  test('e2e build fails when the API URL is production', () {
    expect(
      fluxidiBookingEndpointGuardError(
        e2eBuild: true,
        bookingBaseUrl: 'https://fluxidi-booking-api.fluxidi.workers.dev',
        e2eToken: 'secret-token',
      ),
      'e2e_build_must_not_use_production_api',
    );
    expect(
      fluxidiBookingEndpointGuardError(
        e2eBuild: true,
        bookingBaseUrl: 'https://fluxidi-booking-vat-e2e-test.example.workers.dev',
        e2eToken: 'secret-token',
      ),
      isNull,
    );
  });

  test('e2e tracking URL must be the tracking e2e worker', () {
    expect(
      fluxidiTrackingEndpointGuardError(
        stagingBuild: true,
        trackingBaseUrl: 'https://fluxidi-tracking-api.fluxidi.workers.dev',
      ),
      'staging_build_must_not_use_production_tracking_api',
    );
    expect(
      fluxidiTrackingEndpointGuardError(
        stagingBuild: true,
        trackingBaseUrl: '',
      ),
      'staging_build_must_not_use_production_tracking_api',
    );
    expect(
      fluxidiTrackingEndpointGuardError(
        stagingBuild: true,
        trackingBaseUrl: 'https://fluxidi-tracking-api-e2e.fluxidi.workers.dev',
      ),
      isNull,
    );
    expect(
      fluxidiTrackingEndpointGuardError(
        stagingBuild: false,
        trackingBaseUrl: 'https://fluxidi-tracking-api-e2e.fluxidi.workers.dev',
      ),
      'production_build_must_not_use_e2e_tracking_endpoint',
    );
  });

  test('customer staging rejects production package and booking fallback', () {
    expect(
      fluxidiCustomerStagingGuardError(
        customerStaging: true,
        bookingBaseUrl: 'https://fluxidi-booking-api.fluxidi.workers.dev',
        publicBookingBaseUrl: 'https://fluxidi-booking-api.fluxidi.workers.dev',
        trackingBaseUrl: 'https://fluxidi-tracking-api-e2e.fluxidi.workers.dev',
        applicationId: 'com.fluxidi.customer.dev',
      ),
      'e2e_build_must_not_use_production_api',
    );
    expect(
      fluxidiCustomerStagingGuardError(
        customerStaging: true,
        bookingBaseUrl: '',
        publicBookingBaseUrl: '',
        trackingBaseUrl: 'https://fluxidi-tracking-api-e2e.fluxidi.workers.dev',
        applicationId: 'com.fluxidi.customer.dev',
      ),
      'customer_staging_booking_url_missing',
    );
    expect(
      fluxidiCustomerStagingGuardError(
        customerStaging: true,
        bookingBaseUrl: 'https://fluxidi-booking-vat-e2e-test.fluxidi.workers.dev',
        publicBookingBaseUrl: 'https://fluxidi-booking-vat-e2e-test.fluxidi.workers.dev',
        trackingBaseUrl: 'https://fluxidi-tracking-api-e2e.fluxidi.workers.dev',
        applicationId: 'com.fluxidi.customer',
      ),
      'staging_build_must_not_use_production_package',
    );
    expect(
      fluxidiCustomerStagingGuardError(
        customerStaging: true,
        bookingBaseUrl: 'https://fluxidi-booking-vat-e2e-test.fluxidi.workers.dev',
        publicBookingBaseUrl: 'https://fluxidi-booking-vat-e2e-test.fluxidi.workers.dev',
        trackingBaseUrl: 'https://fluxidi-tracking-api-e2e.fluxidi.workers.dev',
        applicationId: 'com.fluxidi.customer.dev',
      ),
      isNull,
    );
  });

  test('android production applicationId stays untouched and e2e suffix is gated', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle.contains('applicationId = "com.fluxidi.tracking"'), isTrue);
    expect(gradle.contains('applicationIdSuffix = ".e2e"'), isTrue);
    expect(gradle.contains('applicationIdSuffix = ".staging"'), isTrue);
    expect(gradle.contains('val fluxidiE2e'), isTrue);
    expect(gradle.contains('val fluxidiStaging'), isTrue);
    expect(gradle.contains('else if (fluxidiE2e)'), isTrue);
    expect(gradle.contains('"Fluxidi Staging"'), isTrue);
    expect(gradle.contains('"Fluxidi"'), isTrue);
    expect(
      gradle.contains('listOf(fluxidiStaging, fluxidiE2e, fluxidiDeviceQa).count { it } > 1') &&
          gradle.contains('Choose only one Fluxidi alternate Android identity'),
      isTrue,
    );
  });

  test('e2e banner copy is permanent and exact', () {
    expect(kFluxidiE2eBannerText, 'FLUXIDI E2E TEST — GEEN ECHTE BETALING');
    final frame = File('lib/main_parts/fluxidi_shell_widgets.dart').readAsStringSync();
    expect(frame.contains('kFluxidiE2eBannerText'), isTrue);
    expect(frame.contains('kFluxidiE2eBuild'), isTrue);
  });
}
