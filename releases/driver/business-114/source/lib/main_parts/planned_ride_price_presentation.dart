// PLANNED-RIDE-FIXED-PRICE-PRESENTATION-AND-DURABILITY-1
//
// Pure cockpit/tellers fare presentation for planned vs street/direct rides.
// Planned bookings always show the canonical fixed booking/leg price — never
// the live street meter — even while `_liveRideActive` is true.

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/main_parts/direct_ride_booking_link.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';

/// Labels shown above the fare amount (locale-aware).
abstract final class DriverFarePresentationLabels {
  static String fixedPrice(AppLanguage language) =>
      driverTellersFixedPriceLabel(language);

  static const String liveMeterCockpit = '€';

  static String liveMeterTellers(AppLanguage language) =>
      driverTellersFareLabel(language);
}

/// Resolved fare text + label for the driver cockpit / Tellers surface.
class DriverCockpitFarePresentation {
  const DriverCockpitFarePresentation({
    required this.amountText,
    required this.cockpitLabel,
    required this.tellersLabel,
    required this.usesFixedPrice,
  });

  /// e.g. `€ 42.50` or `€ —`
  final String amountText;

  /// Short label for the compact cockpit metric tile.
  final String cockpitLabel;

  /// Full label for the Tellers fare tile.
  final String tellersLabel;

  /// True when the amount comes from a planned booking/leg (never the meter).
  final bool usesFixedPrice;
}

/// True when [bookingRecord] is a street/direct ride (live meter presentation).
bool bookingRecordIsStreetDirect(Map<String, dynamic>? bookingRecord) {
  return isStreetDirectBooking(bookingRecord);
}

/// Formats a fixed EUR amount, or `€ —` when missing/non-positive.
String formatFixedBookingPriceText(double? amountEur) {
  if (amountEur == null || !amountEur.isFinite || amountEur <= 0) {
    return '€ —';
  }
  return '€ ${amountEur.toStringAsFixed(2)}';
}

/// Formats a live meter preview amount (street/direct only).
String formatLiveMeterPriceText(double amountEur) {
  final v = amountEur.isFinite ? amountEur : 0.0;
  return '€ ${v.toStringAsFixed(2)}';
}

/// Resolves what the driver sees as the fare during prepare / START / active.
///
/// [fixedBookingPriceEur] must already be the canonical booking/leg price from
/// `_driverDisplayPriceForBooking` (or equivalent). This helper never invents
/// a server price and never falls back to the live meter for planned rides.
DriverCockpitFarePresentation resolveDriverCockpitFarePresentation({
  required bool hasActiveBooking,
  required bool isStreetOrDirectBooking,
  required double? fixedBookingPriceEur,
  required double liveMeterPreviewEur,
  AppLanguage language = AppLanguage.nl,
}) {
  final plannedBooking = hasActiveBooking && !isStreetOrDirectBooking;
  if (plannedBooking) {
    final label = DriverFarePresentationLabels.fixedPrice(language);
    return DriverCockpitFarePresentation(
      amountText: formatFixedBookingPriceText(fixedBookingPriceEur),
      cockpitLabel: label,
      tellersLabel: label,
      usesFixedPrice: true,
    );
  }

  return DriverCockpitFarePresentation(
    amountText: formatLiveMeterPriceText(liveMeterPreviewEur),
    cockpitLabel: DriverFarePresentationLabels.liveMeterCockpit,
    tellersLabel: DriverFarePresentationLabels.liveMeterTellers(language),
    usesFixedPrice: false,
  );
}

double? _finitePositiveOrNull(num? value) {
  if (value == null) return null;
  final d = value.toDouble();
  if (!d.isFinite || d <= 0) return null;
  return d;
}

double? _numFromDynamic(dynamic value) {
  if (value is num) {
    final d = value.toDouble();
    return d.isFinite ? d : null;
  }
  if (value is String) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }
  return null;
}

/// Canonical planned display price from a booking/leg map.
///
/// Mirrors the operational-leg priority used by [BookingItem] /
/// `_driverDisplayPriceForBooking`: leg price → return/main split → never the
/// parent package total when a leg amount exists.
double? resolvePlannedDisplayPriceFromBookingMap(Map<String, dynamic>? map) {
  if (map == null || map.isEmpty) return null;

  final legId = (map['leg_id'] ?? map['legId'] ?? '').toString().trim();
  final isOperationalLeg = map['is_operational_leg'] == true ||
      map['isOperationalLeg'] == true ||
      legId.isNotEmpty;

  if (isOperationalLeg) {
    final legPrice = _finitePositiveOrNull(
      _numFromDynamic(map['leg_price_incl_vat'] ?? map['legPriceInclVat']),
    );
    if (legPrice != null) return legPrice;

    final legType = (map['leg_type'] ?? map['legType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (legType == 'return') {
      final returnPrice = _finitePositiveOrNull(
        _numFromDynamic(
          map['price_incl_vat_return'] ??
              map['priceInclVatReturn'] ??
              map['return_price_eur'],
        ),
      );
      if (returnPrice != null) return returnPrice;
    } else {
      final mainPrice = _finitePositiveOrNull(
        _numFromDynamic(
          map['price_incl_vat_main'] ??
              map['priceInclVatMain'] ??
              map['outbound_price_eur'],
        ),
      );
      if (mainPrice != null) return mainPrice;
    }

    final segment = _finitePositiveOrNull(
      _numFromDynamic(map['segment_price_eur'] ?? map['segmentPriceEur']),
    );
    if (segment != null) return segment;

    // Never fall back to parent package total for an operational leg.
    return null;
  }

  return _finitePositiveOrNull(
    _numFromDynamic(
      map['price_incl_vat'] ??
          map['priceInclVat'] ??
          map['price'] ??
          map['total_price'],
    ),
  );
}
