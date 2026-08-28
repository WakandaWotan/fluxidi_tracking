/* BILLIT-CONSUMER-PROD-CREATE-1 — production consumer-sale CREATE + manual
 * recovery, and the all-ride-family acceptance matrix.
 *
 * Background: private street rides were correctly classified as consumer_sale
 * and routed through maybeRegisterConsumerBillitSaleAfterCompletion(), but that
 * engine carried a literal `config.environment === "sandbox"` gate around the
 * whole Billit create block. In production the block was skipped silently: the
 * Document Core invoice was issued, the sale intent stayed at billit_creating
 * with last_error=null, nothing was enqueued for retry, and no Billit order was
 * ever created.
 *
 * Proves:
 *   - consumer-sale CREATE runs in production AND still runs in sandbox;
 *   - an unmanaged/unknown environment is rejected and recorded (fail-closed);
 *   - the consumer Billit Idempotent-Key is environment-aware and stable;
 *   - a replay never mints a second Billit order;
 *   - the manual /billit/register route accepts consumer-sale invoices and
 *     reuses the SAME canonical sale-scoped Idempotent-Key as auto-create;
 *   - an OAuth disconnect blocks every create;
 *   - planned / street / limousine invoices all converge on the one canonical
 *     create engine, with frozen amounts posted verbatim;
 *   - limousine stays blocked while company confirmation is still pending;
 *   - Peppol / send is never triggered by any create or register path.
 *
 * Hermetic: global.fetch is a controllable mock; KV is an in-memory Map. No
 * live Billit, Cloudflare, or production credentials.
 *
 *   node --test workers/booking/billit_consumer_prod_create_p1.test.mjs
 */

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";

import worker, {
  maybeRegisterConsumerBillitSaleAfterCompletion,
  runPaidBookingAfterLifecycle,
} from "./fluxidi_booking_worker.js";
import {
  buildDocumentRegistryKey,
  buildDocumentsByBookingKey,
} from "./modules/document_core.js";
import {
  buildBillitConsumerSaleOrderCreateIdempotencyKey,
  buildConsumerSaleIdempotencyKey,
} from "./modules/consumer_billit_sale.mjs";
import {
  startBillitOAuthForScope,
  completeBillitOAuthCallback,
} from "./modules/billit_provider.js";
import { computeBillitOrderLinesTotalInclVatCents } from "./modules/billit_total_reconciliation.js";

const ADMIN = "test-admin-token";
const TENANT = "tenant_consumer_prod";
const COMPANY = "company_consumer_prod";
const SCOPE = { tenant_id: TENANT, company_id: COMPANY };
const PARTY_ID = "6532054";
const REDIRECT_URI =
  "https://fluxidi-booking-api.fluxidi.workers.dev/admin/integrations/billit/oauth/callback";
const NEW_ORDER_ID = "990011";

// ---------------------------------------------------------------------------
// Outbound mock. Records href + method + parsed body so tests can prove exactly
// which Billit endpoints were touched and what was posted.
// ---------------------------------------------------------------------------

let originalFetch;
let calls = [];
let handler = null;

before(() => {
  originalFetch = global.fetch;
  global.fetch = async (input, init) => {
    const href = typeof input === "string" ? input : input?.url || String(input);
    const method = String(init?.method || "GET").toUpperCase();
    let body = null;
    try {
      body = init?.body ? JSON.parse(String(init.body)) : null;
    } catch (_) {
      body = null;
    }
    const headers = {};
    try {
      new Headers(init?.headers || {}).forEach((v, k) => {
        headers[k.toLowerCase()] = v;
      });
    } catch (_) {
      /* ignore */
    }
    calls.push({ href, method, body, headers });
    if (typeof handler === "function") return handler(href, init, method);
    throw new Error(`hermetic test: unexpected fetch ${method} ${href}`);
  };
});

after(() => {
  global.fetch = originalFetch;
});

beforeEach(() => {
  calls = [];
  handler = null;
});

function createPosts() {
  return calls.filter((c) => c.method === "POST" && /\/v1\/orders$/.test(c.href));
}
function sendCalls() {
  return calls.filter((c) => /\/v1\/orders\/commands\/send/.test(c.href));
}

