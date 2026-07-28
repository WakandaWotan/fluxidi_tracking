/* B12-P1 — route-level regression tests for the Billit / Peppol invoice-export
 * safety gates and for the two legacy invoice-render routes.
 *
 * Hermetic by construction:
 *   - global.fetch is replaced by a trap for the whole file, so ANY outbound
 *     call (Billit, PDFShift, Mollie) fails the test instead of leaving the
 *     machine;
 *   - KV is an in-memory Map; no Cloudflare binding, no Durable Object;
 *   - no invoice is issued (no DOCUMENT_REFERENCE_SEQUENCE binding is provided,
 *     so no invoice number can be allocated), no Billit order is created and no
 *     Peppol document is sent.
 *
 *   node --test workers/booking/billit_invoice_export_gates.test.mjs
 */

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import { buildDocumentRegistryKey } from "./modules/document_core.js";
import { buildBillitOAuthConnectionKey } from "./modules/billit_provider.js";

const ADMIN = "test-admin-token";
const TENANT = "tenant_a";
const COMPANY = "company_a";
const OTHER_TENANT = "tenant_b";
const OTHER_COMPANY = "company_b";
const SCOPE = { tenant_id: TENANT, company_id: COMPANY };
const DOC_ID = "doc_inv_b12_p1";
const DOC_NUMBER = "FLX-2026-07-0042";
const ORDER_ID = "998877";
const PARTY_ID = "party-123";

// ---------------------------------------------------------------------------
// Outbound-call trap: proves no Billit / PDFShift / Peppol traffic ever leaves.
// ---------------------------------------------------------------------------

let originalFetch;
let outboundAttempts = [];

before(() => {
  originalFetch = global.fetch;
  global.fetch = async (input) => {
    const href = typeof input === "string" ? input : input?.url || String(input);
    outboundAttempts.push(href);
    throw new Error(`hermetic test: blocked outbound fetch to ${href}`);
  };
});

after(() => {
  global.fetch = originalFetch;
});

beforeEach(() => {
  outboundAttempts = [];
});

function assertNoOutboundTraffic() {
  assert.deepEqual(
    outboundAttempts,
    [],
    `expected zero outbound calls, got: ${outboundAttempts.join(", ")}`,
  );
}

