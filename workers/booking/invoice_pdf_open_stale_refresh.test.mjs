/* FLUXIDI-HISTORICAL-INVOICE-PDF-STALE-ARTIFACT-REFRESH-P0-1
 *
 * Proves the ordinary authenticated download (GET /bookings/:id/invoice/pdf)
 * refreshes a derived PDF artifact that predates the current projection
 * version, reuses a current artifact without regeneration, keeps the issued
 * invoice facts untouched, and never bulk-regenerates anything.
 *
 * Hermetic: in-memory KV + R2, outbound fetch trap, injected ensure impl.
 *
 *   node --test workers/booking/invoice_pdf_open_stale_refresh.test.mjs
 */

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";

import { handleBookingInvoicePdfGet } from "./fluxidi_booking_worker.js";
import {
  STREET_INVOICE_PDF_PROJECTION_VERSION,
  readStoredStreetInvoicePdfProjectionRevision,
} from "./modules/street_invoice_pdf_projection.js";

const TENANT = "tenant_stale_pdf_a";
const COMPANY = "company_stale_pdf_a";
const OTHER_TENANT = "tenant_stale_pdf_b";
const BOOKING_ID = "street_stale_pdf_001";
const DOC_ID = "doc_stale_pdf_001";
const INV_NUMBER = "INV-TEST-STALE-000037";
const ADMIN_TOKEN = "admin-token-stale-pdf-test";
const PDF_KEY = `private-artifacts/tenant/${TENANT}/company/${COMPANY}/bookings/${BOOKING_ID}/invoices/${INV_NUMBER}.pdf`;

const V1_REVISION =
  "street_pdf_proj_v1;pay=paid;vat=6;incl=500;tax=30;ex=470;seller=document_core_seller_snapshot;method=PayPal;trip=2026-07-20|12:00;tier=comfort;svc=private";
const V2_REVISION =
  `${STREET_INVOICE_PDF_PROJECTION_VERSION};pay=paid;vat=6;incl=500;tax=30;ex=470;seller=document_core_seller_snapshot;method=PayPal;trip=2026-07-20|12:00;tier=comfort;svc=private;route=Kortrijksesteenweg 12, Deinze>Sint-Pietersplein 1, Gent`;

// Minimal but structurally real PDFs: one page each, distinguishable content.
const STALE_PDF_BYTES = pdfBytes([
  "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj",
  "2 0 obj<</Type/Pages/Kids[3 0 R 4 0 R]/Count 2>>endobj",
  "% legacy artifact: 50.772006, 3.669447 + broken logo",
]);
const FRESH_PDF_BYTES = pdfBytes([
  "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj",
  "2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj",
  "3 0 obj<</Type/Page/Parent 2 0 R>>endobj",
  "% Kortrijksesteenweg 12, Deinze  /Im-fluxidi-logo Do  btw-vrijstelling",
]);

function pdfBytes(lines) {
  return new TextEncoder().encode(
    `%PDF-1.4\n${lines.join("\n")}\n%%EOF\n`,
  );
}

function countPdfPages(bytes) {
  const text = new TextDecoder().decode(bytes);
  const match = text.match(/\/Count\s+(\d+)/);
  return match ? Number(match[1]) : 0;
}

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
      return {
        keys: [...store.keys()].map((name) => ({ name })),
        list_complete: true,
      };
    },
  };
}

function makeR2(seed = {}) {
  const store = new Map(Object.entries(seed));
  const reads = [];
  const writes = [];
  return {
    store,
    reads,
    writes,
    async get(key) {
      reads.push(key);
      if (!store.has(key)) return null;
      const bytes = store.get(key);
      return {
        httpMetadata: { contentType: "application/pdf" },
        async arrayBuffer() {
          return bytes.buffer.slice(
            bytes.byteOffset,
            bytes.byteOffset + bytes.byteLength,
          );
        },
      };
    },
    async put(key, bytes) {
      writes.push(key);
      store.set(key, bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes));
    },
  };
}

