// LIMOUSINE-MARKETPLACE-P2C2 — manual quote lifecycle, sealed acceptance,
// terms revision and operational-leg reconciliation.
// Run: node --test workers/booking/modules/limousine_manual_quote.test.mjs
//
// All amounts are illustrative TEST fixtures in integer cents.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_AUDIT_FORBIDDEN_KEYS,
  LIMOUSINE_FORBIDDEN_REQUEST_FIELDS,
  LIMOUSINE_QUOTE_REASONS,
  LIMOUSINE_QUOTE_STATES,
  LIMOUSINE_REQUIRED_TERMS_KEYS,
  appendLimousineQuoteAudit,
  applyLimousineCompanyQuoteAction,
  applyLimousineQuoteTransition,
  assertLimousineQuoteAcceptable,
  buildLimousineAcceptanceBinding,
  buildLimousineQuoteAuditEntry,
  canTransitionLimousineQuote,
  itineraryFingerprint,
  limousineManualQuoteGateEnabled,
  limousineQuoteRequestKey,
  publicLimousineQuoteView,
  validateLimousineCompanyQuote,
  validateLimousineQuoteRequest,
  validateLimousineTerms,
} from "./limousine_manual_quote.mjs";
import {
  attachLimousineQuotationSnapshot,
  buildLimousineQuotationSnapshot,
} from "./limousine_quotation_snapshot.mjs";
import {
  LIMOUSINE_ACCEPTANCE_ERRORS,
  limousineAcceptanceBindingMatches,
  sealLimousineAcceptance,
  unsealLimousineAcceptance,
} from "./limousine_acceptance_token.mjs";
import {
  allocateLimousineOperationalLegs,
  limousineLegsReconcile,
} from "./limousine_operational_legs.mjs";
import { LIMOUSINE_COMPONENT_TYPES } from "./limousine_booking.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const S = LIMOUSINE_QUOTE_STATES;
const R = LIMOUSINE_QUOTE_REASONS;
const SECRET = "test-only-secret-not-production";

const TERMS = {
  terms_revision: 3,
  cancellation_deadline_hours: 24,
  cancellation_penalty_percent: 50,
  waiting_time_included_minutes: 15,
  waiting_time_overage_cents_per_minute: 100,
  no_show_penalty_percent: 100,
  overtime_cents_per_hour: 9000,
  mobilisation_disclosure: { en: "Mobilisation included" },
};

function authoritativeOffer(overrides = {}) {
  return {
    offer_id: "off_1",
    enabled: true,
    published: true,
    service_class_id: "executive_sedan",
    vehicle_id: "",
    paid_extras: [
      { extra_id: "wait", active: true, public: true, quote_required: false, amount_cents: 2500 },
      { extra_id: "deco", active: true, public: true, quote_required: true },
      { extra_id: "hidden", active: true, public: false },
    ],
    source_revision: 7,
    ...overrides,
  };
}

function customerRequest(overrides = {}) {
  return {
    offer_id: "off_1",
    journey_type: "point_to_point",
    from: "Gent",
    to: "Brussel",
    scheduled_pickup_iso: "2026-09-01T10:00:00Z",
    pax: 2,
    bags: 1,
    selected_extra_ids: [],
    customer_note: "Please arrive 10 minutes early.",
    locale: "nl",
    ...overrides,
  };
}

function quotedRecord(overrides = {}) {
  const validated = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: authoritativeOffer(),
    gateEnabled: true,
  });
  const quote = validateLimousineCompanyQuote(
    { total_incl_vat_cents: 45000, currency: "EUR", terms: TERMS, expires_at: "2099-01-01T00:00:00Z" },
    { nowIso: "2026-08-17T10:00:00Z" },
  );
  return {
    quote_request_id: "limq_1",
    tenant_id: "t1",
    company_id: "c1",
    state: S.CUSTOMER_ACCEPTANCE_REQUIRED,
    revision: 3,
    request: validated.request,
    quote: quote.quote,
    offer_source_revision: 7,
    pricing_section_revision: 5,
    audit: [],
    ...overrides,
  };
}

