/* BILLIT-PROD-CREATE-1 — production CREATE + manual "Registreren in Billit"
 * recovery route regression tests.
 *
 * Proves:
 *   - production CREATE is allowed only when fully eligible;
 *   - the manual /register route is idempotent (reuse-or-create, no duplicate);
 *   - manual register works even when the auto-create toggle is OFF;
 *   - an OAuth disconnect blocks create;
 *   - a wrong tenant/company is blocked;
 *   - missing canonical invoice data is blocked before any Billit POST;
 *   - Peppol / send is never triggered by register/create.
 *
 * Hermetic: global.fetch is a controllable mock; KV is an in-memory Map. No
 * live Billit, Cloudflare, or production credentials.
 *
 *   node --test workers/booking/billit_prod_register_p1.test.mjs
 */

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import { buildDocumentRegistryKey } from "./modules/document_core.js";
import {
  buildBillitOAuthConnectionKey,
  buildBillitOAuthStateKey,
  startBillitOAuthForScope,
  completeBillitOAuthCallback,
} from "./modules/billit_provider.js";

const ADMIN = "test-admin-token";
const TENANT = "tenant_a";
const COMPANY = "company_a";
const OTHER_TENANT = "tenant_b";
const OTHER_COMPANY = "company_b";
const SCOPE = { tenant_id: TENANT, company_id: COMPANY };
const DOC_ID = "doc_inv_prod_p1";
const DOC_NUMBER = "FLX-2026-08-0072";
const PARTY_ID = "6532054";
const REDIRECT_URI =
  "https://fluxidi-booking-api.fluxidi.workers.dev/admin/integrations/billit/oauth/callback";
const ACCESS_TOKEN = "prod-access-token-plain";
const REFRESH_TOKEN = "prod-refresh-token-plain";
const NEW_ORDER_ID = "555777";

// ---------------------------------------------------------------------------
// Controllable outbound mock. Records every call so tests can prove exactly
// which Billit endpoints were (not) touched.
// ---------------------------------------------------------------------------

let originalFetch;
let calls = [];
let handler = null;