function installHappyBillit({ orderNumber = null } = {}) {
  handler = async (href, init, method) => {
    if (/\/OAuth2\/token/.test(href)) {
      return new Response(
        JSON.stringify({
          token_type: "Bearer",
          access_token: "prod-access-token-plain",
          refresh_token: "prod-refresh-token-plain",
          expires_in: 3600,
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    if (/\/v1\/account\/accountInformation/.test(href)) {
      return new Response(JSON.stringify({ Companies: [{ PartyID: PARTY_ID }] }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    if (/\/v1\/orders\/commands\/send/.test(href)) {
      throw new Error("hermetic test: SEND must never be called by create/register");
    }
    if (method === "POST" && /\/v1\/orders$/.test(href)) {
      return new Response(JSON.stringify(NEW_ORDER_ID), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    if (/\/v1\/orders\//.test(href)) {
      return new Response(
        JSON.stringify({
          OrderID: NEW_ORDER_ID,
          OrderNumber: orderNumber,
          OrderStatus: "Draft",
          Paid: false,
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    throw new Error(`hermetic test: unexpected fetch ${method} ${href}`);
  };
}

// ---------------------------------------------------------------------------
// KV + env.
// ---------------------------------------------------------------------------

function makeKV(seed = {}) {
  const store = new Map(
    Object.entries(seed).map(([k, v]) => [
      k,
      typeof v === "string" ? v : JSON.stringify(v),
    ]),
  );
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
    async list({ prefix = "", limit = 1000 } = {}) {
      const keys = [];
      for (const k of store.keys()) {
        if (k.startsWith(prefix)) {
          keys.push({ name: k });
          if (keys.length >= limit) break;
        }
      }
      return { keys, list_complete: true, cursor: undefined };
    },
  };
}

function businessProfile() {
  return {
    companyName: "Fluxidi Test BV",
    legalName: "Fluxidi Test BV",
    vatNumber: "BE0987654321",
    address: "Verkoperstraat 2",
    postcode: "8500",
    city: "Kortrijk",
    country: "BE",
    countryCode: "BE",
    locale: "nl",
    payment_terms_days: 30,
    enterpriseNumber: "0987654321",
    billit_auto_create_after_paid_business_invoice: true,
    billit_auto_create_environment: "production",
  };
}

const SELLER_SNAPSHOT = {
  legal_name: "Fluxidi Test BV",
  company_name: "Fluxidi Test BV",
  vat_number: "BE0987654321",
  street: "Verkoperstraat 2",
  postal_code: "8500",
  city: "Kortrijk",
  country: "BE",
  country_code: "BE",
};

// Exactly the shape production writes for a private street ride: a name-only
// buyer, no VAT number, no address, Peppol not applicable.
const CONSUMER_BUYER_SNAPSHOT = {
  customer_type: "private",
  name: "Straatrit",
  legal_name: "Straatrit",
  display_name: "Straatrit",
  email: null,
  vat_number: null,
  address_line: null,
  postal_code: null,
  city: null,
  country_code: null,
};

const BUSINESS_BUYER_SNAPSHOT = {
  customer_type: "business",
  legal_name: "ACME NV",
  display_name: "ACME NV",
  name: "ACME NV",
  contact_email: "billing@acme.example",
  email: "billing@acme.example",
  vat_number: "BE0123456789",
  company_registration_number: "0123456789",
  billing_address: {
    street: "Teststraat 1",
    postal_code: "8500",
    city: "Kortrijk",
    country: "BE",
  },
  peppol: { endpoint_id: "0208:0123456789", scheme: "0208" },
  address_line: "Teststraat 1",
  postal_code: "8500",
  city: "Kortrijk",
  country_code: "BE",
};

/** Canonical issued invoice registry record (frozen snapshot included). */
function issuedInvoiceRecord({
  documentId,
  documentNumber,
  bookingId,
  consumer = false,
  totalInclVat = 24.2,
  subtotalExVat = 20.0,
  vatAmount = 4.2,
  vatRatePercent = 21,
  currency = "EUR",
  billitExport = null,
  saleIdempotencyKey = null,
} = {}) {
  const totals = {
    total_incl_vat: totalInclVat,
    subtotal_ex_vat: subtotalExVat,
    vat_amount: vatAmount,
    vat_rate_percent: vatRatePercent,
    currency,
  };
  const buyerSnapshot = consumer ? CONSUMER_BUYER_SNAPSHOT : BUSINESS_BUYER_SNAPSHOT;
  const record = {
    tenant_id: TENANT,
    company_id: COMPANY,
    document_id: documentId,
    document_type: "invoice",
    document_number: documentNumber,
    lifecycle_state: "issued",
    document_status: "issued",
    source_booking_id: bookingId,
    is_leg_scoped: false,
    currency,
    totals,
    buyer_snapshot: buyerSnapshot,
    seller_snapshot: SELLER_SNAPSHOT,
    issue_timestamp: "2026-08-28T10:49:44.375Z",
    content_hash: "test-content-hash",
    immutable_snapshot: {
      tenant_id: TENANT,
      company_id: COMPANY,
      document_id: documentId,
      document_type: "invoice",
      document_number: documentNumber,
      issue_timestamp: "2026-08-28T10:49:44.375Z",
      source_booking_id: bookingId,
      currency,
      totals: { ...totals },
      seller_snapshot: SELLER_SNAPSHOT,
      buyer_snapshot: buyerSnapshot,
    },
  };
  if (consumer) {
    record.fluxidi_sale_kind = "consumer_sale";
    record.created_by_role = "system_consumer_sale";
    record.presentation_label_key = "consumerSale";
    record.peppol_applicable = false;
    record.idempotency_key =
      saleIdempotencyKey ||
      buildConsumerSaleIdempotencyKey({
        tenantId: TENANT,
        companyId: COMPANY,
        bookingId,
      });
  }
  if (billitExport) record.billit_export = billitExport;
  return record;
}

function makeEnv({
  billitEnvironment = "production",
  documents = [],
  bookings = {},
  billitConfigured = true,
} = {}) {
  const seed = {
    [`tenant:${TENANT}:company:${COMPANY}:business_profile:v1`]: businessProfile(),
  };
  for (const record of documents) {
    seed[buildDocumentRegistryKey(SCOPE, record.document_id)] = record;
    seed[
      buildDocumentsByBookingKey(
        SCOPE,
        record.source_booking_id,
        "invoice",
        record.document_id,
      )
    ] = record.document_id;
  }
  for (const [bookingId, rec] of Object.entries(bookings)) {
    seed[`booking:${bookingId}`] = rec;
  }
  const bookingKv = makeKV(seed);
  const env = { ADMIN_TOKEN: ADMIN, BOOKING_KV: bookingKv };
  // Present so the binding guard passes, but fatal if actually used: every test
  // here reuses an already-issued canonical invoice, so Document Core must
  // never allocate a new number.
  env.DOCUMENT_REFERENCE_SEQUENCE = {
    idFromName() {
      throw new Error("Document Core must not mint a new number in these tests");
    },
    get() {
      throw new Error("Document Core must not mint a new number in these tests");
    },
  };
  if (billitEnvironment) env.BILLIT_ENVIRONMENT = billitEnvironment;
  if (billitConfigured) {
    env.BILLIT_CLIENT_ID = "test-client-id";
    env.BILLIT_CLIENT_SECRET = "test-client-secret";
    env.BILLIT_REDIRECT_URI = REDIRECT_URI;
    env.BILLIT_TOKEN_ENCRYPTION_KEY = "test-billit-token-encryption-key";
  }
  return { env, bookingKv };
}

/** Real OAuth start+callback so the stored connection has a decryptable token. */
async function seedConnectedOAuth(env) {
  installHappyBillit();
  const started = await startBillitOAuthForScope(env, SCOPE);
  assert.equal(started.status, 200, JSON.stringify(started.body));
  const authUrl = new URL(started.body.authorization_url);
  const result = await completeBillitOAuthCallback(env, {
    code: "auth-code",
    state: authUrl.searchParams.get("state"),
  });
  assert.equal(result.outcome, "connected", JSON.stringify(result));
}

function registerRequest(documentId, { body = {}, prefix = "company" } = {}) {
  const q = `tenant_id=${encodeURIComponent(TENANT)}&company_id=${encodeURIComponent(COMPANY)}`;
  return new Request(
    `https://booking.internal/${prefix}/documents/${documentId}/billit/register?${q}`,
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-admin-token": ADMIN },
      body: JSON.stringify({
        tenant_id: TENANT,
        company_id: COMPANY,
        confirm_billit_register: true,
        ...body,
      }),
    },
  );
}

// ---------------------------------------------------------------------------
// Consumer-sale booking + injectable impls (fast engine-level tests).
// ---------------------------------------------------------------------------

function consumerStreetBooking(bookingId, over = {}) {
  return {
    booking_id: bookingId,
    tenant_id: TENANT,
    company_id: COMPANY,
    status: "COMPLETED",
    ride_type: "direct",
    source: "street_ride",
    street_ride_fare_finalized: true,
    price_incl_vat: 5.3,
    total_incl_vat: 5.3,
    currency: "EUR",
    booking: { currency: "EUR", price_incl_vat: 5.3 },
    payload: { currency: "EUR", price_incl_vat: 5.3 },
    pricing_profile: { currency: "EUR", vat_rate: 0.06 },
    vat_rate_percent: 6,
    invoice_intent: "none",
    payment_status: "paid",
    payment_method: "cash",
    custName: "Straatrit",
    ...over,
  };
}

function makeIssueImpl(env, bookingId, docId, docNumber) {
  let issueCalls = 0;
  const issueInvoiceImpl = async ({ body }) => {
    issueCalls += 1;
    const record = issuedInvoiceRecord({
      documentId: docId,
      documentNumber: docNumber,
      bookingId,
      consumer: true,
      totalInclVat: 5.3,
      subtotalExVat: 5.0,
      vatAmount: 0.3,
      vatRatePercent: 6,
      saleIdempotencyKey: body?.idempotency_key || null,
    });
    await env.BOOKING_KV.put(
      buildDocumentRegistryKey(SCOPE, docId),
      JSON.stringify(record),
    );
    await env.BOOKING_KV.put(
      buildDocumentsByBookingKey(SCOPE, bookingId, "invoice", docId),
      docId,
    );
    return {
      ok: true,
      status: 200,
      async json() {
        return {
          ok: true,
          document_id: docId,
          document_number: docNumber,
          document_record: record,
        };
      },
    };
  };
  return {
    get issueCalls() {
      return issueCalls;
    },
    issueInvoiceImpl,
  };
}

function makeBillitImpl({ orderId = NEW_ORDER_ID } = {}) {
  let createCalls = 0;
  const keys = [];
  const environments = [];
  const ensureBillitOrderImpl = async (_env, _scope, config, documentRecord, opts = {}) => {
    createCalls += 1;
    const activeEnvironment = String(config?.environment || "").toLowerCase();
    environments.push(activeEnvironment);
    const saleKey = opts.saleIdempotencyKey || null;
    const idem =
      (saleKey
        ? buildBillitConsumerSaleOrderCreateIdempotencyKey(saleKey, activeEnvironment)
        : null) || `legacy:${opts.documentId}`;
    keys.push(idem);
    if (documentRecord && typeof documentRecord === "object") {
      documentRecord.billit_export = {
        environment: activeEnvironment,
        order_id: orderId,
        order_number: opts.documentNumber || null,
        idempotency_key: idem,
        sent: false,
        peppol_sent: false,
      };
      await _env.BOOKING_KV.put(
        buildDocumentRegistryKey(SCOPE, opts.documentId),
        JSON.stringify(documentRecord),
      );
    }
    return {
      ok: true,
      billit_order_id: orderId,
      already_created: createCalls > 1,
      idempotency_key: idem,
    };
  };
  return {
    get createCalls() {
      return createCalls;
    },
    keys,
    environments,
    ensureBillitOrderImpl,
  };
}

async function readBookingMarker(env, bookingId) {
  const rec = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: "json" });
  return rec?.consumer_sale || null;
}

// ===========================================================================
// A. Consumer-sale CREATE gate: production, sandbox, unknown.
// ===========================================================================

test("A1. production consumer-sale auto-create runs and produces exactly one order", async () => {
  const bookingId = "street_prod_consumer_1";
  const { env } = makeEnv({
    billitEnvironment: "production",
    bookings: { [bookingId]: consumerStreetBooking(bookingId) },
  });
  const issue = makeIssueImpl(env, bookingId, "doc-prod-c1", "INV-2026-000077");
  const billit = makeBillitImpl();

  const out = await maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  });

  assert.equal(out.ok, true);
  assert.equal(out.document_id, "doc-prod-c1");
  assert.equal(out.billit_order_id, NEW_ORDER_ID);
  assert.equal(out.reason, "created_or_linked");
  assert.equal(out.peppol_sent, false);
  assert.equal(issue.issueCalls, 1);
  assert.equal(billit.createCalls, 1, "exactly one Billit create");
  assert.equal(billit.environments[0], "production");

  const saleKey = buildConsumerSaleIdempotencyKey({
    tenantId: TENANT,
    companyId: COMPANY,
    bookingId,
  });
  assert.equal(
    billit.keys[0],
    buildBillitConsumerSaleOrderCreateIdempotencyKey(saleKey, "production"),
  );

  const marker = await readBookingMarker(env, bookingId);
  assert.equal(marker.status, "registered");
  assert.equal(marker.billit_order_id, NEW_ORDER_ID);
  assert.equal(marker.last_error, null);
  assert.equal(sendCalls().length, 0);
});

test("A2. sandbox consumer-sale auto-create still runs (no regression)", async () => {
  const bookingId = "street_sandbox_consumer_1";
  const { env } = makeEnv({
    billitEnvironment: "sandbox",
    bookings: { [bookingId]: consumerStreetBooking(bookingId) },
  });
  const issue = makeIssueImpl(env, bookingId, "doc-sbx-c1", "INV-2026-000078");
  const billit = makeBillitImpl();

  const out = await maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  });

  assert.equal(out.ok, true);
  assert.equal(out.billit_order_id, NEW_ORDER_ID);
  assert.equal(billit.createCalls, 1);
  assert.equal(billit.environments[0], "sandbox");

  const saleKey = buildConsumerSaleIdempotencyKey({
    tenantId: TENANT,
    companyId: COMPANY,
    bookingId,
  });
  // Legacy sandbox key shape is unchanged, byte for byte.
  assert.equal(billit.keys[0], `fluxidi-billit-consumer-order:${saleKey}:sandbox:v1`);
  assert.equal(sendCalls().length, 0);
});

test("A3. unmanaged environment is rejected, recorded, and creates nothing", async () => {
  const bookingId = "street_unknown_env_1";
  const { env } = makeEnv({
    billitEnvironment: "sandbox",
    bookings: { [bookingId]: consumerStreetBooking(bookingId) },
  });
  const issue = makeIssueImpl(env, bookingId, "doc-unk-c1", "INV-2026-000079");
  const billit = makeBillitImpl();

  const out = await maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
    // Defence-in-depth: resolveBillitOAuthConfig clamps to sandbox|production,
    // so an unmanaged value can only arrive via a future/other caller.
    configOverride: { environment: "staging", configured: true },
  });

  // The canonical invoice is still issued; only the Billit create is refused.
  assert.equal(out.ok, true);
  assert.equal(out.document_id, "doc-unk-c1");
  assert.equal(out.billit_order_id, null);
  assert.equal(out.reason, "document_issued_billit_pending");
  assert.equal(billit.createCalls, 0, "no Billit create for an unmanaged env");

  const marker = await readBookingMarker(env, bookingId);
  assert.equal(marker.status, "document_issued");
  assert.equal(marker.last_error, "billit_environment_unsupported");
  assert.equal(marker.retryable, true);
  assert.equal(sendCalls().length, 0);
});

test("A4. replay after a production create never mints a second Billit order", async () => {
  const bookingId = "street_prod_consumer_replay";
  const { env } = makeEnv({
    billitEnvironment: "production",
    bookings: { [bookingId]: consumerStreetBooking(bookingId) },
  });
  const issue = makeIssueImpl(env, bookingId, "doc-prod-replay", "INV-2026-000080");
  const billit = makeBillitImpl();

  const first = await maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  });
  const second = await maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  });

  assert.equal(first.billit_order_id, NEW_ORDER_ID);
  assert.equal(second.billit_order_id, NEW_ORDER_ID);
  assert.equal(issue.issueCalls, 1, "exactly one canonical invoice");
  assert.equal(billit.createCalls, 1, "exactly one Billit create across replays");
  assert.equal(sendCalls().length, 0);
});