test("1) gate off performs zero work", () => {
  assert.equal(limousineManualQuoteGateEnabled("0"), false);
  assert.equal(limousineManualQuoteGateEnabled(undefined), false);
  assert.equal(limousineManualQuoteGateEnabled("1"), true);
  const blocked = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: authoritativeOffer(),
    gateEnabled: false,
  });
  assert.equal(blocked.ok, false);
  assert.equal(blocked.reason, R.GATE_OFF);
  const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");
  assert.ok(!wrangler.includes("LIMOUSINE_QUOTE_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_BOOK_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_MANUAL_QUOTE_ENABLED"));
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  assert.ok(worker.includes('env?.LIMOUSINE_MANUAL_QUOTE_ENABLED ?? "0"'));
});

test("2/3) ineligible company or unpublished offer creates no request", () => {
  assert.equal(
    validateLimousineQuoteRequest(customerRequest(), {
      eligible: false,
      offer: authoritativeOffer(),
      gateEnabled: true,
    }).reason,
    R.NOT_ELIGIBLE,
  );
  assert.equal(
    validateLimousineQuoteRequest(customerRequest(), {
      eligible: true,
      offer: authoritativeOffer({ published: false }),
      gateEnabled: true,
    }).reason,
    R.OFFER_UNPUBLISHED,
  );
  assert.equal(
    validateLimousineQuoteRequest(customerRequest(), {
      eligible: true,
      offer: authoritativeOffer({ enabled: false }),
      gateEnabled: true,
    }).reason,
    R.OFFER_UNPUBLISHED,
  );
  assert.equal(
    validateLimousineQuoteRequest(customerRequest(), {
      eligible: true,
      offer: null,
      gateEnabled: true,
    }).reason,
    R.UNKNOWN_OFFER,
  );
});

test("4) request identity is stable so a retry is idempotent", () => {
  const a = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: authoritativeOffer(),
    gateEnabled: true,
  });
  const b = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: authoritativeOffer(),
    gateEnabled: true,
  });
  assert.equal(a.request.itinerary_fingerprint, b.request.itinerary_fingerprint);
  const keyA = limousineQuoteRequestKey({ tenantId: "t1", companyId: "c1", customerRef: "cust@x", request: a.request });
  const keyB = limousineQuoteRequestKey({ tenantId: "t1", companyId: "c1", customerRef: "cust@x", request: b.request });
  assert.equal(keyA, keyB);
  // A different itinerary is a different request.
  const other = validateLimousineQuoteRequest(customerRequest({ to: "Antwerpen" }), {
    eligible: true,
    offer: authoritativeOffer(),
    gateEnabled: true,
  });
  assert.notEqual(a.request.itinerary_fingerprint, other.request.itinerary_fingerprint);
});

test("p3f) fingerprint includes partner, offer, vehicle and journey", () => {
  const a = validateLimousineQuoteRequest(
    customerRequest({ public_partner_id: "p1", vehicle_id: "veh_1" }),
    {
      eligible: true,
      offer: authoritativeOffer({
        target_type: "vehicle",
        vehicle_id: "veh_1",
        vehicle_ids: ["veh_1"],
      }),
      gateEnabled: true,
    },
  );
  const otherVehicle = validateLimousineQuoteRequest(
    customerRequest({ public_partner_id: "p1", vehicle_id: "veh_2" }),
    {
      eligible: true,
      offer: authoritativeOffer({
        target_type: "vehicle",
        vehicle_id: "veh_2",
        vehicle_ids: ["veh_2"],
      }),
      gateEnabled: true,
    },
  );
  assert.equal(a.ok, true);
  assert.notEqual(a.request.itinerary_fingerprint, otherVehicle.request.itinerary_fingerprint);
});

