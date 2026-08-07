// CONSUMER-BILLIT-EXACTLY-ONCE-CREATE-P0
//
// Hermetic concurrency + ambiguous-timeout tests for consumer Billit create.
// Uses injectable issue/ensure impls — no live Billit / Mollie / Document Core.
//
// Run: node --test workers/booking/consumer_billit_exactly_once_create_p0.test.mjs

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";

import {
  maybeRegisterConsumerBillitSaleAfterCompletion,
  maybeSyncConsumerBillitSaleAfterPaid,
  loadConsumerBillitSaleIntent,
} from "./fluxidi_booking_worker.js";
import {
  buildBillitConsumerSaleOrderCreateIdempotencyKey,
  buildConsumerSaleIdempotencyKey,
  resolveConsumerToBusinessConversionDecision,
} from "./modules/consumer_billit_sale.mjs";
import {
  buildDocumentRegistryKey,
  buildDocumentsByBookingKey,
} from "./modules/document_core.js";

const TENANT = "tenant_consumer_xo_a";
const COMPANY = "company_consumer_xo_a";
const TENANT_B = "tenant_consumer_xo_b";
const COMPANY_B = "company_consumer_xo_b";
const SCOPE = { tenant_id: TENANT, company_id: COMPANY };
const SCOPE_B = { tenant_id: TENANT_B, company_id: COMPANY_B };

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

function streetBooking(bookingId, over = {}) {
  return {
    booking_id: bookingId,
    tenant_id: TENANT,
    company_id: COMPANY,
    status: "COMPLETED",
    ride_type: "direct",
    source: "street_ride",
    street_ride_fare_finalized: true,
    price_incl_vat: 18.6,
    total_incl_vat: 18.6,
    // deriveServerSideInvoiceContext reads nested booking/payload currency,
    // not a bare top-level currency field.
    currency: "EUR",
    booking: { currency: "EUR", price_incl_vat: 18.6 },
    payload: { currency: "EUR", price_incl_vat: 18.6 },
    pricing_profile: { currency: "EUR", vat_rate: 0.06 },
    vat_rate_percent: 6,
    invoice_intent: "none",
    payment_status: "unpaid",
    custName: "Test Rider",
    ...over,
  };
}

function makeEnv(bookingId, bookingOver = {}, seedExtra = {}) {
  const booking = streetBooking(bookingId, bookingOver);
  const seed = {
    [`booking:${bookingId}`]: booking,
    ...seedExtra,
  };
  return {
    BOOKING_KV: makeKV(seed),
    BILLIT_ENVIRONMENT: "sandbox",
    BILLIT_CLIENT_ID: "test-client",
    BILLIT_CLIENT_SECRET: "test-secret",
    BILLIT_REDIRECT_URI: "https://example.test/callback",
  };
}

function jsonResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async json() {
      return body;
    },
  };
}

function makeIssueCounter(env, scope, bookingId, { docId = "doc-xo-1", docNumber = "INV-XO-000001" } = {}) {
  let issueCalls = 0;
  const issuedDocs = [];
  const issueInvoiceImpl = async ({ body }) => {
    issueCalls += 1;
    const id = `${docId}-${issueCalls}`;
    // Stable id for exactly-once: only the first mint wins; later calls
    // should not happen. If they do, distinct ids make the failure obvious.
    const documentId = issueCalls === 1 ? docId : id;
    const documentNumber = issueCalls === 1 ? docNumber : `${docNumber}-${issueCalls}`;
    const record = {
      document_id: documentId,
      document_number: documentNumber,
      document_type: "invoice",
      tenant_id: scope.tenant_id,
      company_id: scope.company_id,
      source_booking_id: bookingId,
      fluxidi_sale_kind: "consumer_sale",
      created_by_role: "system_consumer_sale",
      issue_timestamp: new Date().toISOString(),
      totals: {
        total_incl_vat: 18.6,
        vat_rate_percent: 6,
        currency: "EUR",
      },
      idempotency_key: body?.idempotency_key || null,
    };
    const registryKey = buildDocumentRegistryKey(scope, documentId);
    const byBooking = buildDocumentsByBookingKey(
      scope,
      bookingId,
      "invoice",
      documentId,
    );
    await env.BOOKING_KV.put(registryKey, JSON.stringify(record));
    await env.BOOKING_KV.put(byBooking, documentId);
    issuedDocs.push(documentId);
    return jsonResponse({
      ok: true,
      document_id: documentId,
      document_number: documentNumber,
      document_record: record,
    });
  };
  return {
    get issueCalls() {
      return issueCalls;
    },
    issuedDocs,
    issueInvoiceImpl,
  };
}