// ---------------------------------------------------------------------------
// In-memory KV + env.
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
    async put(key, val) {
      writes.push(key);
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

/* Issued business invoice registry record, shaped exactly like
 * buildIssuedDocumentRegistryRecord output: the hashed immutable_snapshot holds
 * the authoritative totals and the buyer/seller snapshots, mirrored on the
 * envelope. Peppol-ready buyer identity so the export readiness gates pass and
 * the total-reconciliation guard is actually reached. */
function issuedInvoiceRecord({
  totalInclVat = 24.2,
  subtotalExVat = 20.0,
  vatAmount = 4.2,
  vatRatePercent = 21,
  currency = "EUR",
  billitExport = null,
  tenantId = TENANT,
  companyId = COMPANY,
  documentId = DOC_ID,
  documentNumber = DOC_NUMBER,
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
    contact_phone: "+3212345678",
    vat_number: "BE0123456789",
    company_registration_number: "0123456789",
    buyer_reference: "PO-42",
    billing_address: {
      street: "Teststraat 1",
      postal_code: "8500",
      city: "Kortrijk",
      country: "BE",
    },
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
  const issueTimestamp = "2026-07-20T10:00:00.000Z";
  const snapshot = {
    tenant_id: tenantId,
    company_id: companyId,
    document_id: documentId,
    document_type: "invoice",
    document_number: documentNumber,
    issue_timestamp: issueTimestamp,
    source_booking_id: "street_1720000000000_ab12cd34",
    currency,
    totals: { ...totals },
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
    totals,
    buyer_snapshot: buyerSnapshot,
    seller_snapshot: sellerSnapshot,
    issue_timestamp: issueTimestamp,
    content_hash: "test-content-hash",
    immutable_snapshot: snapshot,
  };
  if (billitExport) record.billit_export = billitExport;
  return record;
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
  };
}

function makeEnv({
  documents = [],
  billitEnvironment = null,
  billitConfigured = true,
  partyId = PARTY_ID,
  profileScope = SCOPE,
} = {}) {
  const seed = {};
  for (const doc of documents) {
    const scope = {
      tenant_id: doc.tenant_id ?? doc.record?.tenant_id,
      company_id: doc.company_id ?? doc.record?.company_id,
    };
    seed[buildDocumentRegistryKey(scope, doc.record.document_id)] = doc.record;
  }
  if (partyId) {
    seed[buildBillitOAuthConnectionKey(SCOPE)] = {
      provider: "billit",
      environment: "sandbox",
      party_id: partyId,
      connected: true,
    };
    seed[buildBillitOAuthConnectionKey({
      tenant_id: OTHER_TENANT,
      company_id: OTHER_COMPANY,
    })] = {
      provider: "billit",
      environment: "sandbox",
      party_id: "party-other",
      connected: true,
    };
  }
  seed[
    `tenant:${profileScope.tenant_id}:company:${profileScope.company_id}:business_profile:v1`
  ] = businessProfile();
  seed[`tenant:${OTHER_TENANT}:company:${OTHER_COMPANY}:business_profile:v1`] =
    businessProfile();

  const bookingKv = makeKV(seed);
  const env = {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: bookingKv,
    // No DOCUMENT_REFERENCE_SEQUENCE binding: no invoice number can be
    // allocated in this file, so no invoice can be issued.
  };
  if (billitEnvironment) env.BILLIT_ENVIRONMENT = billitEnvironment;
  if (billitConfigured) {
    env.BILLIT_CLIENT_ID = "test-client-id";
    env.BILLIT_CLIENT_SECRET = "test-client-secret";
    env.BILLIT_REDIRECT_URI = "https://booking.internal/admin/integrations/billit/oauth/callback";
  }
  return { env, bookingKv };
}

function adminRequest(path, { method = "POST", body = null, adminToken = ADMIN } = {}) {
  const headers = { "content-type": "application/json" };
  if (adminToken) headers["x-admin-token"] = adminToken;
  return new Request(`https://booking.internal${path}`, {
    method,
    headers,
    ...(body === null ? {} : { body: JSON.stringify(body) }),
  });
}

function scopedPath(path, scope = SCOPE) {
  const sep = path.includes("?") ? "&" : "?";
  return `${path}${sep}tenant_id=${encodeURIComponent(scope.tenant_id)}&company_id=${encodeURIComponent(scope.company_id)}`;
}

// ===========================================================================
// P1-2 — legacy invoice render routes require admin auth.
// ===========================================================================

test("P1-2: anonymous POST /invoice/preview is rejected with 401", async () => {
  const { env } = makeEnv();
  const res = await worker.fetch(
    adminRequest("/invoice/preview", { adminToken: null, body: { total: "121.00" } }),
    env,
    {},
  );
  assert.equal(res.status, 401);
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.equal(body.error, "unauthorized");
  assertNoOutboundTraffic();
});

test("P1-2: anonymous POST /invoice/pdf is rejected with 401 and never calls PDFShift", async () => {
  const { env } = makeEnv();
  env.PDFSHIFT_API_KEY = "pdfshift-secret-should-never-be-used";
  const res = await worker.fetch(
    adminRequest("/invoice/pdf", { adminToken: null, body: { total: "121.00" } }),
    env,
    {},
  );
  assert.equal(res.status, 401);
  const body = await res.json();
  assert.equal(body.error, "unauthorized");
  // The decisive assertion: no render provider was contacted.
  assertNoOutboundTraffic();
  assert.equal(
    res.headers.get("content-type")?.includes("application/pdf"),
    false,
    "an unauthenticated caller must never receive PDF bytes",
  );
});

test("P1-2: a wrong admin token is rejected on both legacy routes", async () => {
  for (const path of ["/invoice/preview", "/invoice/pdf"]) {
    const { env } = makeEnv();
    const res = await worker.fetch(
      adminRequest(path, { adminToken: "not-the-admin-token", body: {} }),
      env,
      {},
    );
    assert.equal(res.status, 401, `${path} should reject a wrong token`);
    const body = await res.json();
    assert.equal(body.error, "unauthorized");
  }
  assertNoOutboundTraffic();
});

test("P1-2: a query-string token does NOT authenticate (header-only helper)", async () => {
  const { env } = makeEnv();
  const res = await worker.fetch(
    new Request(
      `https://booking.internal/invoice/preview?admin_token=${ADMIN}&token=${ADMIN}`,
      { method: "POST", headers: { "content-type": "application/json" }, body: "{}" },
    ),
    env,
    {},
  );
  assert.equal(res.status, 401);
  assertNoOutboundTraffic();
});

test("P1-2: valid admin auth reaches the unchanged preview handler and renders HTML", async () => {
  const { env } = makeEnv();
  const res = await worker.fetch(
    adminRequest("/invoice/preview", {
      body: { invoiceNumber: "FLX-2026-07-0001", total: "121.00" },
    }),
    env,
    {},
  );
  assert.equal(res.status, 200);
  assert.match(res.headers.get("content-type") || "", /text\/html/);
  const text = await res.text();
  assert.match(text, /FLX-2026-07-0001/, "the existing renderer must be reached unchanged");
  assertNoOutboundTraffic();
});

test("P1-2: an admin Bearer token is also accepted (existing helper contract)", async () => {
  const { env } = makeEnv();
  const res = await worker.fetch(
    new Request("https://booking.internal/invoice/preview", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${ADMIN}`,
      },
      body: "{}",
    }),
    env,
    {},
  );
  assert.equal(res.status, 200);
  assertNoOutboundTraffic();
});

test("P1-2: valid admin auth on /invoice/pdf reaches rendering and fails on config, not auth", async () => {
  const { env } = makeEnv();
  // No PDFSHIFT_API_KEY / PDF_RENDER_URL: renderPdfFromHtml returns null, which
  // proves the handler was reached without any outbound provider call.
  const res = await worker.fetch(adminRequest("/invoice/pdf", { body: {} }), env, {});
  assert.equal(res.status, 500);
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.match(body.error, /PDF rendering not configured/);
  assertNoOutboundTraffic();
});

test("P1-2: the CORS preflight answers OPTIONS without reaching the POST handler", async () => {
  const { env } = makeEnv();
  for (const path of ["/invoice/preview", "/invoice/pdf"]) {
    const res = await worker.fetch(
      new Request(`https://booking.internal${path}`, { method: "OPTIONS" }),
      env,
      {},
    );
    // Preflight is answered generically; it must not render or return a document.
    const contentType = res.headers.get("content-type") || "";
    assert.doesNotMatch(contentType, /application\/pdf|text\/html/);
    const text = await res.text();
    assert.equal(text, "", `${path} preflight must not produce a rendered body`);
  }
  assertNoOutboundTraffic();
});

// ===========================================================================
// P1-1 — Billit order create is refused on a total mismatch.
// ===========================================================================

function createRequestFor(scope = SCOPE, { documentNumber = DOC_NUMBER } = {}) {
  return adminRequest(
    scopedPath(`/admin/documents/${DOC_ID}/billit-order/create/sandbox`, scope),
    {
      body: {
        confirm_sandbox_create: true,
        document_number: documentNumber,
      },
    },
  );
}

test("P1-1: a consistent invoice total passes the reconciliation guard", async () => {
  // 20.00 ex VAT + 21% = 24.20 incl, matching the synthesized order line.
  const { env } = makeEnv({
    documents: [{ record: issuedInvoiceRecord({ totalInclVat: 24.2 }) }],
  });
  const res = await worker.fetch(createRequestFor(), env, {});
  const body = await res.json();
  assert.notEqual(
    body.error,
    "billit_total_reconciliation_failed",
    `guard should have passed, got: ${JSON.stringify(body)}`,
  );
  // Positive proof of WHERE it stopped: past every readiness gate and past the
  // reconciliation guard, at the OAuth token step this fixture deliberately has
  // no stored tokens for. A vacuous pass (e.g. billit_order_not_ready, which
  // would mean the guard was never reached) fails this assertion.
  assert.equal(body.error, "billit_not_connected", JSON.stringify(body));
  assertNoOutboundTraffic();
});

test("P1-1: a total mismatch refuses the create with billit_total_reconciliation_failed", async () => {
  // Storage says 30.00 incl VAT; the order lines derive 20.00 + 21% = 24.20.
  const { env, bookingKv } = makeEnv({
    documents: [
      {
        record: issuedInvoiceRecord({
          totalInclVat: 30.0,
          subtotalExVat: 20.0,
          vatAmount: 4.2,
          vatRatePercent: 21,
        }),
      },
    ],
  });
  const res = await worker.fetch(createRequestFor(), env, {});
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.equal(body.ok, false);
  assert.equal(body.error, "billit_total_reconciliation_failed");
  assert.equal(body.reason, "total_mismatch");
  assert.equal(body.expected_total_cents, 3000);
  assert.equal(body.calculated_total_cents, 2420);
  assert.equal(body.delta_cents, -580);
  assert.equal(body.currency, "EUR");
  assert.equal(body.document_id, DOC_ID);
  assert.equal(body.document_number, DOC_NUMBER);

  // The decisive proofs: no Billit call, and nothing persisted.
  assertNoOutboundTraffic();
  assert.deepEqual(bookingKv.writes, [], "a refused create must not write KV");
});

test("P1-1: a refused create leaks no buyer identity in the response", async () => {
  const { env } = makeEnv({
    documents: [{ record: issuedInvoiceRecord({ totalInclVat: 30.0 }) }],
  });
  const res = await worker.fetch(createRequestFor(), env, {});
  const raw = await res.text();
  for (const secret of [
    "ACME NV",
    "billing@acme.example",
    "BE0123456789",
    "Teststraat",
    "Kortrijk",
    "0208:0123456789",
    "test-client-secret",
  ]) {
    assert.equal(
      raw.includes(secret),
      false,
      `refusal payload must not contain ${secret}`,
    );
  }
});

test("P1-1: a missing authoritative total is refused by the reconciliation guard", async () => {
  // The order lines are still synthesizable from subtotal + rate, so the upstream
  // readiness gate passes and the guard is the layer that refuses.
  const record = issuedInvoiceRecord({ totalInclVat: null });
  const { env, bookingKv } = makeEnv({ documents: [{ record }] });
  const res = await worker.fetch(createRequestFor(), env, {});
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_total_reconciliation_failed");
  assert.equal(body.reason, "missing_authoritative_total");
  assert.equal(body.expected_total_cents, null);
  assertNoOutboundTraffic();
  assert.deepEqual(bookingKv.writes, []);
});

test("P1-1: a zero authoritative total is refused by the reconciliation guard", async () => {
  const { env } = makeEnv({
    documents: [{ record: issuedInvoiceRecord({ totalInclVat: 0 }) }],
  });
  const res = await worker.fetch(createRequestFor(), env, {});
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_total_reconciliation_failed");
  assert.equal(body.reason, "invalid_authoritative_total");
  assertNoOutboundTraffic();
});

test("P1-1: a record with no totals at all is refused upstream, before the guard", async () => {
  // Documents the layering: without totals there are no order lines to reconcile,
  // so the pre-existing readiness gate refuses first. Either way: no Billit call.
  const record = issuedInvoiceRecord();
  delete record.totals;
  delete record.immutable_snapshot.totals;
  const { env } = makeEnv({ documents: [{ record }] });
  const res = await worker.fetch(createRequestFor(), env, {});
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_order_not_ready");
  assert.equal(body.reasons.includes("missing_order_lines"), true);
  assertNoOutboundTraffic();
});

test("P1-1: an already-linked sandbox order short-circuits and is never created twice", async () => {
  const { env, bookingKv } = makeEnv({
    documents: [
      {
        record: issuedInvoiceRecord({
          billitExport: {
            environment: "sandbox",
            party_id: PARTY_ID,
            order_id: ORDER_ID,
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
  const res = await worker.fetch(createRequestFor(), env, {});
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.already_created, true);
  assert.equal(body.reused, true);
  assert.equal(body.billit_order_id, ORDER_ID);
  // The stable idempotency key survives the short-circuit unchanged.
  assert.equal(
    body.idempotency_key,
    `fluxidi-billit-order-create:${DOC_ID}:sandbox:v1`,
  );
  assertNoOutboundTraffic();
  assert.deepEqual(bookingKv.writes, []);
});

test("P1-1: create is refused for a production Billit environment", async () => {
  const { env } = makeEnv({
    documents: [{ record: issuedInvoiceRecord() }],
    billitEnvironment: "production",
  });
  const res = await worker.fetch(createRequestFor(), env, {});
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_sandbox_create_sandbox_only");
  assert.equal(body.environment, "production");
  assertNoOutboundTraffic();
});

test("P1-1: create requires the explicit confirm_sandbox_create flag", async () => {
  const { env } = makeEnv({ documents: [{ record: issuedInvoiceRecord() }] });
  const res = await worker.fetch(
    adminRequest(
      scopedPath(`/admin/documents/${DOC_ID}/billit-order/create/sandbox`),
      { body: { document_number: DOC_NUMBER } },
    ),
    env,
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 400);
  assert.equal(body.error, "confirm_sandbox_create_required");
  assertNoOutboundTraffic();
});

// ===========================================================================
// Peppol / send-route gates — exercised WITHOUT ever sending.
// ===========================================================================

function sendRequestBody({
  confirm = true,
  documentNumber = DOC_NUMBER,
  orderId = ORDER_ID,
  transport = "Peppol",
} = {}) {
  const body = {};
  if (confirm) body.confirm_sandbox_send = true;
  if (documentNumber !== null) body.document_number = documentNumber;
  if (orderId !== null) body.billit_order_id = orderId;
  if (transport !== null) body.transport_type = transport;
  return body;
}

function linkedExport(overrides = {}) {
  return {
    environment: "sandbox",
    party_id: PARTY_ID,
    order_id: ORDER_ID,
    order_number: DOC_NUMBER,
    status: "created",
    sent: false,
    peppol_sent: false,
    ...overrides,
  };
}

function adminSendRequest(body, scope = SCOPE, documentId = DOC_ID) {
  return adminRequest(
    scopedPath(`/admin/documents/${documentId}/billit-order/send/sandbox`, scope),
    { body },
  );
}

async function runAdminSend({ body, exportOverrides = {}, billitEnvironment = null }) {
  const { env, bookingKv } = makeEnv({
    documents: [
      { record: issuedInvoiceRecord({ billitExport: linkedExport(exportOverrides) }) },
    ],
    billitEnvironment,
  });
  const res = await worker.fetch(adminSendRequest(body), env, {});
  return { res, body: await res.json(), bookingKv };
}

test("SEND GATE: a production Billit environment is refused before anything else", async () => {
  const { res, body } = await runAdminSend({
    body: sendRequestBody(),
    billitEnvironment: "production",
  });
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_sandbox_send_sandbox_only");
  assert.equal(body.environment, "production");
  assertNoOutboundTraffic();
});

test("SEND GATE: a missing confirm_sandbox_send flag is refused", async () => {
  const { res, body } = await runAdminSend({
    body: sendRequestBody({ confirm: false }),
  });
  assert.equal(res.status, 400);
  assert.equal(body.error, "confirm_sandbox_send_required");
  assertNoOutboundTraffic();
});

test("SEND GATE: a wrong document number is refused", async () => {
  const { res, body } = await runAdminSend({
    body: sendRequestBody({ documentNumber: "FLX-2026-07-9999" }),
  });
  assert.equal(res.status, 400);
  assert.equal(body.error, "document_number_mismatch");
  assertNoOutboundTraffic();
});

test("SEND GATE: a wrong Billit order id is refused", async () => {
  const { res, body } = await runAdminSend({
    body: sendRequestBody({ orderId: "111111" }),
  });
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_order_id_mismatch");
  assertNoOutboundTraffic();
});

test("SEND GATE: an unlinked document is refused", async () => {
  const { env } = makeEnv({ documents: [{ record: issuedInvoiceRecord() }] });
  const res = await worker.fetch(adminSendRequest(sendRequestBody()), env, {});
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_order_not_linked");
  assertNoOutboundTraffic();
});

test("SEND GATE: a non-sandbox stored export envelope is refused", async () => {
  const { res, body } = await runAdminSend({
    body: sendRequestBody(),
    exportOverrides: { environment: "production" },
  });
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_export_not_sandbox");
  assertNoOutboundTraffic();
});

test("SEND GATE: an already-sent order is refused (anti-double-send)", async () => {
  const { res, body } = await runAdminSend({
    body: sendRequestBody(),
    exportOverrides: { sent: true },
  });
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_order_already_sent");
  assertNoOutboundTraffic();
});

test("SEND GATE: an already-Peppol-sent order is refused", async () => {
  const { res, body } = await runAdminSend({
    body: sendRequestBody(),
    exportOverrides: { peppol_sent: true },
  });
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_order_already_peppol_sent");
  assertNoOutboundTraffic();
});

test("SEND GATE: a stored status of 'sent' is refused", async () => {
  const { res, body } = await runAdminSend({
    body: sendRequestBody(),
    exportOverrides: { status: "sent" },
  });
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_order_already_sent");
  assertNoOutboundTraffic();
});

test("SEND GATE: billit_is_sent from a live readback is refused", async () => {
  const { res, body } = await runAdminSend({
    body: sendRequestBody(),
    exportOverrides: { billit_is_sent: true },
  });
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_order_already_sent");
  assertNoOutboundTraffic();
});

test("SEND GATE: each pending flag independently blocks a second send", async () => {
  for (const flag of ["send_pending", "peppol_send_pending", "reconcile_pending"]) {
    const { res, body } = await runAdminSend({
      body: sendRequestBody(),
      exportOverrides: { [flag]: true },
    });
    assert.equal(res.status, 409, `${flag} should block the send`);
    assert.equal(body.error, "billit_order_send_pending", `${flag} reason`);
  }
  assertNoOutboundTraffic();
});

test("SEND GATE: the transport allowlist accepts only 'Peppol'", async () => {
  for (const transport of ["Email", "SMTP", "Letter", "peppol", "PEPPOL", ""]) {
    const { res, body } = await runAdminSend({
      body: sendRequestBody({ transport: transport || null }),
    });
    assert.equal(res.status, 400, `transport '${transport}' must be refused`);
    assert.equal(body.error, "transport_type_not_supported");
  }
  assertNoOutboundTraffic();
});

test("SEND GATE: a party-id mismatch between the export and the connection is refused", async () => {
  const { res, body } = await runAdminSend({
    body: sendRequestBody(),
    exportOverrides: { party_id: "party-someone-else" },
  });
  assert.equal(res.status, 409);
  assert.equal(body.error, "billit_party_id_mismatch");
  assertNoOutboundTraffic();
});

test("SEND GATE: a request that clears the export gates still hits Peppol readiness", async () => {
  // Every gate asserted above is satisfied here, so this is the closest a
  // hermetic run gets to a real transmission. It is still refused, by the Peppol
  // readiness gate that sits in front of the token step -- so nothing in this
  // suite can emit a Peppol document even by accident.
  const { res, body } = await runAdminSend({ body: sendRequestBody() });
  assert.equal(res.status >= 400, true, "a hermetic run must never report a send");
  assert.equal(body.error, "billit_peppol_not_ready", JSON.stringify(body));
  assertNoOutboundTraffic();
});

// ===========================================================================
// Tenant isolation.
// ===========================================================================

test("ISOLATION: a document owned by another tenant/company returns 404 on create", async () => {
  const { env } = makeEnv({
    documents: [
      {
        tenant_id: OTHER_TENANT,
        company_id: OTHER_COMPANY,
        record: issuedInvoiceRecord({
          tenantId: OTHER_TENANT,
          companyId: OTHER_COMPANY,
        }),
      },
    ],
  });
  const res = await worker.fetch(createRequestFor(SCOPE), env, {});
  const body = await res.json();
  assert.equal(res.status, 404);
  assert.equal(body.error, "document_not_found");
  assertNoOutboundTraffic();
});

test("ISOLATION: a Billit order status read for another tenant returns 404", async () => {
  const { env } = makeEnv({
    documents: [
      {
        tenant_id: OTHER_TENANT,
        company_id: OTHER_COMPANY,
        record: issuedInvoiceRecord({
          tenantId: OTHER_TENANT,
          companyId: OTHER_COMPANY,
          billitExport: linkedExport(),
        }),
      },
    ],
  });
  const res = await worker.fetch(
    adminRequest(
      scopedPath(`/admin/documents/${DOC_ID}/billit-order/status/sandbox`, SCOPE),
      { method: "GET" },
    ),
    env,
    {},
  );
  assert.equal(res.status, 404);
  const body = await res.json();
  assert.equal(body.error, "document_not_found");
  assertNoOutboundTraffic();
});

test("ISOLATION: a Peppol send context for another tenant returns 404", async () => {
  const { env } = makeEnv({
    documents: [
      {
        tenant_id: OTHER_TENANT,
        company_id: OTHER_COMPANY,
        record: issuedInvoiceRecord({
          tenantId: OTHER_TENANT,
          companyId: OTHER_COMPANY,
          billitExport: linkedExport(),
        }),
      },
    ],
  });
  const res = await worker.fetch(adminSendRequest(sendRequestBody(), SCOPE), env, {});
  assert.equal(res.status, 404);
  const body = await res.json();
  assert.equal(body.error, "document_not_found");
  assertNoOutboundTraffic();
});

test("ISOLATION: a Billit payload preview for another tenant returns 404", async () => {
  const { env } = makeEnv({
    documents: [
      {
        tenant_id: OTHER_TENANT,
        company_id: OTHER_COMPANY,
        record: issuedInvoiceRecord({
          tenantId: OTHER_TENANT,
          companyId: OTHER_COMPANY,
        }),
      },
    ],
  });
  const res = await worker.fetch(
    adminRequest(
      scopedPath(`/admin/documents/${DOC_ID}/billit-payload-preview`, SCOPE),
      { method: "GET" },
    ),
    env,
    {},
  );
  assert.equal(res.status, 404);
  assertNoOutboundTraffic();
});

test("ISOLATION: the document is only reachable under its OWN scope", async () => {
  const { env } = makeEnv({
    documents: [
      {
        tenant_id: OTHER_TENANT,
        company_id: OTHER_COMPANY,
        record: issuedInvoiceRecord({
          tenantId: OTHER_TENANT,
          companyId: OTHER_COMPANY,
          billitExport: linkedExport(),
        }),
      },
    ],
  });
  const ownScope = { tenant_id: OTHER_TENANT, company_id: OTHER_COMPANY };
  const res = await worker.fetch(
    adminRequest(
      scopedPath(`/admin/documents/${DOC_ID}/billit-order/status/sandbox`, ownScope),
      { method: "GET" },
    ),
    env,
    {},
  );
  // Reachable under its own scope: NOT a 404. (It stops later, at the token /
  // outbound step, which the hermetic trap owns.)
  assert.notEqual(res.status, 404);
});

test("ISOLATION: a mismatched company_id inside the body cannot widen the query scope", async () => {
  const { env } = makeEnv({
    documents: [
      {
        tenant_id: OTHER_TENANT,
        company_id: OTHER_COMPANY,
        record: issuedInvoiceRecord({
          tenantId: OTHER_TENANT,
          companyId: OTHER_COMPANY,
        }),
      },
    ],
  });
  // Query scope is the caller's own; the body tries to point at the other tenant.
  const res = await worker.fetch(
    adminRequest(
      scopedPath(`/admin/documents/${DOC_ID}/billit-order/create/sandbox`, SCOPE),
      {
        body: {
          confirm_sandbox_create: true,
          document_number: DOC_NUMBER,
          tenant_id: OTHER_TENANT,
          company_id: OTHER_COMPANY,
        },
      },
    ),
    env,
    {},
  );
  // Whichever scope wins, the caller must never receive another tenant's
  // document under a conflicting scope pair.
  assert.equal(
    res.status === 404 || res.status === 400 || res.status === 409,
    true,
    `expected a refusal, got ${res.status}`,
  );
  assertNoOutboundTraffic();
});

// ---------------------------------------------------------------------------
// Company-session scope: a caller-supplied company_id cannot widen the verified
// session scope. This is the strongest form of the isolation requirement,
// because the company routes accept a scope from the caller.
// ---------------------------------------------------------------------------

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(String(text || "")),
  );
  let hex = "";
  for (const byte of new Uint8Array(digest)) {
    hex += byte.toString(16).padStart(2, "0");
  }
  return hex;
}

async function seedCompanySession(kv, { token, tenantId, companyId }) {
  const key = `company_admin:session:${await sha256Hex(token)}:v1`;
  await kv.put(key, {
    role: "company_admin",
    tenant_id: tenantId,
    company_id: companyId,
    expires_at: new Date(Date.now() + 3600_000).toISOString(),
  });
  kv.writes.length = 0;
}

function companySendRequest({ token, scope, documentId = DOC_ID, body }) {
  return new Request(
    `https://booking.internal${scopedPath(`/company/documents/${documentId}/billit-order/send/sandbox`, scope)}`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(body),
    },
  );
}

test("ISOLATION: a company session cannot claim another company's scope", async () => {
  const { env, bookingKv } = makeEnv({
    documents: [
      {
        tenant_id: OTHER_TENANT,
        company_id: OTHER_COMPANY,
        record: issuedInvoiceRecord({
          tenantId: OTHER_TENANT,
          companyId: OTHER_COMPANY,
          billitExport: linkedExport(),
        }),
      },
    ],
  });
  await seedCompanySession(bookingKv, {
    token: "company-session-a",
    tenantId: TENANT,
    companyId: COMPANY,
  });
  // The session is verified for (tenant_a, company_a); the request asks for the
  // other company's scope in BOTH the query string and the body.
  const res = await worker.fetch(
    companySendRequest({
      token: "company-session-a",
      scope: { tenant_id: OTHER_TENANT, company_id: OTHER_COMPANY },
      body: {
        ...sendRequestBody(),
        tenant_id: OTHER_TENANT,
        company_id: OTHER_COMPANY,
      },
    }),
    env,
    {},
  );
  assert.equal(res.status, 403);
  const body = await res.json();
  assert.equal(body.error, "forbidden");
  assertNoOutboundTraffic();
});

test("ISOLATION: a company session sees 404 for a document outside its own scope", async () => {
  const { env, bookingKv } = makeEnv({
    documents: [
      {
        tenant_id: OTHER_TENANT,
        company_id: OTHER_COMPANY,
        record: issuedInvoiceRecord({
          tenantId: OTHER_TENANT,
          companyId: OTHER_COMPANY,
          billitExport: linkedExport(),
        }),
      },
    ],
  });
  await seedCompanySession(bookingKv, {
    token: "company-session-a",
    tenantId: TENANT,
    companyId: COMPANY,
  });
  // Consistent, honest scope this time -- the document simply is not theirs.
  const res = await worker.fetch(
    companySendRequest({
      token: "company-session-a",
      scope: SCOPE,
      body: sendRequestBody(),
    }),
    env,
    {},
  );
  assert.equal(res.status, 404);
  const body = await res.json();
  assert.equal(body.error, "document_not_found");
  assertNoOutboundTraffic();
});

test("ISOLATION: an anonymous caller cannot reach the company send route", async () => {
  const { env } = makeEnv({
    documents: [
      { record: issuedInvoiceRecord({ billitExport: linkedExport() }) },
    ],
  });
  const res = await worker.fetch(
    new Request(
      `https://booking.internal${scopedPath(`/company/documents/${DOC_ID}/billit-order/send/sandbox`)}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(sendRequestBody()),
      },
    ),
    env,
    {},
  );
  assert.equal(res.status, 401);
  assertNoOutboundTraffic();
});

test("ISOLATION: the company send route enforces the same send gates", async () => {
  const { env, bookingKv } = makeEnv({
    documents: [
      {
        record: issuedInvoiceRecord({ billitExport: linkedExport({ sent: true }) }),
      },
    ],
  });
  await seedCompanySession(bookingKv, {
    token: "company-session-a",
    tenantId: TENANT,
    companyId: COMPANY,
  });
  const res = await worker.fetch(
    companySendRequest({
      token: "company-session-a",
      scope: SCOPE,
      body: sendRequestBody(),
    }),
    env,
    {},
  );
  assert.equal(res.status, 409);
  const body = await res.json();
  assert.equal(body.error, "billit_order_already_sent");
  assertNoOutboundTraffic();
});

test("ISOLATION: admin routes still require the admin token", async () => {
  const { env } = makeEnv({ documents: [{ record: issuedInvoiceRecord() }] });
  for (const path of [
    `/admin/documents/${DOC_ID}/billit-order/create/sandbox`,
    `/admin/documents/${DOC_ID}/billit-order/send/sandbox`,
  ]) {
    const res = await worker.fetch(
      adminRequest(scopedPath(path), { adminToken: null, body: {} }),
      env,
      {},
    );
    assert.equal(res.status, 401, `${path} must require admin auth`);
  }
  assertNoOutboundTraffic();
});
