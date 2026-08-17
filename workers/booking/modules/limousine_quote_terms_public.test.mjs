// LIMOUSINE-MARKETPLACE-P2D1A — public quote terms projection and re-quote.
// Run: node --test workers/booking/modules/limousine_quote_terms_public.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_ACCEPTANCE_KEY_PURPOSE,
  LIMOUSINE_STATUS_KEY_PURPOSE,
} from "./limousine_aead_token.mjs";
import {
  LIMOUSINE_ACCEPTANCE_TOKEN_VERSION,
  limousineAcceptanceBindingMatches,
  sealLimousineAcceptance,
  unsealLimousineAcceptance,
} from "./limousine_acceptance_token.mjs";
import {
  LIMOUSINE_PUBLIC_FORBIDDEN_KEYS,
  LIMOUSINE_QUOTE_REASONS,
  LIMOUSINE_QUOTE_STATES,
  LIMOUSINE_REQUIRED_TERMS_KEYS,
  applyLimousineCompanyQuoteAction,
  applyLimousineQuoteTransition,
  assertLimousineQuoteAcceptable,
  buildLimousineAcceptanceBinding,
  canTransitionLimousineQuote,
  evaluateLimousineQuoteAcceptanceReadiness,
  isLimousineCommercialCompanyAction,
  limousineManualQuoteGateEnabled,
  publicLimousineQuoteView,
  validateLimousineCompanyQuote,
  validateLimousineQuoteRequest,
  buildLimousineCustomerFingerprint,
} from "./limousine_manual_quote.mjs";
import {
  LIMOUSINE_INBOX_FORBIDDEN_KEYS,
  buildLimousineCompanyInboxView,
  executeLimousineStatusRead,
  projectionContainsForbiddenKey,
} from "./limousine_quote_inbox.mjs";
import { sealLimousineStatusRef } from "./limousine_status_token.mjs";

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
  included_services: [{ item_id: "water", label: { en: "Still water", nl: "Plat water" } }],
  paid_extras: [{
    extra_id: "wait",
    label: { en: "Extra wait", nl: "Extra wachten" },
    amount_cents: 2500,
    quote_required: false,
  }],
  mobilisation_disclosure: { en: "Mobilisation included", nl: "Mobilisatie inbegrepen" },
  customer_obligations: { en: "Be ready at the pickup point", nl: "Klaarstaan op de ophaallocatie" },
  important_information: { en: "No smoking", nl: "Niet roken" },
};

function offer() {
  return {
    offer_id: "off_1",
    enabled: true,
    published: true,
    service_class_id: "executive_sedan",
    vehicle_id: "veh_1",
    paid_extras: [
      { extra_id: "wait", active: true, public: true, quote_required: false, amount_cents: 2500 },
    ],
    source_revision: 7,
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
    selected_extra_ids: ["wait"],
    locale: "nl",
    ...overrides,
  };
}

function companyQuoteInput(overrides = {}, termsOverrides = {}) {
  return {
    total_incl_vat_cents: 45000,
    currency: "EUR",
    vat_treatment: "incl",
    vat_rate: 0.06,
    public_text: { nl: "Vaste prijs", en: "Fixed price" },
    expires_at: "2099-01-01T00:00:00Z",
    terms: { ...TERMS, ...termsOverrides },
    ...overrides,
  };
}

function validatedQuote(overrides = {}, termsOverrides = {}) {
  const out = validateLimousineCompanyQuote(companyQuoteInput(overrides, termsOverrides), {
    nowIso: "2026-08-17T10:00:00Z",
  });
  assert.equal(out.ok, true, out.reason);
  return out.quote;
}

function requestedRecord(overrides = {}) {
  const validated = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: offer(),
    gateEnabled: true,
  });
  return {
    quote_request_id: "limq_1",
    tenant_id: "t1",
    company_id: "c1",
    state: S.REQUESTED,
    revision: 1,
    last_transition_to: S.REQUESTED,
    request: validated.request,
    offer_source_revision: 7,
    pricing_section_revision: 5,
    audit: [],
    created_at: "2026-08-17T09:00:00Z",
    updated_at: "2026-08-17T09:00:00Z",
    ...overrides,
  };
}

