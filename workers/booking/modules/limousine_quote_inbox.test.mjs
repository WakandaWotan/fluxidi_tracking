// LIMOUSINE-MARKETPLACE-P2C2A — secure company inbox and customer status reads.
// Run: node --test workers/booking/modules/limousine_quote_inbox.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_QUOTE_REASONS,
  LIMOUSINE_QUOTE_STATES,
  applyLimousineQuoteTransition,
  buildLimousineCustomerFingerprint,
  isLimousineCommercialCompanyAction,
  limousineManualQuoteGateEnabled,
  observeLimousineQuoteExpiry,
  publicLimousineQuoteView,
  validateLimousineCompanyQuote,
  validateLimousineQuoteRequest,
} from "./limousine_manual_quote.mjs";
import {
  LIMOUSINE_STATUS_ERRORS,
  LIMOUSINE_STATUS_TOKEN_VERSION,
  limousineStatusRefLooksWellFormed,
  sealLimousineStatusRef,
  unsealLimousineStatusRef,
} from "./limousine_status_token.mjs";
import {
  LIMOUSINE_INBOX_FORBIDDEN_KEYS,
  LIMOUSINE_INBOX_PAGE_MAX,
  buildLimousineCompanyInboxView,
  emptyLimousineInboxIndex,
  encodeLimousineInboxCursor,
  executeLimousineStatusRead,
  isLimousineGlobalCustomerSession,
  limousineInboxIndexKey,
  limousineStatusRateKey,
  pageLimousineInboxEntries,
  parseLimousineInboxQuery,
  prevalidateLimousineStatusBody,
  projectionContainsForbiddenKey,
  upsertLimousineInboxEntry,
} from "./limousine_quote_inbox.mjs";
import {
  attachLimousineQuotationSnapshot,
  buildLimousineQuotationSnapshot,
} from "./limousine_quotation_snapshot.mjs";
import {
  LIMOUSINE_STATUS_KEY_PURPOSE,
  sealLimousineAead,
} from "./limousine_aead_token.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const S = LIMOUSINE_QUOTE_STATES;
const SECRET = "test-only-status-secret-not-production";

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

function offer() {
  return {
    offer_id: "off_1",
    enabled: true,
    published: true,
    service_class_id: "executive_sedan",
    paid_extras: [
      { extra_id: "deco", active: true, public: true, quote_required: true },
    ],
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
    offer: offer(),
    gateEnabled: true,
  });
  const quote = validateLimousineCompanyQuote(
    { total_incl_vat_cents: 45000, currency: "EUR", terms: TERMS, expires_at: "2099-01-01T00:00:00Z" },
    { nowIso: "2026-08-17T10:00:00Z" },
  );
  const fingerprint = buildLimousineCustomerFingerprint({
    tenantId: "t1",
    companyId: "c1",
    customerRef: "cust_1",
    quoteRequestId: "limq_1",
    itineraryFingerprint: validated.request.itinerary_fingerprint,
  });
  return {
    quote_request_id: "limq_1",
    tenant_id: "t1",
    company_id: "c1",
    state: S.CUSTOMER_ACCEPTANCE_REQUIRED,
    revision: 3,
    request: validated.request,
    quote: quote.quote,
    status_access: {
      customer_fingerprint: fingerprint,
      issued_at: "2026-08-17T09:00:00Z",
      expires_at: "2026-09-16T09:00:00Z",
      created_revision: 1,
    },
    created_at: "2026-08-17T09:00:00Z",
    updated_at: "2026-08-17T10:00:00Z",
    audit: [{ to_state: S.QUOTED, actor_type: "company" }],
    operating_base_address: "Geheimestraat 1",
    internal_cost: 12000,
    ...overrides,
  };
}

function seedIndex(rows) {
  let index = emptyLimousineInboxIndex("t1", "c1");
  for (const row of rows) {
    const out = upsertLimousineInboxEntry(index, {
      tenant_id: "t1",
      company_id: "c1",
      ...row,
    });
    index = out.index;
  }
  return index;
}