// ===========================================================================
// B. Environment-aware consumer idempotency key (pure).
// ===========================================================================

test("B1. consumer idempotency key is deterministic, stable and environment-aware", () => {
  const saleKey = buildConsumerSaleIdempotencyKey({
    tenantId: TENANT,
    companyId: COMPANY,
    bookingId: "street_key_1",
  });

  const prod = buildBillitConsumerSaleOrderCreateIdempotencyKey(saleKey, "production");
  const sandbox = buildBillitConsumerSaleOrderCreateIdempotencyKey(saleKey, "sandbox");

  // Stable across repeated calls.
  assert.equal(
    prod,
    buildBillitConsumerSaleOrderCreateIdempotencyKey(saleKey, "production"),
  );
  // Environment-scoped: production and sandbox can never collide.
  assert.notEqual(prod, sandbox);
  assert.equal(prod, `fluxidi-billit-consumer-order:${saleKey}:production:v1`);
  // Back-compat: the default argument reproduces every pre-existing key.
  assert.equal(buildBillitConsumerSaleOrderCreateIdempotencyKey(saleKey), sandbox);
  assert.equal(sandbox, `fluxidi-billit-consumer-order:${saleKey}:sandbox:v1`);
  // Case-insensitive, and still document/sale scoped (never a doc UUID).
  assert.equal(
    buildBillitConsumerSaleOrderCreateIdempotencyKey(saleKey, "PRODUCTION"),
    prod,
  );
  assert.equal(buildBillitConsumerSaleOrderCreateIdempotencyKey("", "production"), null);
});