test("p3f) wrong vehicle or journey is rejected", () => {
  const wrongVehicle = validateLimousineQuoteRequest(
    customerRequest({ vehicle_id: "veh_other" }),
    {
      eligible: true,
      offer: authoritativeOffer({
        target_type: "vehicle",
        vehicle_id: "veh_1",
        vehicle_ids: ["veh_1"],
      }),
      gateEnabled: true,
    },
  );
  assert.equal(wrongVehicle.ok, false);
  assert.equal(wrongVehicle.reason, R.VEHICLE_SCOPE_MISMATCH);
  const wrongJourney = validateLimousineQuoteRequest(
    customerRequest({ journey_type: "airport_transfer" }),
    {
      eligible: true,
      offer: authoritativeOffer({ journey_types: ["event_transfer"] }),
      gateEnabled: true,
    },
  );
  assert.equal(wrongJourney.ok, false);
  assert.equal(wrongJourney.reason, R.JOURNEY_TYPE_NOT_ALLOWED);
});

test("p3f) working drafts stay unpublished", () => {
  const draft = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: authoritativeOffer({ published: false, enabled: true }),
    gateEnabled: true,
  });
  assert.equal(draft.ok, false);
  assert.equal(draft.reason, R.OFFER_UNPUBLISHED);
});

test("8/12) quote-required extra is carried; customer pricing is rejected", () => {
  const withQuoteExtra = validateLimousineQuoteRequest(
    customerRequest({ selected_extra_ids: ["deco"] }),
    { eligible: true, offer: authoritativeOffer(), gateEnabled: true },
  );
  assert.equal(withQuoteExtra.ok, true);
  assert.equal(withQuoteExtra.request.requires_manual_extra, true);
  // Non-public and unknown extras fail closed.
  for (const id of ["hidden", "nope"]) {
    assert.equal(
      validateLimousineQuoteRequest(customerRequest({ selected_extra_ids: [id] }), {
        eligible: true,
        offer: authoritativeOffer(),
        gateEnabled: true,
      }).reason,
      R.INVALID_EXTRA,
      id,
    );
  }
  // Every forbidden pricing/readiness assertion is rejected outright.
  for (const field of LIMOUSINE_FORBIDDEN_REQUEST_FIELDS) {
    const out = validateLimousineQuoteRequest(customerRequest({ [field]: 1 }), {
      eligible: true,
      offer: authoritativeOffer(),
      gateEnabled: true,
    });
    assert.equal(out.ok, false, field);
    assert.equal(out.reason, R.CLIENT_PRICING_REJECTED, field);
  }
});

test("request locale aliases persist as quotation locales", () => {
  const cases = [
    ["nl-BE", "nl"],
    ["en-GB", "en"],
    ["en-US", "en"],
    ["fr-BE", "fr"],
    ["fr-FR", "fr"],
    ["es-ES", "es"],
    ["en", "en"],
    ["fr", "fr"],
    ["es", "es"],
  ];
  for (const [raw, expected] of cases) {
    const out = validateLimousineQuoteRequest(customerRequest({ locale: raw }), {
      eligible: true,
      offer: authoritativeOffer(),
      gateEnabled: true,
    });
    assert.equal(out.ok, true, raw);
    assert.equal(out.request.locale, expected, raw);
  }
});

test("state machine: only defined transitions are allowed", () => {
  assert.equal(canTransitionLimousineQuote(S.REQUESTED, S.QUOTED), true);
  assert.equal(canTransitionLimousineQuote(S.QUOTED, S.CUSTOMER_ACCEPTANCE_REQUIRED), true);
  assert.equal(canTransitionLimousineQuote(S.CUSTOMER_ACCEPTANCE_REQUIRED, S.QUOTED), true);
  assert.equal(canTransitionLimousineQuote(S.CUSTOMER_ACCEPTANCE_REQUIRED, S.ACCEPTED), true);
  assert.equal(canTransitionLimousineQuote(S.QUOTED, S.QUOTED), false);
  assert.equal(canTransitionLimousineQuote(S.ACCEPTED, S.BOOKING_CREATED), true);
  // Contradictory / unknown transitions fail closed.
  assert.equal(canTransitionLimousineQuote(S.REQUESTED, S.ACCEPTED), false);
  assert.equal(canTransitionLimousineQuote(S.DECLINED, S.QUOTED), false);
  assert.equal(canTransitionLimousineQuote(S.BOOKING_CREATED, S.CANCELLED), false);
  assert.equal(canTransitionLimousineQuote(S.ACCEPTED, S.SUPERSEDED), false);
  assert.equal(canTransitionLimousineQuote("nonsense", S.QUOTED), false);
  assert.equal(canTransitionLimousineQuote(S.REQUESTED, "nonsense"), false);
});

