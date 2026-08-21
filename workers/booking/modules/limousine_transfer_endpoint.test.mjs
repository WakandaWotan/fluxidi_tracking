import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  attachLimousineItineraryEndpoints,
  deriveLimousineAirportPricingFacts,
  sanitizeLimousineTransferEndpoint,
} from "./limousine_transfer_endpoint.mjs";
import {
  itineraryFingerprint,
  limousineQuoteRequestKey,
  validateLimousineQuoteRequest,
} from "./limousine_manual_quote.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

function quoteOffer() {
  return {
    offer_id: "off_1",
    enabled: true,
    published: true,
    service_class_id: "executive_sedan",
    vehicle_id: "",
    paid_extras: [],
    source_revision: 7,
    price_presentation: "quote_required",
  };
}

function customerRequest(overrides = {}) {
  return {
    offer_id: "off_1",
    journey_type: "airport_transfer",
    from: "Korenmarkt 1, Gent",
    to: "Brussels Airport, Zaventem",
    scheduled_pickup_iso: "2026-09-01T10:00:00Z",
    airport_direction: "to_airport",
    from_endpoint: {
      kind: "address",
      display_name: "Korenmarkt 1, Gent",
      formatted_address: "Korenmarkt 1, Gent",
      latitude: 51.05,
      longitude: 3.72,
      provider_place_id: "address.1",
    },
    to_endpoint: {
      kind: "airport",
      display_name: "Brussels Airport (BRU)",
      formatted_address: "Brussels Airport, Zaventem, Belgium",
      airport_name: "Brussels Airport",
      iata_code: "BRU",
      country_code: "BE",
      latitude: 50.901,
      longitude: 4.484,
    },
    ...overrides,
  };
}

test("typed airport and hotel endpoints sanitize without RateHawk", function () {
  const airport = sanitizeLimousineTransferEndpoint({
    kind: "airport",
    display_name: "Brussels Airport (BRU)",
    formatted_address: "Brussels Airport",
    airport_name: "Brussels Airport",
    iata_code: "bru",
    country_code: "be",
  });
  assert.equal(airport.kind, "airport");
  assert.equal(airport.iata_code, "BRU");
  assert.equal(airport.country_code, "BE");

  const hotel = sanitizeLimousineTransferEndpoint({
    kind: "hotel",
    display_name: "Hotel de Ville",
    formatted_address: "Botermarkt 1, 9000 Gent",
    hotel_name: "Hotel de Ville",
    latitude: 51.05,
    longitude: 3.72,
    provider_place_id: "poi.hotel.1",
    ratehawk_hotel_id: null,
  });
  assert.equal(hotel.kind, "hotel");
  assert.equal(hotel.hotel_name, "Hotel de Ville");
  assert.equal(hotel.ratehawk_hotel_id, null);

  const manual = sanitizeLimousineTransferEndpoint({
    kind: "hotel",
    display_name: "Korenmarkt 1, Gent",
    formatted_address: "Korenmarkt 1, Gent",
    hotel_name: "Korenmarkt 1, Gent",
    manual: true,
  });
  assert.equal(manual.manual, true);

  assert.equal(
    sanitizeLimousineTransferEndpoint({
      kind: "hotel",
      display_name: "Incomplete",
      formatted_address: "Incomplete",
    }),
    null,
  );
});

test("airport pricing facts come from typed endpoints when top-level IATA is absent", () => {
  const facts = deriveLimousineAirportPricingFacts({
    from_endpoint: {
      kind: "address",
      display_name: "Korenmarkt 1, Gent",
      formatted_address: "Korenmarkt 1, Gent",
      latitude: 51.05,
      longitude: 3.72,
    },
    to_endpoint: {
      kind: "airport",
      display_name: "Brussels Airport (BRU)",
      formatted_address: "Brussels Airport",
      airport_name: "Brussels Airport",
      iata_code: "bru",
      country_code: "be",
      latitude: 50.901,
      longitude: 4.484,
    },
  });
  assert.equal(facts.airport_iata, "BRU");
  assert.equal(facts.direction, "to_airport");
});

test("quote and book snapshots keep immutable typed itinerary", function () {
  const a = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: quoteOffer(),
    gateEnabled: true,
  });
  const b = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: quoteOffer(),
    gateEnabled: true,
  });
  assert.equal(a.ok, true);
  assert.equal(a.request.service_type, "limousine");
  assert.equal(a.request.to_endpoint.iata_code, "BRU");
  assert.equal(a.request.from_endpoint.kind, "address");
  assert.equal(a.snapshot.to_endpoint.iata_code, "BRU");
  assert.equal(a.request.itinerary_fingerprint, b.request.itinerary_fingerprint);
  assert.equal(
    limousineQuoteRequestKey({
      tenantId: "t1",
      companyId: "c1",
      customerRef: "cust@x",
      request: a.request,
    }),
    limousineQuoteRequestKey({
      tenantId: "t1",
      companyId: "c1",
      customerRef: "cust@x",
      request: b.request,
    }),
  );
  const laterProviderChange = validateLimousineQuoteRequest(
    customerRequest({
      to_endpoint: {
        ...customerRequest().to_endpoint,
        formatted_address: "Later rewritten airport label",
      },
    }),
    { eligible: true, offer: quoteOffer(), gateEnabled: true },
  );
  assert.notEqual(
    a.request.itinerary_endpoint_fingerprint,
    laterProviderChange.request.itinerary_endpoint_fingerprint,
  );
  assert.equal(
    a.request.to_endpoint.formatted_address.includes("Later rewritten"),
    false,
  );
});