async function statusBindingFor(record, { ttlMinutes = 60, issuedAtIso = "2026-08-17T10:00:00Z" } = {}) {
  return sealLimousineStatusRef({
    secret: SECRET,
    binding: {
      purpose: "customer_status",
      tenant_id: record.tenant_id,
      company_id: record.company_id,
      quote_request_id: record.quote_request_id,
      customer_fingerprint: record.status_access.customer_fingerprint,
      created_revision: record.status_access.created_revision,
    },
    issuedAtIso,
    ttlMinutes,
  });
}

async function quotedRecordWithSnapshot(overrides = {}) {
  const record = quotedRecord(overrides);
  const snap = await buildLimousineQuotationSnapshot({
    quoteRequestId: record.quote_request_id,
    quoteRevision: record.revision,
    termsRevision: 3,
    issuedAt: "2026-08-17T10:00:00Z",
    expiresAt: "2099-01-01T00:00:00Z",
    locale: "nl",
    sellerSnapshot: { legal_name: "Coachline BV" },
    requestSnapshot: record.request,
    vehicleSnapshot: { public_name: "Executive sedan" },
    offerSnapshot: record.quote,
  });
  return attachLimousineQuotationSnapshot(record, snap).record;
}

function quotedRecordForCustomer({
  customerRef,
  quoteRequestId,
  tenantId = "t1",
  companyId = "c1",
} = {}) {
  const validated = validateLimousineQuoteRequest(customerRequest(), {
    eligible: true,
    offer: offer(),
    gateEnabled: true,
  });
  const fingerprint = buildLimousineCustomerFingerprint({
    tenantId,
    companyId,
    customerRef,
    quoteRequestId,
    itineraryFingerprint: validated.request.itinerary_fingerprint,
  });
  return quotedRecord({
    quote_request_id: quoteRequestId,
    tenant_id: tenantId,
    company_id: companyId,
    request: validated.request,
    status_access: {
      customer_fingerprint: fingerprint,
      issued_at: "2026-08-17T09:00:00Z",
      expires_at: "2026-09-16T09:00:00Z",
      created_revision: 1,
    },
  });
}

async function runStatus(body, {
  record = quotedRecord(),
  secret = SECRET,
  bookingKvPresent = true,
  customerSession = null,
  limited = false,
  persist = [],
} = {}) {
  let limiterCalls = 0;
  let loadCalls = 0;
  const result = await executeLimousineStatusRead({
    body,
    nowIso: "2026-08-17T10:30:00Z",
    secret,
    bookingKvPresent,
    customerSession,
    rateLimit: async () => {
      limiterCalls += 1;
      return { limited };
    },
    loadRecord: async () => {
      loadCalls += 1;
      return record;
    },
    persistExpired: async (next) => {
      persist.push(next);
    },
  });
  return { result, limiterCalls, loadCalls, persist };
}

test("22) every limousine gate remains OFF", () => {
  assert.equal(limousineManualQuoteGateEnabled("0"), false);
  assert.equal(limousineManualQuoteGateEnabled(undefined), false);
  const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");
  assert.ok(!wrangler.includes("LIMOUSINE_QUOTE_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_BOOK_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_MANUAL_QUOTE_ENABLED"));
});

