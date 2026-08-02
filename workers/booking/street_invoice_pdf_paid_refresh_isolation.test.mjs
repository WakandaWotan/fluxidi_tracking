/* STREET-INVOICE-PDF-P1 — paid-lifecycle PDF refresh failure isolation.
 *
 * Proves that a controlled PDF refresh failure inside runPaidBookingAfterLifecycle
 * does not throw, does not mutate payment/financial identity, and does not
 * trigger Billit create/PATCH or Peppol. A later retry may attempt PDF again.
 *
 * Hermetic: in-memory KV, outbound fetch trap, injectable DC/Billit/PDF impls.
 *
 *   node --test workers/booking/street_invoice_pdf_paid_refresh_isolation.test.mjs
 */

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";

import {
  runPaidBookingAfterLifecycle,
} from "./fluxidi_booking_worker.js";

const TENANT = "tenant_pdf_iso_a";
const COMPANY = "company_pdf_iso_a";
const BOOKING_ID = "street_pdf_iso_001";
const DOC_ID = "doc_pdf_iso_001";
const INV_NUMBER = "INV-TEST-PDF-ISO-001";
const PAID_AT = "2026-08-01T12:00:00.000Z";
const PDF_KEY =
  "private-artifacts/tenant/tenant_pdf_iso_a/company/company_pdf_iso_a/bookings/street_pdf_iso_001/invoices/INV-TEST-PDF-ISO-001.pdf";

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

function makeKV(seed = {}) {
  const store = new Map(
    Object.entries(seed).map(([k, v]) => [
      k,
      typeof v === "string" ? v : JSON.stringify(v),
    ]),
  );
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
      store.set(key, typeof val === "string" ? val : JSON.stringify(val));
    },
    async delete(key) {
      store.delete(key);
    },
    async list() {
      return { keys: [...store.keys()].map((name) => ({ name })), list_complete: true };
    },
  };
}

function buildPaidStreetBooking() {
  return {
    tenant_id: TENANT,
    company_id: COMPANY,
    booking_id: BOOKING_ID,
    bookingId: BOOKING_ID,
    payment_status: "paid",
    paymentStatus: "paid",
    paid_at: PAID_AT,
    paidAt: PAID_AT,
    payment_method: "qr_code",
    paymentMethod: "qr_code",
    payment_provider: "manual",
    paymentProvider: "manual",
    invoice_number: INV_NUMBER,
    invoiceNumber: INV_NUMBER,
    invoice_document_id: DOC_ID,
    invoiceDocumentId: DOC_ID,
    document_id: DOC_ID,
    invoice_pdf_key: PDF_KEY,
    invoicePdfKey: PDF_KEY,
    invoice_pdf_projection_revision:
      "street_pdf_proj_v1;pay=unpaid;vat=6;incl=500;tax=30;ex=470;seller=document_core_seller_snapshot;method=QR-betaling;trip=2026-08-01|12:00;tier=comfort;svc=private",
    invoice_intent: "business_invoice",
    invoiceIntent: "business_invoice",
    invoice_requested: true,
    invoiceRequested: true,
    invoice_state: "ready_to_send",
    invoiceState: "ready_to_send",
    price_incl_vat: 5,
    price_vat: 0.3,
    price_ex_vat: 4.7,
    vat_rate_percent: 6,
    booking: {
      booking_id: BOOKING_ID,
      from: "Pickup A",
      to: "Dropoff B",
      tier: "comfort",
      service: "private",
      payment_status: "paid",
      paymentStatus: "paid",
      paid_at: PAID_AT,
      paidAt: PAID_AT,
      payment_method: "qr_code",
      invoice_number: INV_NUMBER,
      invoice_pdf_key: PDF_KEY,
    },
  };
}

function paymentSnapshot(rec) {
  return {
    payment_status: rec?.payment_status ?? null,
    paymentStatus: rec?.paymentStatus ?? null,
    paid_at: rec?.paid_at ?? null,
    paidAt: rec?.paidAt ?? null,
    payment_method: rec?.payment_method ?? null,
    invoice_number: rec?.invoice_number ?? null,
    invoiceNumber: rec?.invoiceNumber ?? null,
    invoice_document_id: rec?.invoice_document_id ?? null,
    document_id: rec?.document_id ?? null,
    invoice_pdf_key: rec?.invoice_pdf_key ?? null,
    price_incl_vat: rec?.price_incl_vat ?? null,
    price_vat: rec?.price_vat ?? null,
    price_ex_vat: rec?.price_ex_vat ?? null,
    vat_rate_percent: rec?.vat_rate_percent ?? null,
  };
}

