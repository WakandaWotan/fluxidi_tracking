// Additive typed itinerary endpoint for limousine quote/book payloads.
// `from`/`to` stay backward-compatible display strings. This snapshot is
// immutable after submit: later provider result changes do not rewrite it.

import '../airport/airport_catalog_repository.dart';
import 'limousine_address_lookup.dart';

abstract final class LimousineTransferEndpointKind {
  static const String address = 'address';
  static const String airport = 'airport';
  static const String hotel = 'hotel';
  static const String event = 'event';
  static const String venue = 'venue';

  static const List<String> all = <String>[
    address,
    airport,
    hotel,
    event,
    venue,
  ];

  static bool isEvent(String kind) => kind == event || kind == venue;
}

class LimousineTransferEndpoint {
  const LimousineTransferEndpoint({
    this.kind = LimousineTransferEndpointKind.address,
    this.displayName = '',
    this.formattedAddress = '',
    this.latitude,
    this.longitude,
    this.providerPlaceId,
    this.airportName,
    this.iataCode,
    this.countryCode,
    this.hotelName,
    this.venueName,
    this.eventName,
    this.city,
    this.postcode,
    this.ratehawkHotelId,
    this.manual = false,
  });

  final String kind;
  final String displayName;
  final String formattedAddress;
  final double? latitude;
  final double? longitude;
  final String? providerPlaceId;
  final String? airportName;
  final String? iataCode;
  final String? countryCode;
  final String? hotelName;
  final String? venueName;
  final String? eventName;
  final String? city;
  final String? postcode;
  final String? ratehawkHotelId;
  final bool manual;

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      limousineCoordinatesAreValid(latitude!, longitude!);

  String get routeText {
    final formatted = formattedAddress.trim();
    if (formatted.isNotEmpty) return formatted;
    return displayName.trim();
  }

  bool get isEmpty => routeText.isEmpty;

  LimousineTransferEndpoint copyWith({
    String? kind,
    String? displayName,
    String? formattedAddress,
    double? latitude,
    double? longitude,
    String? providerPlaceId,
    String? airportName,
    String? iataCode,
    String? countryCode,
    String? hotelName,
    String? venueName,
    String? eventName,
    String? city,
    String? postcode,
    String? ratehawkHotelId,
    bool? manual,
    bool clearAirport = false,
    bool clearHotel = false,
    bool clearEvent = false,
    bool clearEventName = false,
    bool clearPlaceId = false,
  }) {
    return LimousineTransferEndpoint(
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      providerPlaceId: clearPlaceId ? null : (providerPlaceId ?? this.providerPlaceId),
      airportName: clearAirport ? null : (airportName ?? this.airportName),
      iataCode: clearAirport ? null : (iataCode ?? this.iataCode),
      countryCode: countryCode ?? (clearAirport ? this.countryCode : this.countryCode),
      hotelName: clearHotel ? null : (hotelName ?? this.hotelName),
      venueName: clearEvent ? null : (venueName ?? this.venueName),
      eventName: clearEvent || clearEventName ? null : (eventName ?? this.eventName),
      city: city ?? this.city,
      postcode: postcode ?? this.postcode,
      ratehawkHotelId: clearHotel ? null : (ratehawkHotelId ?? this.ratehawkHotelId),
      manual: manual ?? this.manual,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'kind': kind,
      'display_name': displayName.trim(),
      'formatted_address': formattedAddress.trim(),
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if ((providerPlaceId ?? '').trim().isNotEmpty)
        'provider_place_id': providerPlaceId!.trim(),
      if ((airportName ?? '').trim().isNotEmpty) 'airport_name': airportName!.trim(),
      if ((iataCode ?? '').trim().isNotEmpty) 'iata_code': iataCode!.trim().toUpperCase(),
      if ((countryCode ?? '').trim().isNotEmpty)
        'country_code': countryCode!.trim().toUpperCase(),
      if ((hotelName ?? '').trim().isNotEmpty) 'hotel_name': hotelName!.trim(),
      if ((venueName ?? '').trim().isNotEmpty) 'venue_name': venueName!.trim(),
      if ((eventName ?? '').trim().isNotEmpty) 'event_name': eventName!.trim(),
      if ((city ?? '').trim().isNotEmpty) 'city': city!.trim(),
      if ((postcode ?? '').trim().isNotEmpty) 'postcode': postcode!.trim(),
      'ratehawk_hotel_id': ratehawkHotelId,
      if (manual) 'manual': true,
    };
    return json;
  }

  static LimousineTransferEndpoint? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final kind = (map['kind'] ?? '').toString().trim();
    if (!LimousineTransferEndpointKind.all.contains(kind)) return null;
    double? number(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse('${value ?? ''}');
    }