before(() => {
  originalFetch = global.fetch;
  global.fetch = async (input, init) => {
    const href = typeof input === "string" ? input : input?.url || String(input);
    const method = String(init?.method || "GET").toUpperCase();
    calls.push({ href, method });
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

// Happy Billit mock: token, account info (PartyID), order create (bare id),
// order read/patch. Never a /commands/send response (a send would throw).
function installHappyBillit() {
  handler = async (href, init, method) => {
    if (/\/OAuth2\/token/.test(href)) {
      return new Response(
        JSON.stringify({
          token_type: "Bearer",
          access_token: ACCESS_TOKEN,
          refresh_token: REFRESH_TOKEN,
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
      throw new Error("hermetic test: SEND must never be called by register/create");
    }
    if (method === "POST" && /\/v1\/orders$/.test(href)) {
      // Billit commonly returns the new OrderID as a bare number.
      return new Response(JSON.stringify(NEW_ORDER_ID), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    if (/\/v1\/orders\//.test(href)) {
      // Order read / payment-state patch after create.
      return new Response(
        JSON.stringify({
          OrderID: NEW_ORDER_ID,
          OrderNumber: DOC_NUMBER,
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
  const store = new Map(Object.entries(seed));
  const writes = [];
  return {
    store,
    writes,
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
    async put(key, val, opts) {
      writes.push({ key, expirationTtl: opts?.expirationTtl ?? null });
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

function issuedInvoiceRecord({
  billitExport = null,
  tenantId = TENANT,
  companyId = COMPANY,
  documentId = DOC_ID,
  documentNumber = DOC_NUMBER,
  totalInclVat = 24.2,
  subtotalExVat = 20.0,
  vatAmount = 4.2,
  vatRatePercent = 21,
  currency = "EUR",
  dropTotals = false,
  billitAutoCreate = false,
} = {}) {
  const totals = {
    total_incl_vat: totalInclVat,
    subtotal_ex_vat: subtotalExVat,
    vat_amount: vatAmount,
    vat_rate_percent: vatRatePercent,
    currency,
  };
  const buyerSnapshot = {
    customer_type: "business",
    legal_name: "ACME NV",
    display_name: "ACME NV",
    contact_email: "billing@acme.example",
    vat_number: "BE0123456789",
    company_registration_number: "0123456789",
    billing_address: { street: "Teststraat 1", postal_code: "8500", city: "Kortrijk", country: "BE" },
    peppol: { endpoint_id: "0208:0123456789", scheme: "0208" },
    name: "ACME NV",
    address_line: "Teststraat 1",
    country_code: "BE",
    email: "billing@acme.example",
    postal_code: "8500",
    city: "Kortrijk",
  };
  const sellerSnapshot = {
    legal_name: "Fluxidi Test BV",
    company_name: "Fluxidi Test BV",
    vat_number: "BE0987654321",
    street: "Verkoperstraat 2",
    postal_code: "8500",
    city: "Kortrijk",
    country: "BE",
    country_code: "BE",
  };
  const snapshot = {
    tenant_id: tenantId,
    company_id: companyId,
    document_id: documentId,
    document_type: "invoice",
    document_number: documentNumber,
    issue_timestamp: "2026-08-20T10:00:00.000Z",
    source_booking_id: "street_1720000000000_ab12cd34",
    currency,
    totals: dropTotals ? undefined : { ...totals },
    seller_snapshot: sellerSnapshot,
    buyer_snapshot: buyerSnapshot,
  };
  const record = {
    tenant_id: tenantId,
    company_id: companyId,
    document_id: documentId,
    document_type: "invoice",
    document_number: documentNumber,
    lifecycle_state: "issued",
    document_status: "issued",
    source_booking_id: "street_1720000000000_ab12cd34",
    is_leg_scoped: false,
    currency,
    totals: dropTotals ? undefined : totals,
    buyer_snapshot: buyerSnapshot,
    seller_snapshot: sellerSnapshot,
    issue_timestamp: "2026-08-20T10:00:00.000Z",
    content_hash: "test-content-hash",
    immutable_snapshot: snapshot,
  };
  if (dropTotals) {
    delete record.totals;
    delete record.immutable_snapshot.totals;
  }
  if (billitExport) record.billit_export = billitExport;
  return record;
}

function businessProfile({ billitAutoCreate = false } = {}) {
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
    billit_auto_create_after_paid_business_invoice: billitAutoCreate,
  };
}

function makeEnv({
  documents = [],
  billitEnvironment = "production",
  billitConfigured = true,
  seedConnection = false,
  connectionOverrides = {},
  billitAutoCreate = false,
} = {}) {
  const seed = {};
  for (const doc of documents) {
    const scope = {
      tenant_id: doc.tenant_id ?? doc.record?.tenant_id,
      company_id: doc.company_id ?? doc.record?.company_id,
    };
    seed[buildDocumentRegistryKey(scope, doc.record.document_id)] = doc.record;
  }
  seed[`tenant:${TENANT}:company:${COMPANY}:business_profile:v1`] = businessProfile({
    billitAutoCreate,
  });
  seed[`tenant:${OTHER_TENANT}:company:${OTHER_COMPANY}:business_profile:v1`] =
    businessProfile();
  if (seedConnection) {
    seed[buildBillitOAuthConnectionKey(SCOPE)] = {
      provider: "billit",
      environment: billitEnvironment,
      party_id: PARTY_ID,
      connected: true,
      status: "connected",
      ...connectionOverrides,
    };
  }
  const bookingKv = makeKV(seed);
  const env = {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: bookingKv,
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

// Drive the real OAuth start+callback so the stored production connection has a
// decryptable access token + resolved PartyID (exactly like a real consent).
async function seedConnectedProductionOAuth(env) {
  installHappyBillit();
  const started = await startBillitOAuthForScope(env, SCOPE);
  assert.equal(started.status, 200, JSON.stringify(started.body));
  const authUrl = new URL(started.body.authorization_url);
  const result = await completeBillitOAuthCallback(env, {
    code: "prod-auth-code",
    state: authUrl.searchParams.get("state"),
  });
  assert.equal(result.outcome, "connected", JSON.stringify(result));
}

function registerRequest(scope = SCOPE, { body = {}, documentId = DOC_ID, prefix = "admin", adminToken = ADMIN } = {}) {
  const headers = { "content-type": "application/json" };
  if (adminToken) headers["x-admin-token"] = adminToken;
  const q = `tenant_id=${encodeURIComponent(scope.tenant_id)}&company_id=${encodeURIComponent(scope.company_id)}`;
  return new Request(
    `https://booking.internal/${prefix}/documents/${documentId}/billit/register?${q}`,
    {
      method: "POST",
      headers,
      body: JSON.stringify({ tenant_id: scope.tenant_id, company_id: scope.company_id, ...body }),
    },
  );
}

// ===========================================================================
// Gating tests (no decryptable token required, no outbound expected).
// ===========================================================================

test("register requires the explicit confirm_billit_register flag", async () => {
  const { env } = makeEnv({ documents: [{ record: issuedInvoiceRecord() }] });
  const res = await worker.fetch(registerRequest(SCOPE, { body: {} }), env, {});
  const body = await res.json();
  assert.equal(res.status, 400);
  assert.equal(body.error, "confirm_billit_register_required");
  assert.deepEqual(calls, []);
});

test("register rejects an anonymous caller", async () => {
  const { env } = makeEnv({ documents: [{ record: issuedInvoiceRecord() }] });
  const res = await worker.fetch(
    registerRequest(SCOPE, { body: { confirm_billit_register: true }, adminToken: null }),
    env,
    {},
  );
  assert.equal(res.status, 401);
  assert.deepEqual(calls, []);
});

test("register is blocked for a document owned by another tenant/company", async () => {
  // Document belongs to SCOPE; caller asks under the OTHER scope -> 404.
  const { env } = makeEnv({ documents: [{ record: issuedInvoiceRecord() }] });
  const res = await worker.fetch(
    registerRequest(
      { tenant_id: OTHER_TENANT, company_id: OTHER_COMPANY },
      { body: { confirm_billit_register: true } },
    ),
    env,
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 404);
  assert.equal(body.error, "document_not_found");
  assert.deepEqual(calls, []);
});

test("register is blocked when Billit OAuth is not configured", async () => {
  const { env } = makeEnv({
    documents: [{ record: issuedInvoiceRecord() }],
    billitConfigured: false,
  });
  const res = await worker.fetch(
    registerRequest(SCOPE, { body: { confirm_billit_register: true } }),
    env,
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 400);
  assert.equal(body.error, "billit_oauth_not_configured");
  assert.deepEqual(calls, []);
});

test("register refuses a document_number mismatch before any Billit POST", async () => {
  const { env } = makeEnv({ documents: [{ record: issuedInvoiceRecord() }] });
  const res = await worker.fetch(
    registerRequest(SCOPE, {
      body: { confirm_billit_register: true, document_number: "FLX-9999-99-9999" },
    }),
    env,
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_register_document_number_mismatch");
  assert.equal(body.document_number, DOC_NUMBER);
  assert.deepEqual(calls, []);
});

test("register is blocked when OAuth is disconnected (no PartyID, no create)", async () => {
  // Configured production env, but no connection/PartyID seeded.
  const { env } = makeEnv({ documents: [{ record: issuedInvoiceRecord() }] });
  const res = await worker.fetch(
    registerRequest(SCOPE, { body: { confirm_billit_register: true } }),
    env,
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 409);
  // Disconnected: no PartyID resolvable, so create is refused at a readiness
  // gate (missing party / not ready). Either exact code proves it stopped
  // before any outbound Billit POST.
  assert.ok(
    ["billit_party_id_missing", "billit_order_not_ready"].includes(body.error),
    `unexpected blocking error: ${JSON.stringify(body)}`,
  );
  assert.equal(createPosts().length, 0);
  assert.equal(sendCalls().length, 0);
});

test("register is blocked when canonical invoice totals are missing", async () => {
  const { env } = makeEnv({
    documents: [{ record: issuedInvoiceRecord({ dropTotals: true }) }],
    seedConnection: true,
  });
  const res = await worker.fetch(
    registerRequest(SCOPE, { body: { confirm_billit_register: true } }),
    env,
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_order_not_ready");
  assert.equal(createPosts().length, 0);
});

test("register is idempotent: an already-linked production order is reused (no duplicate)", async () => {
  const { env, bookingKv } = makeEnv({
    seedConnection: true,
    documents: [
      {
        record: issuedInvoiceRecord({
          billitExport: {
            environment: "production",
            party_id: PARTY_ID,
            order_id: NEW_ORDER_ID,
            order_number: DOC_NUMBER,
            status: "created",
            sent: false,
            peppol_sent: false,
            idempotency_key: `fluxidi-billit-order-create:${DOC_ID}:sandbox:v1`,
          },
        }),
      },
    ],
  });
  // The reuse short-circuit may try a read-only payment sync token acquire, but
  // must never POST a second order and never send Peppol.
  handler = async (href, init, method) => {
    if (/\/v1\/orders\/commands\/send/.test(href)) {
      throw new Error("SEND must never be called");
    }
    if (method === "POST" && /\/v1\/orders$/.test(href)) {
      throw new Error("a second order POST must never happen");
    }
    if (/\/v1\/orders\//.test(href)) {
      return new Response(
        JSON.stringify({ OrderID: NEW_ORDER_ID, OrderNumber: DOC_NUMBER, Paid: false }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    throw new Error(`unexpected fetch ${method} ${href}`);
  };
  const res = await worker.fetch(
    registerRequest(SCOPE, { body: { confirm_billit_register: true } }),
    env,
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.registered, true);
  assert.equal(body.already_registered, true);
  assert.equal(body.reused, true);
  assert.equal(body.billit_order_id, NEW_ORDER_ID);
  assert.equal(body.environment, "production");
  assert.equal(body.sent, false);
  assert.equal(body.peppol_sent, false);
  assert.equal(createPosts().length, 0);
  assert.equal(sendCalls().length, 0);
});

// ===========================================================================
// Full production CREATE happy path (real OAuth seeding + mocked Billit).
// ===========================================================================

test("production CREATE is allowed when fully eligible, is idempotent, and never sends Peppol", async () => {
  const { env, bookingKv } = makeEnv({
    documents: [{ record: issuedInvoiceRecord() }],
    billitAutoCreate: false, // manual register must work with auto-create OFF
  });
  await seedConnectedProductionOAuth(env);

  // First register: one create POST, persisted production link, no Peppol.
  installHappyBillit();
  const first = await worker.fetch(
    registerRequest(SCOPE, { body: { confirm_billit_register: true } }),
    env,
    {},
  );
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

  // The persisted export must carry the production environment.
  const storedRaw = bookingKv.store.get(buildDocumentRegistryKey(SCOPE, DOC_ID));
  const stored = typeof storedRaw === "string" ? JSON.parse(storedRaw) : storedRaw;
  assert.equal(stored.billit_export.environment, "production");
  assert.equal(stored.billit_export.order_id, NEW_ORDER_ID);

  // Second register: idempotent reuse, NO second create POST, still no Peppol.
  calls = [];
  installHappyBillit();
  const second = await worker.fetch(
    registerRequest(SCOPE, { body: { confirm_billit_register: true } }),
    env,
    {},
  );
  const secondBody = await second.json();
  assert.equal(second.status, 200, JSON.stringify(secondBody));
  assert.equal(secondBody.registered, true);
  assert.equal(secondBody.already_registered, true);
  assert.equal(secondBody.reused, true);
  assert.equal(secondBody.billit_order_id, NEW_ORDER_ID);
  assert.equal(createPosts().length, 0, "no duplicate order create on replay");
  assert.equal(sendCalls().length, 0);
});
