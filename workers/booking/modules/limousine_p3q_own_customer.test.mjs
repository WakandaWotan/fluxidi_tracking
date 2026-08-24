// P3Q — company-created own-customer limousine quote lifecycle.
// Adapter coverage only: reuses P3P invitation, P3M VAT, P3O terms,
// existing accept/book/Mollie/invoice engines. No second quote engine.
// Run: node --test workers/booking/modules/limousine_p3q_own_customer.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import worker from "../fluxidi_booking_worker.js";
import {
  LIMOUSINE_EXTERNAL_ORIGIN,
  LIMOUSINE_EXTERNAL_ERRORS,
  projectLimousineCompanyContactSummary,
  publicLimousineExternalCustomerView,
  publicProjectionContainsExternalPii,
} from "./limousine_external_customer.mjs";
import { publicLimousineQuoteView } from "./limousine_manual_quote.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const WORKER_SRC = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const ADMIN = "test-admin-token";
const TENANT = "fluxidi_limo_p3q";
const COMPANY = "company_limo_p3q";
const OTHER_TENANT = "fluxidi_other_p3q";
const OTHER_COMPANY = "company_other_p3q";
const SECRET = "p3q-acceptance-secret-not-production";
const PUBLIC_PARTNER = `company:${TENANT}:${COMPANY}`;
const OTHER_PUBLIC_PARTNER = `company:${OTHER_TENANT}:${OTHER_COMPANY}`;
const VEHICLE = "veh_limo_p3q";
const OFFER = "off_party_p3q";
const FAKE_PDF = new TextEncoder().encode("%PDF-1.4\n1 0 obj<<>>endobj\n%%EOF\n");

const TERMS = {
  terms_revision: 3,
  cancellation_deadline_hours: 24,
  cancellation_penalty_percent: 25,
  waiting_time_included_minutes: 15,
  waiting_time_overage_cents_per_minute: 100,
  no_show_penalty_percent: 100,
  overtime_cents_per_hour: 9000,
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
    async list(opts = {}) {
      const prefix = String(opts?.prefix || "");
      const keys = [...store.keys()].filter((name) =>
        prefix ? name.startsWith(prefix) : true,
      );
      return { keys: keys.map((name) => ({ name })), list_complete: true };
    },
  };
}

function makeR2() {
  const store = new Map();
  return {
    store,
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
      store.set(key, bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes));
    },
  };
}

async function seedSessions() {
  const companyHash = await sha256Hex("co-p3q");
  const otherHash = await sha256Hex("co-other-p3q");
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
  };
}

function vehicles() {
  return [
    {
      vehicle_id: VEHICLE,
      name: "Party Limo",
      service_category: "limousine",
      service_class: "stretch_limousine",
      is_active: true,
      active: true,
      photo_url: "https://cdn.example/party.jpg",
      passenger_capacity: 10,
      luggage_capacity: 4,
    },
  ];
}

function publishedOffer() {
  return {
    offer_id: OFFER,
    enabled: true,
    published: true,
    target_type: "vehicle",
    vehicle_ids: [VEHICLE],
    vehicles: vehicles(),
    service_class_id: "stretch_limousine",
    journey_types: ["point_to_point"],
    price_presentation: "quote_required",
    paid_extras: [],
    source_revision: 4,
  };
}

function jsonReq(path, { method = "POST", token = null, body = null, headers = {} } = {}) {
  const next = { "content-type": "application/json", ...headers };
  if (token) next.authorization = `Bearer ${token}`;
  return new Request(`https://booking.internal${path}`, {
    method,
    headers: next,
    body: body == null ? undefined : JSON.stringify(body),
  });
}

