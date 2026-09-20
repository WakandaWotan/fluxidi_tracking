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
  final hasCoords =
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite;
  return LimousineAddressValue(
    displayText: label,
    canonicalLabel: label,
    lat: hasCoords ? latitude : null,
    lon: hasCoords ? longitude : null,
    acceptance: hasCoords
        ? LimousineAddressAcceptance.selected
        : (selected
              ? LimousineAddressAcceptance.incomplete
              : LimousineAddressAcceptance.manualFallback),
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

/// Return origin: typed return pickup, otherwise the outbound drop-off
/// (airport included). Empty street fields must not wipe a fixed-price leg.
LimousineAddressValue customerBookingReturnFromAddress({
  required LimousineAddressValue returnPickup,
  required LimousineAddressValue outboundDropoff,
}) {
  if (returnPickup.isRouteReady && returnPickup.routeText.trim().isNotEmpty) {
    return returnPickup;
  }
  return outboundDropoff;
}

/// Return destination: typed return drop-off, otherwise the outbound pickup.
LimousineAddressValue customerBookingReturnToAddress({
  required LimousineAddressValue returnDropoff,
  required LimousineAddressValue outboundPickup,
}) {
  if (returnDropoff.isRouteReady && returnDropoff.routeText.trim().isNotEmpty) {
    return returnDropoff;
  }
  return outboundPickup;
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

bool customerBookingPickupNeedsConfirm(LimousineAddressFieldController pickup) {
  if (pickup.locationUserConfirmed && pickup.value.hasCoordinates) {
    return false;
  }
  if (pickup.locationNeedsConfirm) return true;
  if (pickup.value.isRouteReady && pickup.value.hasCoordinates) {
    return false;
  }
  final text = pickup.value.displayText.trim();
  if (text.isEmpty) return false;
  return limousineParseStreetHouse(text).hasNumber &&
      !pickup.value.hasCoordinates;
}

String customerBookingAirportSummary(AirportCatalogAirport airport) {
  final iata = airport.iata.trim().toUpperCase();
  final name = airport.name.trim();
  if (iata.isEmpty) return '✈ $name';
  if (name.isEmpty) return '✈ $iata';
  return '✈ $name ($iata)';
}

bool customerBookingAirportMetadataReady(AirportCatalogAirport? airport) {
  if (airport == null) return false;
  return airport.iata.trim().length >= 3 || airport.id.trim().isNotEmpty;
}

String customerBookingAirportCompactSummary(AirportCatalogAirport airport) {
  final iata = airport.iata.trim().toUpperCase();
  final city = airport.city.trim();
  final name = airport.name.trim();
  final heading = city.isNotEmpty ? city : name;
  if (iata.isEmpty) return heading;
  if (heading.isEmpty) return iata;
  return '$heading · $iata';
}

Future<CustomerBookingOwnedAddressResolution> customerBookingGeocodeIfNeeded(
  LimousineAddressFieldController controller,
) async {
  if (controller.locationUserConfirmed && controller.value.hasCoordinates) {
    return CustomerBookingOwnedAddressResolution(
      value: controller.value,
    );
  }
  final query = controller.value.displayText.trim().isEmpty
      ? controller.textController.text.trim()
      : controller.value.displayText.trim();
  if (query.length < kLimousineAddressMinQueryLength) {
    return CustomerBookingOwnedAddressResolution(value: controller.value);
  }
  final result = await controller.lookup.search(
    query,
    language: controller.language,
    proximityLat: controller.proximityLatitude?.call(),
    proximityLon: controller.proximityLongitude?.call(),
    contextCountry: controller.searchContextCountry?.call(),
  );
  if (controller.locationUserConfirmed && controller.value.hasCoordinates) {
    return CustomerBookingOwnedAddressResolution(value: controller.value);
  }
  if (controller.textController.text.trim() != query) {
    return CustomerBookingOwnedAddressResolution(value: controller.value);
  }
  final resolved = limousineResolveOwnedAddress(query: query, result: result);
  controller.applyOwnedResolution(resolved);
  return resolved;
}