// ===========================================================================
// C. Manual "Registreren in Billit" for consumer sales via the canonical route.
// ===========================================================================

test("C1. consumer-sale manual register succeeds in production and is idempotent", async () => {
  const bookingId = "street_manual_consumer_1";
  const docId = "doc-manual-c1";
  const docNumber = "INV-2026-000081";
  const record = issuedInvoiceRecord({
    documentId: docId,
    documentNumber: docNumber,
    bookingId,
    consumer: true,
    totalInclVat: 5.3,
    subtotalExVat: 5.0,
    vatAmount: 0.3,
    vatRatePercent: 6,
  });
  const { env, bookingKv } = makeEnv({
    billitEnvironment: "production",
    documents: [record],
  });
  await seedConnectedOAuth(env);

  // First manual register: one create POST, production link persisted.
  calls = [];
  installHappyBillit({ orderNumber: docNumber });
  const first = await worker.fetch(registerRequest(docId), env, {});
  const firstBody = await first.json();
  assert.equal(first.status, 200, JSON.stringify(firstBody));
  assert.equal(firstBody.ok, true);
  assert.equal(firstBody.registered, true);
  assert.equal(firstBody.already_registered, false);
  assert.equal(firstBody.environment, "production");
  assert.equal(firstBody.billit_order_id, NEW_ORDER_ID);
  assert.equal(firstBody.sent, false);
  assert.equal(firstBody.peppol_sent, false);
  assert.equal(createPosts().length, 1, "exactly one order create POST");
  assert.equal(sendCalls().length, 0, "no Peppol send");

  // The manual route must present the canonical SALE-scoped Idempotent-Key so
  // it can never race the auto-create path into a second Billit order.
  const saleKey = buildConsumerSaleIdempotencyKey({
    tenantId: TENANT,
    companyId: COMPANY,
    bookingId,
  });
  const expectedIdem = buildBillitConsumerSaleOrderCreateIdempotencyKey(
    saleKey,
    "production",
  );
  const createCall = createPosts()[0];
  const sentIdem =
    createCall.headers["idempotent-key"] ||
    createCall.headers["idempotency-key"] ||
    createCall.headers["x-idempotency-key"];
  assert.equal(sentIdem, expectedIdem, "consumer sale-scoped Idempotent-Key");

  // Frozen amounts are posted verbatim (no recalculation).
  const consumerLines = computeBillitOrderLinesTotalInclVatCents(
    createCall.body?.OrderLines,
  );
  assert.equal(consumerLines.ok, true, JSON.stringify(consumerLines));
  assert.equal(consumerLines.total_incl_vat_cents, 530);

  const storedRaw = bookingKv.store.get(buildDocumentRegistryKey(SCOPE, docId));
  const stored = typeof storedRaw === "string" ? JSON.parse(storedRaw) : storedRaw;
  assert.equal(stored.billit_export.environment, "production");
  assert.equal(stored.billit_export.order_id, NEW_ORDER_ID);
  assert.equal(stored.document_number, docNumber, "canonical number preserved");

  // Second manual register: idempotent reuse, no second create POST.
  calls = [];
  installHappyBillit({ orderNumber: docNumber });
  const second = await worker.fetch(registerRequest(docId), env, {});
  const secondBody = await second.json();
  assert.equal(second.status, 200, JSON.stringify(secondBody));
  assert.equal(secondBody.registered, true);
  assert.equal(secondBody.already_registered, true);
  assert.equal(secondBody.reused, true);
  assert.equal(secondBody.billit_order_id, NEW_ORDER_ID);
  assert.equal(createPosts().length, 0, "no duplicate create on replay");
  assert.equal(sendCalls().length, 0);
});

