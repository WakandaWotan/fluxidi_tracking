// LIMOUSINE-QUOTE-DELIVERY-P3K — viewed lifecycle, quote delivery, acceptance.
// Run: node --test workers/booking/modules/limousine_p3k_quote_delivery.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import worker from "../fluxidi_booking_worker.js";
import {
  LIMOUSINE_QUOTE_STATES as S,
  applyLimousineCompanyQuoteAction,
  applyLimousineCompanyViewedAction,
  publicLimousineQuoteView,
  validateLimousineCompanyQuote,
} from "./limousine_manual_quote.mjs";
import {
  LIMOUSINE_QUOTATION_RENDERER_VERSION,
  attachLimousineQuotationSnapshot,
  buildLimousineQuotationSnapshot,
} from "./limousine_quotation_snapshot.mjs";
import { sealLimousineStatusRef } from "./limousine_status_token.mjs";
import { unsealLimousineAcceptance } from "./limousine_acceptance_token.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ADMIN = "test-admin-token";
const TENANT = "fluxidi_limo_p3k";
const COMPANY = "company_limo_p3k";
const OTHER_COMPANY = "company_other_p3k";
const OTHER_TENANT = "fluxidi_other_p3k";
const SECRET = "p3k-acceptance-secret-not-production";
const FAKE_PDF = new TextEncoder().encode("%PDF-1.4\n1 0 obj<<>>endobj\n%%EOF\n");

const TERMS = {
  terms_revision: 3,
  cancellation_deadline_hours: 24,
  cancellation_penalty_percent: 20,
  waiting_time_included_minutes: 60,
  waiting_time_overage_cents_per_minute: 150,
  no_show_penalty_percent: 100,
  overtime_cents_per_hour: 10000,
};

async function sha256Hex(text) {
  const data = new TextEncoder().encode(String(text || ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list() {
      return { keys: [...store.keys()].map((name) => ({ name })), list_complete: true };
    },
  };
}

function makeR2() {
  const store = new Map();
  const writes = [];
  return {
    store,
    writes,
    async get(key) {
      if (!store.has(key)) return null;
      const bytes = store.get(key);
      return {
        async arrayBuffer() {
          return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
        },
      };
    },
    async put(key, bytes) {
      writes.push(key);
      store.set(key, bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes));
    },
  };
}

async function seedSessions() {
  const companyHash = await sha256Hex("co-p3k");
  const otherHash = await sha256Hex("co-other-p3k");
  const customerHash = await sha256Hex("cus-p3k");
  const expires = new Date(Date.now() + 3600_000).toISOString();
  return {
    [`company_admin:session:${companyHash}:v1`]: {
      role: "company_admin",
      tenant_id: TENANT,
      company_id: COMPANY,
      expires_at: expires,
    },
    [`company_admin:session:${otherHash}:v1`]: {
      role: "company_admin",
      tenant_id: OTHER_TENANT,
      company_id: OTHER_COMPANY,
      expires_at: expires,
    },
    [`customer:session:${customerHash}:v1`]: {
      role: "customer",
      purpose: "customer_session",
      tenant_id: TENANT,
      company_id: COMPANY,
      customer_id: "cust_p3k",
      phone_hash: "phonehash_p3k",
      expires_at: expires,
    },
  };
}

function quoteRecord({ id, state = "requested", extras = {} } = {}) {
  const now = "2026-08-22T10:00:00.000Z";
  return {
    quote_request_id: id,
    tenant_id: TENANT,
    company_id: COMPANY,
    state,
    revision: 1,
    offer_source_revision: 1,
    pricing_section_revision: 1,
    created_at: now,
    updated_at: now,
    request: {
      offer_id: "off_exec",
      service_class_id: "executive_sedan",
      vehicle_id: "veh_limo_p3k",
      journey_type: "point_to_point",
      from: "Gent",
      to: "Brussel",
      scheduled_pickup_iso: "2026-09-01T10:00:00Z",
      pax: 2,
      bags: 1,
      locale: "nl",
      service_type: "limousine",
      pricing_mode: "quote_required",
      vehicle_snapshot: {
        vehicle_id: "veh_limo_p3k",
        public_name: "Executive sedan",
      },
    },
    status_access: {
      customer_fingerprint: "limcf_p3k_owner",
      issued_at: now,
      expires_at: "2026-09-22T10:00:00.000Z",
      created_revision: 1,
    },
    ...extras,
  };
}

