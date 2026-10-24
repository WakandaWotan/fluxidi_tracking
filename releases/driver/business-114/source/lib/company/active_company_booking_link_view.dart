import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/driver/driver_pin_verified_session.dart';
import 'package:fluxidi_tracking/driver/vehicle_device_store.dart';
import 'driver_public_booking_link.dart';
import 'driver_booking_link_trace.dart';

import 'company_public_booking_link.dart';
import 'company_public_booking_link_view.dart';

/// Uses the same authenticated company bootstrap as the Business app.
/// No cached neighbouring profile, admin fallback, or invented company slug.
class ActiveCompanyBookingLinkView extends StatelessWidget {
  const ActiveCompanyBookingLinkView({
    super.key,
    required this.language,
    this.onAvailabilityChanged,
    this.driverOnly = false,
  });

  final AppLanguage language;
  final ValueChanged<bool>? onAvailabilityChanged;
  /// Chauffeur dashboard never selects a simultaneously retained admin session.
  final bool driverOnly;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ActiveCompanySession?>(
      valueListenable: activeCompanySessionNotifier,
      builder: (context, session, _) {
        if (session == null || driverOnly) {
          return ValueListenableBuilder<ActiveDriverSession?>(
            valueListenable: activeDriverSessionNotifier,
            builder: (context, driver, _) {
              bool driverCurrent() =>
                  driver != null &&
                  identical(activeDriverSessionNotifier.value, driver) &&
                  (driverOnly || activeCompanySessionNotifier.value == null);
              return CompanyPublicBookingLinkView(
                key: ObjectKey(driver),
                language: language,
                scopeIsCurrent: driverCurrent,
                onAvailabilityChanged: onAvailabilityChanged,
                loader: () async {
                  final trace = DriverBookingLinkTrace(
                    tenantId: driver?.tenantId, companyId: driver?.companyId,
                    vehicleId: driver?.assignedVehicleId, driverId: driver?.driverId,
                  );
                  return trace.run(() async {
                    final expiry = DateTime.tryParse(driver?.driverSessionExpiresAtUtc ?? '');
                    trace.facts({
                      'driver_present': driver != null,
                      'standalone': driver?.isStandaloneLoginSession == true,
                      'operator_minted': driver?.isOperatorMintedSession == true,
                      'token_present': (driver?.driverSessionToken ?? '').isNotEmpty,
                      'expiry_valid': expiry?.isAfter(DateTime.now()) == true,
                      'tenant_present': (driver?.tenantId ?? '').isNotEmpty,
                      'company_present': (driver?.companyId ?? '').isNotEmpty,
                      'vehicle_present': (driver?.assignedVehicleId ?? '').isNotEmpty,
                      'company_code_present': (driver?.companyCode ?? '').isNotEmpty,
                      'context_current': driverCurrent(),
                    });
                  if (driver == null)
                    throw const CompanyBookingLinkUnavailable();
                  final store = VehicleDeviceStore();
                  final before = await trace.step('local_binding', store.pinScope);
                  trace.facts({'binding_present': before != null});
                  bool sameBinding(Map<String, dynamic>? after) {
                    final unchanged = before != null &&
                      after != null &&
                      before.length == after.length &&
                      before.keys.every((key) => before[key] == after[key]);
                    trace.facts({'binding_unchanged': unchanged});
                    return unchanged;
                  }
                  final link = await resolveDriverPublicBookingLink(
                    tenantId: driver.tenantId ?? '',
                    companyId: driver.companyId ?? '',
                    vehicleId: driver.assignedVehicleId ?? '',
                    driverId: driver.driverId,
                    verifiedSessionCompanyCode: driver.companyCode,
                    verifyDriver: () => trace.step('driver_status', () async {
                      await DriverPinServerSession.fromVerifiedSession(
                        driver,
                      ).verify();
                    }),
                    directoryLoader: () => trace.step('device_directory',
                        () => store.driverChoices(appConfig.bookingBaseUrl)),
                    slugLoader: (code) => trace.step('public_alias', () async {
                      trace.facts({'company_code_present': code.isNotEmpty,
                        'company_code_valid': RegExp(r'^FLX-[0-9]{5,12}$').hasMatch(code)});
                      return fetchRegisteredBookingSlug(code);
                    }),
                    contextLoader: (slug) => trace.step('app_context', () async {
                      final value = await fetchCompanyBookingContext(slug);
                      final company = value['company']; final profile = value['profile'];
                      trace.facts({
                        'tenant_equal': company is Map && company['tenant_id'] == driver.tenantId,
                        'company_equal': company is Map && company['company_id'] == driver.companyId,
                        'public_active': profile is Map && profile['is_active'] == true,
                        'public_bookable': profile is Map && profile['bookable'] == true,
                        'public_profile_enabled': profile is Map && profile['profile_enabled'] != false,
                        'context_current': driverCurrent(),
                      });
                      return value;
                    }),
                    scopeIsCurrent: () {
                      final current = driverCurrent();
                      if (!current) trace.facts({'context_current': false});
                      return current;
                    },
                  );
                  if (!driverCurrent() ||
                      !sameBinding(await trace.step('final_binding', store.pinScope))) {
                    throw const CompanyBookingLinkUnavailable();
                  }
                  return link;
                  });
                },
              );
            },
          );
        }
        bool current() => activeCompanySessionNotifier.value == session;
        return CompanyPublicBookingLinkView(
          key: ObjectKey(session),
          language: language,
          scopeIsCurrent: current,
          onAvailabilityChanged: onAvailabilityChanged,
          loader: () => resolveCompanyPublicBookingLink(
            expectedCompanyId: session.companyId,
            scopeIsCurrent: current,
            profileLoader: () async {
              if (!current()) throw const CompanyBookingLinkUnavailable();
              final auth = await CompanySessionStore.instance
                  .resolveCompanyBootstrapToken(preferredSession: session);
              final token = auth.token?.trim() ?? '';
              if (!current() || token.isEmpty) {
                throw const CompanyBookingLinkUnavailable();
              }
              final bootstrap = await fetchCompanyBootstrapWithToken(
                companySessionToken: token,
              );
              if (bootstrap == null) {
                throw const CompanyBookingLinkUnavailable();
              }
              return bootstrap;
            },
          ),
        );
      },
    );
  }
}