test("1/2) unauthenticated and cross-company inbox reads are rejected in the worker", () => {
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  assert.ok(worker.includes('"/admin/limousine/quote-requests" && request.method === "GET"'));
  assert.ok(worker.includes("ADMIN_LIMOUSINE_QUOTE_INBOX"));
  assert.ok(worker.includes("ADMIN_LIMOUSINE_QUOTE_DETAIL"));
  assert.ok(worker.includes("_requireAdminOrCompanySessionForExplicitScope"));
  assert.ok(worker.includes("_limousineInboxNotFound"));
  assert.ok(worker.includes('error: "not_found"'));
  const listStart = worker.indexOf('url.pathname === "/admin/limousine/quote-requests" && request.method === "GET"');
  const listEnd = worker.indexOf("LIMOUSINE-MARKETPLACE-P2C2A — company quote-request detail");
  const listBody = worker.slice(listStart, listEnd);
  assert.ok(listBody.includes("if (!authScope.ok) return authScope.response"));
  assert.ok(listBody.includes("_limousineQuoteScopeMatches(loaded, scope)"));
  const detailStart = worker.indexOf("company quote-request detail");
  const detailEnd = worker.indexOf("customer status poll via opaque ref");
  const detailBody = worker.slice(detailStart, detailEnd);
  assert.ok(detailBody.includes("if (!record || !_limousineQuoteScopeMatches(record, scope))"));
  assert.ok(detailBody.includes("return _limousineInboxNotFound()"));
  assert.ok(!detailBody.includes("unauthorized_scope"), "detail must not distinguish missing vs cross-scope");
});

test("3) bounded stable pagination is newest-first with deterministic ties", () => {
  const index = seedIndex([
    { quote_request_id: "limq_a", revision: 1, state: S.REQUESTED, updated_at: "2026-08-17T10:00:00Z" },
    { quote_request_id: "limq_b", revision: 1, state: S.REQUESTED, updated_at: "2026-08-17T10:01:00Z" },
    { quote_request_id: "limq_c", revision: 1, state: S.REQUESTED, updated_at: "2026-08-17T10:02:00Z" },
  ]);
  const first = pageLimousineInboxEntries(index, { pageSize: 2 });
  assert.equal(first.entries.length, 2);
  assert.equal(first.entries[0].quote_request_id, "limq_c");
  assert.equal(first.entries[1].quote_request_id, "limq_b");
  assert.equal(first.has_more, true);
  assert.ok(first.next_cursor);
  const second = pageLimousineInboxEntries(index, {
    pageSize: 2,
    cursor: { activity_seq: first.entries[1].activity_seq, quote_request_id: "limq_b" },
  });
  assert.equal(second.entries.length, 1);
  assert.equal(second.entries[0].quote_request_id, "limq_a");
  assert.equal(second.has_more, false);
  assert.equal(second.next_cursor, null);
  const replay = pageLimousineInboxEntries(index, { pageSize: 2 });
  assert.equal(replay.next_cursor, first.next_cursor);
  assert.equal(parseLimousineInboxQuery({ page_size: String(LIMOUSINE_INBOX_PAGE_MAX + 1) }).ok, false);
});

test("4/5) state and updated-since filters; unknown filters fail closed", () => {
  const index = seedIndex([
    { quote_request_id: "limq_old", revision: 1, state: S.DECLINED, updated_at: "2026-08-01T00:00:00Z" },
    { quote_request_id: "limq_new", revision: 1, state: S.ACCEPTED, updated_at: "2026-08-17T12:00:00Z" },
    { quote_request_id: "limq_mid", revision: 1, state: S.REQUESTED, updated_at: "2026-08-10T00:00:00Z" },
  ]);
  const accepted = pageLimousineInboxEntries(index, { pageSize: 25, state: S.ACCEPTED });
  assert.deepEqual(accepted.entries.map((e) => e.quote_request_id), ["limq_new"]);
  const since = pageLimousineInboxEntries(index, {
    pageSize: 25,
    updatedSinceMs: Date.parse("2026-08-10T00:00:00Z"),
  });
  // Newest activity first (seed order: old, new, mid → mid then new).
  assert.deepEqual(since.entries.map((e) => e.quote_request_id), ["limq_mid", "limq_new"]);
  assert.equal(parseLimousineInboxQuery({ state: "quoted" }).ok, true);
  assert.equal(parseLimousineInboxQuery({ state: "nope" }).ok, false);
  assert.equal(parseLimousineInboxQuery({ updated_since: "not-a-date" }).ok, false);
  assert.equal(parseLimousineInboxQuery({ updated_since: "x".repeat(41) }).ok, false);
  assert.equal(parseLimousineInboxQuery({ cursor: "%%%" }).ok, false);
  assert.equal(parseLimousineInboxQuery({ page_size: "0" }).ok, false);
  assert.equal(parseLimousineInboxQuery({ page_size: "1.5" }).ok, false);
});