function buildIssuedBooking(projectionRevision) {
  return {
    tenant_id: TENANT,
    company_id: COMPANY,
    booking_id: BOOKING_ID,
    bookingId: BOOKING_ID,
    payment_status: "paid",
    paymentStatus: "paid",
    paid_at: "2026-07-20T12:30:00.000Z",
    payment_method: "paypal",
    paymentMethod: "paypal",
    payment_provider: "mollie",
    invoice_number: INV_NUMBER,
    invoiceNumber: INV_NUMBER,
    invoice_document_id: DOC_ID,
    document_id: DOC_ID,
    invoice_pdf_key: PDF_KEY,
    invoicePdfKey: PDF_KEY,
    invoice_pdf_projection_revision: projectionRevision,
    invoicePdfProjectionRevision: projectionRevision,
    invoice_pdf_sha256: "aa11bb22cc33dd44ee55ff6600112233",
    invoice_pdf_content_type: "application/pdf",
    invoice_intent: "business_invoice",
    invoice_state: "ready_to_send",
    price_incl_vat: 5,
    price_vat: 0.3,
    price_ex_vat: 4.7,
    vat_rate_percent: 6,
    booking: {
      booking_id: BOOKING_ID,
      from: "Kortrijksesteenweg 12, Deinze",
      to: "Sint-Pietersplein 1, Gent",
      tier: "comfort",
      service: "private",
      payment_status: "paid",
      payment_method: "paypal",
      invoice_number: INV_NUMBER,
      invoice_pdf_key: PDF_KEY,
    },
  };
}

/** Immutable issued facts that a derived-artifact refresh must never touch. */
function issuedFactsSnapshot(rec) {
  return {
    invoice_number: rec?.invoice_number ?? null,
    invoiceNumber: rec?.invoiceNumber ?? null,
    invoice_document_id: rec?.invoice_document_id ?? null,
    document_id: rec?.document_id ?? null,
    payment_status: rec?.payment_status ?? null,
    payment_method: rec?.payment_method ?? null,
    payment_provider: rec?.payment_provider ?? null,
    paid_at: rec?.paid_at ?? null,
    price_incl_vat: rec?.price_incl_vat ?? null,
    price_vat: rec?.price_vat ?? null,
    price_ex_vat: rec?.price_ex_vat ?? null,
    vat_rate_percent: rec?.vat_rate_percent ?? null,
  };
}

function adminRequest() {
  return new Request(
    `https://api.test/bookings/${BOOKING_ID}/invoice/pdf?tenant_id=${TENANT}&company_id=${COMPANY}`,
    { method: "GET", headers: { "x-admin-token": ADMIN_TOKEN } },
  );
}

function adminScope(tenantId = TENANT, companyId = COMPANY) {
  return { hasScope: true, tenant_id: tenantId, company_id: companyId };
}

/**
 * Ensure impl stand-in: rewrites only the derived artifact + projection
 * revision, exactly like the real persist step, and counts invocations.
 */
function makeEnsureSpy({ kv, r2, outcome = "refresh" } = {}) {
  const calls = [];
  return {
    calls,
    impl: async (env, scope, bookingId, rec, opts) => {
      calls.push({ scope, bookingId, reason: opts?.reason ?? null });
      if (outcome === "fail") {
        return { ok: false, skipped: false, reason: "pdf_persist_failed" };
      }
      if (outcome === "throw") {
        throw new Error("forced_ensure_error");
      }
      await r2.put(PDF_KEY, FRESH_PDF_BYTES);
      const latest = await kv.get(`booking:${bookingId}`, { type: "json" });
      latest.invoice_pdf_projection_revision = V2_REVISION;
      latest.invoicePdfProjectionRevision = V2_REVISION;
      latest.invoice_pdf_sha256 = "99ff88ee77dd66cc55bb44aa33221100";
      await kv.put(`booking:${bookingId}`, latest);
      return {
        ok: true,
        skipped: false,
        reason: "persisted",
        key: PDF_KEY,
        projection_revision: V2_REVISION,
        invoice_number: INV_NUMBER,
      };
    },
  };
}

function makeEnv(kv, r2) {
  return { BOOKING_KV: kv, PUBLIC_MEDIA: r2, ADMIN_TOKEN };
}

