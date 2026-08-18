// P2D4C1F — unscoped limousine nearby test-preview projection.
// Run: node --test workers/booking/modules/limousine_p2d4c1f_discovery_preview.test.mjs
//
// No deploy, no secret upload, no allowlist/gate change.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  limousineBookGateEnabled,
} from "./limousine_booking.mjs";
import {
  limousineManualQuoteGateEnabled,
} from "./limousine_manual_quote.mjs";
import {
  limousineQuoteGateEnabled,
} from "./limousine_pricing_resolver.mjs";
import { isTrustedLimousineTestCompany } from "./limousine_test_company_allowlist.mjs";
import {
  LIMOUSINE_DISCOVERY_FORBIDDEN_KEYS,
  LIMOUSINE_DISCOVERY_LISTING_MODE_TEST_PREVIEW,
  LIMOUSINE_DISCOVERY_NEARBY_LOADERS,
  LIMOUSINE_DISCOVERY_NEARBY_MAX_KV_GETS,
  buildLimousineNearbyCardProjection,
  filterLimousineDiscoveryPartners,
  hasPublishedLimousineOfferOrQuoteRequired,
  isLimousineDiscoveryListable,
  limousineDiscoveryPayloadHasPrivateFields,
  limousineNearbyAllowsUnscopedListing,
} from "./limousine_discovery_preview.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");

const ALLOWED = "fluxidi_internal_limo_a";
const OTHER = "fluxidi_internal_limo_b";

function limousineVehicle(overrides = {}) {
  return {
    name: "Fleet One",
    service_category: "limousine",
    service_class: "executive_sedan",
    is_active: true,
    photo_url: "https://cdn.example/v1.jpg",
    passenger_capacity: 3,
    luggage_capacity: 2,
    ...overrides,
  };
}

function publishedOffer(overrides = {}) {
  return {
    offer_id: "off_1",
    enabled: true,
    published: true,
    price_presentation: "from_price",
    display_amount_cents: 45000,
    currency: "EUR",
    ...overrides,
  };
}

function eligibleProfile(overrides = {}) {
  return {
    partner_id: "pub_cmp_a",
    company_name: "Maison Noire",
    company_id: ALLOWED,
    is_active: true,
    bookable: true,
    profile_enabled: true,
    published_at: "2026-08-17T10:00:00Z",
    subscription_status: "active",
    limousine_entitled: true,
    services: ["limousine"],
    coverage: { city: "Gent" },
    trust: { verified_partner: true },
    vehicles: [limousineVehicle()],
    limousine_offers: [publishedOffer()],
    ...overrides,
  };
}

test("unscoped nearby is allowed only for service=limousine without geo or postcode", () => {
  assert.equal(limousineNearbyAllowsUnscopedListing({ service: "limousine" }), true);
  assert.equal(
    limousineNearbyAllowsUnscopedListing({ service: "limousine", postcode: "9000" }),
    false,
  );
  assert.equal(
    limousineNearbyAllowsUnscopedListing({ service: "limousine", lat: 51.05, lng: 3.72 }),
    false,
  );
  assert.equal(limousineNearbyAllowsUnscopedListing({ service: "taxi" }), false);
  assert.equal(limousineNearbyAllowsUnscopedListing({}), false);
});

test("allowlisted published limousine is listable; taxi, airport, draft and others are not", () => {
  const allowlisted = (id) => isTrustedLimousineTestCompany(
    { LIMOUSINE_TEST_COMPANY_ALLOWLIST: ALLOWED },
    id,
  );
  const ok = eligibleProfile();
  assert.equal(isLimousineDiscoveryListable(ok), true);
  assert.equal(hasPublishedLimousineOfferOrQuoteRequired(ok), true);

  const taxiOnly = eligibleProfile({
    company_id: ALLOWED,
    services: ["taxi"],
    limousine_entitled: false,
    vehicles: [{ name: "Stretch Limousine", service_category: "taxi", is_active: true }],
    limousine_offers: [],
  });
  const airportOnly = eligibleProfile({
    company_id: ALLOWED,
    services: ["airport"],
    limousine_entitled: false,
    vehicles: [{ name: "Van", service_category: "airport", is_active: true }],
  });
  const draft = eligibleProfile({
    limousine_offers: [publishedOffer({ enabled: false, published: false, draft: true })],
  });
  const nameOnly = eligibleProfile({
    limousine_entitled: false,
    vehicles: [{ name: "Mercedes Limousine", brand: "Mercedes", category: "limousine" }],
    limousine_offers: [],
  });
  const otherCompany = eligibleProfile({ company_id: OTHER });

  const filtered = filterLimousineDiscoveryPartners(
    [ok, taxiOnly, airportOnly, draft, nameOnly, otherCompany],
    { allowlisted },
  );
  assert.deepEqual(
    filtered.map((row) => row.partner_id),
    ["pub_cmp_a"],
  );
});