test("C2. consumer-sale manual register is blocked when Billit OAuth is disconnected", async () => {
  const bookingId = "street_manual_consumer_disc";
  const docId = "doc-manual-c-disc";
  const record = issuedInvoiceRecord({
    documentId: docId,
    documentNumber: "INV-2026-000082",
    bookingId,
    consumer: true,
    totalInclVat: 5.3,
    subtotalExVat: 5.0,
    vatAmount: 0.3,
    vatRatePercent: 6,
  });
  // Configured production env, but no OAuth consent was ever completed.
  const { env } = makeEnv({ billitEnvironment: "production", documents: [record] });

  const res = await worker.fetch(registerRequest(docId), env, {});
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.ok(
    ["billit_party_id_missing", "billit_order_not_ready"].includes(body.error),
    `unexpected blocking error: ${JSON.stringify(body)}`,
  );
  assert.equal(createPosts().length, 0);
  assert.equal(sendCalls().length, 0);
});

// ===========================================================================
// D. Ride-family acceptance matrix — one canonical engine for all three.
// ===========================================================================

const RIDE_FAMILIES = [
  {
    label: "planned",
    bookingId: "bk_planned_2026_0001",
    docId: "doc-planned-biz",
    docNumber: "INV-2026-000090",
    totalInclVat: 121.0,
    subtotalExVat: 100.0,
    vatAmount: 21.0,
    vatRatePercent: 21,
  },
  {
    label: "street",
    bookingId: "street_1787914084944_eo0lb5xv",
    docId: "doc-street-biz",
    docNumber: "INV-2026-000091",
    totalInclVat: 24.2,
    subtotalExVat: 20.0,
    vatAmount: 4.2,
    vatRatePercent: 21,
  },
  {
    label: "limousine",
    bookingId: "bk_limo_accepted_0001",
    docId: "doc-limo-biz",
    docNumber: "INV-2026-000092",
    // Accepted limousine quotation amounts, frozen at acceptance.
    totalInclVat: 453.75,
    subtotalExVat: 375.0,
    vatAmount: 78.75,
    vatRatePercent: 21,
  },
];