test("A) pre-v2 artifact is detected stale and refreshed exactly once on open", async () => {
  const booking = buildIssuedBooking(V1_REVISION);
  const before = issuedFactsSnapshot(booking);
  const kv = makeKV({ [`booking:${BOOKING_ID}`]: booking });
  const r2 = makeR2({ [PDF_KEY]: STALE_PDF_BYTES });
  const ensure = makeEnsureSpy({ kv, r2 });

  const req = adminRequest();
  const res = await handleBookingInvoicePdfGet(
    req,
    new URL(req.url),
    makeEnv(kv, r2),
    BOOKING_ID,
    adminScope(),
    { ensureInvoicePdfArtifactImpl: ensure.impl },
  );

  assert.equal(res.status, 200);
  assert.equal(ensure.calls.length, 1, "exactly one derived-artifact refresh");
  assert.equal(ensure.calls[0].reason, "ensure");
  assert.equal(ensure.calls[0].scope.tenant_id, TENANT);
  assert.equal(ensure.calls[0].scope.company_id, COMPANY);

  const served = new Uint8Array(await res.arrayBuffer());
  assert.deepEqual(served, FRESH_PDF_BYTES, "refreshed bytes must be served");
  assert.equal(countPdfPages(served), 1, "short invoice is one page");

  const servedText = new TextDecoder().decode(served);
  assert.match(servedText, /Im-fluxidi-logo/, "embedded logo present");
  assert.doesNotMatch(
    servedText,
    /\d{1,3}\.\d{4,}\s*,\s*\d{1,3}\.\d{4,}/,
    "no raw coordinates",
  );

  // Immutable issued facts unchanged; only derived artifact fields moved.
  const after = await kv.get(`booking:${BOOKING_ID}`, { type: "json" });
  assert.deepEqual(issuedFactsSnapshot(after), before);
  assert.equal(
    readStoredStreetInvoicePdfProjectionRevision(after),
    V2_REVISION,
  );
  assertNoOutboundTraffic();
});

test("B) current v2 artifact is reused without any regeneration", async () => {
  const booking = buildIssuedBooking(V2_REVISION);
  const kv = makeKV({ [`booking:${BOOKING_ID}`]: booking });
  const r2 = makeR2({ [PDF_KEY]: FRESH_PDF_BYTES });
  const ensure = makeEnsureSpy({ kv, r2 });

  const req = adminRequest();
  const res = await handleBookingInvoicePdfGet(
    req,
    new URL(req.url),
    makeEnv(kv, r2),
    BOOKING_ID,
    adminScope(),
    { ensureInvoicePdfArtifactImpl: ensure.impl },
  );

  assert.equal(res.status, 200);
  assert.equal(ensure.calls.length, 0, "no regeneration for a current artifact");
  assert.equal(kv.writes.length, 0, "no booking write for a current artifact");
  assert.equal(r2.writes.length, 0, "no artifact write for a current artifact");
  assert.deepEqual(new Uint8Array(await res.arrayBuffer()), FRESH_PDF_BYTES);
  assertNoOutboundTraffic();
});

test("C) repeated opens are idempotent: refresh happens once, then reuse", async () => {
  const booking = buildIssuedBooking(V1_REVISION);
  const kv = makeKV({ [`booking:${BOOKING_ID}`]: booking });
  const r2 = makeR2({ [PDF_KEY]: STALE_PDF_BYTES });
  const ensure = makeEnsureSpy({ kv, r2 });
  const env = makeEnv(kv, r2);

  for (let i = 0; i < 3; i += 1) {
    const req = adminRequest();
    const res = await handleBookingInvoicePdfGet(
      req,
      new URL(req.url),
      env,
      BOOKING_ID,
      adminScope(),
      { ensureInvoicePdfArtifactImpl: ensure.impl },
    );
    assert.equal(res.status, 200);
    assert.deepEqual(new Uint8Array(await res.arrayBuffer()), FRESH_PDF_BYTES);
  }

  assert.equal(ensure.calls.length, 1, "only the first open refreshes");
  assert.equal(r2.store.size, 1, "no extra artifacts created");
  assertNoOutboundTraffic();
});

test("D) concurrent opens converge on one deterministic artifact key", async () => {
  const booking = buildIssuedBooking(V1_REVISION);
  const kv = makeKV({ [`booking:${BOOKING_ID}`]: booking });
  const r2 = makeR2({ [PDF_KEY]: STALE_PDF_BYTES });
  const ensure = makeEnsureSpy({ kv, r2 });
  const env = makeEnv(kv, r2);

  const responses = await Promise.all(
    [0, 1, 2, 3].map(() => {
      const req = adminRequest();
      return handleBookingInvoicePdfGet(
        req,
        new URL(req.url),
        env,
        BOOKING_ID,
        adminScope(),
        { ensureInvoicePdfArtifactImpl: ensure.impl },
      );
    }),
  );

  for (const res of responses) {
    assert.equal(res.status, 200);
    assert.deepEqual(new Uint8Array(await res.arrayBuffer()), FRESH_PDF_BYTES);
  }
  assert.equal(r2.store.size, 1, "no conflicting artifact keys");
  assert.deepEqual([...r2.store.keys()], [PDF_KEY]);
  // Invoice number is never re-allocated by the read path.
  const after = await kv.get(`booking:${BOOKING_ID}`, { type: "json" });
  assert.equal(after.invoice_number, INV_NUMBER);
  assertNoOutboundTraffic();
});

