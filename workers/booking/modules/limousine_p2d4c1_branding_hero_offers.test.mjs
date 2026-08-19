import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  applyPublicLimousineHeroFields,
  normalizeLimousineHero,
  normalizeLimousinePricingSection,
} from "./limousine_pricing_resolver.mjs";
import {
  buildSafePublicLimousineOffers,
  normalizeLimousineOffer,
} from "./limousine_offers.mjs";
import { buildLimousineNearbyCardProjection } from "./limousine_discovery_preview.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(here, "../fluxidi_booking_worker.js"), "utf8");

const CLASS_IDS = ["party_stretch", "suv_stretch"];
const FLEET = [
  {
    id: "vh_party",
    is_active: true,
    service_category: "limousine",
    service_class_id: "party_stretch",
  },
  {
    id: "vh_hummer",
    is_active: true,
    service_category: "limousine",
    service_class_id: "suv_stretch",
  },
  {
    id: "vh_hidden",
    is_active: true,
    service_category: "",
    service_class_id: "",
  },
];

function offer(overrides = {}) {
  return {
    offer_id: "off_1",
    enabled: true,
    published: true,
    target_type: "vehicle",
    vehicle_id: "vh_party",
    vehicle_ids: ["vh_party"],
    applies_to_all_selected_vehicles: false,
    price_presentation: "from_price",
    display_amount_cents: 25000,
    currency: "EUR",
    title: { nl: "Party", en: "Party", fr: "", es: "" },
    ...overrides,
  };
}

test("hero persists on the pricing section and never copies taxi cover", () => {
  const section = normalizeLimousinePricingSection({
    enabled: true,
    currency: "EUR",
    limousine_hero: {
      photo_url: "https://cdn.example/limousine-hero.jpg",
      source_kind: "upload",
      alignment: "top",
      source_revision: 3,
    },
  });
  assert.equal(section.limousine_hero.photo_url, "https://cdn.example/limousine-hero.jpg");
  assert.equal(section.limousine_hero.source_kind, "upload");
  assert.equal(section.limousine_hero.alignment, "top");
  const again = normalizeLimousineHero(section);
  assert.equal(again.photo_url, section.limousine_hero.photo_url);
  const stamped = applyPublicLimousineHeroFields(
    {
      hero_photo_url: "https://cdn.example/taxi-cover.jpg",
      media: { hero_photo_url: "https://cdn.example/taxi-cover.jpg" },
    },
    section,
  );
  assert.equal(stamped.limousine_hero_url, "https://cdn.example/limousine-hero.jpg");
  assert.equal(stamped.hero_photo_url, "https://cdn.example/taxi-cover.jpg");
  const cleared = applyPublicLimousineHeroFields(stamped, { limousine_hero: {} });
  assert.equal(cleared.limousine_hero_url, undefined);
});

test("legacy unbound offers become all-selected; vehicle bindings stay distinct", () => {
  const legacy = normalizeLimousineOffer({
    offer_id: "off_legacy",
    enabled: true,
    published: true,
    target_type: "service_class",
    service_class_id: "party_stretch",
    price_presentation: "quote_required",
    currency: "EUR",
  });
  assert.equal(legacy.applies_to_all_selected_vehicles, true);
  assert.deepEqual(legacy.vehicle_ids, []);

  const party = normalizeLimousineOffer(offer());
  const hummer = normalizeLimousineOffer(
    offer({
      offer_id: "off_hummer",
      vehicle_id: "vh_hummer",
      vehicle_ids: ["vh_hummer"],
      price_presentation: "exact_fixed",
      display_amount_cents: 65000,
    }),
  );
  const publicOffers = buildSafePublicLimousineOffers([party, hummer], {
    eligible: true,
    knownVehicles: FLEET,
    knownClassIds: CLASS_IDS,
    readiness: true,
  });
  const partyPublic = publicOffers.find((item) => item.offer_id === "off_1");
  const hummerPublic = publicOffers.find((item) => item.offer_id === "off_hummer");
  assert.deepEqual(partyPublic.vehicle_ids, ["vh_party"]);
  assert.deepEqual(hummerPublic.vehicle_ids, ["vh_hummer"]);
  assert.equal(partyPublic.display_amount_cents, 25000);
  assert.equal(hummerPublic.display_amount_cents, 65000);
});