for (const family of RIDE_FAMILIES) {
  test(`D. ${family.label} business invoice: manual register creates exactly one order with frozen amounts`, async () => {
    const record = issuedInvoiceRecord({
      documentId: family.docId,
      documentNumber: family.docNumber,
      bookingId: family.bookingId,
      consumer: false,
      totalInclVat: family.totalInclVat,
      subtotalExVat: family.subtotalExVat,
      vatAmount: family.vatAmount,
      vatRatePercent: family.vatRatePercent,
    });
    const { env, bookingKv } = makeEnv({
      billitEnvironment: "production",
      documents: [record],
    });
    await seedConnectedOAuth(env);

    calls = [];
    installHappyBillit({ orderNumber: family.docNumber });
    const first = await worker.fetch(registerRequest(family.docId), env, {});
    const firstBody = await first.json();
    assert.equal(first.status, 200, JSON.stringify(firstBody));
    assert.equal(firstBody.registered, true);
    assert.equal(firstBody.already_registered, false);
    assert.equal(firstBody.environment, "production");
    assert.equal(firstBody.document_number, family.docNumber);
    assert.equal(firstBody.sent, false);
    assert.equal(firstBody.peppol_sent, false);
    assert.equal(createPosts().length, 1, "exactly one order create POST");
    assert.equal(sendCalls().length, 0, "no Peppol send");

    // Frozen accepted amounts are posted verbatim — never recalculated. The
    // engine additionally fail-closes on any divergence via
    // reconcileBillitOrderTotalAgainstDocument, so reaching a POST at all
    // already proves the totals matched the frozen document.
    const posted = createPosts()[0].body;
    const computed = computeBillitOrderLinesTotalInclVatCents(posted?.OrderLines);
    assert.equal(computed.ok, true, JSON.stringify(computed));
    assert.equal(
      computed.total_incl_vat_cents,
      Math.round(family.totalInclVat * 100),
      `${family.label}: posted total must equal the frozen invoice total`,
    );
    assert.equal(
      computed.subtotal_ex_vat_cents,
      Math.round(family.subtotalExVat * 100),
      `${family.label}: posted net must equal the frozen net`,
    );
    assert.equal(String(posted?.Currency || "").toUpperCase(), "EUR");

    const storedRaw = bookingKv.store.get(
      buildDocumentRegistryKey(SCOPE, family.docId),
    );
    const stored = typeof storedRaw === "string" ? JSON.parse(storedRaw) : storedRaw;
    assert.equal(stored.document_number, family.docNumber);
    assert.equal(stored.totals.total_incl_vat, family.totalInclVat);
    assert.equal(stored.totals.vat_amount, family.vatAmount);
    assert.equal(stored.billit_export.order_id, NEW_ORDER_ID);
    assert.equal(stored.billit_export.environment, "production");

    // Replay is idempotent for every ride family.
    calls = [];
    installHappyBillit({ orderNumber: family.docNumber });
    const second = await worker.fetch(registerRequest(family.docId), env, {});
    const secondBody = await second.json();
    assert.equal(second.status, 200, JSON.stringify(secondBody));
    assert.equal(secondBody.already_registered, true);
    assert.equal(secondBody.reused, true);
    assert.equal(createPosts().length, 0, "no duplicate order on replay");
    assert.equal(sendCalls().length, 0);
  });
}

