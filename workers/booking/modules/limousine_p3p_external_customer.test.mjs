// P3P — external customer quotation invitations + guest accept/book.
// Run: node --test workers/booking/modules/limousine_p3p_external_customer.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import worker from "../fluxidi_booking_worker.js";
import {
  LIMOUSINE_EXTERNAL_ORIGIN,
  LIMOUSINE_EXTERNAL_ERRORS,
  buildLimousineExternalInvitationUrl,
  guestCustomerFromExternalContact,
  limousineExternalInvitationBindingMatches,
  looksLikeLimousineInviteToken,
  projectLimousineCompanyContactSummary,
  publicLimousineExternalCustomerView,
  publicProjectionContainsExternalPii,
  sanitizeLimousineExternalLog,
  sealLimousineExternalInvitation,
  unsealLimousineExternalInvitation,
  validateLimousineExternalContact,
  withLimousineExternalDeliveryView,
} from "./limousine_external_customer.mjs";
import { publicLimousineQuoteView } from "./limousine_manual_quote.mjs";
import { renderLimousineExternalQuotationPage } from "./limousine_external_customer_page.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const WORKER_SRC = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const ADMIN = "test-admin-token";
const TENANT = "fluxidi_limo_p3p";
const COMPANY = "company_limo_p3p";
const OTHER_TENANT = "fluxidi_other_p3p";
const OTHER_COMPANY = "company_other_p3p";
const SECRET = "p3p-acceptance-secret-not-production";
const PUBLIC_PARTNER = `company:${TENANT}:${COMPANY}`;
const OTHER_PUBLIC_PARTNER = `company:${OTHER_TENANT}:${OTHER_COMPANY}`;
const VEHICLE = "veh_limo_p3p";
const OFFER = "off_party_p3p";
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
  const companyHash = await sha256Hex("co-p3p");
  const otherHash = await sha256Hex("co-other-p3p");
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
        company_name: "P3P Limo",
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
        trading_name: "P3P Limo",
        legal_name: "P3P Limo BV",
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
            JSON.stringify({ ok: true, document_reference: "DOC-P3P-1" }),
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
      locale: "nl",
      company_name: "Analytical Engines",
    },
    request: {
      offer_id: OFFER,
      vehicle_id: VEHICLE,
      journey_type: "point_to_point",
      from: "Korenmarkt 1, Gent",
      to: "Graslei, Gent",
      scheduled_pickup_iso: "2026-09-01T16:00:00.000Z",
      locale: "nl",
      pax: 8,
      bags: 2,
      occasion: "wedding",
    },
    quote: {
      entered_amount_cents: 80000,
      currency: "EUR",
      vat_treatment: "excl",
      terms: TERMS,
      public_text: { nl: "Vaste prijs", en: "Fixed price" },
      expires_at: "2099-01-01T00:00:00Z",
    },
    ...extra,
  };
}

async function createExternal(env, { token = "co-p3p", body = createBody() } = {}) {
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
  const first = String(setCookie || "").split(";")[0];
  return first;
}

test("1) company can create external customer quote", async () => {
  const { env } = await setup();
  const { res, json } = await createExternal(env);
  assert.equal(res.status, 200, JSON.stringify(json));
  assert.equal(json.ok, true);
  assert.equal(json.quote_request.origin_channel, LIMOUSINE_EXTERNAL_ORIGIN);
  assert.equal(json.quote_request.pax, 8);
  assert.equal(json.quote_request.bags, 2);
  assert.equal(json.quote_request.quote.vat_rate, 0.06);
  assert.ok(String(json.invitation_url).includes("/l/i/"));
  assert.equal(json.contact.display_name, "Ada Lovelace");
});

test("2/3) contact record is protected and excluded from public projection", async () => {
  const { env, kv } = await setup();
  const { json } = await createExternal(env);
  const id = json.quote_request.quote_request_id;
  const record = await kv.get(`limousine_quote_record:${id}`, { type: "json" });
  const publicView = publicLimousineQuoteView(record);
  const guestView = publicLimousineExternalCustomerView(record);
  assert.equal(publicProjectionContainsExternalPii(publicView).length, 0);
  assert.equal(publicProjectionContainsExternalPii(guestView).length, 0);
  assert.equal(publicView.email, undefined);
  assert.equal(publicView.phone, undefined);
  assert.equal(publicView.customer_name, undefined);
  assert.ok(record.external_contact_id);
  const contact = await kv.get(`limousine_external_contact:${record.external_contact_id}`, { type: "json" });
  assert.equal(contact.mail, "ada@example.test");
  assert.equal(projectLimousineCompanyContactSummary(contact).mail, "ada@example.test");
  assert.ok(!JSON.stringify(publicView).includes("ada@example.test"));
});

