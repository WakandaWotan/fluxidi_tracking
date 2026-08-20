// P2D4C1G — limousine discovery lists every eligible allowlisted company and
// ranks by customer distance. Run:
// node --test workers/booking/modules/limousine_p2d4c1g_discovery_rank.test.mjs
//
// Fixtures only. No live company, no secret, no gate or allowlist change.

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
  compareLimousineNearbyRank,
  limousineNearbyDistanceKm,
  limousineNearbyIgnoresCoverageFilter,
  limousinePostcodeCentroid,
  publicLimousineDistanceFields,
  rankLimousineNearbyEntries,
  resolveLimousineCompanyPoint,
  resolveLimousineSearchOrigin,
} from "./limousine_distance_rank.mjs";
import {
  LIMOUSINE_DISCOVERY_FORBIDDEN_KEYS,
  buildLimousineNearbyCardProjection,
  filterLimousineDiscoveryPartners,
  isLimousineDiscoveryListable,
  limousineDiscoveryPayloadHasPrivateFields,
} from "./limousine_discovery_preview.mjs";
import {
  evaluateLimousineProviderEligibility,
} from "./limousine_provider_eligibility.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");

const ALLOWED = "fluxidi_internal_limo_a";
const OTHER = "fluxidi_internal_limo_b";

function vehicle(overrides = {}) {
  return {
    service_category: "limousine",
    service_class: "executive_sedan",
    is_active: true,
    photo_url: "https://cdn.example/v1.jpg",
    ...overrides,
  };
}

function offer(overrides = {}) {
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
    bookable: false,
    profile_enabled: true,
    published_at: "2026-08-17T10:00:00Z",
    subscription_status: "active",
    limousine_entitled: true,
    services: ["limousine"],
    coverage: { city: "Maarkedal", primary_postcode: "9688" },
    vehicles: [vehicle()],
    limousine_offers: [offer()],
    ...overrides,
  };
}

test("unscoped listing keeps every eligible allowlisted company", () => {
  const allowlisted = (id) => isTrustedLimousineTestCompany(
    { LIMOUSINE_TEST_COMPANY_ALLOWLIST: ALLOWED },
    id,
  );
  const near = eligibleProfile();
  const far = eligibleProfile({
    partner_id: "pub_cmp_far",
    company_name: "Far Coach",
    coverage: { city: "Brussel", primary_postcode: "1000" },
  });
  const kept = filterLimousineDiscoveryPartners([near, far], { allowlisted });
  assert.deepEqual(
    kept.map((row) => row.partner_id).sort(),
    ["pub_cmp_a", "pub_cmp_far"],
  );
});

test("postcode 9688 does not drop a valid far company", () => {
  const origin = resolveLimousineSearchOrigin({ postcode: "9688" });
  assert.deepEqual(origin, limousinePostcodeCentroid("9688"));
  const near = {
    partnerId: "pub_cmp_a",
    idx: 0,
    distanceKm: limousineNearbyDistanceKm({
      postcode: "9688",
      primaryPostcode: "9688",
    }),
  };
  const far = {
    partnerId: "pub_cmp_far",
    idx: 1,
    distanceKm: limousineNearbyDistanceKm({
      postcode: "9688",
      primaryPostcode: "1000",
    }),
  };
  const ranked = rankLimousineNearbyEntries([far, near]);
  assert.equal(ranked.length, 2);
  assert.equal(ranked[0].partnerId, "pub_cmp_a");
  assert.equal(ranked[1].partnerId, "pub_cmp_far");
  assert.ok(ranked[0].distanceKm < ranked[1].distanceKm);
});

test("two fixtures rank nearest then farthest; far company stays", () => {
  const ranked = rankLimousineNearbyEntries([
    { partnerId: "far", idx: 0, distanceKm: 84.2 },
    { partnerId: "near", idx: 1, distanceKm: 3.1 },
  ]);
  assert.deepEqual(ranked.map((row) => row.partnerId), ["near", "far"]);
});

test("missing distance sorts after calculable distances", () => {
  const ranked = rankLimousineNearbyEntries([
    { partnerId: "unknown", idx: 0, distanceKm: null },
    { partnerId: "near", idx: 1, distanceKm: 4 },
    { partnerId: "far", idx: 2, distanceKm: 40 },
  ]);
  assert.deepEqual(
    ranked.map((row) => row.partnerId),
    ["near", "far", "unknown"],
  );
});

test("equal or missing distance uses deterministic partner_id tie-break", () => {
  const ranked = rankLimousineNearbyEntries([
    { partnerId: "zeta", idx: 9, distanceKm: 12 },
    { partnerId: "alpha", idx: 1, distanceKm: 12 },
    { partnerId: "missing_b", idx: 3, distanceKm: null },
    { partnerId: "missing_a", idx: 2, distanceKm: null },
  ]);
  assert.deepEqual(
    ranked.map((row) => row.partnerId),
    ["alpha", "zeta", "missing_a", "missing_b"],
  );
});

