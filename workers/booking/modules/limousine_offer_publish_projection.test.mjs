// Offer publish → public projection → discovery consistency.
// Run: node --test workers/booking/modules/limousine_offer_publish_projection.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  isLimousineDiscoveryListable,
  limousineNearbyAllowsUnscopedListing,
} from "./limousine_discovery_preview.mjs";
import { compareLimousineNearbyRank } from "./limousine_distance_rank.mjs";
import {
  applyLimousinePublicFieldsToProfileEntry,
  buildLimousineProjection,
  limousineProjectionFingerprint,
  limousinePublicContentDigest,
  resolveLimousineProjectionRevision,
  stampLimousineProjectionOnProfile,
} from "./limousine_projection.mjs";
import {
  countPublishedLimousineOffers,
  mergeLimousinePricingSection,
  normalizeLimousinePricingSection,
} from "./limousine_pricing_resolver.mjs";
import { mergePublicPartnerProfilePreserveOmitted } from "./limousine_public_service_persist.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");

function publishedOffer(overrides = {}) {
  return {
    offer_id: "off_1",
    enabled: true,
    published: true,
    target_type: "service_class",
    service_class_id: "stretch_limousine",
    applies_to_all_selected_vehicles: true,
    price_presentation: "quote_required",
    currency: "EUR",
    title: { nl: "Avond" },
    description: { nl: "Avondrit" },
    ...overrides,
  };
}

function eligibleProfile(overrides = {}) {
  return {
    partner_id: "cmp_fluxidi",
    company_name: "Fluxidi",
    is_active: true,
    profile_enabled: true,
    published_at: "2026-08-19T08:00:00Z",
    subscription_status: "active",
    limousine_entitled: true,
    services: ["limousine"],
    vehicles: [
      {
        service_category: "limousine",
        service_class: "stretch_limousine",
        is_active: true,
      },
    ],
    ...overrides,
  };
}

test("PATCH merge keeps omitted offers and clears an explicit empty list", () => {
  const existing = normalizeLimousinePricingSection({
    enabled: true,
    source_revision: 4,
    offers: [publishedOffer()],
    selected_vehicle_ids: ["vh_party"],
    public_title: { nl: "Maison" },
    public_description: { nl: "Limousines" },
    limousine_hero: { photo_url: "https://cdn.example/hero.jpg", source_kind: "upload" },
  });
  const omitted = mergeLimousinePricingSection(existing, {
    enabled: true,
    source_revision: 4,
    public_title: { nl: "Nieuw" },
  });
  assert.equal(omitted.offers[0].offer_id, "off_1");
  assert.deepEqual(omitted.selected_vehicle_ids, ["vh_party"]);
  assert.equal(omitted.public_title.nl, "Nieuw");
  assert.equal(omitted.limousine_hero.photo_url, "https://cdn.example/hero.jpg");

  const cleared = mergeLimousinePricingSection(existing, { offers: [] });
  assert.deepEqual(cleared.offers, []);
  assert.equal(countPublishedLimousineOffers(cleared), 0);
});

test("stale source revision is still a 409 in the pricing POST", () => {
  assert.match(
    worker,
    /clientRevision > 0 && clientRevision < existingSection\.source_revision/,
  );
  assert.match(worker, /error: "stale_source_revision"/);
  assert.match(worker, /}, 409\)/);
});