function makeBillitCounter({
  orderId = "billit-ord-xo-1",
  failFirstAsAmbiguous = false,
} = {}) {
  let createCalls = 0;
  const keys = [];
  const ensureBillitOrderImpl = async (
    _env,
    _scope,
    _config,
    documentRecord,
    opts = {},
  ) => {
    createCalls += 1;
    const saleKey = opts.saleIdempotencyKey || null;
    const idem =
      (saleKey
        ? buildBillitConsumerSaleOrderCreateIdempotencyKey(saleKey)
        : null) || `legacy:${opts.documentId}`;
    keys.push(idem);
    if (failFirstAsAmbiguous && createCalls === 1) {
      return {
        ok: false,
        error: "billit_order_create_failed",
        billit_error_code: "order_create_request_failed",
        ambiguous_remote_outcome: true,
        idempotency_key: idem,
      };
    }
    // Persist export on the in-memory registry when possible.
    if (documentRecord && typeof documentRecord === "object") {
      documentRecord.billit_export = {
        environment: "sandbox",
        order_id: orderId,
        order_number: opts.documentNumber || null,
        idempotency_key: idem,
      };
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
    ensureBillitOrderImpl,
  };
}

test("1. normal consumer sale → exactly one invoice + one Billit order", async () => {
  const bookingId = "street_xo_normal_1";
  const env = makeEnv(bookingId);
  const issue = makeIssueCounter(env, SCOPE, bookingId);
  const billit = makeBillitCounter();
  const out = await maybeRegisterConsumerBillitSaleAfterCompletion(
    env,
    SCOPE,
    bookingId,
    {
      issueInvoiceImpl: issue.issueInvoiceImpl,
      ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
    },
  );
  assert.equal(out.ok, true);
  assert.equal(out.document_id, "doc-xo-1");
  assert.equal(out.billit_order_id, "billit-ord-xo-1");
  assert.equal(issue.issueCalls, 1);
  assert.equal(billit.createCalls, 1);
  const saleKey = buildConsumerSaleIdempotencyKey({
    tenantId: TENANT,
    companyId: COMPANY,
    bookingId,
  });
  assert.equal(
    billit.keys[0],
    buildBillitConsumerSaleOrderCreateIdempotencyKey(saleKey),
  );
  assert.equal(outboundAttempts.length, 0);
});

test("2. finalize called twice concurrently → one document + one Billit create", async () => {
  const bookingId = "street_xo_concurrent_finalize";
  const env = makeEnv(bookingId);
  const issue = makeIssueCounter(env, SCOPE, bookingId, {
    docId: "doc-xo-fin",
  });
  const billit = makeBillitCounter({ orderId: "ord-fin" });
  const opts = {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  };
  await Promise.all([
    maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, opts),
    maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, opts),
  ]);
  // Peer may have returned in_progress; one more call converges.
  const final = await maybeRegisterConsumerBillitSaleAfterCompletion(
    env,
    SCOPE,
    bookingId,
    opts,
  );
  assert.equal(final.document_id, "doc-xo-fin");
  assert.equal(final.billit_order_id, "ord-fin");
  assert.equal(issue.issueCalls, 1);
  assert.equal(billit.createCalls, 1);
});

test("3. finalize + Mollie webhook concurrently", async () => {
  const bookingId = "street_xo_fin_webhook";
  const env = makeEnv(bookingId, { payment_status: "paid", payment_method: "bancontact" });
  const issue = makeIssueCounter(env, SCOPE, bookingId, { docId: "doc-xo-wh" });
  const billit = makeBillitCounter({ orderId: "ord-wh" });
  const opts = {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  };
  await Promise.all([
    maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, opts),
    maybeSyncConsumerBillitSaleAfterPaid(env, SCOPE, bookingId, {
      ...opts,
      rec: streetBooking(bookingId, {
        payment_status: "paid",
        payment_method: "bancontact",
      }),
    }),
  ]);
  const final = await maybeRegisterConsumerBillitSaleAfterCompletion(
    env,
    SCOPE,
    bookingId,
    opts,
  );
  assert.equal(issue.issueCalls, 1);
  assert.equal(final.document_id, "doc-xo-wh");
  assert.equal(final.billit_order_id, "ord-wh");
});

