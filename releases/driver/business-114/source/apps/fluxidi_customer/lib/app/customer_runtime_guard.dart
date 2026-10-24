import 'package:fluxidi_tracking/app_config.dart' as shared;
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart' as runtime;
import 'customer_app_config.dart';

/// Runs before sessions, payment listeners or network clients are initialized.
String? customerRuntimeConfigurationError({
  required CustomerAppConfig config,
  required String runtimeEnv,
  required String bookingUrl,
  required String publicBookingUrl,
  required String trackingUrl,
  required String navigationUrl,
  bool e2e = false,
  bool legacyStaging = false,
  bool localQa = false,
  String e2eToken = '',
  String adminToken = '',
}) {
  if (![
    '',
    'production',
    'prod',
    'local',
    'local_test',
    'staging',
  ].contains(runtimeEnv)) {
    return 'unknown_customer_runtime';
  }
  if (e2e ||
      legacyStaging ||
      localQa ||
      e2eToken.isNotEmpty ||
      adminToken.isNotEmpty) {
    return 'customer_runtime_forbids_e2e_or_qa';
  }
  final staging = runtimeEnv == 'staging';
  if (config.androidApplicationId !=
          (staging ? 'com.fluxidi.customer.staging' : 'com.fluxidi.customer') ||
      config.deepLinkScheme !=
          (staging ? 'fluxidicustomerstaging' : 'fluxidicustomer') ||
      config.appName !=
          (staging ? 'Fluxidi Klanten Staging' : 'Fluxidi Klanten') ||
      config.environmentLabel.isNotEmpty) {
    return 'customer_identity_runtime_mismatch';
  }
  final endpoints = [
    (bookingUrl, runtime.kFluxidiStagingBookingHost),
    (publicBookingUrl, runtime.kFluxidiStagingBookingHost),
    (config.publicBookingBaseUrl, runtime.kFluxidiStagingBookingHost),
    (trackingUrl, runtime.kFluxidiStagingTrackingHost),
    (navigationUrl, runtime.kFluxidiStagingNavigationHost),
  ];
  for (final entry in endpoints) {
    final uri = Uri.tryParse(entry.$1);
    if (staging &&
        (uri == null ||
            uri.scheme != 'https' ||
            uri.host != entry.$2 ||
            uri.userInfo.isNotEmpty ||
            uri.hasPort ||
            uri.hasQuery ||
            uri.hasFragment ||
            (uri.path.isNotEmpty && uri.path != '/'))) {
      return 'customer_staging_endpoint_missing_or_invalid';
    }
    if (!staging &&
        (endpoints.any((item) => item.$2 == uri?.host) ||
            entry.$1.contains('-e2e'))) {
      return 'normal_customer_must_not_use_staging_or_e2e';
    }
  }
  String trim(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  if (trim(bookingUrl) != trim(config.publicBookingBaseUrl) ||
      trim(bookingUrl) != trim(publicBookingUrl)) {
    return 'customer_booking_endpoints_diverge';
  }
  return null;
}

void assertCustomerRuntimeConfiguration({
  CustomerAppConfig config = kCustomerAppConfig,
}) {
  final error = customerRuntimeConfigurationError(
    config: config,
    runtimeEnv: runtime.kFluxidiRuntimeEnvDefine,
    bookingUrl: shared.appConfig.bookingBaseUrl,
    publicBookingUrl: shared.kPublicBookingBaseUrl,
    trackingUrl: shared.appConfig.workerBaseUrl,
    navigationUrl: shared.appConfig.navigationWorkerBaseUrl,
    e2e: shared.kFluxidiE2eBuild,
    legacyStaging: shared.kFluxidiCustomerStaging,
    localQa: runtime.kFluxidiLocalQaCustomerSessionDefine,
    e2eToken: shared.kFluxidiE2eTestToken,
    adminToken:
        runtime.kFluxidiLocalQaAdminTokenDefine +
        const String.fromEnvironment('ADMIN_TOKEN'),
  );
  if (error != null) throw StateError(error);
}