// ===========================================================================
// E. Auto-create ON, per ride family, through the live paid-lifecycle chain.
// ===========================================================================

/** Paid BUSINESS booking record for a given ride family. */
function businessBooking(bookingId, { family, totalInclVat, exVat, vat }) {
  const limousine = family === "limousine";
  const inner = {
    tenant_id: TENANT,
    company_id: COMPANY,
    status: "COMPLETED",
    currency: "EUR",
    price_incl_vat: totalInclVat,
    price_ex_vat: exVat,
    price_vat: vat,
    vat_rate_percent: 0.21,
    payment_status: "paid",
    payment_method: "bancontact",
    payment_provider: "mollie",
    paid_at: "2026-08-28T10:49:43.356Z",
    completed_at: "2026-08-28T10:48:45.921Z",
    lifecycle_status: "completed",
    invoice_requested: true,
    business_detected: true,
    invoice_intent: "business_invoice",
    invoice_state: "pending_payment",
    billing_customer_snapshot: {
      customer_type: "business",
      legal_name: "ACME NV",
      display_name: "ACME NV",
      vat_number: "BE0123456789",
    },
    ...(limousine
      ? {
          service_type: "limousine",
          company_confirmation_required: false,
          company_confirmed_at: "2026-08-28T09:00:00.000Z",
        }
      : {}),
  };
  return {
    booking_id: bookingId,
    tenant_id: TENANT,
    company_id: COMPANY,
    source: family === "street" ? "street_ride" : family === "limousine" ? "limousine" : "planned",
    ride_type: family === "street" ? "direct" : family,
    status: "COMPLETED",
    stage: "COMPLETED",
    lifecycle_status: "completed",
    completed_at: "2026-08-28T10:48:45.921Z",
    currency: "EUR",
    price_incl_vat: totalInclVat,
    price_ex_vat: exVat,
    price_vat: vat,
    vat_rate_percent: 0.21,
    payment_status: "paid",
    payment_method: "bancontact",
    payment_provider: "mollie",
    paid_at: "2026-08-28T10:49:43.356Z",
    invoice_requested: true,
    business_detected: true,
    invoice_intent: "business_invoice",
    invoice_state: "pending_payment",
    billing_customer_snapshot: inner.billing_customer_snapshot,
    billingCustomerSnapshot: inner.billing_customer_snapshot,
    ...(limousine
      ? {
          service_type: "limousine",
          serviceType: "limousine",
          company_confirmation_required: false,
          company_confirmed_at: "2026-08-28T09:00:00.000Z",
        }
      : {}),
    booking: inner,
    payload: { currency: "EUR", price_incl_vat: totalInclVat },
  };
}