test("4. finalize + /pay/status concurrently", async () => {
  const bookingId = "street_xo_fin_status";
  const env = makeEnv(bookingId, { payment_status: "paid" });
  const issue = makeIssueCounter(env, SCOPE, bookingId, { docId: "doc-xo-st" });
  const billit = makeBillitCounter({ orderId: "ord-st" });
  const opts = {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  };
  await Promise.all([
    maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, opts),
    maybeSyncConsumerBillitSaleAfterPaid(env, SCOPE, bookingId, {
      ...opts,
      rec: streetBooking(bookingId, { payment_status: "paid" }),
    }),
  ]);
  const final = await maybeRegisterConsumerBillitSaleAfterCompletion(
    env,
    SCOPE,
    bookingId,
    opts,
  );
  assert.equal(issue.issueCalls, 1);
  assert.equal(final.document_id, "doc-xo-st");
  assert.equal(final.billit_order_id, "ord-st");
});

test("5. finalize + webhook + /pay/status all concurrently", async () => {
  const bookingId = "street_xo_triple";
  const env = makeEnv(bookingId, { payment_status: "paid" });
  const issue = makeIssueCounter(env, SCOPE, bookingId, { docId: "doc-xo-tri" });
  const billit = makeBillitCounter({ orderId: "ord-tri" });
  const opts = {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  };
  const paidRec = streetBooking(bookingId, { payment_status: "paid" });
  await Promise.all([
    maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, opts),
    maybeSyncConsumerBillitSaleAfterPaid(env, SCOPE, bookingId, {
      ...opts,
      rec: paidRec,
    }),
    maybeSyncConsumerBillitSaleAfterPaid(env, SCOPE, bookingId, {
      ...opts,
      rec: paidRec,
    }),
  ]);
  const final = await maybeRegisterConsumerBillitSaleAfterCompletion(
    env,
    SCOPE,
    bookingId,
    opts,
  );
  assert.equal(issue.issueCalls, 1);
  assert.equal(billit.createCalls, 1);
  assert.equal(final.document_id, "doc-xo-tri");
  assert.equal(final.billit_order_id, "ord-tri");
});

test("6+7. Billit remote success + lost local response → retry same sale key", async () => {
  const bookingId = "street_xo_ambiguous";
  const env = makeEnv(bookingId);
  const issue = makeIssueCounter(env, SCOPE, bookingId, { docId: "doc-xo-amb" });
  const billit = makeBillitCounter({
    orderId: "ord-amb",
    failFirstAsAmbiguous: true,
  });
  const opts = {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  };
  const first = await maybeRegisterConsumerBillitSaleAfterCompletion(
    env,
    SCOPE,
    bookingId,
    opts,
  );
  assert.equal(first.document_id, "doc-xo-amb");
  assert.equal(first.billit_order_id, null);
  assert.equal(issue.issueCalls, 1);

  const second = await maybeRegisterConsumerBillitSaleAfterCompletion(
    env,
    SCOPE,
    bookingId,
    opts,
  );
  assert.equal(second.document_id, "doc-xo-amb");
  assert.equal(second.billit_order_id, "ord-amb");
  assert.equal(issue.issueCalls, 1, "must not mint a second document after timeout");
  assert.equal(billit.createCalls, 2);
  assert.equal(billit.keys[0], billit.keys[1]);
  assert.match(billit.keys[0], /^fluxidi-billit-consumer-order:inv-consumer:/);
});

