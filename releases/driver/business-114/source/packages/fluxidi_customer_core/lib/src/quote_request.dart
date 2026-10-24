/// Builds the `POST /quote` body for a customer taxi ride.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// `lib/company/company_plan_quote.dart` — `CompanyPlanQuoteRequest`,
/// `companyPlanQuoteFingerprint`, `companyPlanQuoteRequestFromAddresses`.
///
/// The field names are the contract. Do not rename or add fields here without
/// checking the existing flow first.
library;

import 'address_value.dart';
import 'ride_options.dart';
import 'schedule.dart';

class FluxidiQuoteRequest {
  const FluxidiQuoteRequest({required this.fingerprint, required this.body});

  /// Identifies the inputs this body was built from. A response only belongs to
  /// a request with the same fingerprint.
  final String fingerprint;

  final Map<String, dynamic> body;
}

String fluxidiQuoteFingerprint({
  required FluxidiAddressValue from,
  required FluxidiAddressValue to,
  required DateTime? pickupLocal,
  required FluxidiRideOptions options,
  required int passengers,
  DateTime? returnPickupLocal,
  FluxidiAddressValue? returnFrom,
  FluxidiAddressValue? returnTo,
  bool returnEnabled = false,
  bool whenNow = false,
  String vehicleId = '',
}) {
  String coord(FluxidiAddressValue value) {
    final lat = value.lat;
    final lon = value.lon;
    if (lat != null && lon != null && lat.isFinite && lon.isFinite) {
      return '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
    }
    return '${value.placeId ?? ''}|${value.routeText}';
  }

  String minute(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return '${local.year}-${local.month}-${local.day}T${local.hour}:${local.minute}';
  }

  return <String>[
    coord(from),
    coord(to),
    whenNow ? 'now' : minute(pickupLocal),
    options.service,
    options.tier,
    options.vehicleType,
    '${options.bags}',
    '${options.waitMin}',
    '$passengers',
    returnEnabled ? 'rt' : 'one',
    if (returnEnabled) minute(returnPickupLocal),
    if (returnEnabled) coord(returnFrom ?? const FluxidiAddressValue()),
    if (returnEnabled) coord(returnTo ?? const FluxidiAddressValue()),
    vehicleId.trim(),
  ].join('|');
}

/// Same body without coordinates, for a confirmed address that has none.
///
/// The public `/quote` requires `from`, `to`, `date` and `time` and geocodes the
/// address text itself; verified live on 2026-09-21, where the answer carried
/// `from_lat` / `to_lng` for text-only input. The existing app always sends
/// coordinates because it also draws the route, which is why
/// [buildFluxidiQuoteRequest] keeps that stricter rule unchanged.
FluxidiQuoteRequest? buildFluxidiQuoteRequestFromText({
  required FluxidiAddressValue from,
  required FluxidiAddressValue to,
  required DateTime? pickupLocal,
  required FluxidiRideOptions options,
  required int passengers,
  DateTime? returnPickupLocal,
  FluxidiAddressValue? returnFrom,
  FluxidiAddressValue? returnTo,
  bool returnEnabled = false,
  String currency = 'EUR',
  bool whenNow = false,
  String vehicleId = '',
}) {
  if (!from.isRouteReady ||
      from.routeText.isEmpty ||
      !to.isRouteReady ||
      to.routeText.isEmpty ||
      (!whenNow && pickupLocal == null)) {
    return null;
  }
  return _buildQuoteRequest(
    from: from,
    to: to,
    pickupLocal: pickupLocal,
    options: options,
    passengers: passengers,
    returnPickupLocal: returnPickupLocal,
    returnFrom: returnFrom,
    returnTo: returnTo,
    returnEnabled: returnEnabled,
    currency: currency,
    whenNow: whenNow,
    vehicleId: vehicleId,
  );
}

/// Returns null when the inputs are not complete enough to ask for a price.
FluxidiQuoteRequest? buildFluxidiQuoteRequest({
  required FluxidiAddressValue from,
  required FluxidiAddressValue to,
  required DateTime? pickupLocal,
  required FluxidiRideOptions options,
  required int passengers,
  DateTime? returnPickupLocal,
  FluxidiAddressValue? returnFrom,
  FluxidiAddressValue? returnTo,
  bool returnEnabled = false,
  String currency = 'EUR',
  bool whenNow = false,
  String vehicleId = '',
}) {
  if (!fluxidiAddressIsQuoteReady(from) ||
      !fluxidiAddressIsQuoteReady(to) ||
      (!whenNow && pickupLocal == null)) {
    return null;
  }
  return _buildQuoteRequest(
    from: from,
    to: to,
    pickupLocal: pickupLocal,
    options: options,
    passengers: passengers,
    returnPickupLocal: returnPickupLocal,
    returnFrom: returnFrom,
    returnTo: returnTo,
    returnEnabled: returnEnabled,
    currency: currency,
    whenNow: whenNow,
    vehicleId: vehicleId,
  );
}

