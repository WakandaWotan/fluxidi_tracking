import test from "node:test";
import assert from "node:assert/strict";

import {
  LIMOUSINE_MOBILISATION_METHODS,
  LIMOUSINE_OFFER_TARGETS,
  LIMOUSINE_PRICE_PRESENTATIONS,
  buildSafePublicLimousineOffers,
  normalizeLimousineOffers,
  normalizeLimousinePublicSortOrder,
  sortPublicLimousineOffers,
} from "./limousine_offers.mjs";

const CLASS_IDS = ["party_stretch"];
const VEHICLES = [
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
    service_class_id: "party_stretch",
  },
];

function offer(src) {
  return {
    offer_id: src.offer_id,
    enabled: true,
    published: true,
    target_type: LIMOUSINE_OFFER_TARGETS.SERVICE_CLASS,
    applies_to_all_selected_vehicles: true,
    featured: src.featured === true,
    sort_order: src.sort_order,
    service_class_id: "party_stretch",
    price_presentation: LIMOUSINE_PRICE_PRESENTATIONS.FROM_PRICE,
    display_amount_cents: 25000,
    currency: "EUR",
    journey_types: ["point_to_point"],
    title: { nl: src.offer_id, en: src.offer_id, fr: src.offer_id, es: src.offer_id },
    description: { nl: "d", en: "d", fr: "d", es: "d" },
    mobilisation: { method: LIMOUSINE_MOBILISATION_METHODS.INCLUDED },
    source_revision: 1,
  };
}

test("public sort order parser rejects 0/negative/decimal/text and treats empty as automatic", () => {
  assert.equal(normalizeLimousinePublicSortOrder(""), null);
  assert.equal(normalizeLimousinePublicSortOrder(0), null);
  assert.equal(normalizeLimousinePublicSortOrder(-1), null);
  assert.equal(normalizeLimousinePublicSortOrder(1.5), null);
  assert.equal(normalizeLimousinePublicSortOrder("abc"), null);
  assert.equal(normalizeLimousinePublicSortOrder("1"), 1);
  assert.equal(normalizeLimousinePublicSortOrder(3), 3);
});

test("normalize persists automatic as null, never 0", () => {
  const [normalized] = normalizeLimousineOffers([
    offer({ offer_id: "auto", sort_order: 0 }),
  ]);
  assert.equal(normalized.sort_order, null);
  assert.equal(normalized.featured, false);
});

test("explicit 1,2,3 sort before automatic and keep stable ties; featured is ignored", () => {
  const ranked = sortPublicLimousineOffers([
    offer({ offer_id: "auto_a" }),
    offer({ offer_id: "two", sort_order: 2, featured: true }),
    offer({ offer_id: "auto_b", featured: true }),
    offer({ offer_id: "one", sort_order: 1 }),
    offer({ offer_id: "two_b", sort_order: 2 }),
  ]);
  assert.deepEqual(
    ranked.map((row) => row.offer_id),
    ["one", "two", "two_b", "auto_a", "auto_b"],
  );
});

test("safe public projection copies featured/sort_order and hides unpublished", () => {
  const publicOffers = buildSafePublicLimousineOffers(
    [
      { ...offer({ offer_id: "live", sort_order: 2, featured: true }), published: true },
      { ...offer({ offer_id: "draft", sort_order: 1, featured: true }), published: false },
    ],
    {
      eligible: true,
      knownVehicles: VEHICLES,
      knownClassIds: CLASS_IDS,
      readiness: true,
    },
  );
  assert.equal(publicOffers.length, 1);
  assert.equal(publicOffers[0].offer_id, "live");
  assert.equal(publicOffers[0].featured, true);
  assert.equal(publicOffers[0].sort_order, 2);
});