function jsonReq(path, { method = "POST", token = null, body = null, query = "", headers = {} } = {}) {
  const next = { "content-type": "application/json", ...headers };
  if (token) next.authorization = `Bearer ${token}`;
  return new Request(`https://booking.internal${path}${query}`, {
    method,
    headers: next,
    body: body == null ? undefined : JSON.stringify(body),
  });
}

async function setup({ quotes = [] } = {}) {
  const sessions = await seedSessions();
  const seed = { ...sessions };
  for (const quote of quotes) {
    seed[`limousine_quote_record:${quote.quote_request_id}`] = quote;
  }
  seed[`tenant:${TENANT}:company:${COMPANY}:business_profile:v1`] = {
    business_profile: {
      trading_name: "Coachline",
      legal_name: "Coachline BV",
      legal_form: "bv",
      vat_number: "BE0772931038",
      enterprise_number: "0772931038",
      address: "Markt 1",
      city: "Gent",
      postcode: "9000",
      country: "BE",
      invoice_email: "billing@coachline.test",
    },
  };
  const kv = makeKV(seed);
  const r2 = makeR2();
  const htmls = [];
  const env = {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    PUBLIC_MEDIA: r2,
    LIMOUSINE_QUOTE_ENABLED: "1",
    LIMOUSINE_MANUAL_QUOTE_ENABLED: "1",
    LIMOUSINE_BOOK_ENABLED: "1",
    LIMOUSINE_TEST_COMPANY_ALLOWLIST: `${COMPANY},${OTHER_COMPANY}`,
    LIMOUSINE_ACCEPTANCE_SECRET: SECRET,
    LIMOUSINE_QUOTATION_RENDER_PDF: async (html) => {
      htmls.push(html);
      return FAKE_PDF;
    },
    fetch: async (input) => {
      throw new Error(`blocked outbound ${input?.url || input}`);
    },
  };
  return { env, kv, r2, htmls };
}

async function respond(env, { id, action, expectedRevision = 1, extra = {}, token = "co-p3k", tenant = TENANT, company = COMPANY }) {
  return worker.fetch(
    jsonReq("/admin/limousine/quote-requests/respond", {
      token,
      body: {
        tenant_id: tenant,
        company_id: company,
        quote_request_id: id,
        action,
        expected_revision: expectedRevision,
        ...extra,
      },
    }),
    env,
    {},
  );
}

async function sendQuote(env, id, { expectedRevision, total = 18500, terms = TERMS } = {}) {
  return respond(env, {
    id,
    action: "quote",
    expectedRevision,
    extra: {
      total_incl_vat_cents: total,
      currency: "EUR",
      vat_rate: 0.06,
      vat_treatment: "incl",
      terms,
      public_text: { nl: "Vaste prijs", en: "Fixed price", fr: "Prix fixe", es: "Precio fijo" },
      expires_at: "2099-01-01T00:00:00Z",
    },
  });
}

async function customerStatus(env, statusRef) {
  return worker.fetch(
    jsonReq("/limousine/quote-requests/status", {
      body: { status_ref: statusRef },
    }),
    env,
    {},
  );
}

test("1-8) company viewed stamps once and never creates a snapshot", async () => {
  const requested = quoteRecord({ id: "limq_p3k_view" });
  const first = applyLimousineCompanyViewedAction(requested, {
    expectedRevision: 1,
    nowIso: "2026-08-22T10:05:00.000Z",
  });
  assert.equal(first.ok, true);
  assert.equal(first.changed, true);
  assert.equal(first.record.state, S.VIEWED_BY_COMPANY);
  assert.equal(first.record.company_viewed_at, "2026-08-22T10:05:00.000Z");
  assert.equal(first.record.quotation_snapshots, undefined);
  const view = publicLimousineQuoteView(first.record);
  assert.equal(view.company_viewed, true);
  assert.equal(view.company_viewed_at, "2026-08-22T10:05:00.000Z");
  assert.equal(view.quotation_available, false);
  const again = applyLimousineCompanyViewedAction(first.record, {
    expectedRevision: first.record.revision,
    nowIso: "2026-08-22T11:00:00.000Z",
  });
  assert.equal(again.ok, true);
  assert.equal(again.changed, false);
  assert.equal(again.record.company_viewed_at, "2026-08-22T10:05:00.000Z");

  const quoted = { ...first.record, state: S.CUSTOMER_ACCEPTANCE_REQUIRED, revision: 4 };
  const afterQuote = applyLimousineCompanyViewedAction(quoted, {
    nowIso: "2026-08-22T12:00:00.000Z",
  });
  assert.equal(afterQuote.ok, true);
  assert.equal(afterQuote.record.state, S.CUSTOMER_ACCEPTANCE_REQUIRED);
  assert.equal(afterQuote.record.company_viewed_at, "2026-08-22T10:05:00.000Z");

  const accepted = { ...quoted, state: S.ACCEPTED, company_viewed_at: undefined };
  const acceptedView = applyLimousineCompanyViewedAction(accepted, {
    nowIso: "2026-08-22T13:00:00.000Z",
  });
  assert.equal(acceptedView.ok, true);
  assert.equal(acceptedView.record.state, S.ACCEPTED);
  assert.equal(acceptedView.record.company_viewed_at, "2026-08-22T13:00:00.000Z");
});

