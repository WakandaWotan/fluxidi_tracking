import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

export 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart'
    show limousineResolveOwnedAddress, LimousineOwnedAddressResolution;

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
  if (street.isEmpty) return '';
  final postal = profile.billingPostalCode.trim().isNotEmpty
      ? profile.billingPostalCode.trim()
      : profile.preferredPostcode.trim();
  return companyPlanCanonicalAddressLine(
    street: street,
    postalCode: postal,
    city: profile.billingCity.trim(),
    country: profile.billingCountry.trim(),
  );
}

LimousineAddressValue? customerBookingAddressFromProfile(CustomerProfile profile) {
  final line = customerProfileDefaultAddressLine(profile);
  if (line.isEmpty) return null;
  return customerBookingAddressFromText(line);
}

typedef CustomerBookingOwnedAddressResolution = LimousineOwnedAddressResolution;

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

Future<CustomerBookingOwnedAddressResolution> customerBookingGeocodeIfNeeded(
  LimousineAddressFieldController controller,
) async {
  final query = controller.value.displayText.trim().isEmpty
      ? controller.textController.text.trim()
      : controller.value.displayText.trim();
  if (query.length < kLimousineAddressMinQueryLength) {
    return CustomerBookingOwnedAddressResolution(value: controller.value);
  }
  final result = await controller.lookup.search(
    query,
    language: controller.language,
  );
  if (controller.textController.text.trim() != query) {
    return CustomerBookingOwnedAddressResolution(value: controller.value);
  }
  final resolved = limousineResolveOwnedAddress(query: query, result: result);
  controller.applyOwnedResolution(resolved);
  return resolved;
}