function quotedRecord(overrides = {}, quoteOverrides = {}, termsOverrides = {}) {
  const base = requestedRecord();
  return {
    ...base,
    state: S.CUSTOMER_ACCEPTANCE_REQUIRED,
    revision: 3,
    last_transition_from: S.QUOTED,
    last_transition_to: S.CUSTOMER_ACCEPTANCE_REQUIRED,
    quote: validatedQuote(quoteOverrides, termsOverrides),
    ...overrides,
  };
}

function collectKeys(value, into = new Set()) {
  if (Array.isArray(value)) {
    for (const item of value) collectKeys(item, into);
    return into;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      into.add(key);
      collectKeys(child, into);
    }
  }
  return into;
}

function simulateManualBookPreflight(record, unsealedBinding) {
  const writes = [];
  const fail = (error, extra = {}) => ({
    ok: false,
    wrote: writes.length > 0,
    writes,
    error,
    ...extra,
  });
  if (String(record.state || "") !== S.ACCEPTED) {
    return fail("limousine_quote_not_accepted", { state: record.state });
  }
  const expected = buildLimousineAcceptanceBinding(record);
  const match = limousineAcceptanceBindingMatches(unsealedBinding, expected);
  if (!match.ok) {
    return fail("limousine_quote_refresh_required", { mismatched_field: match.mismatched_field });
  }
  writes.push("booking_intent");
  return { ok: true, wrote: true, writes };
}

test("1/2) complete safe terms appear and every required category is mapped", () => {
  const rec = quotedRecord();
  const view = publicLimousineQuoteView(rec, { nowIso: "2026-08-17T10:00:00Z" });
  assert.equal(view.acceptance_allowed, true);
  assert.equal(view.acceptance_blocked_reason, undefined);
  const terms = view.quote.terms;
  for (const key of LIMOUSINE_REQUIRED_TERMS_KEYS) {
    assert.equal(typeof terms[key], "number", key);
    assert.ok(terms[key] >= 0, key);
  }
  assert.equal(terms.terms_revision, 3);
  assert.equal(view.quote.terms_revision, 3);
  assert.equal(terms.cancellation_deadline_hours, 24);
  assert.equal(terms.cancellation_penalty_percent, 50);
  assert.equal(terms.waiting_time_included_minutes, 15);
  assert.equal(terms.waiting_time_overage_cents_per_minute, 100);
  assert.equal(terms.no_show_penalty_percent, 100);
  assert.equal(terms.overtime_cents_per_hour, 9000);
  assert.equal(terms.included_services[0].item_id, "water");
  assert.equal(terms.paid_extras[0].amount_cents, 2500);
  assert.equal(terms.mobilisation_disclosure.en, "Mobilisation included");
  assert.equal(terms.customer_obligations.nl, "Klaarstaan op de ophaallocatie");
  assert.equal(terms.important_information.en, "No smoking");
  assert.equal(view.quote.total_incl_vat_cents, 45000);
  assert.equal(view.quote.currency, "EUR");
  assert.equal(view.quote.vat_treatment, "incl");
  assert.equal(view.quote.expires_at, "2099-01-01T00:00:00Z");
  assert.equal(view.quote.public_text.en, "Fixed price");
});

test("3-7) missing booking-critical terms block acceptance without omitting the key", () => {
  const cases = [
    ["cancellation_deadline_hours", "cancellation"],
    ["waiting_time_included_minutes", "waiting"],
    ["no_show_penalty_percent", "no-show"],
    ["overtime_cents_per_hour", "overtime"],
    ["terms_revision", "terms revision"],
  ];
  for (const [key] of cases) {
    const rec = quotedRecord();
    const terms = { ...rec.quote.terms };
    delete terms[key];
    const next = {
      ...rec,
      quote: {
        ...rec.quote,
        terms,
        ...(key === "terms_revision" ? { terms_revision: 0 } : {}),
      },
    };
    const view = publicLimousineQuoteView(next, { nowIso: "2026-08-17T10:00:00Z" });
    assert.equal(view.acceptance_allowed, false, key);
    assert.equal(view.acceptance_blocked_reason, R.QUOTE_TERMS_INCOMPLETE, key);
    assert.ok(view.missing_terms.includes(key), key);
    assert.ok(Object.prototype.hasOwnProperty.call(view.quote.terms, key), `present ${key}`);
    assert.equal(view.quote.terms[key], null, `null ${key}`);
    assert.equal(assertLimousineQuoteAcceptable(next).ok, false, key);
    assert.equal(assertLimousineQuoteAcceptable(next).reason, R.QUOTE_TERMS_INCOMPLETE, key);
  }
});