test("8. process/retry after document id allocation reuses same INV", async () => {
  const bookingId = "street_xo_allocated";
  const env = makeEnv(bookingId);
  const issue = makeIssueCounter(env, SCOPE, bookingId, { docId: "doc-xo-alloc" });
  // Seed intent with document already allocated (crash after issue, before Billit).
  const saleKey = buildConsumerSaleIdempotencyKey({
    tenantId: TENANT,
    companyId: COMPANY,
    bookingId,
  });
  const intentKey = `tenant:${TENANT}:company:${COMPANY}:consumer_billit_sale_intent:${bookingId}:main:v1`;
  const docId = "doc-xo-alloc";
  const record = {
    document_id: docId,
    document_number: "INV-XO-ALLOC",
    document_type: "invoice",
    tenant_id: TENANT,
    company_id: COMPANY,
    source_booking_id: bookingId,
    fluxidi_sale_kind: "consumer_sale",
    issue_timestamp: new Date().toISOString(),
    totals: { total_incl_vat: 18.6, vat_rate_percent: 6, currency: "EUR" },
  };
  await env.BOOKING_KV.put(
    buildDocumentRegistryKey(SCOPE, docId),
    JSON.stringify(record),
  );
  await env.BOOKING_KV.put(
    buildDocumentsByBookingKey(SCOPE, bookingId, "invoice", docId),
    docId,
  );
  await env.BOOKING_KV.put(
    intentKey,
    JSON.stringify({
      document_id: docId,
      document_number: "INV-XO-ALLOC",
      billit_order_id: null,
      sale_idempotency_key: saleKey,
      holder_id: "prior-owner",
      state: "billit_creating",
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }),
  );
  const billit = makeBillitCounter({ orderId: "ord-alloc" });
  const out = await maybeRegisterConsumerBillitSaleAfterCompletion(
    env,
    SCOPE,
    bookingId,
    {
      issueInvoiceImpl: issue.issueInvoiceImpl,
      ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
    },
  );
  assert.equal(out.document_id, docId);
  assert.equal(out.billit_order_id, "ord-alloc");
  assert.equal(issue.issueCalls, 0);
  assert.equal(billit.createCalls, 1);
});

test("9. repeated paid reconciliation stays sync-only / same document", async () => {
  const bookingId = "street_xo_paid_reconcile";
  const env = makeEnv(bookingId, { payment_status: "paid" });
  const issue = makeIssueCounter(env, SCOPE, bookingId, { docId: "doc-xo-pay" });
  const billit = makeBillitCounter({ orderId: "ord-pay" });
  const opts = {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
    rec: streetBooking(bookingId, { payment_status: "paid" }),
  };
  await maybeSyncConsumerBillitSaleAfterPaid(env, SCOPE, bookingId, opts);
  await maybeSyncConsumerBillitSaleAfterPaid(env, SCOPE, bookingId, opts);
  await maybeSyncConsumerBillitSaleAfterPaid(env, SCOPE, bookingId, opts);
  assert.equal(issue.issueCalls, 1);
  const intent = await loadConsumerBillitSaleIntent(env, SCOPE, bookingId);
  assert.equal(intent.intent.document_id, "doc-xo-pay");
  assert.equal(intent.intent.billit_order_id, "ord-pay");
});

test("10. weak-network retry converges on same identity", async () => {
  const bookingId = "street_xo_weak_net";
  const env = makeEnv(bookingId);
  const issue = makeIssueCounter(env, SCOPE, bookingId, { docId: "doc-xo-wn" });
  const billit = makeBillitCounter({
    orderId: "ord-wn",
    failFirstAsAmbiguous: true,
  });
  const opts = {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  };
  for (let i = 0; i < 3; i += 1) {
    await maybeRegisterConsumerBillitSaleAfterCompletion(env, SCOPE, bookingId, opts);
  }
  assert.equal(issue.issueCalls, 1);
  const intent = await loadConsumerBillitSaleIntent(env, SCOPE, bookingId);
  assert.equal(intent.intent.document_id, "doc-xo-wn");
  assert.equal(intent.intent.billit_order_id, "ord-wn");
});

test("11+12+13. one canonical Fluxidi document, one Billit create, stable identity", async () => {
  const bookingId = "street_xo_stable";
  const env = makeEnv(bookingId);
  const issue = makeIssueCounter(env, SCOPE, bookingId, {
    docId: "doc-xo-stable",
    docNumber: "INV-XO-STABLE",
  });
  const billit = makeBillitCounter({ orderId: "ord-stable" });
  const opts = {
    issueInvoiceImpl: issue.issueInvoiceImpl,
    ensureBillitOrderImpl: billit.ensureBillitOrderImpl,
  };
  const r1 = await maybeRegisterConsumerBillitSaleAfterCompletion(
    env,
    SCOPE,
    bookingId,
    opts,
  );
  const r2 = await maybeRegisterConsumerBillitSaleAfterCompletion(
    env,
    SCOPE,
    bookingId,
    opts,
  );
  assert.equal(r1.document_id, r2.document_id);
  assert.equal(r1.document_id, "doc-xo-stable");
  assert.equal(issue.issueCalls, 1);
  // Second call should short-circuit on reuse (no second Billit create).
  assert.equal(billit.createCalls, 1);
});

test("14. late business conversion still requires CreditNote pipeline", () => {
  const d = resolveConsumerToBusinessConversionDecision({
    hasConsumerSale: true,
    consumerBillitOrderId: "ord-c",
    hasCreditNoteDocument: false,
    hasCreditNoteBillitOrder: false,
  });
  assert.equal(d.requires_credit_note, true);
  assert.equal(d.allow_business_invoice, false);
  assert.equal(d.double_revenue_risk, false);
});