test("6) an exact company quote is accepted and validated", () => {
  const out = validateLimousineCompanyQuote({
    total_incl_vat_cents: 45000,
    currency: "EUR",
    vat_treatment: "incl",
    vat_rate: 0.06,
    public_text: { nl: "Vaste prijs", en: "Fixed price" },
    terms: TERMS,
  });
  assert.equal(out.ok, true);
  assert.equal(out.quote.total_incl_vat_cents, 45000);
  assert.equal(out.quote.currency, "EUR");
  assert.equal(out.quote.terms_revision, 3);
  assert.ok(out.quote.expires_at);
  // Invalid amounts/currency fail closed.
  assert.equal(validateLimousineCompanyQuote({ total_incl_vat_cents: 0, currency: "EUR", terms: TERMS }).reason, R.INVALID_AMOUNT);
  assert.equal(validateLimousineCompanyQuote({ total_incl_vat_cents: 100, currency: "EU", terms: TERMS }).reason, R.INVALID_CURRENCY);
});

test("terms revision: unknown booking-critical terms fail closed", () => {
  assert.equal(validateLimousineTerms(TERMS).valid, true);
  for (const key of LIMOUSINE_REQUIRED_TERMS_KEYS) {
    const partial = { ...TERMS };
    delete partial[key];
    const out = validateLimousineTerms(partial);
    assert.equal(out.valid, false, key);
    assert.ok(out.missing.includes(key), key);
  }
  // A missing terms revision is itself booking-critical.
  const noRevision = validateLimousineTerms({ ...TERMS, terms_revision: 0 });
  assert.equal(noRevision.valid, false);
  assert.ok(noRevision.missing.includes("terms_revision"));
  // No legal text or commercial default is invented.
  const empty = validateLimousineTerms({});
  assert.equal(empty.terms.cancellation_deadline_hours, null);
  assert.deepEqual(empty.terms.included_services, []);
});

test("9/10) stale revisions are rejected and a newer quote supersedes", () => {
  const record = quotedRecord({ state: S.QUOTED, revision: 3 });
  // Stale (too low) and future (too high) both conflict, writing nothing.
  for (const expected of [2, 4]) {
    const out = applyLimousineQuoteTransition(record, {
      to: S.CUSTOMER_ACCEPTANCE_REQUIRED,
      expectedRevision: expected,
    });
    assert.equal(out.ok, false, String(expected));
    assert.equal(out.reason, R.STALE_REVISION);
    assert.equal(out.current_revision, 3);
  }
  // Correct revision advances by exactly one.
  const ok = applyLimousineQuoteTransition(record, {
    to: S.CUSTOMER_ACCEPTANCE_REQUIRED,
    expectedRevision: 3,
  });
  assert.equal(ok.ok, true);
  assert.equal(ok.record.revision, 4);
  // A newer quote supersedes the previous one.
  const superseded = applyLimousineQuoteTransition(record, { to: S.SUPERSEDED });
  assert.equal(superseded.ok, true);
  assert.equal(superseded.record.state, S.SUPERSEDED);
});

test("idempotent replay writes nothing", () => {
  const record = quotedRecord({
    state: S.QUOTED,
    revision: 3,
    last_transition_to: S.QUOTED,
  });
  const replay = applyLimousineQuoteTransition(record, { to: S.QUOTED, expectedRevision: 3 });
  assert.equal(replay.ok, true);
  assert.equal(replay.changed, false);
  assert.equal(replay.record.revision, 3);
});