test("E) refresh failure still serves the existing artifact (no hard error)", async () => {
  for (const outcome of ["fail", "throw"]) {
    const booking = buildIssuedBooking(V1_REVISION);
    const kv = makeKV({ [`booking:${BOOKING_ID}`]: booking });
    const r2 = makeR2({ [PDF_KEY]: STALE_PDF_BYTES });
    const ensure = makeEnsureSpy({ kv, r2, outcome });

    const req = adminRequest();
    const res = await handleBookingInvoicePdfGet(
      req,
      new URL(req.url),
      makeEnv(kv, r2),
      BOOKING_ID,
      adminScope(),
      { ensureInvoicePdfArtifactImpl: ensure.impl },
    );

    assert.equal(res.status, 200, `outcome=${outcome} must not break download`);
    assert.deepEqual(new Uint8Array(await res.arrayBuffer()), STALE_PDF_BYTES);
    assert.equal(ensure.calls.length, 1);
    assert.equal(kv.writes.length, 0, "failed refresh writes nothing");
  }
  assertNoOutboundTraffic();
});

test("F) response exposes an artifact revision that changes with the refresh", async () => {
  const stale = buildIssuedBooking(V1_REVISION);
  const staleKv = makeKV({ [`booking:${BOOKING_ID}`]: stale });
  const staleR2 = makeR2({ [PDF_KEY]: STALE_PDF_BYTES });
  const noRefresh = {
    ensureInvoicePdfArtifactImpl: async () => ({
      ok: true,
      skipped: true,
      reason: "projection_unchanged",
    }),
  };
  const staleReq = adminRequest();
  const staleRes = await handleBookingInvoicePdfGet(
    staleReq,
    new URL(staleReq.url),
    makeEnv(staleKv, staleR2),
    BOOKING_ID,
    adminScope(),
    noRefresh,
  );
  const staleRevision = staleRes.headers.get(
    "x-fluxidi-invoice-artifact-revision",
  );
  assert.match(staleRevision, /^street_pdf_proj_v1\./);
  assert.equal(staleRes.headers.get("etag"), `"${staleRevision}"`);

  const fresh = buildIssuedBooking(V2_REVISION);
  const freshKv = makeKV({ [`booking:${BOOKING_ID}`]: fresh });
  const freshR2 = makeR2({ [PDF_KEY]: FRESH_PDF_BYTES });
  const freshReq = adminRequest();
  const freshRes = await handleBookingInvoicePdfGet(
    freshReq,
    new URL(freshReq.url),
    makeEnv(freshKv, freshR2),
    BOOKING_ID,
    adminScope(),
    noRefresh,
  );
  const freshRevision = freshRes.headers.get(
    "x-fluxidi-invoice-artifact-revision",
  );
  assert.match(
    freshRevision,
    new RegExp(`^${STREET_INVOICE_PDF_PROJECTION_VERSION}\\.`),
  );
  assert.notEqual(freshRevision, staleRevision);
  assert.match(
    freshRes.headers.get("access-control-expose-headers") || "",
    /X-Fluxidi-Invoice-Artifact-Revision/,
  );
  assert.equal(
    freshRes.headers.get("cache-control"),
    "private, no-store, max-age=0",
  );
  assertNoOutboundTraffic();
});