test("8) invalid money or currency blocks acceptance", () => {
  const storedBadAmount = {
    ...quotedRecord(),
    quote: { ...quotedRecord().quote, total_incl_vat_cents: -100 },
  };
  const amountView = publicLimousineQuoteView(storedBadAmount);
  assert.equal(amountView.acceptance_allowed, false);
  assert.equal(amountView.acceptance_blocked_reason, R.INVALID_AMOUNT);
  assert.equal(assertLimousineQuoteAcceptable(storedBadAmount).reason, R.INVALID_AMOUNT);

  const storedBadCurrency = {
    ...quotedRecord(),
    quote: { ...quotedRecord().quote, currency: "EU" },
  };
  const currencyView = publicLimousineQuoteView(storedBadCurrency);
  assert.equal(currencyView.acceptance_allowed, false);
  assert.equal(currencyView.acceptance_blocked_reason, R.INVALID_CURRENCY);
  assert.equal(assertLimousineQuoteAcceptable(storedBadCurrency).reason, R.INVALID_CURRENCY);
});

test("9) unknown critical field blocks acceptance", () => {
  const rec = quotedRecord();
  const next = {
    ...rec,
    quote: {
      ...rec.quote,
      terms: { ...rec.quote.terms, internal_cost: 12000, margin: 4000 },
    },
  };
  const view = publicLimousineQuoteView(next);
  assert.equal(view.acceptance_allowed, false);
  assert.equal(view.acceptance_blocked_reason, R.UNKNOWN_CRITICAL_FIELD);
  assert.equal(assertLimousineQuoteAcceptable(next).reason, R.UNKNOWN_CRITICAL_FIELD);
  assert.equal(view.quote.terms.internal_cost, undefined);
  assert.equal(view.quote.terms.margin, undefined);
});

test("10) no internal or private fields enter the public DTO", () => {
  const rec = {
    ...quotedRecord(),
    email: "hidden@example.com",
    phone: "+320000",
    customer_name: "Ada",
    customer_reference: "cust_secret",
    operating_base_address: "Geheimestraat 1",
    internal_cost: 9000,
    margin: 3000,
    audit: [{ secret: "nope" }],
    status_access: { customer_fingerprint: "limcf_hidden", token: "leak" },
    acceptance_reference: "limacc1.should.not.leak",
    authorization: "Bearer x",
  };
  const view = publicLimousineQuoteView(rec);
  const inbox = buildLimousineCompanyInboxView(rec, { activity_seq: 1 });
  const keys = collectKeys(view);
  for (const forbidden of [
    ...LIMOUSINE_PUBLIC_FORBIDDEN_KEYS,
    ...LIMOUSINE_INBOX_FORBIDDEN_KEYS,
  ]) {
    assert.equal(keys.has(forbidden), false, forbidden);
  }
  assert.equal(view.itinerary_fingerprint, undefined);
  assert.equal(view.quote.vat_rate_source, undefined);
  assert.equal(view.acceptance_reference, undefined);
  assert.equal(view.status_ref, undefined);
  const leaked = projectionContainsForbiddenKey(view);
  assert.deepEqual(leaked, [], leaked.join(","));
  assert.deepEqual(projectionContainsForbiddenKey(inbox), [], "inbox");
  const rendered = JSON.stringify(view);
  assert.ok(!rendered.includes("Geheimestraat"));
  assert.ok(!rendered.includes("hidden@example.com"));
  assert.ok(!rendered.includes("limcf_hidden"));
});