test("6) cross-company viewed is rejected; 9-20 quote delivery projection", async () => {
  const { env, kv } = await setup({
    quotes: [quoteRecord({ id: "limq_p3k_del" })],
  });
  const cross = await respond(env, {
    id: "limq_p3k_del",
    action: "viewed",
    token: "co-other-p3k",
    tenant: OTHER_TENANT,
    company: OTHER_COMPANY,
  });
  assert.equal(cross.status, 403);

  const viewed = await respond(env, { id: "limq_p3k_del", action: "viewed" });
  const viewedBody = await viewed.json();
  assert.equal(viewed.status, 200, JSON.stringify(viewedBody));
  assert.equal(viewedBody.quote_request.state, "viewed_by_company");
  assert.ok(viewedBody.quote_request.company_viewed_at);
  const viewedRec = await kv.get("limousine_quote_record:limq_p3k_del", { type: "json" });
  assert.equal(viewedRec.quotation_snapshots, undefined);

  const quoted = await sendQuote(env, "limq_p3k_del", {
    expectedRevision: viewedBody.quote_request.revision,
  });
  const quotedBody = await quoted.json();
  assert.equal(quoted.status, 200, JSON.stringify(quotedBody));
  const qr = quotedBody.quote_request;
  assert.equal(qr.state, "customer_acceptance_required");
  assert.equal(qr.quotation_available, true);
  assert.ok(qr.quotation_revision >= 1);
  assert.ok(qr.quotation_sent_at);
  assert.ok(qr.quotation_expires_at);
  assert.equal(qr.quotation_total_incl_vat_cents, 18500);
  assert.equal(qr.quotation_currency, "EUR");
  assert.equal(qr.company_viewed, true);
  assert.equal(qr.content_hash, undefined);
  assert.equal(qr.quotation_snapshots, undefined);
  assert.equal(qr.status_ref, undefined);
  const stored = await kv.get("limousine_quote_record:limq_p3k_del", { type: "json" });
  assert.equal(
    stored.quotation_snapshots[String(qr.quotation_revision)].renderer_version,
    LIMOUSINE_QUOTATION_RENDERER_VERSION,
  );

  const sealed = await sealLimousineStatusRef({
    secret: SECRET,
    binding: {
      purpose: "customer_status",
      tenant_id: TENANT,
      company_id: COMPANY,
      quote_request_id: "limq_p3k_del",
      customer_fingerprint: "limcf_p3k_owner",
      created_revision: 1,
    },
    issuedAtIso: new Date().toISOString(),
    ttlMinutes: 60,
  });
  const status = await customerStatus(env, sealed.reference);
  const statusBody = await status.json();
  assert.equal(status.status, 200, JSON.stringify(statusBody));
  assert.equal(statusBody.quote_request.quotation_available, true);
  assert.equal(statusBody.quote_request.quotation_revision, qr.quotation_revision);
  assert.equal(statusBody.quote_request.quotation_total_incl_vat_cents, 18500);
  assert.ok(!JSON.stringify(statusBody).includes("limqs1"));
  assert.ok(!JSON.stringify(statusBody).includes(sealed.reference));

  const bare = await worker.fetch(
    jsonReq("/limousine/quote-requests/status", {
      body: { quote_request_id: "limq_p3k_del" },
    }),
    env,
    {},
  );
  assert.notEqual(bare.status, 200);

  const requote = await sendQuote(env, "limq_p3k_del", {
    expectedRevision: qr.revision,
    total: 22000,
    terms: { ...TERMS, terms_revision: 4 },
  });
  const requoteBody = await requote.json();
  assert.equal(requote.status, 200, JSON.stringify(requoteBody));
  assert.equal(requoteBody.quote_request.quotation_total_incl_vat_cents, 22000);
  assert.notEqual(requoteBody.quote_request.quotation_revision, qr.quotation_revision);
  const after = await kv.get("limousine_quote_record:limq_p3k_del", { type: "json" });
  assert.equal(after.quotation_snapshots[String(qr.quotation_revision)].totals_snapshot.total_incl_vat_cents, 18500);
  assert.equal(
    after.quotation_snapshots[String(requoteBody.quote_request.quotation_revision)].totals_snapshot.total_incl_vat_cents,
    22000,
  );
});