test("11) expired, withdrawn, declined and superseded quotes cannot be accepted", () => {
  const expired = quotedRecord({
    quote: { ...quotedRecord().quote, expires_at: "2020-01-01T00:00:00Z" },
  });
  assert.equal(assertLimousineQuoteAcceptable(expired, { nowIso: "2026-08-17T10:00:00Z" }).reason, R.QUOTE_EXPIRED);
  for (const state of [S.WITHDRAWN, S.DECLINED, S.SUPERSEDED, S.EXPIRED, S.CANCELLED, S.REQUESTED]) {
    const rec = quotedRecord({ state });
    assert.equal(assertLimousineQuoteAcceptable(rec, {}).ok, false, state);
    assert.equal(assertLimousineQuoteAcceptable(rec, {}).reason, R.NOT_ACCEPTABLE_STATE, state);
  }
  // Acceptance at a stale revision is rejected.
  assert.equal(
    assertLimousineQuoteAcceptable(quotedRecord(), { expectedRevision: 2 }).reason,
    R.STALE_REVISION,
  );
});

test("13) acceptance binds to exact amount, currency, itinerary, extras and terms", () => {
  const record = quotedRecord();
  const binding = buildLimousineAcceptanceBinding(record);
  assert.equal(binding.total_incl_vat_cents, 45000);
  assert.equal(binding.currency, "EUR");
  assert.equal(binding.terms_revision, 3);
  assert.equal(binding.offer_id, "off_1");
  assert.equal(binding.quote_revision, 3);
  assert.equal(binding.vat_treatment, "incl");
  assert.equal(binding.offer_source_revision, 7);
  assert.equal(binding.pricing_section_revision, 5);
  assert.equal(binding.expires_at, "2099-01-01T00:00:00Z");
  assert.equal(binding.itinerary_fingerprint, record.request.itinerary_fingerprint);
  // Any change to the authoritative record invalidates the binding.
  const changedAmount = buildLimousineAcceptanceBinding({
    ...record,
    quote: { ...record.quote, total_incl_vat_cents: 46000 },
  });
  assert.equal(limousineAcceptanceBindingMatches(binding, changedAmount).ok, false);
  const changedTerms = buildLimousineAcceptanceBinding({
    ...record,
    quote: { ...record.quote, terms_revision: 4 },
  });
  assert.equal(limousineAcceptanceBindingMatches(binding, changedTerms).mismatched_field, "terms_revision");
});

test("14) sealed acceptance reference: opaque, tamper-evident and expiring", async () => {
  const binding = buildLimousineAcceptanceBinding(quotedRecord());
  const sealed = await sealLimousineAcceptance({
    secret: SECRET,
    binding,
    acceptedAtIso: "2026-08-17T10:00:00Z",
    ttlMinutes: 60,
  });
  assert.equal(sealed.ok, true);
  // Opaque: the customer-facing string is not readable JSON.
  assert.ok(!sealed.reference.includes("total_incl_vat_cents"));

  const good = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: sealed.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(good.ok, true);
  assert.equal(good.binding.total_incl_vat_cents, 45000);

  // Tampered ciphertext fails authentication.
  const [v, iv, ct] = sealed.reference.split(".");
  const tampered = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: `${v}.${iv}.${(ct[0] === "A" ? "B" : "A")}${ct.slice(1)}`,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(tampered.ok, false);
  assert.equal(tampered.error, LIMOUSINE_ACCEPTANCE_ERRORS.BAD_SIGNATURE);

  // A different usable secret cannot decrypt.
  const wrongSecret = await unsealLimousineAcceptance({
    secret: "other-secret-value-16",
    reference: sealed.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(wrongSecret.error, LIMOUSINE_ACCEPTANCE_ERRORS.BAD_SIGNATURE);

  // Expiry is enforced.
  const expired = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: sealed.reference,
    nowIso: "2026-08-18T10:30:00Z",
  });
  assert.equal(expired.error, LIMOUSINE_ACCEPTANCE_ERRORS.EXPIRED);

  // Malformed input fails closed.
  assert.equal(
    (await unsealLimousineAcceptance({ secret: SECRET, reference: "garbage" })).error,
    LIMOUSINE_ACCEPTANCE_ERRORS.MALFORMED,
  );
});