test("11) historical view stays readable when acceptance is blocked", () => {
  const rec = quotedRecord({ state: S.DECLINED, decline: { reason_code: "company_declined" } });
  const terms = { ...rec.quote.terms };
  delete terms.cancellation_deadline_hours;
  const next = { ...rec, quote: { ...rec.quote, terms } };
  const before = JSON.stringify(next);
  const view = publicLimousineQuoteView(next);
  assert.equal(JSON.stringify(next), before);
  assert.equal(view.acceptance_allowed, false);
  assert.equal(view.acceptance_blocked_reason, R.QUOTE_TERMS_INCOMPLETE);
  assert.equal(view.quote.total_incl_vat_cents, 45000);
  assert.equal(view.quote.terms.cancellation_deadline_hours, null);
  assert.equal(view.quote.terms.waiting_time_included_minutes, 15);
  assert.equal(view.state, S.DECLINED);
  assert.equal(view.decline.reason_code, "company_declined");
});

test("12) first quote follows requested → quoted → customer_acceptance_required", () => {
  const rec = requestedRecord();
  const quote = validatedQuote();
  const out = applyLimousineCompanyQuoteAction(rec, {
    expectedRevision: 1,
    quote,
    nowIso: "2026-08-17T10:00:00Z",
  });
  assert.equal(out.ok, true);
  assert.equal(out.changed, true);
  assert.equal(out.record.state, S.CUSTOMER_ACCEPTANCE_REQUIRED);
  assert.equal(out.record.revision, 3);
  assert.equal(out.record.superseded_revision, undefined);
  assert.equal(out.audits.length, 2);
  assert.equal(out.audits[0].from_state, S.REQUESTED);
  assert.equal(out.audits[0].to_state, S.QUOTED);
  assert.equal(out.audits[1].from_state, S.QUOTED);
  assert.equal(out.audits[1].to_state, S.CUSTOMER_ACCEPTANCE_REQUIRED);
  assert.equal(canTransitionLimousineQuote(S.REQUESTED, S.QUOTED), true);
  assert.equal(canTransitionLimousineQuote(S.QUOTED, S.CUSTOMER_ACCEPTANCE_REQUIRED), true);
});

test("13/14/15) valid re-quote uses CAR → quoted → CAR and increments both revisions", () => {
  const rec = quotedRecord();
  const replacement = validatedQuote(
    { total_incl_vat_cents: 52000 },
    { terms_revision: 4, cancellation_penalty_percent: 60 },
  );
  const out = applyLimousineCompanyQuoteAction(rec, {
    expectedRevision: 3,
    quote: replacement,
    nowIso: "2026-08-17T11:00:00Z",
  });
  assert.equal(out.ok, true);
  assert.equal(out.record.state, S.CUSTOMER_ACCEPTANCE_REQUIRED);
  assert.equal(out.record.revision, 5);
  assert.equal(out.record.superseded_revision, 3);
  assert.equal(out.record.quote.terms_revision, 4);
  assert.equal(out.record.quote.total_incl_vat_cents, 52000);
  assert.equal(out.audits[0].from_state, S.CUSTOMER_ACCEPTANCE_REQUIRED);
  assert.equal(out.audits[0].to_state, S.QUOTED);
  assert.equal(out.audits[1].to_state, S.CUSTOMER_ACCEPTANCE_REQUIRED);
  const view = publicLimousineQuoteView(out.record, { nowIso: "2026-08-17T11:00:00Z" });
  assert.equal(view.quote.total_incl_vat_cents, 52000);
  assert.equal(view.quote.terms_revision, 4);
  assert.equal(view.quote.terms.cancellation_penalty_percent, 60);
  assert.equal(view.revision, 5);
  const inbox = buildLimousineCompanyInboxView(out.record);
  assert.equal(inbox.quote.terms_revision, view.quote.terms_revision);
  assert.equal(inbox.revision, view.revision);
});

