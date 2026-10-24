import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer/app/customer_app_config.dart';
import 'package:fluxidi_customer/app/customer_runtime_guard.dart';
import 'package:fluxidi_customer/deeplinks/customer_deep_link.dart';
import 'package:fluxidi_tracking/app_config.dart' as shared;
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart' as runtime;

CustomerAppConfig config(bool staging, {String? publicUrl}) =>
    CustomerAppConfig(
      appName: staging ? 'Fluxidi Klanten Staging' : 'Fluxidi Klanten',
      environmentLabel: '',
      androidApplicationId: staging
          ? 'com.fluxidi.customer.staging'
          : 'com.fluxidi.customer',
      deepLinkScheme: staging ? 'fluxidicustomerstaging' : 'fluxidicustomer',
      deepLinkHost: 'pay',
      deepLinkPath: '/return',
      variant: CustomerAppVariant.fluxidiMarketplace,
      brand: kCustomerAppConfig.brand,
      publicBookingBaseUrl:
          publicUrl ??
          (staging ? stagingBooking : runtime.kFluxidiProductionBookingUrl),
    );
const stagingBooking =
    'https://fluxidi-booking-api-staging.fluxidi.workers.dev';
const stagingTracking =
    'https://fluxidi-tracking-api-staging.fluxidi.workers.dev';
const stagingNavigation =
    'https://fluxidi-navigation-api-staging.fluxidi.workers.dev';
String? guard({
  bool staging = true,
  CustomerAppConfig? app,
  String? booking,
  String? publicBooking,
  String? tracking,
  String? navigation,
  bool e2e = false,
  bool legacyStaging = false,
  bool qa = false,
  String token = '',
  String admin = '',
}) => customerRuntimeConfigurationError(
  config: app ?? config(staging),
  runtimeEnv: staging ? 'staging' : 'production',
  bookingUrl:
      booking ??
      (staging ? stagingBooking : runtime.kFluxidiProductionBookingUrl),
  publicBookingUrl:
      publicBooking ??
      (staging ? stagingBooking : runtime.kFluxidiProductionBookingUrl),
  trackingUrl:
      tracking ??
      (staging ? stagingTracking : runtime.kFluxidiProductionTrackingUrl),
  navigationUrl:
      navigation ??
      (staging ? stagingNavigation : runtime.kFluxidiProductionNavigationUrl),
  e2e: e2e,
  legacyStaging: legacyStaging,
  localQa: qa,
  e2eToken: token,
  adminToken: admin,
);

void main() {
  test(
    'compiled customer config, native contract and all shared API consumers agree',
    () {
      assertCustomerRuntimeConfiguration();
      expect(
        kCustomerAppConfig.androidApplicationId,
        kCustomerStagingRuntime
            ? 'com.fluxidi.customer.staging'
            : 'com.fluxidi.customer',
      );
      expect(
        kCustomerAppConfig.appName,
        kCustomerStagingRuntime ? 'Fluxidi Klanten Staging' : 'Fluxidi Klanten',
      );
      expect(kCustomerAppConfig.environmentLabel, isEmpty);
      expect(shared.kFluxidiE2eBuild, isFalse);
      expect(shared.kFluxidiE2eTestToken, isEmpty);
      expect(shared.kFluxidiCustomerStaging, isFalse);
      expect(
        shared.appConfig.bookingBaseUrl,
        kCustomerAppConfig.publicBookingBaseUrl,
      );
      if (kCustomerStagingRuntime) {
        expect(shared.appConfig.workerBaseUrl, stagingTracking);
        expect(shared.appConfig.navigationWorkerBaseUrl, stagingNavigation);
      }
    },
  );
  test('both complete customer runtimes are valid', () {
    expect(guard(), isNull);
    expect(guard(staging: false), isNull);
    expect(config(true).supportsCompanyDiscovery, isTrue);
    expect(config(true).variant, config(false).variant);
  });
  test('normal and staging identities cannot cross runtime boundaries', () {
    expect(guard(app: config(false)), 'customer_identity_runtime_mismatch');
    expect(
      guard(staging: false, app: config(true)),
      'customer_identity_runtime_mismatch',
    );
  });
  for (final url in [
    '',
    runtime.kFluxidiProductionBookingUrl,
    'https://fluxidi-booking-vat-e2e-test.fluxidi.workers.dev',
    'http://fluxidi-booking-api-staging.fluxidi.workers.dev',
    '$stagingBooking/path',
    '$stagingBooking?redirect=prod',
  ]) {
    test('staging refuses unsafe/missing booking URL: $url', () {
      expect(guard(booking: url), isNotNull);
      expect(guard(publicBooking: url), isNotNull);
      expect(guard(app: config(true, publicUrl: url)), isNotNull);
    });
  }
  test('no tracking/navigation production fallback or absent URLs', () {
    for (final url in ['', runtime.kFluxidiProductionTrackingUrl]) {
      expect(guard(tracking: url), isNotNull);
    }
    for (final url in ['', runtime.kFluxidiProductionNavigationUrl]) {
      expect(guard(navigation: url), isNotNull);
    }
  });
  test('normal runtime refuses staging services and divergent public API', () {
    expect(guard(staging: false, tracking: stagingTracking), isNotNull);
    expect(guard(staging: false, navigation: stagingNavigation), isNotNull);
    expect(
      guard(staging: false, app: config(false, publicUrl: stagingBooking)),
      isNotNull,
    );
  });
  test('E2E login, QA bypass and administrative credentials refused', () {
    expect(guard(e2e: true), isNotNull);
    expect(guard(legacyStaging: true), isNotNull);
    expect(guard(qa: true), isNotNull);
    expect(guard(token: 'test'), isNotNull);
    expect(guard(admin: 'test'), isNotNull);
  });
  test('payment return schemes are exclusive in both directions', () {
    for (final staging in [false, true]) {
      final own = config(staging);
      final foreign = config(!staging);
      expect(
        resolveCustomerDeepLink(
          Uri.parse(own.paymentReturnUrl),
          config: own,
        ).opensPaymentReturnScreen,
        isTrue,
      );
      expect(
        resolveCustomerDeepLink(
          Uri.parse(foreign.paymentReturnUrl),
          config: own,
        ).opensPaymentReturnScreen,
        isFalse,
      );
    }
  });
  test('existing disk state namespace is isolated in staging', () {
    expect(
      runtime.fluxidiRuntimeStateDirName(
        'customer',
        kind: runtime.FluxidiRuntimeKind.staging,
      ),
      'customer_staging',
    );
    expect(
      runtime.fluxidiRuntimeStateDirName(
        'customer',
        kind: runtime.FluxidiRuntimeKind.production,
      ),
      'customer',
    );
  });
}
