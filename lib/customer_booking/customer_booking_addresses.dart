import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

import 'customer_booking_entry.dart';

LimousineAddressValue customerBookingAddressFromText(
  String text, {
  double? latitude,
  double? longitude,
  bool selected = true,
}) {
  final label = text.trim();
  if (label.isEmpty) return const LimousineAddressValue();
  return LimousineAddressValue(
    displayText: label,
    canonicalLabel: label,
    lat: latitude,
    lon: longitude,
    acceptance: selected
        ? LimousineAddressAcceptance.selected
        : LimousineAddressAcceptance.manualFallback,
  );
}

LimousineAddressValue customerBookingAddressFromAirport(
  AirportCatalogAirport airport,
) {
  return customerBookingAddressFromText(
    airport.formattedAddress,
    latitude: airport.latitude,
    longitude: airport.longitude,
  );
}

LimousineAddressValue customerBookingAddressFromPlace(
  CustomerBookingPlace place,
) {
  return customerBookingAddressFromText(
    place.displayAddress,
    latitude: place.latitude,
    longitude: place.longitude,
  );
}

String customerProfileDefaultAddressLine(CustomerProfile profile) {
  final street = profile.billingStreet.trim();
  final postal = profile.billingPostalCode.trim();
  final city = profile.billingCity.trim();
  final postcode = postal.isNotEmpty ? postal : profile.preferredPostcode.trim();
  return [
    if (street.isNotEmpty) street,
    if (postcode.isNotEmpty || city.isNotEmpty)
      [postcode, city].where((part) => part.trim().isNotEmpty).join(' '),
  ].join(', ');
}

LimousineAddressValue? customerBookingAddressFromProfile(CustomerProfile profile) {
  final line = customerProfileDefaultAddressLine(profile);
  if (line.isEmpty) return null;
  return customerBookingAddressFromText(line);
}

bool customerBookingPickupIsVacant(LimousineAddressValue value) {
  return value.displayText.trim().isEmpty && !value.isRouteReady;
}

String customerBookingAirportSummary(AirportCatalogAirport airport) {
  final iata = airport.iata.trim().toUpperCase();
  final name = airport.name.trim();
  if (iata.isEmpty) return '✈ $name';
  if (name.isEmpty) return '✈ $iata';
  return '✈ $name ($iata)';
}

Future<void> customerBookingGeocodeIfNeeded(
  LimousineAddressFieldController controller,
) async {
  final value = controller.value;
  if (value.hasCoordinates) return;
  final query = value.routeText.trim().isEmpty
      ? value.displayText.trim()
      : value.routeText.trim();
  if (query.length < kLimousineAddressMinQueryLength) return;
  final result = await controller.lookup.search(
    query,
    language: controller.language,
  );
  if (controller.textController.text.trim() != query) return;
  final best = limousinePreferStreetLevelSuggestion(query, result.suggestions);
  if (best == null || !best.hasCoordinates) return;
  if (best.isStreetLevel == false &&
      !limousineAddressLooksLikeLocalityOnly(query)) {
    return;
  }
  final kept = limousinePreferCanonicalLabel(
    original: query,
    suggestion: best.label,
  );
  controller.acceptCopy(
    LimousineAddressValue(
      displayText: kept,
      canonicalLabel: kept,
      lat: best.lat,
      lon: best.lon,
      placeId: best.placeId,
      acceptance: LimousineAddressAcceptance.selected,
    ),
  );
}