test("4) invitation token is generated and quote id is not the token", async () => {
  const { env } = await setup();
  const { json } = await createExternal(env);
  const token = inviteTokenFromUrl(json.invitation_url);
  assert.equal(looksLikeLimousineInviteToken(token), true);
  assert.notEqual(token, json.quote_request.quote_request_id);
  assert.ok(!json.invitation_url.includes("status_ref"));
  assert.ok(!json.invitation_url.includes("limqs1"));
});

test("5) quote id alone is insufficient", async () => {
  const { env } = await setup();
  const { json } = await createExternal(env);
  const id = json.quote_request.quote_request_id;
  const bare = await worker.fetch(
    new Request(`https://booking.internal/l/q?quote=${id}`, { method: "GET" }),
    env,
    {},
  );
  assert.equal(bare.status, 401);
  const api = await worker.fetch(
    new Request(`https://booking.internal/l/api/quotation?quote_request_id=${id}`, { method: "GET" }),
    env,
    {},
  );
  const apiJson = await api.json();
  assert.equal(api.status, 401);
  assert.equal(apiJson.error, LIMOUSINE_EXTERNAL_ERRORS.SESSION_REQUIRED);
});

test("6) invalid token is rejected", async () => {
  const { env } = await setup();
  const res = await worker.fetch(
    new Request("https://booking.internal/l/i/liminv1.notavalidtokenvalueherexx.alsoinvalidciphertextvalue", {
      method: "GET",
    }),
    env,
    {},
  );
  assert.equal(res.status, 404);
});

test("7/8) wrong company or wrong quote is rejected", async () => {
  const { env } = await setup();
  const created = await createExternal(env);
  const token = inviteTokenFromUrl(created.json.invitation_url);
  const unsealed = await unsealLimousineExternalInvitation({ secret: SECRET, reference: token });
  assert.equal(unsealed.ok, true);
  const mismatch = limousineExternalInvitationBindingMatches(unsealed.binding, {
    ...unsealed.binding,
    company_id: OTHER_COMPANY,
  });
  assert.equal(mismatch, false);
  const wrongQuote = limousineExternalInvitationBindingMatches(unsealed.binding, {
    ...unsealed.binding,
    quote_request_id: "limq_otherquote00000000000",
  });
  assert.equal(wrongQuote, false);
  const other = await createExternal(env, {
    token: "co-other-p3p",
    body: {
      ...createBody(),
      tenant_id: OTHER_TENANT,
      company_id: OTHER_COMPANY,
    },
  });
  assert.notEqual(other.res.status, 200);
});

test("9) expired invitation is rejected", async () => {
  const sealed = await sealLimousineExternalInvitation({
    secret: SECRET,
    binding: {
      tenant_id: TENANT,
      company_id: COMPANY,
      quote_request_id: "limq_expired0000000000001",
      invitation_id: "limxi_expired",
      contact_id: "limxc_expired",
    },
    issuedAtIso: "2020-01-01T00:00:00.000Z",
    ttlMinutes: 1,
  });
  const opened = await unsealLimousineExternalInvitation({
    secret: SECRET,
    reference: sealed.reference,
    nowIso: "2026-08-23T00:00:00.000Z",
  });
  assert.equal(opened.ok, false);
  assert.equal(opened.error, LIMOUSINE_EXTERNAL_ERRORS.EXPIRED_INVITATION);
});

test("10) clean session is established after invite", async () => {
  const { env } = await setup();
  const created = await createExternal(env);
  const redeemed = await redeemInvite(env, created.json.invitation_url);
  assert.equal(redeemed.res.status, 302);
  assert.equal(redeemed.location.endsWith("/l/q"), true);
  assert.ok(redeemed.cookie.startsWith("fx_lxs="));
  assert.ok(!redeemed.location.includes("liminv1"));
  const page = await worker.fetch(
    new Request("https://booking.internal/l/q", {
      method: "GET",
      headers: { cookie: cookieHeader(redeemed.cookie) },
    }),
    env,
    {},
  );
  assert.equal(page.status, 200);
  const html = await page.text();
  assert.ok(html.includes("Offerte"));
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
  assert.equal(body.trip.from.includes("Korenmarkt"), true);
});