test("18/19) operational legs reconcile exactly and never duplicate mobilisation", () => {
  const total = {
    vat_rate: 0.06,
    total_incl_vat_cents: 43000,
    components: [
      { type: LIMOUSINE_COMPONENT_TYPES.MAIN_JOURNEY, amount_cents: 18000 },
      { type: LIMOUSINE_COMPONENT_TYPES.RETURN_JOURNEY, amount_cents: 17000 },
      { type: LIMOUSINE_COMPONENT_TYPES.PAID_EXTRA, amount_cents: 2500 },
      { type: LIMOUSINE_COMPONENT_TYPES.MOBILISATION_OUTBOUND, amount_cents: 3000 },
      { type: LIMOUSINE_COMPONENT_TYPES.MOBILISATION_RETURN, amount_cents: 2500 },
    ],
  };
  const allocation = allocateLimousineOperationalLegs(total);
  assert.equal(allocation.has_return_leg, true);
  // Return leg carries only its own journey + return mobilisation.
  assert.equal(allocation.return.incl_cents, 17000 + 2500);
  // Outbound carries the rest and absorbs any rounding delta.
  assert.equal(allocation.outbound.incl_cents, 43000 - (17000 + 2500));
  const proof = limousineLegsReconcile(allocation);
  assert.equal(proof.ok, true);
  assert.equal(proof.sum_matches, true);
  assert.equal(proof.mobilisation_not_duplicated, true);
  assert.equal(proof.outbound_cents + proof.return_cents, 43000);

  // A rounding delta is absorbed without breaking reconciliation.
  const rounded = allocateLimousineOperationalLegs({ ...total, total_incl_vat_cents: 43010 });
  assert.equal(rounded.rounding_delta_cents, 10);
  assert.equal(limousineLegsReconcile(rounded).sum_matches, true);

  // One-way keeps a single leg.
  const oneWay = allocateLimousineOperationalLegs({
    vat_rate: 0.06,
    total_incl_vat_cents: 20000,
    components: [{ type: LIMOUSINE_COMPONENT_TYPES.MAIN_JOURNEY, amount_cents: 20000 }],
  });
  assert.equal(oneWay.has_return_leg, false);
  assert.equal(limousineLegsReconcile(oneWay).ok, true);
});

test("23) audit trail is privacy-minimized and immutable", () => {
  const entry = buildLimousineQuoteAuditEntry({
    from: S.QUOTED,
    to: S.ACCEPTED,
    revision: 4,
    actorType: "customer",
    reasonCode: "customer_accepted",
    nowIso: "2026-08-17T10:00:00Z",
    amountCents: 45000,
    currency: "EUR",
    termsRevision: 3,
  });
  const keys = Object.keys(entry);
  for (const forbidden of LIMOUSINE_AUDIT_FORBIDDEN_KEYS) {
    assert.ok(!keys.includes(forbidden), forbidden);
  }
  assert.equal(entry.actor_type, "customer");
  assert.equal(entry.amount_cents, 45000);
  // An unknown actor collapses to "system" rather than being echoed.
  assert.equal(buildLimousineQuoteAuditEntry({ actorType: "hacker" }).actor_type, "system");
  // Appending never rewrites history.
  const first = appendLimousineQuoteAudit({ audit: [] }, entry);
  const second = appendLimousineQuoteAudit(first, { ...entry, to: S.BOOKING_CREATED });
  assert.equal(second.audit.length, 2);
  assert.equal(second.audit[0].to_state, S.ACCEPTED);
});

