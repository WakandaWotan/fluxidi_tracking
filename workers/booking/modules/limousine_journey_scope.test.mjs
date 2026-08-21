// Published offer journey-type scope: working → public → quote/book fail-closed.
// Run: node --test workers/booking/modules/limousine_journey_scope.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_OFFER_ERRORS,
  buildSafePublicLimousineOffers,
  offerAllowsPublishedJourneyType,
  offerHasExplicitPublishedJourneyScope,
  publishedLimousineJourneyScope,
  validateLimousineOffer,
} from "./limousine_offers.mjs";
import {
  LIMOUSINE_BOOK_REASONS,
  composeLimousineTotal,
} from "./limousine_booking.mjs";
import {
  LIMOUSINE_QUOTE_REASONS,
  limousineQuoteRequestKey,
  validateLimousineQuoteRequest,
} from "./limousine_manual_quote.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

function classOffer(overrides = {}) {
  return {
    offer_id: "off_class",
    enabled: true,
    published: true,
    target_type: "service_class",
    service_class_id: "executive_sedan",
    price_presentation: "quote_required",
    currency: "EUR",
    journey_types: ["event_transfer"],
    title: { nl: "Klasse", en: "Class", fr: "Classe", es: "Clase" },
    mobilisation: { method: "included" },
    source_revision: 2,
    ...overrides,
  };
}

function quoteOffer(overrides = {}) {
  return {
    offer_id: "off_1",
    enabled: true,
    published: true,
    service_class_id: "executive_sedan",
    vehicle_id: "",
    paid_extras: [],
    source_revision: 7,
    price_presentation: "quote_required",
    journey_types: ["event_transfer"],
    ...overrides,
  };
}

function customerRequest(overrides = {}) {
  return {
    offer_id: "off_1",
    journey_type: "event_transfer",
    from: "Gent",
    to: "Brussel",
    scheduled_pickup_iso: "2026-09-01T10:00:00Z",
    pax: 2,
    bags: 1,
    selected_extra_ids: [],
    locale: "nl",
    ...overrides,
  };
}

function compose(offerOverrides = {}, request = {}) {
  return composeLimousineTotal({
    section: {
      enabled: true,
      currency: "EUR",
      source_revision: 5,
      offers: [
        {
          offer_id: "off_1",
          enabled: true,
          published: true,
          target_type: "service_class",
          service_class_id: "executive_sedan",
          price_presentation: "exact_fixed",
          currency: "EUR",
          journey_types: ["event_transfer"],
          fixed_rules: [
            {
              rule_id: "r1",
              enabled: true,
              journey_type: "event_transfer",
              zone_type: "none",
              amount_cents: 20000,
              currency: "EUR",
            },
          ],
          mobilisation: { method: "included" },
          source_revision: 3,
          ...offerOverrides,
        },
      ],
    },
    offerId: "off_1",
    request: {
      service_class_id: "executive_sedan",
      journey_type: "event_transfer",
      currency: "EUR",
      ...request,
    },
    routes: { main: { distance_km: 12, duration_min: 22 } },
  });
}

test("explicit published scope never silently expands to all types", () => {
  assert.deepEqual(publishedLimousineJourneyScope(classOffer()), ["event_transfer"]);
  assert.equal(offerHasExplicitPublishedJourneyScope(classOffer()), true);
  assert.equal(offerAllowsPublishedJourneyType(classOffer(), "event_transfer"), true);
  assert.equal(offerAllowsPublishedJourneyType(classOffer(), "airport_transfer"), false);
  assert.equal(offerAllowsPublishedJourneyType(classOffer(), "hotel_transfer"), false);
  assert.equal(offerAllowsPublishedJourneyType(classOffer(), "point_to_point"), false);
  assert.equal(offerAllowsPublishedJourneyType(classOffer(), "hourly_package"), false);
});

test("legacy offers without journey_types use the named catalog fallback", () => {
  const legacy = classOffer({ journey_types: [] });
  assert.equal(offerHasExplicitPublishedJourneyScope(legacy), false);
  assert.deepEqual(publishedLimousineJourneyScope(legacy), [
    "point_to_point",
    "airport_transfer",
    "hotel_transfer",
    "event_transfer",
    "hourly_package",
  ]);
  assert.equal(offerAllowsPublishedJourneyType(legacy, "airport_transfer"), true);
  assert.equal(offerAllowsPublishedJourneyType(legacy, "street_ride"), false);
});

test("legacy published offers without journey_types stay valid", () => {
  const result = validateLimousineOffer(classOffer({ journey_types: [] }), {
    readiness: true,
    knownClassIds: ["executive_sedan"],
    vehicles: [],
  });
  assert.equal(result.valid, true);
  assert.equal(
    result.errors.includes(LIMOUSINE_OFFER_ERRORS.MISSING_JOURNEY_TYPES),
    false,
  );
});