async function setup() {
  const sessions = await seedSessions();
  const seed = {
    ...sessions,
    [`tenant:${TENANT}:company:${COMPANY}:partner:profile:v1`]: {
      partner_profile: {
        partner_id: PUBLIC_PARTNER,
        company_name: "P3Q Limo",
        company_id: COMPANY,
        is_active: true,
        bookable: true,
        profile_enabled: true,
        published_at: "2026-08-17T10:00:00Z",
        subscription_status: "active",
        limousine_entitled: true,
        services: ["limousine"],
        vehicles: vehicles(),
      },
    },
    [`tenant:${TENANT}:company:${COMPANY}:pricing:v1`]: {
      pricing_profile: { limousine: { offers: [publishedOffer()] } },
    },
    [`tenant:${TENANT}:company:${COMPANY}:fleet:vehicles:v1`]: {
      vehicles: vehicles(),
    },
    [`tenant:${TENANT}:company:${COMPANY}:business_profile:v1`]: {
      business_profile: {
        trading_name: "P3Q Limo",
        legal_name: "P3Q Limo BV",
        vat_number: "BE0772931038",
        address: "Markt 1",
        city: "Gent",
        postcode: "9000",
        country: "BE",
      },
    },
    "public:partners:booking-routes:v2": {
      routes: [
        { partner_id: PUBLIC_PARTNER, tenant_id: TENANT, company_id: COMPANY, is_active: true, subscription_status: "active" },
        { partner_id: OTHER_PUBLIC_PARTNER, tenant_id: OTHER_TENANT, company_id: OTHER_COMPANY, is_active: true, subscription_status: "active" },
      ],
    },
  };
  const kv = makeKV(seed);
  const r2 = makeR2();
  const env = {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    PUBLIC_MEDIA: r2,
    LIMOUSINE_QUOTE_ENABLED: "1",
    LIMOUSINE_MANUAL_QUOTE_ENABLED: "1",
    LIMOUSINE_BOOK_ENABLED: "1",
    LIMOUSINE_TEST_COMPANY_ALLOWLIST: `${COMPANY},${OTHER_COMPANY}`,
    LIMOUSINE_ACCEPTANCE_SECRET: SECRET,
    LIMOUSINE_QUOTATION_RENDER_PDF: async () => FAKE_PDF,
    DOCUMENT_REFERENCE_SEQUENCE: {
      idFromName: (name) => ({ name }),
      get: () => ({
        fetch: async () =>
          new Response(
            JSON.stringify({ ok: true, document_reference: "DOC-P3Q-1" }),
            { status: 200 },
          ),
      }),
    },
    fetch: async (input) => {
      throw new Error(`blocked outbound ${input?.url || input}`);
    },
  };
  return { kv, env };
}

function createBody(extra = {}) {
  return {
    tenant_id: TENANT,
    company_id: COMPANY,
    contact: {
      name: "Ada Lovelace",
      email: "ada@example.test",
      phone: "+32470000000",
      locale: "nl-BE",
      company_name: "Analytical Engines",
    },
    request: {
      offer_id: OFFER,
      vehicle_id: VEHICLE,
      journey_type: "point_to_point",
      from: "Korenmarkt 1, Gent",
      to: "Graslei, Gent",
      scheduled_pickup_iso: "2026-10-01T16:00:00.000Z",
      locale: "nl",
      pax: 8,
      bags: 2,
      occasion: "website form",
    },
    quote: {
      entered_amount_cents: 100000,
      currency: "EUR",
      vat_treatment: "excl",
      terms: TERMS,
      public_text: { nl: "Vaste prijs", en: "Fixed price" },
      expires_at: "2099-01-01T00:00:00Z",
    },
    ...extra,
  };
}

async function createExternal(env, { token = "co-p3q", body = createBody() } = {}) {
  const res = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests/create-external", { token, body }),
    env,
    {},
  );
  const json = await res.json();
  return { res, json };
}