test("5/7/15/16/17/20/21/22/24) worker wiring: auth, gates, isolation, preservation", () => {
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  // Every manual-quote route is gated and returns before touching KV.
  const routes = [
    '"/limousine/quote-requests" && request.method === "POST"',
    '"/admin/limousine/quote-requests/respond" && request.method === "POST"',
    '"/limousine/quote-requests/accept" && request.method === "POST"',
  ];
  for (const route of routes) assert.ok(worker.includes(route), route);
  assert.ok(worker.includes('return json({ ok: false, error: "manual_quote_gate_off" }, 404);'));
  // Company response requires an authenticated, scope-matched company.
  assert.ok(worker.includes("ADMIN_LIMOUSINE_QUOTE_RESPOND"));
  assert.ok(worker.includes('return json({ ok: false, error: "unauthorized_scope" }, 403);'));
  // Accepted manual quote enters the SHARED /book lifecycle.
  assert.ok(worker.includes("_prepareLimousineManualBooking"));
  assert.ok(worker.includes("_unsealLimousineAcceptance({"));
  assert.ok(worker.includes("_limousineAcceptanceBindingMatches(binding, expected)"));
  // Re-validates eligibility for NEW bookings after acceptance.
  assert.ok(/_prepareLimousineManualBooking[\s\S]*?_assertFluxidiCompanyCanCreateNewBooking/.test(worker));
  assert.ok(/_prepareLimousineManualBooking[\s\S]*?_resolveLimousineProviderEligibility/.test(worker));
  // The human total is never recomputed with taxi pricing.
  const manualStart = worker.indexOf("async function _prepareLimousineManualBooking");
  const manualEnd = worker.indexOf("/// LIMOUSINE-MARKETPLACE-P2C1: /book pre-flight");
  const manualBody = worker.slice(manualStart, manualEnd);
  for (const forbidden of ["calcPrice(", "resolveAirportFixedFare(", "directTripTotals", "composeLimousineTotal"]) {
    assert.ok(!manualBody.includes(forbidden), `manual path must not use ${forbidden}`);
  }
  // Booking creation closes the lifecycle idempotently and keeps the snapshot.
  assert.ok(worker.includes("to: _LIMOUSINE_QUOTE_STATES.BOOKING_CREATED"));
  assert.ok(worker.includes("limousine_accepted_price: _limousineAccepted.snapshot"));
  // Existing booking idempotency is untouched.
  assert.ok(worker.includes("buildBookingIntentDescriptor({"));
  // New requests are blocked for suspended companies but existing data is kept.
  assert.ok(/\/limousine\/quote-requests[\s\S]*?_assertFluxidiCompanyCanCreateNewBooking/.test(worker));
  // Operational legs split for a limousine roundtrip.
  assert.ok(worker.includes("_allocateLimousineOperationalLegs(_limousineAccepted.total)"));
  assert.ok(worker.includes("returnEnabled: _limousineHasReturnLeg ? true : ret.enabled"));
  // Taxi/airport untouched: no limousine symbol inside calcPrice.
  const calcStart = worker.indexOf("function calcPrice({");
  const calcEnd = worker.indexOf("function buildNote(");
  if (calcStart > 0 && calcEnd > calcStart) {
    assert.ok(!worker.slice(calcStart, calcEnd).includes("limousine"));
  }
});

test("P3J) public view projects quotation availability without snapshot payload", async () => {
  const legacy = publicLimousineQuoteView(quotedRecord());
  assert.equal(legacy.quotation_available, false);
  assert.equal(legacy.quotation_snapshots, undefined);
  assert.equal(legacy.content_hash, undefined);
  const snap = await buildLimousineQuotationSnapshot({
    quoteRequestId: "limq_1",
    quoteRevision: 3,
    termsRevision: 3,
    issuedAt: "2026-08-17T10:00:00Z",
    expiresAt: "2099-01-01T00:00:00Z",
    locale: "nl",
    sellerSnapshot: { legal_name: "Coachline BV" },
    requestSnapshot: quotedRecord().request,
    vehicleSnapshot: { public_name: "Executive sedan" },
    offerSnapshot: quotedRecord().quote,
  });
  const withSnap = attachLimousineQuotationSnapshot(quotedRecord(), snap).record;
  const view = publicLimousineQuoteView(withSnap);
  assert.equal(view.quotation_available, true);
  assert.equal(view.quotation_revision, 3);
  assert.equal(view.content_hash, undefined);
  assert.equal(view.quotation_snapshots, undefined);
  assert.equal(JSON.stringify(view).includes(snap.content_hash), false);
});