test("11) PDF view works from the guest session", async () => {
  const { env } = await setup();
  const created = await createExternal(env);
  const redeemed = await redeemInvite(env, created.json.invitation_url);
  const pdf = await worker.fetch(
    new Request("https://booking.internal/l/api/quotation.pdf", {
      method: "GET",
      headers: { cookie: cookieHeader(redeemed.cookie) },
    }),
    env,
    {},
  );
  assert.equal(pdf.status, 200);
  assert.equal(pdf.headers.get("content-type"), "application/pdf");
  assert.ok(String(pdf.headers.get("cache-control") || "").includes("no-store"));
});

test("12/13) acceptance uses exact revision and rejects stale revision", async () => {
  const { env } = await setup();
  const created = await createExternal(env);
  const redeemed = await redeemInvite(env, created.json.invitation_url);
  const stale = await worker.fetch(
    jsonReq("/l/api/accept", {
      headers: { cookie: cookieHeader(redeemed.cookie) },
      body: { expected_revision: 1 },
    }),
    env,
    {},
  );
  const staleJson = await stale.json();
  assert.equal(stale.status, 409, JSON.stringify(staleJson));
  const ok = await worker.fetch(
    jsonReq("/l/api/accept", {
      headers: { cookie: cookieHeader(redeemed.cookie) },
      body: { expected_revision: created.json.quote_request.revision },
    }),
    env,
    {},
  );
  const accepted = await ok.json();
  assert.equal(ok.status, 200, JSON.stringify(accepted));
  assert.equal(accepted.quote_request.state, "accepted");
  assert.equal(accepted.acceptance_reference, undefined);
});

test("14/16) booking after acceptance reuses the manual path", async () => {
  const { env, kv } = await setup();
  const created = await createExternal(env);
  const redeemed = await redeemInvite(env, created.json.invitation_url);
  await worker.fetch(
    jsonReq("/l/api/accept", {
      headers: { cookie: cookieHeader(redeemed.cookie) },
      body: { expected_revision: created.json.quote_request.revision },
    }),
    env,
    {},
  );
  const booked = await worker.fetch(
    jsonReq("/l/api/book", {
      headers: { cookie: cookieHeader(redeemed.cookie) },
      body: {
        payment_method: "qr_code",
        __booking_id: "2026-08-701",
        __public_booking_reference: "FLX-P3P-701",
        __planning_reference: "PLN-P3P-701",
      },
    }),
    env,
    {},
  );
  const body = await booked.json();
  assert.equal(booked.status, 200, JSON.stringify(body));
  const stored = await kv.get("booking:2026-08-701", { type: "json" });
  assert.ok(stored, JSON.stringify(body));
  assert.equal(String(stored.payment_mode || stored.paymentMode).toLowerCase(), "manual");
  const loaded = await kv.get(
    `limousine_quote_record:${created.json.quote_request.quote_request_id}`,
    { type: "json" },
  );
  assert.equal(loaded?.state, "booking_created");
  assert.ok(String(loaded?.booking_reference || "").length > 0);
  const keys = [...kv.store.keys()].join(",");
  assert.ok(!keys.toLowerCase().includes("billit_outbox"));
  assert.ok(!keys.toLowerCase().includes("peppol_outbox"));
});

test("15) Mollie path is reused by guest book", () => {
  assert.ok(WORKER_SRC.includes('pathname === "/l/api/book"'));
  assert.ok(WORKER_SRC.includes("handleBooking(normalizedBody"));
  assert.ok(WORKER_SRC.includes("limousine_acceptance_reference: acceptanceReference"));
  assert.ok(WORKER_SRC.includes("payment_method: paymentMethod"));
  assert.ok(WORKER_SRC.includes('payment_mode: mollieMethod ? "mollie" : "manual"'));
  assert.ok(WORKER_SRC.includes("await _markLimousineAcceptedQuoteConsumed(env,"));
});