function inviteTokenFromUrl(invitationUrl) {
  const url = new URL(invitationUrl);
  return decodeURIComponent(url.pathname.replace(/^\/l\/i\//, ""));
}

async function redeemInvite(env, invitationUrl) {
  const token = inviteTokenFromUrl(invitationUrl);
  const res = await worker.fetch(
    new Request(`https://booking.internal/l/i/${encodeURIComponent(token)}`, { method: "GET" }),
    env,
    {},
  );
  return { res, cookie: res.headers.get("set-cookie") || "", location: res.headers.get("location") || "" };
}

function cookieHeader(setCookie) {
  return String(setCookie || "").split(";")[0];
}

async function listInbox(env, token = "co-p3q") {
  const res = await worker.fetch(
    new Request(
      `https://booking.internal/admin/limousine/quote-requests?tenant_id=${TENANT}&company_id=${COMPANY}`,
      { method: "GET", headers: { authorization: `Bearer ${token}` } },
    ),
    env,
    {},
  );
  const json = await res.json();
  return { res, json };
}

async function respondQuote(env, { id, expectedRevision, total = 110000 }) {
  const res = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests/respond", {
      token: "co-p3q",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        quote_request_id: id,
        action: "quote",
        expected_revision: expectedRevision,
        quote: {
          entered_amount_cents: total,
          currency: "EUR",
          vat_treatment: "excl",
          terms: { ...TERMS, terms_revision: 4 },
          public_text: { nl: "Heraanbieding" },
          expires_at: "2099-02-01T00:00:00Z",
        },
      },
    }),
    env,
    {},
  );
  const json = await res.json();
  return { res, json };
}

test("1) company can create own-customer quote", async () => {
  const { env } = await setup();
  const { res, json } = await createExternal(env);
  assert.equal(res.status, 200, JSON.stringify(json));
  assert.equal(json.ok, true);
  assert.equal(json.quote_request.origin_channel, LIMOUSINE_EXTERNAL_ORIGIN);
  assert.ok(String(json.quote_request.quote_request_id).startsWith("limq_"));
});

test("2) protected contact is linked", async () => {
  const { env, kv } = await setup();
  const { json } = await createExternal(env);
  const id = json.quote_request.quote_request_id;
  const record = await kv.get(`limousine_quote_record:${id}`, { type: "json" });
  assert.ok(record.external_contact_id);
  const contact = await kv.get(`limousine_external_contact:${record.external_contact_id}`, { type: "json" });
  assert.equal(contact.mail, "ada@example.test");
  assert.equal(contact.locale, "nl");
  assert.equal(projectLimousineCompanyContactSummary(contact).display_name, "Ada Lovelace");
});

test("3/4) quote appears in existing inbox with own-customer origin", async () => {
  const { env } = await setup();
  const created = await createExternal(env);
  const listed = await listInbox(env);
  assert.equal(listed.res.status, 200, JSON.stringify(listed.json));
  const item = (listed.json.items || []).find(
    (row) => row.quote_request_id === created.json.quote_request.quote_request_id,
  );
  assert.ok(item, JSON.stringify(listed.json));
  assert.equal(item.origin_channel, LIMOUSINE_EXTERNAL_ORIGIN);
  assert.equal(item.contact_display_name, "Ada Lovelace");
  assert.equal(item.email, undefined);
  assert.equal(item.phone, undefined);
  assert.equal(item.customer_name, undefined);
});

test("5/6) pax 8 and bags 2 are preserved", async () => {
  const { env } = await setup();
  const { json } = await createExternal(env);
  assert.equal(json.quote_request.pax, 8);
  assert.equal(json.quote_request.bags, 2);
});

test("7) vehicle seller ownership is validated", async () => {
  const { env } = await setup();
  const { res, json } = await createExternal(env, {
    body: {
      ...createBody(),
      request: {
        ...createBody().request,
        vehicle_id: "veh_other_company",
      },
    },
  });
  assert.equal(res.status, 400, JSON.stringify(json));
  assert.match(String(json.error || ""), /vehicle|scope|published|unknown/i);
});