test("P3J) re-quote keeps earlier snapshots on the live record", async () => {
  const snap = await buildLimousineQuotationSnapshot({
    quoteRequestId: "limq_1",
    quoteRevision: 3,
    termsRevision: 3,
    issuedAt: "2026-08-17T10:00:00Z",
    expiresAt: "2099-01-01T00:00:00Z",
    locale: "nl",
    sellerSnapshot: { legal_name: "Coachline BV" },
    requestSnapshot: quotedRecord().request,
    vehicleSnapshot: { public_name: "Executive sedan" },
    offerSnapshot: quotedRecord().quote,
  });
  const seeded = attachLimousineQuotationSnapshot(quotedRecord(), snap).record;
  const nextQuote = validateLimousineCompanyQuote(
    {
      total_incl_vat_cents: 52000,
      currency: "EUR",
      terms: { ...TERMS, terms_revision: 4 },
      expires_at: "2099-02-01T00:00:00Z",
    },
    { nowIso: "2026-08-17T12:00:00Z" },
  );
  const requote = applyLimousineCompanyQuoteAction(seeded, {
    expectedRevision: 3,
    quote: nextQuote.quote,
    nowIso: "2026-08-17T12:00:00Z",
  });
  assert.equal(requote.ok, true);
  assert.equal(requote.record.quotation_snapshots["3"].content_hash, snap.content_hash);
  assert.equal(requote.record.quotation_snapshots["3"].totals_snapshot.total_incl_vat_cents, 45000);
});

test("P3J) quote-send attaches snapshots; decline/viewed/accept/book do not", () => {
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  const respondStart = worker.indexOf('"/admin/limousine/quote-requests/respond" && request.method === "POST"');
  const respondEnd = worker.indexOf('"/limousine/quote-requests/accept" && request.method === "POST"');
  const respond = worker.slice(respondStart, respondEnd);
  const quoteBlock = respond.slice(respond.indexOf('if (action !== "quote")'));
  assert.ok(quoteBlock.includes("_attachLimousineQuotationSnapshotAtSend"));
  const decline = respond.slice(
    respond.indexOf('if (action === "decline")'),
    respond.indexOf('if (action === "viewed")'),
  );
  assert.ok(!decline.includes("_attachLimousineQuotationSnapshotAtSend"));
  const viewed = respond.slice(
    respond.indexOf('if (action === "viewed")'),
    respond.indexOf('if (action !== "quote")'),
  );
  assert.ok(!viewed.includes("_attachLimousineQuotationSnapshotAtSend"));
  const acceptStart = worker.indexOf('"/limousine/quote-requests/accept" && request.method === "POST"');
  const acceptEnd = worker.indexOf("LIMOUSINE-MARKETPLACE-P2C2A — company inbox list");
  const accept = worker.slice(acceptStart, acceptEnd);
  assert.ok(!accept.includes("_attachLimousineQuotationSnapshotAtSend"));
  assert.ok(accept.includes("_buildLimousineAcceptanceBindingFromSnapshot"));
  assert.ok(!worker.includes("/limousine/quote-requests/reject"));
  assert.ok(!worker.includes("customer_rejected"));
  const bookStart = worker.indexOf("async function _prepareLimousineManualBooking");
  const bookEnd = worker.indexOf("/// LIMOUSINE-MARKETPLACE-P2C1: /book pre-flight");
  const book = worker.slice(bookStart, bookEnd);
  assert.ok(!book.includes("_attachLimousineQuotationSnapshotAtSend"));
  assert.ok(book.includes("quotation_content_hash"));
});