test("event and venue endpoints sanitize and reject incomplete live venues", function () {
  const live = sanitizeLimousineTransferEndpoint({
    kind: "event",
    display_name: "Flanders Expo",
    formatted_address: "Maaltekouter 1, 9051 Gent",
    venue_name: "Flanders Expo",
    event_name: "Wedding Expo",
    latitude: 51.026,
    longitude: 3.69,
    provider_place_id: "poi.venue.1",
    city: "Gent",
    postcode: "9051",
    country_code: "be",
  });
  assert.equal(live.kind, "event");
  assert.equal(live.venue_name, "Flanders Expo");
  assert.equal(live.event_name, "Wedding Expo");
  assert.equal(live.country_code, "BE");
  assert.equal(live.manual, false);

  const venueAlias = sanitizeLimousineTransferEndpoint({
    kind: "venue",
    display_name: "Lotto Arena",
    formatted_address: "Schijnpoortweg 119, Antwerpen",
    venue_name: "Lotto Arena",
    latitude: 51.23,
    longitude: 4.44,
  });
  assert.equal(venueAlias.kind, "venue");

  const manual = sanitizeLimousineTransferEndpoint({
    kind: "event",
    display_name: "Tijdelijke festivalweide, Oostende",
    formatted_address: "Tijdelijke festivalweide, Oostende",
    venue_name: "Tijdelijke festivalweide, Oostende",
    manual: true,
  });
  assert.equal(manual.manual, true);

  assert.equal(
    sanitizeLimousineTransferEndpoint({
      kind: "event",
      display_name: "Incomplete",
      formatted_address: "Incomplete",
    }),
    null,
  );
});

test("event quote snapshots keep venue data and reject a mismatched destination", function () {
  const eventOffer = {
    ...quoteOffer(),
    journey_types: ["event_transfer"],
  };
  const accepted = validateLimousineQuoteRequest(
    customerRequest({
      journey_type: "event_transfer",
      to: "Flanders Expo, Gent",
      from_endpoint: customerRequest().from_endpoint,
      to_endpoint: {
        kind: "event",
        display_name: "Flanders Expo",
        formatted_address: "Maaltekouter 1, 9051 Gent",
        venue_name: "Flanders Expo",
        event_name: "Wedding Expo",
        latitude: 51.026,
        longitude: 3.69,
        provider_place_id: "poi.venue.1",
        city: "Gent",
        postcode: "9051",
        country_code: "BE",
      },
      return_pickup_endpoint: {
        kind: "event",
        display_name: "Flanders Expo",
        formatted_address: "Maaltekouter 1, 9051 Gent",
        venue_name: "Flanders Expo",
        latitude: 51.026,
        longitude: 3.69,
      },
      return_destination_endpoint: customerRequest().from_endpoint,
    }),
    { eligible: true, offer: eventOffer, gateEnabled: true },
  );
  assert.equal(accepted.ok, true);
  assert.equal(accepted.request.to_endpoint.kind, "event");
  assert.equal(accepted.request.to_endpoint.venue_name, "Flanders Expo");
  assert.equal(accepted.request.to_endpoint.event_name, "Wedding Expo");
  assert.equal(accepted.snapshot.to_endpoint.kind, "event");
  assert.equal(accepted.request.return_pickup_endpoint.kind, "event");
  assert.equal(accepted.request.return_destination_endpoint.kind, "address");

  const mismatched = validateLimousineQuoteRequest(
    customerRequest({
      journey_type: "event_transfer",
      to: "Brussels Airport",
    }),
    { eligible: true, offer: eventOffer, gateEnabled: true },
  );
  assert.equal(mismatched.ok, false);
  assert.equal(mismatched.field, "to_endpoint");

  const forbiddenType = validateLimousineQuoteRequest(
    customerRequest({ journey_type: "airport_transfer" }),
    { eligible: true, offer: eventOffer, gateEnabled: true },
  );
  assert.equal(forbiddenType.ok, false);
  assert.equal(forbiddenType.reason, "journey_type_not_allowed");
});

test("client claims stay rejected and no RateHawk datastore is added", function () {
  const rejected = validateLimousineQuoteRequest(
    customerRequest({ total_incl_vat_cents: 99000, company_id: "evil" }),
    { eligible: true, offer: quoteOffer(), gateEnabled: true },
  );
  assert.equal(rejected.ok, false);
  const source = readFileSync(join(__dirname, "limousine_transfer_endpoint.mjs"), "utf8");
  assert.equal(source.includes("RATEHAWK_"), false);
  assert.equal(source.includes("api.ratehawk"), false);
  assert.equal(source.includes("BOOKING_KV"), false);
  assert.equal(source.includes("CREATE TABLE"), false);
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  assert.match(worker, /LIMOUSINE_SERVICE_TYPE/);
  const attached = attachLimousineItineraryEndpoints(
    { from: "A", to: "B" },
    customerRequest(),
  );
  assert.equal(attached.to_endpoint.iata_code, "BRU");
  assert.ok(itineraryFingerprint(attached).startsWith("limi_"));
});