test("8/9) VAT is frozen from company profile with explicit %", async () => {
  const { env } = await setup();
  const { json } = await createExternal(env);
  const quote = json.quote_request.quote;
  assert.equal(quote.vat_rate, 0.06);
  assert.equal(quote.vat_treatment, "excl");
  assert.equal(quote.total_ex_vat_cents, 100000);
  assert.equal(quote.vat_amount_cents, 6000);
  assert.equal(quote.total_incl_vat_cents, 106000);
});

test("10) cancellation terms are frozen", async () => {
  const { env } = await setup();
  const { json } = await createExternal(env);
  const terms = json.quote_request.quote.terms || {};
  assert.equal(terms.cancellation_deadline_hours, 24);
  assert.equal(terms.cancellation_penalty_percent, 25);
  assert.equal(terms.no_show_penalty_percent, 100);
});

test("11) invitation is generated", async () => {
  const { env } = await setup();
  const { json } = await createExternal(env);
  assert.ok(String(json.invitation_url).includes("/l/i/"));
  assert.ok(!json.invitation_url.includes("status_ref"));
  assert.ok(!json.invitation_url.includes("acceptance_ref"));
});

test("12) PII is not in the public projection", async () => {
  const { env, kv } = await setup();
  const { json } = await createExternal(env);
  const record = await kv.get(`limousine_quote_record:${json.quote_request.quote_request_id}`, { type: "json" });
  const publicView = publicLimousineQuoteView(record);
  const guestView = publicLimousineExternalCustomerView(record);
  assert.equal(publicProjectionContainsExternalPii(publicView).length, 0);
  assert.equal(publicProjectionContainsExternalPii(guestView).length, 0);
  assert.equal(publicView.contact_display_name, undefined);
  assert.ok(!JSON.stringify(publicView).includes("ada@example.test"));
  assert.ok(!JSON.stringify(guestView).includes("+32470000000"));
});

test("13) quote id alone is insufficient", async () => {
  const { env } = await setup();
  const { json } = await createExternal(env);
  const id = json.quote_request.quote_request_id;
  const bare = await worker.fetch(
    new Request(`https://booking.internal/l/q?quote=${id}`, { method: "GET" }),
    env,
    {},
  );
  assert.equal(bare.status, 401);
});

test("14/15) invitation session and PDF work", async () => {
  const { env } = await setup();
  const created = await createExternal(env);
  const redeemed = await redeemInvite(env, created.json.invitation_url);
  assert.equal(redeemed.res.status, 302);
  assert.ok(redeemed.cookie.startsWith("fx_lxs="));
  const api = await worker.fetch(
    new Request("https://booking.internal/l/api/quotation", {
      method: "GET",
      headers: { cookie: cookieHeader(redeemed.cookie) },
    }),
    env,
    {},
  );
  const body = await api.json();
  assert.equal(api.status, 200, JSON.stringify(body));
  assert.equal(body.quote_request.quote.vat_rate, 0.06);
  const pdf = await worker.fetch(
    new Request("https://booking.internal/l/api/quotation.pdf", {
      method: "GET",
      headers: { cookie: cookieHeader(redeemed.cookie) },
    }),
    env,
    {},
  );
  assert.equal(pdf.status, 200);
  assert.ok(String(pdf.headers.get("cache-control") || "").includes("no-store"));
});

test("16/17/19) accept and manual book work on the existing engines", async () => {
  const { env, kv } = await setup();
  const created = await createExternal(env);
  const redeemed = await redeemInvite(env, created.json.invitation_url);
  const accepted = await worker.fetch(
    jsonReq("/l/api/accept", {
      headers: { cookie: cookieHeader(redeemed.cookie) },
      body: { expected_revision: created.json.quote_request.revision },
    }),
    env,
    {},
  );
  const acceptedJson = await accepted.json();
  assert.equal(accepted.status, 200, JSON.stringify(acceptedJson));
  assert.equal(acceptedJson.quote_request.state, "accepted");
  const booked = await worker.fetch(
    jsonReq("/l/api/book", {
      headers: { cookie: cookieHeader(redeemed.cookie) },
      body: {
        payment_method: "qr_code",
        __booking_id: "2026-08-801",
        __public_booking_reference: "FLX-P3Q-801",
        __planning_reference: "PLN-P3Q-801",
      },
    }),
    env,
    {},
  );
  const body = await booked.json();
  assert.equal(booked.status, 200, JSON.stringify(body));
  const stored = await kv.get("booking:2026-08-801", { type: "json" });
  assert.equal(String(stored.payment_mode || stored.paymentMode).toLowerCase(), "manual");
  const loaded = await kv.get(
    `limousine_quote_record:${created.json.quote_request.quote_request_id}`,
    { type: "json" },
  );
  assert.equal(loaded?.state, "booking_created");
});