test("working draft changes stay off the public snapshot until publish", () => {
  const working = classOffer({
    published: false,
    journey_types: ["airport_transfer"],
    offer_id: "off_draft",
  });
  const live = classOffer({
    published: true,
    journey_types: ["event_transfer"],
    offer_id: "off_live",
  });
  const safe = buildSafePublicLimousineOffers([working, live], {
    eligible: true,
    readiness: true,
    knownClassIds: ["executive_sedan"],
    vehicles: [],
  });
  assert.equal(safe.length, 1);
  assert.equal(safe[0].offer_id, "off_live");
  assert.deepEqual(safe[0].journey_types, ["event_transfer"]);

  const afterPublish = buildSafePublicLimousineOffers(
    [{ ...working, published: true, offer_id: "off_draft" }, live],
    {
      eligible: true,
      readiness: true,
      knownClassIds: ["executive_sedan"],
      vehicles: [],
    },
  );
  assert.equal(afterPublish.length, 2);
  assert.deepEqual(
    afterPublish.find((o) => o.offer_id === "off_draft").journey_types,
    ["airport_transfer"],
  );
});

test("forged quote journey type is rejected before any quote write", () => {
  const forged = validateLimousineQuoteRequest(
    customerRequest({ journey_type: "airport_transfer" }),
    { eligible: true, offer: quoteOffer(), gateEnabled: true },
  );
  assert.equal(forged.ok, false);
  assert.equal(forged.reason, LIMOUSINE_QUOTE_REASONS.JOURNEY_TYPE_NOT_ALLOWED);
  assert.equal(forged.field, "journey_type");

  const allowed = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: quoteOffer(),
    gateEnabled: true,
  });
  assert.equal(allowed.ok, true);
  assert.equal(allowed.request.journey_type, "event_transfer");
});

test("stale republished scope fails closed on quote and book totals", () => {
  const staleQuote = validateLimousineQuoteRequest(
    customerRequest({ journey_type: "event_transfer" }),
    {
      eligible: true,
      offer: quoteOffer({ journey_types: ["hotel_transfer"], source_revision: 9 }),
      gateEnabled: true,
    },
  );
  assert.equal(staleQuote.ok, false);
  assert.equal(staleQuote.reason, LIMOUSINE_QUOTE_REASONS.JOURNEY_TYPE_NOT_ALLOWED);

  const staleBook = compose(
    { journey_types: ["hotel_transfer"], source_revision: 9 },
    { journey_type: "event_transfer" },
  );
  assert.equal(staleBook.ok, false);
  assert.equal(staleBook.reason, LIMOUSINE_BOOK_REASONS.JOURNEY_TYPE_NOT_ALLOWED);
  assert.equal(staleBook.components.length, 0);
});

test("duplicate quote submissions stay idempotent on the same scoped type", () => {
  const first = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: quoteOffer(),
    gateEnabled: true,
  });
  const second = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: quoteOffer(),
    gateEnabled: true,
  });
  assert.equal(first.ok && second.ok, true);
  assert.equal(
    limousineQuoteRequestKey({
      tenantId: "t1",
      companyId: "c1",
      customerRef: "cust_1",
      request: first.request,
    }),
    limousineQuoteRequestKey({
      tenantId: "t1",
      companyId: "c1",
      customerRef: "cust_1",
      request: second.request,
    }),
  );
});

test("tenant A cannot use tenant B offer scope", () => {
  const tenantA = quoteOffer({
    offer_id: "off_a",
    journey_types: ["event_transfer"],
  });
  const tenantB = quoteOffer({
    offer_id: "off_b",
    journey_types: ["airport_transfer"],
  });
  const stolen = validateLimousineQuoteRequest(
    customerRequest({ offer_id: "off_b", journey_type: "airport_transfer" }),
    { eligible: true, offer: tenantA, gateEnabled: true },
  );
  assert.equal(stolen.ok, false);
  assert.equal(stolen.reason, LIMOUSINE_QUOTE_REASONS.JOURNEY_TYPE_NOT_ALLOWED);
  assert.equal(offerAllowsPublishedJourneyType(tenantB, "event_transfer"), false);
});

test("quote success still creates no booking side effects in the validator", () => {
  const allowed = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: quoteOffer(),
    gateEnabled: true,
  });
  assert.equal(allowed.ok, true);
  assert.equal(allowed.request.intent_kind, "quote_request");
  assert.equal(allowed.request.booking_id, undefined);
});

test("worker fail-closes forged types on quote-requests and /book before writes", () => {
  const worker = readFileSync(join(__dirname, "../fluxidi_booking_worker.js"), "utf8");
  assert.match(worker, /failQuote\(400, reason/);
  assert.match(worker, /field: validated\.field/);
  assert.match(worker, /unavailable\("journey_type_not_allowed"/);
  assert.match(worker, /_offerAllowsPublishedJourneyType\(offer, journeyType\)/);
  assert.match(worker, /async function _loadAuthoritativeLimousineOffer\(env, scope, offerId\)/);
  assert.match(
    worker,
    /const section = await _loadLimousinePricingSection\(env, scope\);/,
  );
  const quoteIdx = worker.indexOf('"/limousine/quote-requests" && request.method === "POST"');
  const bookIdx = worker.indexOf('url.pathname === "/book" && request.method === "POST"');
  const allowIdx = worker.indexOf("_offerAllowsPublishedJourneyType(offer, journeyType)");
  assert.ok(quoteIdx > 0 && bookIdx > 0 && allowIdx > 0);
  assert.ok(allowIdx < worker.indexOf("mollieCreatePayment"));
  assert.ok(!worker.includes("CREATE TABLE"));
});