FluxidiQuoteRequest _buildQuoteRequest({
  required FluxidiAddressValue from,
  required FluxidiAddressValue to,
  required DateTime? pickupLocal,
  required FluxidiRideOptions options,
  required int passengers,
  required DateTime? returnPickupLocal,
  required FluxidiAddressValue? returnFrom,
  required FluxidiAddressValue? returnTo,
  required bool returnEnabled,
  required String currency,
  required bool whenNow,
  required String vehicleId,
}) {
  final fingerprint = fluxidiQuoteFingerprint(
    from: from,
    to: to,
    pickupLocal: whenNow ? null : pickupLocal,
    options: options,
    passengers: passengers,
    returnPickupLocal: returnPickupLocal,
    returnFrom: returnFrom,
    returnTo: returnTo,
    returnEnabled: returnEnabled,
    whenNow: whenNow,
    vehicleId: vehicleId,
  );

  final userPostcode = options.isAirport
      ? fluxidiPostcodeFromAddress(from)
      : '';

  final body = <String, dynamic>{
    'from': from.routeText,
    'to': to.routeText,
    'passengers': passengers,
    'currency': currency,
    'ride_options': options.toJson(),
    if (options.service.isNotEmpty) 'service': options.service,
    if (options.tier.isNotEmpty) 'tier': options.tier,
    if (options.bags > 0) 'bags': options.bags,
    if (!options.isAirport && options.waitMin > 0) 'wait_min': options.waitMin,
    if (userPostcode.isNotEmpty) ...<String, dynamic>{
      'postcode': userPostcode,
      'postal_code': userPostcode,
      'pickup_postcode': userPostcode,
      'from_postcode': userPostcode,
      'fixed_fare_zone_type': 'postcode',
      'fixed_fare_zone_value': userPostcode,
    },
    if (from.lat != null && from.lon != null) ...<String, dynamic>{
      'pickup_lat': from.lat,
      'pickup_lon': from.lon,
      'from_lat': from.lat,
      'from_lng': from.lon,
    },
    if (to.lat != null && to.lon != null) ...<String, dynamic>{
      'dropoff_lat': to.lat,
      'dropoff_lon': to.lon,
      'to_lat': to.lat,
      'to_lng': to.lon,
    },
    'return_enabled': returnEnabled,
    if (returnEnabled && returnPickupLocal != null)
      'return_pickup_iso': fluxidiPickupIso(returnPickupLocal),
    if (returnEnabled && returnFrom != null && returnFrom.routeText.isNotEmpty)
      'return_from': returnFrom.routeText,
    if (returnEnabled && returnTo != null && returnTo.routeText.isNotEmpty)
      'return_to': returnTo.routeText,
    if (returnEnabled &&
        returnFrom != null &&
        returnFrom.lat != null &&
        returnFrom.lon != null) ...<String, dynamic>{
      'return_from_lat': returnFrom.lat,
      'return_from_lng': returnFrom.lon,
    },
    if (returnEnabled &&
        returnTo != null &&
        returnTo.lat != null &&
        returnTo.lon != null) ...<String, dynamic>{
      'return_to_lat': returnTo.lat,
      'return_to_lng': returnTo.lon,
    },
    if (vehicleId.trim().isNotEmpty) ...<String, dynamic>{
      'vehicle_id': vehicleId.trim(),
      'preferred_vehicle_id': vehicleId.trim(),
    },
  };

  if (whenNow) {
    body.addAll(fluxidiWhenWireFields(whenNow: true));
    fluxidiStripClientScheduleFields(body);
  } else if (pickupLocal != null) {
    body['pickup_iso'] = fluxidiPickupIso(pickupLocal);
  }
  if (options.isAirport) {
    fluxidiStripWaitFields(body);
  }

  return FluxidiQuoteRequest(fingerprint: fingerprint, body: body);
}