test("15. different rides with identical amount remain separate", async () => {
  const aId = "street_xo_amt_a";
  const bId = "street_xo_amt_b";
  const envA = makeEnv(aId, { price_incl_vat: 25 });
  const envB = makeEnv(bId, { price_incl_vat: 25 });
  const issueA = makeIssueCounter(envA, SCOPE, aId, { docId: "doc-amt-a" });
  const issueB = makeIssueCounter(envB, SCOPE, bId, { docId: "doc-amt-b" });
  const billitA = makeBillitCounter({ orderId: "ord-amt-a" });
  const billitB = makeBillitCounter({ orderId: "ord-amt-b" });
  const outA = await maybeRegisterConsumerBillitSaleAfterCompletion(
    envA,
    SCOPE,
    aId,
    {
      issueInvoiceImpl: issueA.issueInvoiceImpl,
      ensureBillitOrderImpl: billitA.ensureBillitOrderImpl,
    },
  );
  const outB = await maybeRegisterConsumerBillitSaleAfterCompletion(
    envB,
    SCOPE,
    bId,
    {
      issueInvoiceImpl: issueB.issueInvoiceImpl,
      ensureBillitOrderImpl: billitB.ensureBillitOrderImpl,
    },
  );
  assert.notEqual(outA.document_id, outB.document_id);
  assert.notEqual(outA.billit_order_id, outB.billit_order_id);
  assert.notEqual(
    buildConsumerSaleIdempotencyKey({
      tenantId: TENANT,
      companyId: COMPANY,
      bookingId: aId,
    }),
    buildConsumerSaleIdempotencyKey({
      tenantId: TENANT,
      companyId: COMPANY,
      bookingId: bId,
    }),
  );
});

test("16. roundtrip legs remain distinct sale identities", () => {
  const out = buildConsumerSaleIdempotencyKey({
    tenantId: TENANT,
    companyId: COMPANY,
    bookingId: "bk_rt_xo",
    legId: "leg_outbound",
  });
  const ret = buildConsumerSaleIdempotencyKey({
    tenantId: TENANT,
    companyId: COMPANY,
    bookingId: "bk_rt_xo",
    legId: "leg_return",
  });
  assert.notEqual(out, ret);
  assert.match(out, /:leg_outbound:consumer_sale:v1$/);
  assert.match(ret, /:leg_return:consumer_sale:v1$/);
});

test("17. tenant isolation of sale intent + Billit create key", async () => {
  const bookingId = "street_xo_tenant";
  const envA = makeEnv(bookingId);
  // Same booking id string under a foreign tenant must not share intent.
  const bookingB = streetBooking(bookingId, {
    tenant_id: TENANT_B,
    company_id: COMPANY_B,
  });
  const envB = {
    BOOKING_KV: makeKV({ [`booking:${bookingId}`]: bookingB }),
    BILLIT_ENVIRONMENT: "sandbox",
    BILLIT_CLIENT_ID: "test-client",
    BILLIT_CLIENT_SECRET: "test-secret",
    BILLIT_REDIRECT_URI: "https://example.test/callback",
  };
  const issueA = makeIssueCounter(envA, SCOPE, bookingId, { docId: "doc-t-a" });
  const issueB = makeIssueCounter(envB, SCOPE_B, bookingId, { docId: "doc-t-b" });
  const billitA = makeBillitCounter({ orderId: "ord-t-a" });
  const billitB = makeBillitCounter({ orderId: "ord-t-b" });
  const outA = await maybeRegisterConsumerBillitSaleAfterCompletion(
    envA,
    SCOPE,
    bookingId,
    {
      issueInvoiceImpl: issueA.issueInvoiceImpl,
      ensureBillitOrderImpl: billitA.ensureBillitOrderImpl,
    },
  );
  const outB = await maybeRegisterConsumerBillitSaleAfterCompletion(
    envB,
    SCOPE_B,
    bookingId,
    {
      issueInvoiceImpl: issueB.issueInvoiceImpl,
      ensureBillitOrderImpl: billitB.ensureBillitOrderImpl,
    },
  );
  assert.equal(outA.document_id, "doc-t-a");
  assert.equal(outB.document_id, "doc-t-b");
  assert.notEqual(billitA.keys[0], billitB.keys[0]);
});