test("transaction gates off still leave discovery visible", () => {
  assert.equal(limousineQuoteGateEnabled("0"), false);
  assert.equal(limousineBookGateEnabled("0"), false);
  assert.equal(limousineManualQuoteGateEnabled("0"), false);
  const profile = eligibleProfile({ bookable: false });
  assert.equal(evaluateLimousineProviderEligibility(profile).eligible, true);
  assert.equal(isLimousineDiscoveryListable(profile), true);
  const card = buildLimousineNearbyCardProjection(profile);
  assert.equal(card.limousine_available, true);
});

test("non-allowlisted companies stay hidden", () => {
  const allowlisted = (id) => isTrustedLimousineTestCompany(
    { LIMOUSINE_TEST_COMPANY_ALLOWLIST: ALLOWED },
    id,
  );
  const hidden = filterLimousineDiscoveryPartners(
    [eligibleProfile({ company_id: OTHER, partner_id: "other" })],
    { allowlisted },
  );
  assert.deepEqual(hidden, []);
});

test("taxi and airport never become a limousine fallback", () => {
  const allowlisted = (id) => isTrustedLimousineTestCompany(
    { LIMOUSINE_TEST_COMPANY_ALLOWLIST: ALLOWED },
    id,
  );
  const taxi = eligibleProfile({
    partner_id: "taxi",
    services: ["taxi"],
    limousine_entitled: false,
    vehicles: [{ service_category: "taxi", is_active: true }],
    limousine_offers: [],
  });
  const airport = eligibleProfile({
    partner_id: "air",
    services: ["airport"],
    limousine_entitled: false,
    vehicles: [{ service_category: "airport", is_active: true }],
  });
  assert.equal(isLimousineDiscoveryListable(taxi), false);
  assert.equal(isLimousineDiscoveryListable(airport), false);
  assert.deepEqual(
    filterLimousineDiscoveryPartners([taxi, airport], { allowlisted }),
    [],
  );
  assert.equal(limousineNearbyIgnoresCoverageFilter("taxi"), false);
  assert.equal(limousineNearbyIgnoresCoverageFilter("airport"), false);
  assert.equal(limousineNearbyIgnoresCoverageFilter("limousine"), true);
});

test("public ranking payload never includes private source coordinates", () => {
  const card = buildLimousineNearbyCardProjection(
    eligibleProfile({
      operating_base: { lat: 50.796, lng: 3.621 },
      tenant_id: "ten_secret",
      company_id: ALLOWED,
      license_plate: "1-ABC-234",
      vin: "VINSECRET",
      driver_id: "drv_1",
    }),
  );
  const ranked = {
    ...card,
    ...publicLimousineDistanceFields(12.4),
  };
  assert.equal(ranked.distance_km, 12.4);
  assert.equal(ranked.operating_base, undefined);
  assert.equal(limousineDiscoveryPayloadHasPrivateFields(ranked), false);
  for (const key of LIMOUSINE_DISCOVERY_FORBIDDEN_KEYS) {
    assert.equal(Object.prototype.hasOwnProperty.call(ranked, key), false, key);
  }
  const point = resolveLimousineCompanyPoint({
    coverageLat: 50.796,
    coverageLng: 3.621,
  });
  assert.deepEqual(point, { lat: 50.796, lng: 3.621 });
  assert.equal(Object.prototype.hasOwnProperty.call(ranked, "lat"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(ranked, "lng"), false);
});

test("valid vehicle plus published offer is eligible; incomplete stays out", () => {
  assert.equal(isLimousineDiscoveryListable(eligibleProfile()), true);
  assert.equal(
    isLimousineDiscoveryListable(eligibleProfile({ vehicles: [] })),
    false,
  );
  assert.equal(
    isLimousineDiscoveryListable(
      eligibleProfile({ limousine_offers: [offer({ published: false, enabled: false })] }),
    ),
    false,
  );
  assert.equal(
    evaluateLimousineProviderEligibility(eligibleProfile({ bookable: false })).reason,
    "eligible",
  );
});

test("worker nearby ranks limousine instead of applying taxi radius/postcode exclusion", () => {
  const nearbyFn = worker.slice(
    worker.indexOf("async function listNearbyPartners"),
    worker.indexOf("function supportedPostcodesIncludes"),
  );
  assert.equal(nearbyFn.includes("_limousineNearbyDistanceKm"), true);
  assert.equal(nearbyFn.includes("_compareLimousineNearbyRank"), true);
  assert.equal(nearbyFn.includes("_publicLimousineDistanceFields"), true);
  assert.equal(nearbyFn.includes("operating_base"), false);
  assert.equal(nearbyFn.includes(".list("), false);
  assert.equal(wrangler.includes("LIMOUSINE_QUOTE_ENABLED"), false);
  assert.equal(wrangler.includes("LIMOUSINE_BOOK_ENABLED"), false);
  assert.equal(wrangler.includes("LIMOUSINE_MANUAL_QUOTE_ENABLED"), false);
  assert.match(wrangler, /RATEHAWK_TEST_PREBOOK_ENABLED\s*=\s*"0"/);
});