test("17) legacy records remain loadable without snapshots", () => {
  const view = publicLimousineQuoteView(quoteRecord({ id: "limq_legacy", extras: { quote: {
    total_incl_vat_cents: 18500,
    currency: "EUR",
    vat_treatment: "incl",
    terms: TERMS,
    terms_revision: 3,
    expires_at: "2026-08-24T08:00:00Z",
    quoted_at: "2026-08-22T10:00:00Z",
  } } }));
  assert.equal(view.quotation_available, false);
  assert.equal(view.quote.total_incl_vat_cents, 18500);
});

test("21-26) accept binds current revision and preserves quotation", async () => {
  const { env, kv } = await setup({
    quotes: [quoteRecord({ id: "limq_p3k_acc" })],
  });
  const quoted = await sendQuote(env, "limq_p3k_acc", { expectedRevision: 1 });
  const quotedBody = await quoted.json();
  assert.equal(quoted.status, 200, JSON.stringify(quotedBody));
  const revision = quotedBody.quote_request.revision;
  const stale = await worker.fetch(
    jsonReq("/limousine/quote-requests/accept", {
      token: "cus-p3k",
      body: { quote_request_id: "limq_p3k_acc", expected_revision: 1 },
    }),
    env,
    {},
  );
  assert.equal(stale.status, 409);
  const accept = await worker.fetch(
    jsonReq("/limousine/quote-requests/accept", {
      token: "cus-p3k",
      body: { quote_request_id: "limq_p3k_acc", expected_revision: revision },
    }),
    env,
    {},
  );
  const accepted = await accept.json();
  assert.equal(accept.status, 200, JSON.stringify(accepted));
  assert.equal(accepted.quote_request.state, "accepted");
  assert.equal(accepted.quote_request.quotation_available, true);
  const opened = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: accepted.acceptance_reference,
  });
  assert.equal(opened.ok, true);
  assert.equal(opened.binding.total_incl_vat_cents, 18500);
  const stored = await kv.get("limousine_quote_record:limq_p3k_acc", { type: "json" });
  assert.equal(stored.quotation_snapshots[String(quotedBody.quote_request.quotation_revision)].totals_snapshot.total_incl_vat_cents, 18500);
  const src = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  assert.ok(!src.includes("billit") || src.includes("_prepareLimousineManualBooking"));
  assert.ok(!JSON.stringify(accepted).toLowerCase().includes("peppol"));
  assert.ok(!JSON.stringify(accepted).toLowerCase().includes("billit"));
});

test("re-quote keeps earlier snapshot hashes", async () => {
  const snap = await buildLimousineQuotationSnapshot({
    quoteRequestId: "limq_1",
    quoteRevision: 3,
    termsRevision: 3,
    issuedAt: "2026-08-22T08:00:00Z",
    expiresAt: "2026-08-24T08:00:00Z",
    locale: "nl",
    sellerSnapshot: { legal_name: "Coachline BV" },
    requestSnapshot: quoteRecord({ id: "limq_1" }).request,
    offerSnapshot: {
      total_incl_vat_cents: 18500,
      currency: "EUR",
      vat_rate: 0.06,
      terms: TERMS,
      terms_revision: 3,
      expires_at: "2026-08-24T08:00:00Z",
    },
  });
  const seeded = attachLimousineQuotationSnapshot(
    { ...quoteRecord({ id: "limq_1" }), state: S.CUSTOMER_ACCEPTANCE_REQUIRED, revision: 3, quote: {
      total_incl_vat_cents: 18500,
      currency: "EUR",
      vat_treatment: "incl",
      terms: TERMS,
      terms_revision: 3,
      expires_at: "2026-08-24T08:00:00Z",
    } },
    snap,
  ).record;
  const nextQuote = validateLimousineCompanyQuote({
    total_incl_vat_cents: 22000,
    currency: "EUR",
    vat_treatment: "incl",
    terms: { ...TERMS, terms_revision: 4 },
    expires_at: "2026-08-25T08:00:00Z",
  }, { nowIso: "2026-08-22T12:00:00Z" });
  const requote = applyLimousineCompanyQuoteAction(seeded, {
    expectedRevision: 3,
    quote: nextQuote.quote,
    nowIso: "2026-08-22T12:00:00Z",
  });
  assert.equal(requote.ok, true);
  assert.equal(requote.record.quotation_snapshots["3"].content_hash, snap.content_hash);
});