test("paid lifecycle: PDF refresh failure is isolated; retry may attempt PDF again", async () => {
  const booking = buildPaidStreetBooking();
  const kv = makeKV({ [`booking:${BOOKING_ID}`]: booking });
  const env = {
    BOOKING_KV: kv,
    // No DOCUMENT_REFERENCE_SEQUENCE — proves no invoice number allocation.
    // No Billit OAuth tokens / Peppol bindings.
    BILLIT_ENVIRONMENT: "production",
  };

  let documentCoreCalls = 0;
  let billitCalls = 0;
  let pdfCalls = 0;
  let peppolCalls = 0;

  const documentCoreResult = {
    ok: true,
    skipped: false,
    reason: "idempotent_replay",
    document_id: DOC_ID,
    document_number: INV_NUMBER,
    reused_existing_invoice: true,
  };
  const billitResult = {
    ok: true,
    skipped: true,
    reason: "config_not_sandbox",
    peppol_sent: false,
    sent: false,
    billit_order_id: null,
  };

  const hooks = {
    source: "pdf_isolation_test",
    rec: booking,
    background: false,
    documentCoreImpl: async () => {
      documentCoreCalls += 1;
      return { ...documentCoreResult };
    },
    billitImpl: async () => {
      billitCalls += 1;
      return { ...billitResult };
    },
    pdfRefreshImpl: async () => {
      pdfCalls += 1;
      // Simulate renderer/persist throw at the lifecycle PDF boundary.
      throw new Error("forced_pdf_renderer_persist_fail");
    },
  };

  const beforeSnap = paymentSnapshot(booking);

  let first;
  await assert.doesNotReject(async () => {
    first = await runPaidBookingAfterLifecycle(
      env,
      { tenant_id: TENANT, company_id: COMPANY },
      BOOKING_ID,
      hooks,
    );
  });

  assert.equal(first?.error, undefined);
  assert.equal(first?.document_core_result?.ok, true);
  assert.equal(first?.document_core_result?.reason, "idempotent_replay");
  assert.equal(first?.document_core_result?.document_id, DOC_ID);
  assert.equal(first?.document_core_result?.document_number, INV_NUMBER);
  assert.equal(first?.billit_result?.ok, true);
  assert.equal(first?.billit_result?.reason, "config_not_sandbox");
  assert.equal(first?.billit_result?.peppol_sent, false);
  assert.equal(first?.pdf_result?.ok, false);
  assert.equal(first?.pdf_result?.reason, "pdf_refresh_exception");

  assert.equal(documentCoreCalls, 1);
  assert.equal(billitCalls, 1);
  assert.equal(pdfCalls, 1);
  assert.equal(peppolCalls, 0);
  assertNoOutboundTraffic();

  const afterFirst = await kv.get(`booking:${BOOKING_ID}`, { type: "json" });
  assert.deepEqual(paymentSnapshot(afterFirst), beforeSnap);
  assert.equal(afterFirst.payment_status, "paid");
  assert.equal(afterFirst.paid_at, PAID_AT);
  assert.equal(afterFirst.invoice_number, INV_NUMBER);
  assert.equal(afterFirst.invoice_document_id, DOC_ID);

  // Booking KV must not have been rewritten by the PDF failure path.
  assert.equal(kv.writes.length, 0);

  // Second run: PDF may be attempted again; payment/financial identity stays put.
  let second;
  await assert.doesNotReject(async () => {
    second = await runPaidBookingAfterLifecycle(
      env,
      { tenant_id: TENANT, company_id: COMPANY },
      BOOKING_ID,
      hooks,
    );
  });

  assert.equal(second?.pdf_result?.ok, false);
  assert.equal(second?.pdf_result?.reason, "pdf_refresh_exception");
  assert.equal(pdfCalls, 2, "retry must re-attempt PDF refresh");
  assert.equal(documentCoreCalls, 2);
  assert.equal(billitCalls, 2);
  assert.equal(peppolCalls, 0);
  assertNoOutboundTraffic();

  // Successful DC/Billit envelopes are not downgraded by the PDF failure.
  assert.equal(second?.document_core_result?.ok, true);
  assert.equal(second?.document_core_result?.reason, "idempotent_replay");
  assert.equal(second?.document_core_result?.document_number, INV_NUMBER);
  assert.equal(second?.billit_result?.ok, true);
  assert.equal(second?.billit_result?.peppol_sent, false);
  assert.equal(second?.billit_result?.billit_order_id, null);

  const afterSecond = await kv.get(`booking:${BOOKING_ID}`, { type: "json" });
  assert.deepEqual(paymentSnapshot(afterSecond), beforeSnap);
  assert.equal(kv.writes.length, 0);
});