test("unpublished linked vehicle is omitted without deleting the offer", () => {
  const publicOffers = buildSafePublicLimousineOffers(
    [
      offer({
        vehicle_ids: ["vh_party", "vh_hidden"],
        vehicle_id: "vh_party",
      }),
    ],
    {
      eligible: true,
      knownVehicles: FLEET,
      knownClassIds: CLASS_IDS,
      readiness: true,
    },
  );
  assert.equal(publicOffers.length, 1);
  assert.deepEqual(publicOffers[0].vehicle_ids, ["vh_party"]);
  assert.equal(publicOffers[0].vehicle_ids.includes("vh_hidden"), false);
});

test("shared and all-selected offers publish for every classified limousine", () => {
  const shared = buildSafePublicLimousineOffers(
    [
      offer({
        offer_id: "off_both",
        vehicle_ids: ["vh_party", "vh_hummer"],
        vehicle_id: "vh_party",
        price_presentation: "quote_required",
        display_amount_cents: null,
      }),
    ],
    {
      eligible: true,
      knownVehicles: FLEET,
      knownClassIds: CLASS_IDS,
      readiness: true,
    },
  );
  assert.deepEqual(shared[0].vehicle_ids, ["vh_party", "vh_hummer"]);

  const all = buildSafePublicLimousineOffers(
    [
      offer({
        offer_id: "off_all",
        applies_to_all_selected_vehicles: true,
        vehicle_ids: [],
        vehicle_id: "",
        target_type: "service_class",
        service_class_id: "party_stretch",
        price_presentation: "quote_required",
        display_amount_cents: null,
      }),
    ],
    {
      eligible: true,
      knownVehicles: FLEET,
      knownClassIds: CLASS_IDS,
      readiness: true,
    },
  );
  assert.equal(all[0].applies_to_all_selected_vehicles, true);
});

test("nearby summary prefers featured then lowest from-price and never labels a package as from", () => {
  const card = buildLimousineNearbyCardProjection({
    partner_id: "limo_1",
    company_name: "Maison",
    is_active: true,
    bookable: true,
    profile_enabled: true,
    published_at: "2026-08-17T10:00:00Z",
    subscription_status: "active",
    limousine_entitled: true,
    limousine_available: true,
    limousine_service_enabled: true,
    services: ["limousine"],
    logo_url: "https://cdn.example/logo.png",
    vehicles: [
      {
        service_category: "limousine",
        service_class: "party_stretch",
        photo_url: "https://cdn.example/party.jpg",
        pax: 8,
        is_active: true,
      },
    ],
    limousine_offers: [
      {
        offer_id: "off_pkg",
        published: true,
        enabled: true,
        price_presentation: "exact_fixed",
        display_amount_cents: 9000,
        currency: "EUR",
        hourly: { enabled: true, package_amount_cents: 65000, package_duration_minutes: 240 },
      },
      {
        offer_id: "off_from",
        published: true,
        enabled: true,
        price_presentation: "from_price",
        display_amount_cents: 25000,
        currency: "EUR",
        featured: true,
      },
    ],
  });
  assert.equal(card.logo_url, "https://cdn.example/logo.png");
  assert.equal(card.limousine_price_presentation, "from_price");
  assert.equal(card.display_amount_cents, 25000);
});

test("worker preserves public hero fields and limousine vehicle_id", () => {
  assert.match(worker, /limousine_hero_url/);
  assert.match(worker, /_applyPublicLimousineHeroFields/);
  assert.match(worker, /serviceCategory === "limousine" && publicVehicleId/);
  assert.match(worker, /applies_to_all_selected_vehicles/);
  assert.doesNotMatch(worker, /hero_photo_url:\s*hero\.photo_url/);
});