test("6) historical accepted/declined/expired rows stay in the company index", () => {
  const index = seedIndex([
    { quote_request_id: "limq_acc", revision: 4, state: S.ACCEPTED, updated_at: "2026-08-17T10:00:00Z" },
    { quote_request_id: "limq_dec", revision: 2, state: S.DECLINED, updated_at: "2026-08-17T09:00:00Z" },
    { quote_request_id: "limq_exp", revision: 3, state: S.EXPIRED, updated_at: "2026-08-17T08:00:00Z" },
  ]);
  const page = pageLimousineInboxEntries(index, { pageSize: 25 });
  assert.equal(page.entries.length, 3);
  assert.deepEqual(
    new Set(page.entries.map((e) => e.quote_request_id)),
    new Set(["limq_acc", "limq_dec", "limq_exp"]),
  );
});

test("7) suspension blocks commercial transitions but not history reads", () => {
  assert.equal(isLimousineCommercialCompanyAction("quote"), true);
  assert.equal(isLimousineCommercialCompanyAction("decline"), true);
  assert.equal(isLimousineCommercialCompanyAction("withdraw"), true);
  assert.equal(isLimousineCommercialCompanyAction("viewed"), false);
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  const respondStart = worker.indexOf('"/admin/limousine/quote-requests/respond"');
  const respondEnd = worker.indexOf('"/limousine/quote-requests/accept"');
  const respond = worker.slice(respondStart, respondEnd);
  assert.ok(respond.includes("_isLimousineCommercialCompanyAction(action)"));
  assert.ok(respond.includes("_assertFluxidiCompanyCanCreateNewBooking"));
  const listStart = worker.indexOf('"/admin/limousine/quote-requests" && request.method === "GET"');
  const list = worker.slice(listStart, listStart + 2600);
  assert.ok(list.includes("transitions_blocked"));
  assert.ok(!list.includes("return _subscriptionBlockedResponse"));
});

test("8/9) customer status requires a well-formed opaque reference, not a bare id", () => {
  assert.equal(limousineStatusRefLooksWellFormed("limq_1"), false);
  assert.equal(prevalidateLimousineStatusBody({ quote_request_id: "limq_1" }).ok, false);
  assert.equal(prevalidateLimousineStatusBody({ status_ref: "limq_1" }).ok, false);
  assert.equal(prevalidateLimousineStatusBody({ status_ref: "limqs1.abc.def" }).ok, false);
  assert.equal(
    limousineStatusRefLooksWellFormed("limqs1.abcdefghijklmnop.klmnopqrstuvwxyzabcdef"),
    true,
  );
});