test("16/23) older limacc1 fails after re-quote before /book writes", async () => {
  const rec = quotedRecord();
  const oldBinding = buildLimousineAcceptanceBinding(rec);
  const sealed = await sealLimousineAcceptance({
    secret: SECRET,
    binding: oldBinding,
    acceptedAtIso: "2026-08-17T10:00:00Z",
    ttlMinutes: 60,
  });
  assert.equal(sealed.ok, true);
  assert.match(sealed.reference, /^limacc1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
  assert.ok(!sealed.reference.includes("total_incl_vat_cents"));

  const replacement = validatedQuote({ total_incl_vat_cents: 52000 }, { terms_revision: 4 });
  const requote = applyLimousineCompanyQuoteAction(rec, {
    expectedRevision: 3,
    quote: replacement,
    nowIso: "2026-08-17T11:00:00Z",
  });
  assert.equal(requote.ok, true);

  const opened = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: sealed.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(opened.ok, true);
  const match = limousineAcceptanceBindingMatches(
    opened.binding,
    buildLimousineAcceptanceBinding(requote.record),
  );
  assert.equal(match.ok, false);
  assert.ok(["quote_revision", "terms_revision", "total_incl_vat_cents"].includes(match.mismatched_field));

  const preflight = simulateManualBookPreflight(requote.record, opened.binding);
  assert.equal(preflight.ok, false);
  assert.equal(preflight.error, "limousine_quote_not_accepted");
  assert.equal(preflight.wrote, false);
  assert.deepEqual(preflight.writes, []);

  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  const bookStart = worker.indexOf("if (_isLimousineServiceRequest(payload) || _limousineAcceptanceReference)");
  const intentStart = worker.indexOf("const bookingIntent = buildBookingIntentDescriptor({");
  const prepareAt = worker.indexOf("const manual = await _prepareLimousineManualBooking(");
  assert.ok(bookStart > 0 && prepareAt > bookStart && intentStart > prepareAt);
  const prepareBody = worker.slice(
    worker.indexOf("async function _prepareLimousineManualBooking"),
    worker.indexOf("/// LIMOUSINE-MARKETPLACE-P2C1: /book pre-flight"),
  );
  assert.ok(prepareBody.includes('state !== _LIMOUSINE_QUOTE_STATES.ACCEPTED'));
  assert.ok(prepareBody.includes("_limousineAcceptanceBindingMatches(binding, expected)"));
  assert.ok(!prepareBody.includes("buildBookingIntentDescriptor"));
});

test("17) stale expected_revision writes nothing", () => {
  const rec = quotedRecord();
  const snapshot = JSON.stringify(rec);
  const replacement = validatedQuote({ total_incl_vat_cents: 52000 }, { terms_revision: 4 });
  for (const expected of [2, 4]) {
    const out = applyLimousineCompanyQuoteAction(rec, {
      expectedRevision: expected,
      quote: replacement,
    });
    assert.equal(out.ok, false, String(expected));
    assert.equal(out.reason, R.STALE_REVISION);
    assert.equal(out.current_revision, 3);
  }
  assert.equal(JSON.stringify(rec), snapshot);
});

test("18) identical replay is idempotent", () => {
  const rec = quotedRecord();
  const out = applyLimousineCompanyQuoteAction(rec, {
    expectedRevision: 3,
    quote: rec.quote,
    nowIso: "2026-08-17T12:00:00Z",
  });
  assert.equal(out.ok, true);
  assert.equal(out.changed, false);
  assert.equal(out.reason, R.IDEMPOTENT_REPLAY);
  assert.equal(out.record.revision, 3);
  assert.equal(out.record.state, S.CUSTOMER_ACCEPTANCE_REQUIRED);
});

test("19) accepted quote cannot be superseded", () => {
  const rec = quotedRecord();
  const accepted = applyLimousineQuoteTransition(rec, {
    to: S.ACCEPTED,
    expectedRevision: 3,
    actorType: "customer",
    reasonCode: "customer_accepted",
  });
  assert.equal(accepted.ok, true);
  const out = applyLimousineCompanyQuoteAction(accepted.record, {
    expectedRevision: accepted.record.revision,
    quote: validatedQuote({ total_incl_vat_cents: 52000 }, { terms_revision: 4 }),
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, R.INVALID_TRANSITION);
  assert.equal(canTransitionLimousineQuote(S.ACCEPTED, S.QUOTED), false);
  assert.equal(canTransitionLimousineQuote(S.ACCEPTED, S.SUPERSEDED), false);
});

test("20) booking_created and terminal records cannot be re-quoted", () => {
  for (const state of [
    S.BOOKING_CREATED,
    S.DECLINED,
    S.EXPIRED,
    S.WITHDRAWN,
    S.SUPERSEDED,
    S.CANCELLED,
  ]) {
    const rec = quotedRecord({ state });
    const out = applyLimousineCompanyQuoteAction(rec, {
      expectedRevision: 3,
      quote: validatedQuote({ total_incl_vat_cents: 52000 }, { terms_revision: 4 }),
    });
    assert.equal(out.ok, false, state);
    assert.equal(out.reason, R.INVALID_TRANSITION, state);
  }
});

test("21) suspension blocks re-quote commercially and preserves reads", () => {
  assert.equal(isLimousineCommercialCompanyAction("quote"), true);
  assert.equal(isLimousineCommercialCompanyAction("viewed"), false);
  const rec = quotedRecord();
  const view = publicLimousineQuoteView(rec);
  assert.equal(view.quote.total_incl_vat_cents, 45000);
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  const respondStart = worker.indexOf('url.pathname === "/admin/limousine/quote-requests/respond"');
  const respondEnd = worker.indexOf('url.pathname === "/limousine/quote-requests/accept"');
  const respond = worker.slice(respondStart, respondEnd);
  assert.ok(respond.includes("_isLimousineCommercialCompanyAction(action)"));
  assert.ok(respond.includes("_assertFluxidiCompanyCanCreateNewBooking"));
  assert.ok(respond.includes("_applyLimousineCompanyQuoteAction"));
});

test("22) acceptance reference stays AES-GCM with purpose separation", async () => {
  const rec = quotedRecord();
  const sealed = await sealLimousineAcceptance({
    secret: SECRET,
    binding: buildLimousineAcceptanceBinding(rec),
    acceptedAtIso: "2026-08-17T10:00:00Z",
  });
  assert.equal(sealed.ok, true);
  const parts = sealed.reference.split(".");
  assert.equal(parts[0], LIMOUSINE_ACCEPTANCE_TOKEN_VERSION);
  assert.equal(parts.length, 3);
  assert.ok(!sealed.reference.includes("{"));
  const opened = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: sealed.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(opened.ok, true);
  assert.equal(LIMOUSINE_ACCEPTANCE_KEY_PURPOSE, "limousine_acceptance_reference_v1");
  assert.notEqual(LIMOUSINE_ACCEPTANCE_KEY_PURPOSE, LIMOUSINE_STATUS_KEY_PURPOSE);
  const hmacLegacy = `${LIMOUSINE_ACCEPTANCE_TOKEN_VERSION}.${Buffer.from("{}").toString("base64url")}.deadbeef`;
  const rejected = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: hmacLegacy,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(rejected.ok, false);
});

test("15b) status polling and company inbox see the same newest quote", async () => {
  const rec = quotedRecord();
  const replacement = validatedQuote({ total_incl_vat_cents: 61000 }, { terms_revision: 5 });
  const requote = applyLimousineCompanyQuoteAction(rec, {
    expectedRevision: 3,
    quote: replacement,
    nowIso: "2026-08-17T11:00:00Z",
  });
  const fingerprint = buildLimousineCustomerFingerprint({
    tenantId: "t1",
    companyId: "c1",
    customerRef: "cust_1",
    quoteRequestId: "limq_1",
    itineraryFingerprint: requote.record.request.itinerary_fingerprint,
  });
  const live = {
    ...requote.record,
    status_access: {
      customer_fingerprint: fingerprint,
      issued_at: "2026-08-17T09:00:00Z",
      expires_at: "2026-09-16T09:00:00Z",
      created_revision: 1,
    },
  };
  const sealed = await sealLimousineStatusRef({
    secret: SECRET,
    binding: {
      purpose: "customer_status",
      tenant_id: "t1",
      company_id: "c1",
      quote_request_id: "limq_1",
      customer_fingerprint: fingerprint,
      created_revision: 1,
    },
    issuedAtIso: "2026-08-17T09:00:00Z",
    ttlMinutes: 60 * 24 * 30,
  });
  const status = await executeLimousineStatusRead({
    body: { status_ref: sealed.reference },
    nowIso: "2026-08-17T11:05:00Z",
    secret: SECRET,
    bookingKvPresent: true,
    rateLimit: async () => ({ limited: false }),
    loadRecord: async () => live,
  });
  const inbox = buildLimousineCompanyInboxView(live);
  assert.equal(status.status, 200);
  assert.equal(status.body.quote_request.quote.total_incl_vat_cents, 61000);
  assert.equal(status.body.quote_request.quote.terms_revision, 5);
  assert.equal(inbox.quote.total_incl_vat_cents, 61000);
  assert.equal(inbox.quote.terms_revision, 5);
  assert.equal(status.body.quote_request.revision, inbox.revision);
});

test("24/25) taxi/airport stay unchanged and all limousine gates remain OFF", () => {
  assert.equal(limousineManualQuoteGateEnabled("0"), false);
  assert.equal(limousineManualQuoteGateEnabled(undefined), false);
  const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");
  assert.ok(wrangler.includes('LIMOUSINE_QUOTE_ENABLED = "0"'));
  assert.ok(wrangler.includes('LIMOUSINE_BOOK_ENABLED = "0"'));
  assert.ok(wrangler.includes('LIMOUSINE_MANUAL_QUOTE_ENABLED = "0"'));
  const dart = readFileSync(
    join(__dirname, "..", "..", "..", "lib", "limousine", "limousine_customer_entry.dart"),
    "utf8",
  );
  assert.ok(dart.includes("FLUXIDI_LIMOUSINE_MARKETPLACE_ENTRY"));
  assert.ok(dart.includes("defaultValue: false"));
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  const calcStart = worker.indexOf("function calcPrice({");
  const calcEnd = worker.indexOf("function buildNote(");
  assert.ok(calcStart > 0 && calcEnd > calcStart);
  assert.ok(!worker.slice(calcStart, calcEnd).includes("limousine"));
  assert.ok(!worker.includes("LIMOUSINE_ACCEPTANCE_SECRET ="));
});

test("re-quote from quoted (pre-CAR) and stale terms revision fail closed", () => {
  const stuck = quotedRecord({
    state: S.QUOTED,
    revision: 2,
    last_transition_to: S.QUOTED,
  });
  const replacement = validatedQuote({ total_incl_vat_cents: 48000 }, { terms_revision: 4 });
  const out = applyLimousineCompanyQuoteAction(stuck, {
    expectedRevision: 2,
    quote: replacement,
    nowIso: "2026-08-17T11:00:00Z",
  });
  assert.equal(out.ok, true);
  assert.equal(out.record.state, S.CUSTOMER_ACCEPTANCE_REQUIRED);
  assert.equal(out.record.superseded_revision, 2);
  assert.equal(out.record.quote.terms_revision, 4);

  const staleTerms = applyLimousineCompanyQuoteAction(quotedRecord(), {
    expectedRevision: 3,
    quote: validatedQuote({ total_incl_vat_cents: 48000 }, { terms_revision: 3 }),
  });
  assert.equal(staleTerms.ok, false);
  assert.equal(staleTerms.reason, R.STALE_TERMS_REVISION);
});

test("acceptance binding still seals tenant, revisions, VAT, extras and expiry", () => {
  const rec = quotedRecord();
  const binding = buildLimousineAcceptanceBinding(rec);
  assert.equal(binding.tenant_id, "t1");
  assert.equal(binding.company_id, "c1");
  assert.equal(binding.quote_request_id, "limq_1");
  assert.equal(binding.quote_revision, 3);
  assert.equal(binding.terms_revision, 3);
  assert.equal(binding.total_incl_vat_cents, 45000);
  assert.equal(binding.currency, "EUR");
  assert.equal(binding.vat_treatment, "incl");
  assert.equal(binding.offer_source_revision, 7);
  assert.equal(binding.pricing_section_revision, 5);
  assert.equal(binding.service_class_id, "executive_sedan");
  assert.equal(binding.vehicle_id, "veh_1");
  assert.deepEqual(binding.selected_extra_ids, ["wait"]);
  assert.equal(binding.expires_at, "2099-01-01T00:00:00Z");
  assert.equal(
    limousineAcceptanceBindingMatches(binding, { ...binding, vat_treatment: "excl" }).mismatched_field,
    "vat_treatment",
  );
  assert.equal(
    limousineAcceptanceBindingMatches(binding, { ...binding, expires_at: "2026-01-01T00:00:00Z" }).mismatched_field,
    "expires_at",
  );
  const ready = evaluateLimousineQuoteAcceptanceReadiness(rec);
  assert.equal(ready.ok, true);
  assert.equal(ready.binding.terms_revision, binding.terms_revision);
});