test("18) Mollie path stays the existing booking engine", () => {
  assert.ok(WORKER_SRC.includes('pathname === "/l/api/book"'));
  assert.ok(WORKER_SRC.includes("handleBooking(normalizedBody"));
  assert.ok(WORKER_SRC.includes('payment_mode: mollieMethod ? "mollie" : "manual"'));
});

test("20) re-quote revision works before acceptance", async () => {
  const { env } = await setup();
  const created = await createExternal(env);
  const requote = await respondQuote(env, {
    id: created.json.quote_request.quote_request_id,
    expectedRevision: created.json.quote_request.revision,
    total: 110000,
  });
  assert.equal(requote.res.status, 200, JSON.stringify(requote.json));
  assert.equal(requote.json.quote_request.state, "customer_acceptance_required");
  assert.ok(requote.json.quote_request.revision > created.json.quote_request.revision);
  assert.equal(requote.json.quote_request.quote.total_ex_vat_cents, 110000);
});

test("21) accepted revision is immutable", async () => {
  const { env, kv } = await setup();
  const created = await createExternal(env);
  const redeemed = await redeemInvite(env, created.json.invitation_url);
  const accepted = await worker.fetch(
    jsonReq("/l/api/accept", {
      headers: { cookie: cookieHeader(redeemed.cookie) },
      body: { expected_revision: created.json.quote_request.revision },
    }),
    env,
    {},
  );
  const acceptedJson = await accepted.json();
  const requote = await respondQuote(env, {
    id: created.json.quote_request.quote_request_id,
    expectedRevision: acceptedJson.quote_request.revision,
    total: 120000,
  });
  assert.equal(requote.res.status, 409, JSON.stringify(requote.json));
  const loaded = await kv.get(
    `limousine_quote_record:${created.json.quote_request.quote_request_id}`,
    { type: "json" },
  );
  assert.equal(loaded.state, "accepted");
  assert.equal(loaded.quote.total_ex_vat_cents, 100000);
});

test("22/23) no second invoice engine; Billit/Peppol path unchanged", () => {
  assert.ok(!WORKER_SRC.includes("createLimousineInvoiceEngine"));
  assert.ok(WORKER_SRC.includes("_acceptLimousineQuoteRecord"));
  assert.ok(WORKER_SRC.includes("_attachLimousineQuotationSnapshotAtSend"));
  const createStart = WORKER_SRC.indexOf('"/admin/limousine/quote-requests/create-external"');
  const createEnd = WORKER_SRC.indexOf("const _limousineExternalInviteAction");
  const slice = WORKER_SRC.slice(createStart, createEnd);
  assert.ok(!slice.toLowerCase().includes("billit.create"));
  assert.ok(!slice.toLowerCase().includes("peppol"));
});

test("24) taxi street-ride flow is unchanged", () => {
  assert.ok(WORKER_SRC.includes("booking_source: \"street_ride\""));
  const createStart = WORKER_SRC.indexOf('"/admin/limousine/quote-requests/create-external"');
  const createEnd = WORKER_SRC.indexOf("const _limousineExternalInviteAction");
  const slice = WORKER_SRC.slice(createStart, createEnd);
  assert.ok(!slice.includes("taxi_qr"));
  assert.ok(!slice.includes("street_ride"));
});
