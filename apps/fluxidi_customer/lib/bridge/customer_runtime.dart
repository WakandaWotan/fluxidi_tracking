import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:fluxidi_tracking/active_local_customer_store.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';
import 'package:fluxidi_tracking/payment_return.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../app/customer_app_config.dart';
import '../app/customer_theme.dart';
import '../security/customer_session_lock.dart';
import 'customer_language.dart';

/// Boots only what a customer needs.
///
/// The combined app's `main()` also restores a company session, a driver
/// session, fleet state, business themes and an E2E auto-login. None of that
/// belongs to a customer, and starting it here would pull this app into
/// company scope it must never have. This boot therefore stops at the customer
/// session, the customer profile, the customer theme, the app language and the
/// payment-return coordinator.
Future<void> bootCustomerRuntime({
  CustomerAppConfig config = kCustomerAppConfig,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Same fail-closed startup guards the combined app runs: an E2E token or an
  // E2E host may never reach a production build, and a production runtime may
  // never point at a loopback booking host.
  assertFluxidiBookingEndpointGuards();
  assertFluxidiRuntimeEnvGuards();

  await loadCustomerThemePreference();
  await loadCustomerLanguagePreference();
  applyCustomerThemeSystemUiOverlay(activeCustomerPalette());

  final mapboxToken = config.mapboxToken.trim();
  if (mapboxToken.isEmpty) {
    debugPrint('[CUSTOMER_BOOT][MAPBOX] no token; map and route fall back');
  } else {
    mb.MapboxOptions.setAccessToken(mapboxToken);
  }

  // This app owns fluxidicustomerdev://pay/return. Declaring it here keeps the
  // combined app's fluxidi://pay/return untouched, so both can be installed
  // side by side and neither answers the other's return link. Server status
  // stays the only thing that may mark a ride paid.
  paymentReturnCoordinator.start(
    bookingBaseUrl: config.publicBookingBaseUrl,
    scheme: config.deepLinkScheme,
    host: config.deepLinkHost,
    returnUrl: config.paymentReturnUrl,
  );

  await CustomerSessionLock.instance.attach();

  debugPrint(
    '[CUSTOMER_BOOT] runtime=${fluxidiRuntimeKind.name} '
    'booking=${Uri.tryParse(config.publicBookingBaseUrl)?.host ?? "unset"} '
    'return=${config.paymentReturnUrl} '
    'mapbox=${mapboxToken.isNotEmpty}',
  );
}

/// Pulls the customer profile the server holds for the current session into
/// the local store.
///
/// Public counterpart of the combined app's private
/// `_syncCustomerProfileFromBackendBestEffort`, which lives inside the
/// `main.dart` part library and cannot be called from here. Same contract:
/// best effort, never throws, and an expired session is cleared rather than
/// retried.
Future<CustomerProfile?> syncCustomerProfileFromBackend({
  required String reason,
}) async {
  try {
    final session = await CustomerSessionStore.instance.loadValidSession();
    if (session == null) {
      debugPrint(
        '[CUSTOMER_PROFILE_SYNC][PULL] ok=false reason=$reason '
        'stage=no_valid_session',
      );
      return null;
    }
    await ActiveLocalCustomerStore.instance.setActiveCustomerId(
      session.customerId,
    );
    CustomerProfileStore.instance.invalidateCache();
    final remote = await fetchPublicCustomerProfile(
      customerSessionToken: session.customerSessionToken,
    );
    if (remote == null) {
      final status = lastCustomerProfileHttpStatusCode ?? 0;
      if (status == 401 || status == 403) {
        await CustomerSessionStore.instance.clear();
      }
      debugPrint(
        '[CUSTOMER_PROFILE_SYNC][PULL] ok=false reason=$reason '
        'stage=fetch_failed status=$status',
      );
      return null;
    }
    final merged = await CustomerProfileStore.instance
        .mergeBackendProfileForSession(
          remote,
          sessionCustomerId: session.customerId,
          sessionPhoneE164: session.phoneE164,
        );
    debugPrint('[CUSTOMER_PROFILE_SYNC][PULL] ok=true reason=$reason');
    return merged;
  } catch (error) {
    debugPrint(
      '[CUSTOMER_PROFILE_SYNC][PULL] ok=false reason=$reason '
      'stage=error error=$error',
    );
    return null;
  }
}

/// How long a local store read may take before the screen gives up on it.
///
/// These reads go through platform channels. A channel that never answers
/// would otherwise leave the profile page loading forever, so the screen
/// settles on "signed out" instead of waiting indefinitely.
const Duration kCustomerLocalReadTimeout = Duration(seconds: 5);

/// Reads the locally cached customer profile, if this device has one.
Future<CustomerProfile?> loadLocalCustomerProfile() async {
  try {
    return await CustomerProfileStore.instance.load().timeout(
      kCustomerLocalReadTimeout,
      onTimeout: () => null,
    );
  } catch (error) {
    debugPrint('[CUSTOMER_PROFILE][LOAD] error=$error');
    return null;
  }
}

/// True when a customer session is present and still valid.
Future<bool> hasValidCustomerSession() async {
  try {
    final session = await CustomerSessionStore.instance
        .loadValidSession()
        .timeout(kCustomerLocalReadTimeout, onTimeout: () => null);
    return session != null;
  } catch (_) {
    return false;
  }
}

/// Refreshes the profile in the background without blocking a screen build.
void scheduleCustomerProfileSync({required String reason}) {
  unawaited(syncCustomerProfileFromBackend(reason: reason));
}