    String? text(Object? value) {
      final out = (value ?? '').toString().trim();
      return out.isEmpty ? null : out;
    }

    return LimousineTransferEndpoint(
      kind: kind,
      displayName: text(map['display_name'] ?? map['displayName']) ?? '',
      formattedAddress:
          text(map['formatted_address'] ?? map['formattedAddress']) ?? '',
      latitude: number(map['latitude'] ?? map['lat']),
      longitude: number(map['longitude'] ?? map['lng'] ?? map['lon']),
      providerPlaceId: text(map['provider_place_id'] ?? map['providerPlaceId']),
      airportName: text(map['airport_name'] ?? map['airportName']),
      iataCode: text(map['iata_code'] ?? map['iataCode'])?.toUpperCase(),
      countryCode: text(map['country_code'] ?? map['countryCode'])?.toUpperCase(),
      hotelName: text(map['hotel_name'] ?? map['hotelName']),
      venueName: text(map['venue_name'] ?? map['venueName']),
      eventName: text(map['event_name'] ?? map['eventName']),
      city: text(map['city']),
      postcode: text(map['postcode'] ?? map['postal_code']),
      ratehawkHotelId: text(map['ratehawk_hotel_id'] ?? map['ratehawkHotelId']),
      manual: map['manual'] == true,
    );
  }
}

LimousineTransferEndpoint limousineEndpointFromAddress(LimousineAddressValue value) {
  return LimousineTransferEndpoint(
    kind: LimousineTransferEndpointKind.address,
    displayName: value.routeText,
    formattedAddress: value.routeText,
    latitude: value.lat,
    longitude: value.lon,
    providerPlaceId: value.placeId,
    manual: value.acceptance == LimousineAddressAcceptance.manualFallback,
  );
}

LimousineAddressValue limousineAddressValueFromEndpoint(
  LimousineTransferEndpoint endpoint,
) {
  return LimousineAddressValue(
    displayText: endpoint.routeText,
    canonicalLabel: endpoint.routeText,
    lat: endpoint.latitude,
    lon: endpoint.longitude,
    placeId: endpoint.providerPlaceId,
    acceptance: LimousineAddressAcceptance.selected,
  );
}

LimousineTransferEndpoint limousineEndpointFromAirport(AirportCatalogAirport airport) {
  return LimousineTransferEndpoint(
    kind: LimousineTransferEndpointKind.airport,
    displayName: airport.displayLabel,
    formattedAddress: airport.formattedAddress,
    latitude: airport.latitude,
    longitude: airport.longitude,
    airportName: airport.name,
    iataCode: airport.iata,
    countryCode: airport.countryCode,
    city: airport.city,
  );
}

LimousineTransferEndpoint limousineEndpointRetainAddressOnKindChange(
  LimousineTransferEndpoint current,
  String nextKind,
) {
  return LimousineTransferEndpoint(
    kind: nextKind,
    displayName: current.displayName,
    formattedAddress: current.formattedAddress,
    latitude: current.latitude,
    longitude: current.longitude,
    providerPlaceId: nextKind == LimousineTransferEndpointKind.address
        ? current.providerPlaceId
        : null,
    city: current.city,
    postcode: current.postcode,
    countryCode: current.countryCode,
    manual: nextKind != LimousineTransferEndpointKind.airport,
  );
}

({LimousineTransferEndpoint from, LimousineTransferEndpoint to})
    reverseLimousineEndpoints({
  required LimousineTransferEndpoint from,
  required LimousineTransferEndpoint to,
}) {
  return (from: to, to: from);
}

bool limousineAirportEndpointIsCanonical(
  LimousineTransferEndpoint endpoint, {
  List<AirportCatalogAirport>? airports,
}) {
  if (endpoint.kind != LimousineTransferEndpointKind.airport) return false;
  final iata = (endpoint.iataCode ?? '').trim();
  final country = (endpoint.countryCode ?? '').trim();
  final match = airportByIata(iata, countryCode: country, airports: airports);
  if (match == null) return false;
  final name = (endpoint.airportName ?? '').trim();
  if (name.isNotEmpty && name != match.name) {
    return match.iata == iata && match.countryCode == country;
  }
  return true;
}

bool limousineHotelEndpointIsUsable(LimousineTransferEndpoint endpoint) {
  if (endpoint.kind != LimousineTransferEndpointKind.hotel) return false;
  final name = (endpoint.hotelName ?? endpoint.displayName).trim();
  final address = endpoint.formattedAddress.trim();
  if (name.isEmpty || address.isEmpty) return false;
  if (endpoint.manual) return true;
  return endpoint.hasCoordinates;
}