test("card projection is server-authoritative and omits private fields", () => {
  const card = buildLimousineNearbyCardProjection(
    eligibleProfile({
      operating_base: { lat: 51.05, lng: 3.72 },
      tenant_id: "ten_secret",
      company_id: ALLOWED,
    }),
  );
  assert.equal(card.limousine_available, true);
  assert.equal(card.public_city, "Gent");
  assert.equal(card.trust.verified_partner, true);
  assert.equal(card.limousine_vehicles.length, 1);
  assert.equal(card.limousine_vehicles[0].service_category, "limousine");
  assert.equal(card.limousine_vehicles[0].service_class_id, "executive_sedan");
  assert.equal(card.limousine_price_presentation, "from_price");
  assert.equal(card.display_amount_cents, 45000);
  assert.equal(card.currency, "EUR");
  assert.equal(card.test_preview, true);
  assert.equal(card.distance_km, undefined);
  assert.equal(limousineDiscoveryPayloadHasPrivateFields(card), false);
  for (const key of LIMOUSINE_DISCOVERY_FORBIDDEN_KEYS) {
    assert.equal(Object.prototype.hasOwnProperty.call(card, key), false, key);
  }
});

test("quote-required cards omit fabricated amounts; drafts stay invisible", () => {
  const quote = buildLimousineNearbyCardProjection(
    eligibleProfile({
      limousine_offers: [publishedOffer({ price_presentation: "quote_required" })],
    }),
  );
  assert.equal(quote.limousine_price_presentation, "quote_required");
  assert.equal(quote.display_amount_cents, undefined);

  const draft = buildLimousineNearbyCardProjection(
    eligibleProfile({
      limousine_offers: [publishedOffer({ published: false, enabled: false })],
    }),
  );
  assert.deepEqual(draft, {});
});

test("global quote/book/manual-quote gates remain OFF and wrangler stays empty", () => {
  assert.equal(limousineQuoteGateEnabled("0"), false);
  assert.equal(limousineBookGateEnabled("0"), false);
  assert.equal(limousineManualQuoteGateEnabled("0"), false);
  assert.equal(limousineQuoteGateEnabled(undefined), false);
  assert.equal(limousineBookGateEnabled(undefined), false);
  assert.equal(limousineManualQuoteGateEnabled(undefined), false);
  assert.ok(!wrangler.includes("LIMOUSINE_TEST_COMPANY_ALLOWLIST"));
  assert.ok(!wrangler.includes("LIMOUSINE_QUOTE_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_BOOK_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_MANUAL_QUOTE_ENABLED"));
});

test("worker nearby reuses three loaders, honors unscoped limousine, and stays bounded", () => {
  assert.equal(LIMOUSINE_DISCOVERY_NEARBY_MAX_KV_GETS, 6);
  for (const loader of LIMOUSINE_DISCOVERY_NEARBY_LOADERS) {
    assert.equal((worker.match(new RegExp(loader, "g")) || []).length >= 1, true, loader);
  }
  const nearbyFn = worker.slice(
    worker.indexOf("async function listNearbyPartners"),
    worker.indexOf("function supportedPostcodesIncludes"),
  );
  assert.equal(nearbyFn.includes("_loadPartnerDirectory(env)"), true);
  assert.equal(nearbyFn.includes("_loadPublicPartnerProfiles(env)"), true);
  assert.equal(nearbyFn.includes("_loadPartnerBookingRoutes(env)"), true);
  assert.equal(nearbyFn.includes("BOOKING_KV.get("), false);
  assert.equal(nearbyFn.includes(".list("), false);
  assert.equal(nearbyFn.includes("operating_base"), false);
  assert.equal(nearbyFn.includes("_buildLimousineNearbyCardProjection"), true);
  assert.equal(nearbyFn.includes("_isLimousineDiscoveryListable"), true);
  assert.equal(nearbyFn.includes("_limousineNearbyAllowsUnscopedListing"), true);
  assert.equal(nearbyFn.includes("if (unscopedLimousine)"), true);
  assert.equal(nearbyFn.includes("distanceKm: null"), true);

  const route = worker.slice(
    worker.indexOf('url.pathname === "/partners/nearby"'),
    worker.indexOf('url.pathname === "/partners/profile"'),
  );
  assert.equal(route.includes("_limousineNearbyAllowsUnscopedListing"), true);
  assert.equal(route.includes("postcode or lat/lng is required"), true);
  assert.equal(route.includes("limousine_listing_mode"), true);
  assert.equal(route.includes("_LIMOUSINE_DISCOVERY_LISTING_MODE_TEST_PREVIEW"), true);
  assert.equal(LIMOUSINE_DISCOVERY_LISTING_MODE_TEST_PREVIEW, "test_preview");
  assert.equal(nearbyFn.includes(".list("), false);
});