for (const family of RIDE_FAMILIES) {
  test(`E. ${family.label} business invoice: auto-create ON registers exactly one order in production`, async () => {
    const bookingId = `${family.bookingId}_auto`;
    const docId = `${family.docId}-auto`;
    const record = issuedInvoiceRecord({
      documentId: docId,
      documentNumber: family.docNumber,
      bookingId,
      consumer: false,
      totalInclVat: family.totalInclVat,
      subtotalExVat: family.subtotalExVat,
      vatAmount: family.vatAmount,
      vatRatePercent: family.vatRatePercent,
    });
    const { env, bookingKv } = makeEnv({
      billitEnvironment: "production",
      documents: [record],
      bookings: {
        [bookingId]: businessBooking(bookingId, {
          family: family.label,
          totalInclVat: family.totalInclVat,
          exVat: family.subtotalExVat,
          vat: family.vatAmount,
        }),
      },
    });
    await seedConnectedOAuth(env);

    // Document Core already issued the invoice above; this proves the BILLIT
    // half of the live paid-lifecycle chain reaches the canonical engine.
    calls = [];
    installHappyBillit({ orderNumber: family.docNumber });
    const out = await runPaidBookingAfterLifecycle(env, SCOPE, bookingId, {
      source: "test_paid_lifecycle",
      skipDocumentCore: true,
    });

    const billitResult = out.billit_result || out.billitResult || null;
    assert.ok(billitResult, `no billit_result: ${JSON.stringify(out)}`);
    assert.equal(billitResult.ok, true, JSON.stringify(billitResult));
    assert.equal(
      billitResult.skipped === true,
      false,
      `auto-create was skipped: ${JSON.stringify(billitResult)}`,
    );
    assert.equal(String(billitResult.billit_order_id), NEW_ORDER_ID);
    assert.equal(billitResult.peppol_sent, false);
    assert.equal(createPosts().length, 1, "exactly one order create POST");
    assert.equal(sendCalls().length, 0, "auto-create never sends Peppol");

    const storedRaw = bookingKv.store.get(buildDocumentRegistryKey(SCOPE, docId));
    const stored = typeof storedRaw === "string" ? JSON.parse(storedRaw) : storedRaw;
    assert.equal(stored.document_number, family.docNumber, "canonical number kept");
    assert.equal(stored.totals.total_incl_vat, family.totalInclVat, "frozen total");
    assert.equal(stored.billit_export.order_id, NEW_ORDER_ID);
    assert.equal(stored.billit_export.environment, "production");

    // Replay of the whole paid lifecycle must not create a second order.
    calls = [];
    installHappyBillit({ orderNumber: family.docNumber });
    await runPaidBookingAfterLifecycle(env, SCOPE, bookingId, {
      source: "test_paid_lifecycle_replay",
      skipDocumentCore: true,
    });
    assert.equal(createPosts().length, 0, "no duplicate order on lifecycle replay");
    assert.equal(sendCalls().length, 0);
  });
}

test("D4. limousine stays blocked while company confirmation is still pending", async () => {
  const bookingId = "bk_limo_unconfirmed_0001";
  const limoBooking = consumerStreetBooking(bookingId, {
    source: "limousine",
    service_type: "limousine",
    serviceType: "limousine",
    ride_type: "limousine",
    company_confirmation_required: true,
    booking: {
      currency: "EUR",
      price_incl_vat: 453.75,
      service_type: "limousine",
      company_confirmation_required: true,
    },
  });
  const { env } = makeEnv({
    billitEnvironment: "production",
    bookings: { [bookingId]: limoBooking },
  });
  const issue = makeIssueImpl(env, bookingId, "doc-limo-pending", "INV-2026-000093");
  const billit = makeBillitImpl();

  const out = await maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  });

  assert.equal(out.skipped, true);
  assert.equal(out.reason, "limousine_invoice_blocked");
  assert.equal(issue.issueCalls, 0, "no invoice minted while unconfirmed");
  assert.equal(billit.createCalls, 0, "no Billit create while unconfirmed");
  assert.equal(sendCalls().length, 0);
});