test("10) malformed, expired and tampered status references are rejected", async () => {
  const record = quotedRecord();
  const sealed = await statusBindingFor(record, { ttlMinutes: 60 });
  assert.equal(sealed.ok, true);
  const live = await unsealLimousineStatusRef({
    secret: SECRET,
    reference: sealed.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(live.ok, true);

  const expired = await unsealLimousineStatusRef({
    secret: SECRET,
    reference: sealed.reference,
    nowIso: "2026-08-18T12:00:00Z",
  });
  assert.equal(expired.ok, false);
  assert.equal(expired.error, LIMOUSINE_STATUS_ERRORS.EXPIRED);

  const parts = sealed.reference.split(".");
  const sig = parts[2] || "sig";
  parts[2] = (sig[0] === "A" ? "B" : "A") + sig.slice(1);
  const tampered = await unsealLimousineStatusRef({
    secret: SECRET,
    reference: parts.join("."),
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(tampered.ok, false);

  const malformed = await runStatus({ status_ref: "not-a-token" });
  assert.equal(malformed.result.status, 404);
  assert.equal(malformed.result.body.error, "invalid_status_ref");
});

test("11) status reference cannot cross company or customer scope", async () => {
  const record = quotedRecord();
  const sealed = await statusBindingFor(record);
  const otherCompany = await runStatus(
    { status_ref: sealed.reference },
    { record: { ...record, company_id: "c2" } },
  );
  assert.equal(otherCompany.result.status, 404);
  assert.equal(otherCompany.result.body.error, "invalid_status_ref");

  const otherCustomer = await runStatus(
    { status_ref: sealed.reference },
    {
      record,
      customerSession: { tenant_id: "t1", company_id: "c1", customer_id: "cust_OTHER" },
    },
  );
  assert.equal(otherCustomer.result.status, 404);

  const sameCustomer = await runStatus(
    { status_ref: sealed.reference },
    {
      record,
      customerSession: { tenant_id: "t1", company_id: "c1", customer_id: "cust_1" },
    },
  );
  assert.equal(sameCustomer.result.status, 200);
});

test("12) status polling of a live quote performs zero state writes", async () => {
  const record = quotedRecord();
  const sealed = await statusBindingFor(record);
  const persist = [];
  const { result } = await runStatus({ status_ref: sealed.reference }, { record, persist });
  assert.equal(result.status, 200);
  assert.equal(result.wrote, false);
  assert.equal(persist.length, 0);
  assert.equal(result.body.quote_request.state, S.CUSTOMER_ACCEPTANCE_REQUIRED);
});

test("13) malformed body is rejected before KV", async () => {
  const { result, limiterCalls, loadCalls } = await runStatus({ quote_request_id: "limq_1" });
  assert.equal(result.status, 404);
  assert.equal(limiterCalls, 0);
  assert.equal(loadCalls, 0);
  assert.equal(result.limiter_called, false);
  assert.equal(result.loaded_record, false);
});

test("14) rate-limit denial performs zero storage read beyond the limiter", async () => {
  const record = quotedRecord();
  const sealed = await statusBindingFor(record);
  const { result, limiterCalls, loadCalls } = await runStatus(
    { status_ref: sealed.reference },
    { record, limited: true },
  );
  assert.equal(result.status, 429);
  assert.equal(result.body.error, "rate_limited");
  assert.equal(limiterCalls, 1);
  assert.equal(loadCalls, 0);
  assert.equal(result.loaded_record, false);
});

test("15/16/17) public and inbox projections stay bounded and secret-free", async () => {
  const record = quotedRecord({
    booking_reference: "B-1",
    email: "hidden@example.com",
    phone: "+320000",
    customer_name: "Ada",
  });
  const pub = publicLimousineQuoteView(record);
  const inbox = buildLimousineCompanyInboxView(record, { activity_seq: 4, transitions_blocked: true });
  assert.equal(pub.quote_request_id, "limq_1");
  assert.equal(pub.quote.total_incl_vat_cents, 45000);
  assert.equal(inbox.fulfilment.from, "Gent");
  assert.equal(inbox.inbox.activity_seq, 4);
  assert.equal(inbox.inbox.transitions_blocked, true);
  for (const view of [pub, inbox]) {
    const leaked = projectionContainsForbiddenKey(view);
    assert.deepEqual(leaked, [], `leaked ${leaked.join(",")}`);
    assert.equal(view.acceptance_reference, undefined);
    assert.equal(view.status_ref, undefined);
    assert.equal(view.audit, undefined);
    assert.equal(view.status_access, undefined);
    assert.equal(view.internal_cost, undefined);
    assert.equal(view.operating_base_address, undefined);
  }
  const sealed = await statusBindingFor(record);
  const { result } = await runStatus({ status_ref: sealed.reference }, { record });
  assert.equal(result.body.quote_request.acceptance_reference, undefined);
  assert.equal(result.body.status_ref, undefined);
  assert.ok(!JSON.stringify(result.body).includes("Geheimestraat"));
  assert.ok(!JSON.stringify(result.body).includes("hidden@example.com"));
});

test("18) inbox-index updates are idempotent and reject stale revisions", async () => {
  let index = emptyLimousineInboxIndex("t1", "c1");
  const first = upsertLimousineInboxEntry(index, {
    tenant_id: "t1",
    company_id: "c1",
    quote_request_id: "limq_1",
    revision: 2,
    state: S.QUOTED,
    updated_at: "2026-08-17T10:00:00Z",
  });
  assert.equal(first.changed, true);
  const replay = upsertLimousineInboxEntry(first.index, {
    tenant_id: "t1",
    company_id: "c1",
    quote_request_id: "limq_1",
    revision: 2,
    state: S.QUOTED,
    updated_at: "2026-08-17T10:00:00Z",
  });
  assert.equal(replay.changed, false);
  assert.equal(replay.reason, "idempotent");
  assert.equal(replay.index.next_activity_seq, first.index.next_activity_seq);
  const stale = upsertLimousineInboxEntry(first.index, {
    tenant_id: "t1",
    company_id: "c1",
    quote_request_id: "limq_1",
    revision: 1,
    state: S.REQUESTED,
    updated_at: "2026-08-17T09:00:00Z",
  });
  assert.equal(stale.changed, false);
  assert.equal(stale.reason, "stale_revision");
  assert.equal(stale.index.entries[0].state, S.QUOTED);
  assert.equal(limousineInboxIndexKey("t1", "c1"), "limousine_quote_inbox_v1:t1:c1");
  const rateKey = await limousineStatusRateKey("limqs1.aaa.bbb");
  assert.ok(rateKey.startsWith("limousine_status_rl:v1:"));
  assert.ok(!rateKey.includes("limqs1.aaa.bbb"));
});

test("19) expiry observation is monotonic and cannot revive a terminal quote", () => {
  const live = quotedRecord({
    quote: { ...quotedRecord().quote, expires_at: "2026-08-17T11:00:00Z" },
  });
  const first = observeLimousineQuoteExpiry(live, { nowIso: "2026-08-17T12:00:00Z" });
  assert.equal(first.ok, true);
  assert.equal(first.changed, true);
  assert.equal(first.record.state, S.EXPIRED);
  const firstRevision = first.record.revision;
  const second = observeLimousineQuoteExpiry(first.record, { nowIso: "2026-08-17T13:00:00Z" });
  assert.equal(second.changed, false);
  assert.equal(second.record.revision, firstRevision);
  const revived = applyLimousineQuoteTransition(first.record, {
    to: S.QUOTED,
    expectedRevision: firstRevision,
    actorType: "company",
  });
  assert.equal(revived.ok, false);
  assert.equal(revived.reason, LIMOUSINE_QUOTE_REASONS.INVALID_TRANSITION);
  const booked = quotedRecord({ state: S.BOOKING_CREATED, revision: 8 });
  booked.quote.expires_at = "2020-01-01T00:00:00Z";
  const preserved = observeLimousineQuoteExpiry(booked, { nowIso: "2026-08-17T12:00:00Z" });
  assert.equal(preserved.changed, false);
  assert.equal(preserved.record.state, S.BOOKING_CREATED);
});

test("20) existing request/respond/accept/book lifecycle wiring is intact", () => {
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  for (const route of [
    '"/limousine/quote-requests" && request.method === "POST"',
    '"/admin/limousine/quote-requests/respond" && request.method === "POST"',
    '"/limousine/quote-requests/accept" && request.method === "POST"',
    '"/limousine/quote-requests/status" && request.method === "POST"',
  ]) {
    assert.ok(worker.includes(route), route);
  }
  assert.ok(worker.includes("_prepareLimousineManualBooking"));
  assert.ok(worker.includes("_sealLimousineStatusRef"));
  assert.ok(worker.includes("limousineQuoteSuccessBody"));
  assert.ok(worker.includes("sealedStatus.reference"));
  assert.ok(worker.includes("status_ref"));
  assert.ok(worker.includes("_upsertLimousineInboxIndex"));
  assert.ok(!worker.includes("BOOKING_KV.list({ prefix: \"limousine_quote"));
});

test("21) taxi and airport paths stay free of limousine inbox/status symbols", () => {
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  const calcStart = worker.indexOf("function calcPrice({");
  const calcEnd = worker.indexOf("function buildNote(");
  if (calcStart > 0 && calcEnd > calcStart) {
    assert.ok(!worker.slice(calcStart, calcEnd).includes("limousine"));
  }
  const airportIdx = worker.indexOf("function resolveAirportFixedFare(");
  if (airportIdx > 0) {
    const slice = worker.slice(airportIdx, airportIdx + 2500);
    assert.ok(!slice.includes("quote-requests"));
    assert.ok(!slice.includes("status_ref"));
  }
});

test("status token version cannot be confused with an acceptance reference", async () => {
  const record = quotedRecord();
  const sealed = await statusBindingFor(record);
  assert.ok(sealed.reference.startsWith(`${LIMOUSINE_STATUS_TOKEN_VERSION}.`));
  assert.equal(encodeLimousineInboxCursor({ activity_seq: 3, quote_request_id: "limq_1" }).length > 0, true);
  const missingKv = await executeLimousineStatusRead({
    body: { status_ref: sealed.reference },
    secret: SECRET,
    bookingKvPresent: false,
    rateLimit: async () => ({ limited: false }),
    loadRecord: async () => record,
  });
  assert.equal(missingKv.status, 500);
  assert.equal(missingKv.limiter_called, false);
});

function assertQuotedStatusSuccess(result, record) {
  assert.equal(result.status, 200);
  assert.equal(result.body.ok, true);
  assert.equal(result.body.quote_request.state, S.CUSTOMER_ACCEPTANCE_REQUIRED);
  assert.equal(result.body.quote_request.quotation_available, true);
  assert.equal(result.body.quote_request.quotation_revision, record.quotation_revision);
  assert.equal(result.body.status_ref, undefined);
}

test("global customer session is only the explicit global/global form", () => {
  assert.equal(
    isLimousineGlobalCustomerSession({ tenant_id: "global", company_id: "global" }),
    true,
  );
  assert.equal(
    isLimousineGlobalCustomerSession({ tenant_id: "GLOBAL", company_id: "Global" }),
    true,
  );
  assert.equal(
    isLimousineGlobalCustomerSession({ tenant_id: "t1", company_id: "c1" }),
    false,
  );
  assert.equal(
    isLimousineGlobalCustomerSession({ tenant_id: "global", company_id: "c1" }),
    false,
  );
  assert.equal(
    isLimousineGlobalCustomerSession({ tenant_id: "t1", company_id: "global" }),
    false,
  );
});

test("status-ref security matrix: global, scoped, capability, and fail-closed", async () => {
  const record = await quotedRecordWithSnapshot();
  const sealed = await statusBindingFor(record);
  const otherQuote = quotedRecordForCustomer({
    customerRef: "cust_2",
    quoteRequestId: "limq_2",
  });
  const otherSealed = await statusBindingFor(otherQuote);

  const globalSame = await runStatus(
    { status_ref: sealed.reference },
    {
      record,
      customerSession: { tenant_id: "global", company_id: "global", customer_id: "cust_1" },
    },
  );
  assertQuotedStatusSuccess(globalSame.result, record);

  const noSession = await runStatus({ status_ref: sealed.reference }, { record });
  assertQuotedStatusSuccess(noSession.result, record);

  const globalOther = await runStatus(
    { status_ref: sealed.reference },
    {
      record,
      customerSession: { tenant_id: "global", company_id: "global", customer_id: "cust_OTHER" },
    },
  );
  assert.equal(globalOther.result.status, 404);
  assert.equal(globalOther.result.body.error, "invalid_status_ref");

  const scopedSame = await runStatus(
    { status_ref: sealed.reference },
    {
      record,
      customerSession: { tenant_id: "t1", company_id: "c1", customer_id: "cust_1" },
    },
  );
  assertQuotedStatusSuccess(scopedSame.result, record);

  const scopedWrongCompany = await runStatus(
    { status_ref: sealed.reference },
    {
      record,
      customerSession: { tenant_id: "t1", company_id: "c2", customer_id: "cust_1" },
    },
  );
  assert.equal(scopedWrongCompany.result.status, 404);

  const scopedWrongTenant = await runStatus(
    { status_ref: sealed.reference },
    {
      record,
      customerSession: { tenant_id: "t2", company_id: "c1", customer_id: "cust_1" },
    },
  );
  assert.equal(scopedWrongTenant.result.status, 404);

  const wrongQuoteBound = await runStatus(
    { status_ref: otherSealed.reference },
    { record },
  );
  assert.equal(wrongQuoteBound.result.status, 404);

  const expired = await executeLimousineStatusRead({
    body: { status_ref: sealed.reference },
    nowIso: "2026-08-18T12:00:00Z",
    secret: SECRET,
    bookingKvPresent: true,
    customerSession: { tenant_id: "global", company_id: "global", customer_id: "cust_1" },
    rateLimit: async () => ({ limited: false }),
    loadRecord: async () => record,
  });
  assert.equal(expired.status, 404);
  assert.equal(expired.loaded_record, false);

  const wrongPurpose = await sealLimousineAead({
    secret: SECRET,
    version: LIMOUSINE_STATUS_TOKEN_VERSION,
    purpose: LIMOUSINE_STATUS_KEY_PURPOSE,
    payload: {
      v: LIMOUSINE_STATUS_TOKEN_VERSION,
      purpose: "customer_acceptance",
      binding: {
        purpose: "customer_acceptance",
        tenant_id: record.tenant_id,
        company_id: record.company_id,
        quote_request_id: record.quote_request_id,
        customer_fingerprint: record.status_access.customer_fingerprint,
        created_revision: 1,
      },
      issued_at: "2026-08-17T10:00:00Z",
      expires_at: "2099-01-01T00:00:00Z",
    },
  });
  assert.equal(wrongPurpose.ok, true);
  const purposeDenied = await runStatus(
    { status_ref: wrongPurpose.reference },
    {
      record,
      customerSession: { tenant_id: "global", company_id: "global", customer_id: "cust_1" },
    },
  );
  assert.equal(purposeDenied.result.status, 404);

  const malformed = await runStatus(
    { status_ref: "limqs1.not-a-valid.token" },
    {
      record,
      customerSession: { tenant_id: "global", company_id: "global", customer_id: "cust_1" },
    },
  );
  assert.equal(malformed.result.status, 404);
  assert.equal(malformed.loadCalls, 0);

  const bareId = await runStatus(
    { quote_request_id: record.quote_request_id },
    {
      record,
      customerSession: { tenant_id: "global", company_id: "global", customer_id: "cust_1" },
    },
  );
  assert.equal(bareId.result.status, 404);
  assert.equal(bareId.loadCalls, 0);

  const missingCustomer = await runStatus(
    { status_ref: sealed.reference },
    {
      record,
      customerSession: { tenant_id: "global", company_id: "global", customer_id: "" },
    },
  );
  assert.equal(missingCustomer.result.status, 404);

  const secondCustomerQuote = await runStatus(
    { status_ref: otherSealed.reference },
    {
      record: otherQuote,
      customerSession: { tenant_id: "global", company_id: "global", customer_id: "cust_1" },
    },
  );
  assert.equal(secondCustomerQuote.result.status, 404);
});
