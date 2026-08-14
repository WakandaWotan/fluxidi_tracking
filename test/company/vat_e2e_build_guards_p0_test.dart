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

  test('android production applicationId stays untouched and e2e suffix is gated', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle.contains('applicationId = "com.fluxidi.tracking"'), isTrue);
    expect(gradle.contains('applicationIdSuffix = ".e2e"'), isTrue);
    expect(gradle.contains('val fluxidiE2e'), isTrue);
    expect(gradle.contains('if (fluxidiE2e)'), isTrue);
  });

  test('e2e banner copy is permanent and exact', () {
    expect(kFluxidiE2eBannerText, 'FLUXIDI E2E TEST — GEEN ECHTE BETALING');
    final frame = File('lib/main_parts/fluxidi_shell_widgets.dart').readAsStringSync();
    expect(frame.contains('kFluxidiE2eBannerText'), isTrue);
    expect(frame.contains('kFluxidiE2eBuild'), isTrue);
  });
}