test("fingerprint changes when offer content or hero changes at the same count", () => {
  const base = limousinePublicContentDigest({
    offers: [publishedOffer({ display_amount_cents: 12000 })],
    hero: { photo_url: "https://cdn.example/a.jpg", source_kind: "upload", alignment: "center", source_revision: 1 },
    selectedVehicleIds: ["vh_1"],
  });
  const priceChange = limousinePublicContentDigest({
    offers: [publishedOffer({ display_amount_cents: 15000 })],
    hero: { photo_url: "https://cdn.example/a.jpg", source_kind: "upload", alignment: "center", source_revision: 1 },
    selectedVehicleIds: ["vh_1"],
  });
  const heroChange = limousinePublicContentDigest({
    offers: [publishedOffer({ display_amount_cents: 12000 })],
    hero: { photo_url: "https://cdn.example/b.jpg", source_kind: "upload", alignment: "top", source_revision: 2 },
    selectedVehicleIds: ["vh_1"],
  });
  assert.notEqual(base, priceChange);
  assert.notEqual(base, heroChange);

  const projection = { limousine_available: true, published_offer_count: 1, reason: "eligible" };
  assert.notEqual(
    limousineProjectionFingerprint(projection, true, base),
    limousineProjectionFingerprint(projection, true, priceChange),
  );
});

test("pricing publish projects the full limousine subdocument onto scoped, v1 and v2", () => {
  assert.match(worker, /_mergeLimousinePricingSection\(existingSection, incomingSection\)/);
  assert.match(worker, /_syncLimousinePublicFieldsInProfileArray/);
  assert.match(worker, /PARTNER_PROFILES_KEY/);
  assert.match(worker, /PUBLIC_PARTNER_PROFILES_V2_KEY/);
  assert.match(worker, /visibility_ok: discoveryListable && publicProjectedOfferCount > 0/);
  assert.match(worker, /public_projected_offer_count/);
  assert.match(worker, /discovery_listable/);
  assert.doesNotMatch(worker, /_setLimousineEntitledInProfileArray/);
});

test("array sync preserves other partners and non-limousine fields", () => {
  const other = { partner_id: "cmp_other", company_name: "Taxi", services: ["taxi_vvb"] };
  const current = eligibleProfile({
    tagline: "Stay",
    services: ["limousine", "taxi_vvb"],
    limousine_offers: [],
  });
  const stamped = stampLimousineProjectionOnProfile({
    profile: {
      ...current,
      limousine_offers: [publishedOffer()],
      limousine_hero_url: "https://cdn.example/hero.jpg",
      limousine_hero_source: "upload",
      limousine_hero_alignment: "center",
      limousine_hero_revision: 2,
    },
    entitled: true,
    projection: buildLimousineProjection({
      ...current,
      limousine_offers: [publishedOffer()],
    }),
    sourceRevision: 8,
  });
  const next = applyLimousinePublicFieldsToProfileEntry(current, {
    ...stamped,
    limousine_offers: [publishedOffer()],
  });
  assert.equal(next.tagline, "Stay");
  assert.deepEqual(next.services, ["limousine", "taxi_vvb"]);
  assert.equal(next.limousine_offers[0].offer_id, "off_1");
  assert.equal(next.limousine_available, true);
  assert.equal(other.services[0], "taxi_vvb");
});

test("public profile cannot claim eligible/visible while offers are empty", () => {
  const empty = applyLimousinePublicFieldsToProfileEntry(eligibleProfile(), {
    limousine_entitled: true,
    limousine_available: true,
    limousine_projection: { reason: "eligible", limousine_available: true },
    limousine_offers: [],
  });
  assert.equal(empty.limousine_available, false);
  assert.equal(empty.limousine_projection.reason, "no_published_offer");
  assert.equal(isLimousineDiscoveryListable(empty), false);
});

test("fresh public projection with one safe offer is discovery-listable", () => {
  const profile = applyLimousinePublicFieldsToProfileEntry(eligibleProfile(), {
    limousine_entitled: true,
    limousine_available: true,
    limousine_projection: { reason: "eligible", limousine_available: true },
    limousine_offers: [publishedOffer()],
  });
  assert.equal(isLimousineDiscoveryListable(profile), true);
  assert.equal(profile.limousine_offers.length, 1);
});

