// Additive typed itinerary endpoints for limousine quote/book.
// Does not introduce a second catalog, RateHawk client, or booking aggregate.

const KINDS = Object.freeze(["address", "airport", "hotel", "event", "venue"]);

export function limousineEndpointIsEventKind(kind) {
  return kind === "event" || kind === "venue";
}

function asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function safeText(value, max = 240) {
  return String(value ?? "").trim().slice(0, max);
}

function toFinite(value) {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

function endpointFingerprint(endpoint) {
  const e = asObject(endpoint);
  return [
    safeText(e.kind, 16),
    safeText(e.display_name, 160).toLowerCase(),
    safeText(e.formatted_address, 240).toLowerCase(),
    safeText(e.iata_code, 8).toUpperCase(),
    safeText(e.country_code, 8).toUpperCase(),
    safeText(e.hotel_name, 120).toLowerCase(),
    safeText(e.venue_name, 160).toLowerCase(),
    safeText(e.event_name, 160).toLowerCase(),
    safeText(e.provider_place_id, 80),
    e.manual === true ? "manual" : "live",
    e.latitude ?? "",
    e.longitude ?? "",
  ].join("|");
}

export function sanitizeLimousineTransferEndpoint(raw) {
  const src = asObject(raw);
  const kind = safeText(src.kind, 16);
  if (!KINDS.includes(kind)) return null;
  const displayName = safeText(src.display_name ?? src.displayName, 240);
  const formattedAddress = safeText(
    src.formatted_address ?? src.formattedAddress,
    320,
  );
  if (!displayName && !formattedAddress) return null;
  const latitude = toFinite(src.latitude ?? src.lat);
  const longitude = toFinite(src.longitude ?? src.lng ?? src.lon);
  const endpoint = {
    kind,
    display_name: displayName || formattedAddress,
    formatted_address: formattedAddress || displayName,
    latitude,
    longitude,
    provider_place_id: safeText(src.provider_place_id ?? src.providerPlaceId, 120) || null,
    country_code: safeText(src.country_code ?? src.countryCode, 8).toUpperCase() || null,
    city: safeText(src.city, 80) || null,
    postcode: safeText(src.postcode ?? src.postal_code, 16) || null,
    manual: src.manual === true,
  };

  if (kind === "airport") {
    const iata = safeText(src.iata_code ?? src.iataCode, 8).toUpperCase();
    const country = safeText(src.country_code ?? src.countryCode, 8).toUpperCase();
    const airportName = safeText(src.airport_name ?? src.airportName, 160);
    if (!/^[A-Z]{3}$/.test(iata) || !/^[A-Z]{2}$/.test(country)) return null;
    endpoint.airport_name = airportName || displayName;
    endpoint.iata_code = iata;
    endpoint.country_code = country;
    return endpoint;
  }

  if (kind === "hotel") {
    const hotelName = safeText(src.hotel_name ?? src.hotelName, 160) || displayName;
    const address = formattedAddress || displayName;
    if (!hotelName || !address) return null;
    if (src.manual !== true && (latitude == null || longitude == null)) return null;
    endpoint.hotel_name = hotelName;
    endpoint.ratehawk_hotel_id =
      safeText(src.ratehawk_hotel_id ?? src.ratehawkHotelId, 64) || null;
    return endpoint;
  }

  if (limousineEndpointIsEventKind(kind)) {
    const venueName =
      safeText(src.venue_name ?? src.venueName, 160) || displayName;
    const address = formattedAddress || displayName;
    if (!venueName || !address) return null;
    if (src.manual !== true && (latitude == null || longitude == null)) return null;
    endpoint.venue_name = venueName;
    endpoint.event_name = safeText(src.event_name ?? src.eventName, 160) || null;
    return endpoint;
  }

  return endpoint;
}

export function sanitizeLimousineItineraryEndpoints(input) {
  const src = asObject(input);
  const from = sanitizeLimousineTransferEndpoint(src.from_endpoint ?? src.fromEndpoint);
  const to = sanitizeLimousineTransferEndpoint(src.to_endpoint ?? src.toEndpoint);
  const returnPickup = sanitizeLimousineTransferEndpoint(
    src.return_pickup_endpoint ?? src.returnPickupEndpoint,
  );
  const returnDestination = sanitizeLimousineTransferEndpoint(
    src.return_destination_endpoint ?? src.returnDestinationEndpoint,
  );
  const stops = Array.isArray(src.stop_endpoints ?? src.stopEndpoints)
    ? (src.stop_endpoints ?? src.stopEndpoints)
        .map((item) => sanitizeLimousineTransferEndpoint(item))
        .filter(Boolean)
        .slice(0, 8)
    : [];
  return {
    from_endpoint: from,
    to_endpoint: to,
    return_pickup_endpoint: returnPickup,
    return_destination_endpoint: returnDestination,
    stop_endpoints: stops,
    airport_direction: safeText(src.airport_direction ?? src.airportDirection, 24),
    hotel_direction: safeText(src.hotel_direction ?? src.hotelDirection, 24),
    itinerary_endpoint_fingerprint: [
      endpointFingerprint(from),
      endpointFingerprint(to),
      endpointFingerprint(returnPickup),
      endpointFingerprint(returnDestination),
    ].join("~"),
  };
}

export function deriveLimousineAirportPricingFacts(input) {
  const src = asObject(input);
  const itinerary = sanitizeLimousineItineraryEndpoints(src);
  const from = itinerary.from_endpoint;
  const to = itinerary.to_endpoint;
  let airportIata = safeText(src.airport_iata ?? src.airportIata, 8).toUpperCase();
  let direction = safeText(
    src.airport_direction ?? src.direction ?? itinerary.airport_direction,
    24,
  );
  if (to?.kind === "airport" && to.iata_code) {
    if (!airportIata) airportIata = String(to.iata_code).toUpperCase();
    if (!direction) direction = "to_airport";
  } else if (from?.kind === "airport" && from.iata_code) {
    if (!airportIata) airportIata = String(from.iata_code).toUpperCase();
    if (!direction) direction = "from_airport";
  }
  return {
    airport_iata: airportIata,
    direction,
    itinerary,
  };
}

export function attachLimousineItineraryEndpoints(target, input) {
  const next = { ...asObject(target) };
  const itinerary = sanitizeLimousineItineraryEndpoints(input);
  if (itinerary.from_endpoint) next.from_endpoint = itinerary.from_endpoint;
  if (itinerary.to_endpoint) next.to_endpoint = itinerary.to_endpoint;
  if (itinerary.return_pickup_endpoint) {
    next.return_pickup_endpoint = itinerary.return_pickup_endpoint;
  }
  if (itinerary.return_destination_endpoint) {
    next.return_destination_endpoint = itinerary.return_destination_endpoint;
  }
  if (itinerary.stop_endpoints.length) next.stop_endpoints = itinerary.stop_endpoints;
  if (itinerary.airport_direction) next.airport_direction = itinerary.airport_direction;
  if (itinerary.hotel_direction) next.hotel_direction = itinerary.hotel_direction;
  next.itinerary_endpoint_fingerprint = itinerary.itinerary_endpoint_fingerprint;
  return next;
}

export function limousineItineraryConflictsWithJourney(journeyType, itinerary) {
  const journey = String(journeyType ?? "").trim();
  const src = asObject(itinerary);
  if (journey === "event_transfer" && src.to_endpoint) {
    return !limousineEndpointIsEventKind(src.to_endpoint.kind);
  }
  return false;
}