test("G) foreign tenant scope is rejected and never triggers a refresh", async () => {
  const booking = buildIssuedBooking(V1_REVISION);
  const kv = makeKV({ [`booking:${BOOKING_ID}`]: booking });
  const r2 = makeR2({ [PDF_KEY]: STALE_PDF_BYTES });
  const ensure = makeEnsureSpy({ kv, r2 });

  const req = adminRequest();
  const res = await handleBookingInvoicePdfGet(
    req,
    new URL(req.url),
    makeEnv(kv, r2),
    BOOKING_ID,
    adminScope(OTHER_TENANT, COMPANY),
    { ensureInvoicePdfArtifactImpl: ensure.impl },
  );

  assert.equal(res.status, 403);
  assert.equal(ensure.calls.length, 0, "authorization precedes any refresh");
  assert.equal(r2.reads.length, 0);
  assert.equal(kv.writes.length, 0);

  // Unauthenticated callers likewise get nothing and trigger nothing.
  const anonReq = new Request(
    `https://api.test/bookings/${BOOKING_ID}/invoice/pdf`,
    { method: "GET" },
  );
  const anonRes = await handleBookingInvoicePdfGet(
    anonReq,
    new URL(anonReq.url),
    makeEnv(kv, r2),
    BOOKING_ID,
    null,
    { ensureInvoicePdfArtifactImpl: ensure.impl },
  );
  assert.equal(anonRes.status, 403);
  assert.equal(ensure.calls.length, 0);
  assertNoOutboundTraffic();
});

test("H) only the requested invoice is refreshed — no bulk regeneration", async () => {
  const sibling = "street_stale_pdf_002";
  const siblingKey = `private-artifacts/tenant/${TENANT}/company/${COMPANY}/bookings/${sibling}/invoices/INV-TEST-STALE-000038.pdf`;
  const siblingRec = {
    ...buildIssuedBooking(V1_REVISION),
    booking_id: sibling,
    bookingId: sibling,
    invoice_number: "INV-TEST-STALE-000038",
    invoice_pdf_key: siblingKey,
  };
  const kv = makeKV({
    [`booking:${BOOKING_ID}`]: buildIssuedBooking(V1_REVISION),
    [`booking:${sibling}`]: siblingRec,
  });
  const r2 = makeR2({
    [PDF_KEY]: STALE_PDF_BYTES,
    [siblingKey]: STALE_PDF_BYTES,
  });
  const ensure = makeEnsureSpy({ kv, r2 });

  const req = adminRequest();
  const res = await handleBookingInvoicePdfGet(
    req,
    new URL(req.url),
    makeEnv(kv, r2),
    BOOKING_ID,
    adminScope(),
    { ensureInvoicePdfArtifactImpl: ensure.impl },
  );
  assert.equal(res.status, 200);

  assert.equal(ensure.calls.length, 1);
  assert.equal(ensure.calls[0].bookingId, BOOKING_ID);
  assert.deepEqual(kv.writes, [`booking:${BOOKING_ID}`]);
  assert.deepEqual(r2.writes, [PDF_KEY]);

  const untouched = await kv.get(`booking:${sibling}`, { type: "json" });
  assert.equal(
    readStoredStreetInvoicePdfProjectionRevision(untouched),
    V1_REVISION,
    "sibling historical invoice must stay untouched",
  );
  assert.deepEqual(r2.store.get(siblingKey), STALE_PDF_BYTES);
  assertNoOutboundTraffic();
});

test("I) missing artifact is regenerated instead of returning 404", async () => {
  const booking = buildIssuedBooking("");
  delete booking.invoice_pdf_key;
  delete booking.invoicePdfKey;
  delete booking.booking.invoice_pdf_key;
  const kv = makeKV({ [`booking:${BOOKING_ID}`]: booking });
  const r2 = makeR2();
  const ensure = {
    calls: 0,
    impl: async (env, scope, bookingId) => {
      ensure.calls += 1;
      await r2.put(PDF_KEY, FRESH_PDF_BYTES);
      const latest = await kv.get(`booking:${bookingId}`, { type: "json" });
      latest.invoice_pdf_key = PDF_KEY;
      latest.invoice_pdf_projection_revision = V2_REVISION;
      await kv.put(`booking:${bookingId}`, latest);
      return { ok: true, skipped: false, reason: "persisted", key: PDF_KEY };
    },
  };

  const req = adminRequest();
  const res = await handleBookingInvoicePdfGet(
    req,
    new URL(req.url),
    makeEnv(kv, r2),
    BOOKING_ID,
    adminScope(),
    { ensureInvoicePdfArtifactImpl: ensure.impl },
  );

  assert.equal(res.status, 200);
  assert.equal(ensure.calls, 1);
  assert.deepEqual(new Uint8Array(await res.arrayBuffer()), FRESH_PDF_BYTES);
  assertNoOutboundTraffic();
});
