import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  attachLimousineItineraryEndpoints,
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