bool limousineEventEndpointIsUsable(LimousineTransferEndpoint endpoint) {
  if (!LimousineTransferEndpointKind.isEvent(endpoint.kind)) return false;
  final name = (endpoint.venueName ?? endpoint.displayName).trim();
  final address = endpoint.formattedAddress.trim();
  if (name.isEmpty || address.isEmpty) return false;
  if (endpoint.manual) return true;
  return endpoint.hasCoordinates;
}

class LimousineItineraryEndpoints {
  const LimousineItineraryEndpoints({
    this.from,
    this.to,
    this.returnPickup,
    this.returnDestination,
    this.stops = const <LimousineTransferEndpoint>[],
    this.airportDirection = '',
    this.hotelDirection = '',
  });

  final LimousineTransferEndpoint? from;
  final LimousineTransferEndpoint? to;
  final LimousineTransferEndpoint? returnPickup;
  final LimousineTransferEndpoint? returnDestination;
  final List<LimousineTransferEndpoint> stops;
  final String airportDirection;
  final String hotelDirection;

  LimousineItineraryEndpoints copyWith({
    LimousineTransferEndpoint? from,
    LimousineTransferEndpoint? to,
    LimousineTransferEndpoint? returnPickup,
    LimousineTransferEndpoint? returnDestination,
    List<LimousineTransferEndpoint>? stops,
    String? airportDirection,
    String? hotelDirection,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return LimousineItineraryEndpoints(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      returnPickup: returnPickup ?? this.returnPickup,
      returnDestination: returnDestination ?? this.returnDestination,
      stops: stops ?? this.stops,
      airportDirection: airportDirection ?? this.airportDirection,
      hotelDirection: hotelDirection ?? this.hotelDirection,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (from != null && !from!.isEmpty) 'from_endpoint': from!.toJson(),
      if (to != null && !to!.isEmpty) 'to_endpoint': to!.toJson(),
      if (returnPickup != null && !returnPickup!.isEmpty)
        'return_pickup_endpoint': returnPickup!.toJson(),
      if (returnDestination != null && !returnDestination!.isEmpty)
        'return_destination_endpoint': returnDestination!.toJson(),
      if (stops.isNotEmpty)
        'stop_endpoints': stops
            .where((stop) => !stop.isEmpty)
            .map((stop) => stop.toJson())
            .toList(growable: false),
      if (airportDirection.trim().isNotEmpty)
        'airport_direction': airportDirection.trim(),
      if (hotelDirection.trim().isNotEmpty)
        'hotel_direction': hotelDirection.trim(),
    };
  }
}

LimousineItineraryEndpoints applyAirportDirection({
  required String direction,
  required AirportCatalogAirport airport,
  LimousineTransferEndpoint? other,
  LimousineItineraryEndpoints current = const LimousineItineraryEndpoints(),
}) {
  final airportEndpoint = limousineEndpointFromAirport(airport);
  final toAirport = direction == 'to_airport';
  return current.copyWith(
    airportDirection: toAirport ? 'to_airport' : 'from_airport',
    from: toAirport ? other : airportEndpoint,
    to: toAirport ? airportEndpoint : other,
    clearFrom: toAirport && other == null,
    clearTo: !toAirport && other == null,
  );
}

LimousineItineraryEndpoints applyHotelDirection({
  required String direction,
  required LimousineTransferEndpoint hotel,
  LimousineTransferEndpoint? other,
  LimousineItineraryEndpoints current = const LimousineItineraryEndpoints(),
}) {
  final toHotel = direction != 'from_hotel';
  return current.copyWith(
    hotelDirection: toHotel ? 'to_hotel' : 'from_hotel',
    from: toHotel ? other : hotel,
    to: toHotel ? hotel : other,
    clearFrom: toHotel && other == null,
    clearTo: !toHotel && other == null,
  );
}

LimousineItineraryEndpoints clearIncompatibleAirportOnCountryChange({
  required LimousineItineraryEndpoints current,
  required String countryCode,
  List<AirportCatalogAirport>? airports,
}) {
  LimousineTransferEndpoint? keep(LimousineTransferEndpoint? endpoint) {
    if (endpoint == null) return null;
    if (endpoint.kind != LimousineTransferEndpointKind.airport) return endpoint;
    if ((endpoint.countryCode ?? '').toUpperCase() == countryCode.toUpperCase() &&
        limousineAirportEndpointIsCanonical(endpoint, airports: airports)) {
      return endpoint;
    }
    return limousineEndpointRetainAddressOnKindChange(
      endpoint,
      LimousineTransferEndpointKind.address,
    );
  }

  return current.copyWith(
    from: keep(current.from),
    to: keep(current.to),
    returnPickup: keep(current.returnPickup),
    returnDestination: keep(current.returnDestination),
  );
}