test("unscoped, 9688 and 1000 stay listable; postcode only ranks", () => {
  const profile = applyLimousinePublicFieldsToProfileEntry(
    eligibleProfile({
      coverage: { primary_postcode: "9688", lat: 53.18, lng: 6.99 },
    }),
    {
      limousine_entitled: true,
      limousine_available: true,
      limousine_projection: { reason: "eligible", limousine_available: true },
      limousine_offers: [publishedOffer()],
    },
  );
  assert.equal(isLimousineDiscoveryListable(profile), true);
  assert.equal(
    limousineNearbyAllowsUnscopedListing({ service: "limousine" }),
    true,
  );
  const near = { partnerId: "near", distanceKm: 4, p: profile };
  const far = { partnerId: "far", distanceKm: 40, p: profile };
  const ranked = [far, near].sort(compareLimousineNearbyRank);
  assert.equal(ranked[0].partnerId, "near");
  assert.equal(isLimousineDiscoveryListable(profile), true);
});

test("general profile publish and hero-only writes keep existing offers", () => {
  const existing = eligibleProfile({ limousine_offers: [publishedOffer()] });
  const merged = mergePublicPartnerProfilePreserveOmitted(existing, {
    tagline: "Nieuw",
    company_name: "Fluxidi",
  });
  assert.equal(merged.limousine_offers[0].offer_id, "off_1");
  const heroOnly = mergeLimousinePricingSection(
    {
      offers: [publishedOffer()],
      selected_vehicle_ids: ["vh_1"],
      public_title: { nl: "Maison" },
    },
    { limousine_hero: { photo_url: "https://cdn.example/new.jpg", source_kind: "upload" } },
  );
  assert.equal(heroOnly.offers[0].offer_id, "off_1");
});

test("pricing save N to N+1 and stale N stay monotonic", () => {
  const existing = normalizeLimousinePricingSection({
    source_revision: 4,
    offers: [publishedOffer()],
  });
  const next = mergeLimousinePricingSection(existing, {
    source_revision: 4,
    offers: [publishedOffer({ title: { nl: "Nieuw" } })],
  });
  next.source_revision = existing.source_revision + 1;
  assert.equal(next.source_revision, 5);
  const stale = existing.source_revision;
  assert.equal(stale < next.source_revision, true);
  const profile = eligibleProfile({ limousine_offers: [publishedOffer()] });
  const stamped = stampLimousineProjectionOnProfile({
    profile,
    entitled: true,
    projection: buildLimousineProjection(profile),
    sourceRevision: 7,
  });
  const contentChange = resolveLimousineProjectionRevision({
    existingRecord: { source_revision: 7, partner_profile: stamped },
    existingProfile: stamped,
    nextProjection: buildLimousineProjection(profile),
    entitled: true,
    existingContentDigest: limousinePublicContentDigest({
      offers: [publishedOffer({ title: { nl: "Avond" } })],
    }),
    nextContentDigest: limousinePublicContentDigest({
      offers: [publishedOffer({ title: { nl: "Nieuw" } })],
    }),
  });
  assert.equal(contentChange.changed, true);
  assert.equal(contentChange.source_revision, 8);
});

test("quote/book gates stay off in wrangler and worker defaults", () => {
  const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");
  assert.ok(!wrangler.includes("LIMOUSINE_QUOTE_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_MANUAL_QUOTE_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_BOOK_ENABLED"));
  assert.match(worker, /env\?\.LIMOUSINE_QUOTE_ENABLED \?\? "0"/);
  assert.match(worker, /_limousineManualQuoteGateEnabledRaw/);
  assert.match(worker, /_limousineBookGateEnabledRaw/);
});

test("taxi and airport pricing branches stay isolated from limousine merge", () => {
  const postIdx = worker.indexOf('url.pathname === "/admin/pricing/limousine" && request.method === "POST"');
  const nextRouteIdx = worker.indexOf('url.pathname === "/admin/cancellation-policy/profile" && request.method === "GET"');
  const window = worker.slice(postIdx, nextRouteIdx);
  assert.ok(!window.includes("calcPrice("));
  assert.ok(!window.includes("resolveAirportFixedFare("));
  assert.ok(!window.includes("RATEHAWK"));
  assert.ok(!window.includes("Billit"));
});