test("17/18) no second invoice engine and Billit/Peppol stay untouched", () => {
  assert.ok(!WORKER_SRC.includes("createLimousineInvoiceEngine"));
  assert.ok(WORKER_SRC.includes("_acceptLimousineQuoteRecord"));
  assert.ok(WORKER_SRC.includes("_attachLimousineQuotationSnapshotAtSend"));
  const p3pSlice = WORKER_SRC.slice(
    WORKER_SRC.indexOf("P3P — external customer invitation"),
    WORKER_SRC.indexOf("LIMOUSINE-MARKETPLACE-P2C2 — manual quote lifecycle"),
  );
  assert.ok(!p3pSlice.toLowerCase().includes("billit.create"));
  assert.ok(!p3pSlice.toLowerCase().includes("peppol"));
});

test("19) PII is not logged", () => {
  const cleaned = sanitizeLimousineExternalLog({
    quote_request_id: "limq_x",
    email: "hidden@example.test",
    phone: "+32470000000",
    invitation_token: "liminv1.aaa.bbb",
    display_name: "Ada",
    origin: LIMOUSINE_EXTERNAL_ORIGIN,
  });
  assert.equal(cleaned.email, undefined);
  assert.equal(cleaned.phone, undefined);
  assert.equal(cleaned.invitation_token, undefined);
  assert.equal(cleaned.display_name, undefined);
  assert.equal(cleaned.quote_request_id, "limq_x");
});

test("20) create-external replay is idempotent", async () => {
  const { env } = await setup();
  const first = await createExternal(env);
  const second = await createExternal(env);
  assert.equal(second.json.idempotent, true);
  assert.equal(second.json.quote_request.quote_request_id, first.json.quote_request.quote_request_id);
});

test("contact validation and page localization/breakpoints", () => {
  assert.equal(validateLimousineExternalContact({ name: "Ada" }).ok, false);
  assert.equal(validateLimousineExternalContact({ name: "Ada", email: "ada@example.test" }).ok, true);
  const nl = renderLimousineExternalQuotationPage({ locale: "nl" });
  const en = renderLimousineExternalQuotationPage({ locale: "en" });
  const fr = renderLimousineExternalQuotationPage({ locale: "fr" });
  const es = renderLimousineExternalQuotationPage({ locale: "es" });
  assert.ok(nl.includes("Offerte"));
  assert.ok(en.includes("Quotation"));
  assert.ok(fr.includes("Devis"));
  assert.ok(es.includes("Presupuesto"));
  assert.ok(nl.includes("min-width:360px"));
  assert.ok(nl.includes("min-width:390px"));
  assert.ok(nl.includes("min-width:430px"));
  assert.ok(nl.includes("min-width:768px"));
  assert.ok(nl.includes("min-width:1100px"));
  assert.ok(nl.includes("/l/api/quotation.pdf"));
  assert.ok(nl.includes("/l/api/accept"));
  assert.ok(nl.includes("/l/api/book"));
  const guest = guestCustomerFromExternalContact({
    display_name: "Ada",
    mail: "ada@example.test",
    mobile: "+32470000000",
  });
  assert.equal(guest.email, "ada@example.test");
  const delivery = withLimousineExternalDeliveryView(
    { quote_request_id: "limq_x" },
    { invitation_id: "limxi_x", created_at: "2026-08-23T10:00:00.000Z" },
    { origin: { channel: LIMOUSINE_EXTERNAL_ORIGIN } },
  );
  assert.equal(delivery.external_delivery.invitation_state, "link_created");
  assert.equal(
    buildLimousineExternalInvitationUrl("https://booking.internal", "liminv1.aaa.bbb").includes("/l/i/"),
    true,
  );
});

test("status_ref contract stays out of the invitation URL model", () => {
  assert.ok(WORKER_SRC.includes("_parseLimousineInvitePathToken"));
  assert.ok(WORKER_SRC.includes("_buildLimousineExternalInvitationUrl"));
  assert.ok(WORKER_SRC.includes("_limousineExternalSessionCookieHeader"));
  assert.ok(WORKER_SRC.includes("_buildLimousineExternalCleanUrl"));
  assert.ok(!WORKER_SRC.includes("/l/i/${sealedStatus"));
});
