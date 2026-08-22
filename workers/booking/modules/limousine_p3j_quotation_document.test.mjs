// LIMOUSINE-QUOTE-DOCUMENT-P3J — quotation HTML, PDF routes, R2, auth.
// Run: node --test workers/booking/modules/limousine_p3j_quotation_document.test.mjs
// Never calls real PDFShift, Billit, Peppol, or payment providers.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import worker from "../fluxidi_booking_worker.js";
import {
  LIMOUSINE_QUOTATION_STATUS_REF_HEADER,
  buildLimousineQuotationArtifactKey,
  renderLimousineQuotationHtml,
} from "./limousine_quotation_document.mjs";
import { buildLimousineQuotationSnapshot } from "./limousine_quotation_snapshot.mjs";
import { sealLimousineStatusRef } from "./limousine_status_token.mjs";
import { unsealLimousineAcceptance } from "./limousine_acceptance_token.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ADMIN = "test-admin-token";
const TENANT = "fluxidi_limo_p3j";
const COMPANY = "company_limo_p3j";
const OTHER_TENANT = "fluxidi_other_p3j";
const OTHER_COMPANY = "company_other_p3j";
const SECRET = "p3j-acceptance-secret-not-production";
const FAKE_PDF = new TextEncoder().encode("%PDF-1.4\n1 0 obj<<>>endobj\n%%EOF\n");

const TERMS = {
  terms_revision: 3,
  cancellation_deadline_hours: 24,
  cancellation_penalty_percent: 50,
  waiting_time_included_minutes: 15,
  waiting_time_overage_cents_per_minute: 100,
  no_show_penalty_percent: 100,
  overtime_cents_per_hour: 9000,
  mobilisation_disclosure: { en: "Mobilisation included", nl: "Inbegrepen" },
  customer_obligations: {
    nl: "Klaarstaan\nlijn 2",
    en: "Be ready\nline 2",
    fr: "Être prêt",
    es: "Estar listo",
  },
  important_information: {
    nl: "Niet roken. <script>alert(1)</script> & \"quotes\" " + "WORD".repeat(80),
    en: "No smoking. <script>alert(1)</script> & \"quotes\" " + "WORD".repeat(80),
    fr: "Ne pas fumer. <script>alert(1)</script> & \"quotes\" " + "WORD".repeat(80),
    es: "No fumar. <script>alert(1)</script> & \"quotes\" " + "WORD".repeat(80),
  },
};

const TERMS_V4 = { ...TERMS, terms_revision: 4 };

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
  const companyHash = await sha256Hex("co-p3j");
  const otherHash = await sha256Hex("co-other");
  const customerHash = await sha256Hex("cus-p3j");
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
      customer_id: "cust_p3j",
      phone_hash: "phonehash_p3j",
      expires_at: expires,
    },
  };
}

function quoteRecord({ id, state = "requested", extras = {} } = {}) {
  const now = new Date().toISOString();
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
      vehicle_id: "veh_limo_p3j",
      journey_type: "point_to_point",
      from: "Gent",
      to: "Brussel",
      stops: ["Aalst"],
      scheduled_pickup_iso: new Date(Date.now() + 2 * 3600_000).toISOString(),
      pax: 2,
      bags: 1,
      occasion: "wedding",
      locale: "nl",
      customer_note: "Gate 2",
      service_type: "limousine",
      pricing_mode: "quote_required",
      vehicle_snapshot: {
        vehicle_id: "veh_limo_p3j",
        public_name: "Executive sedan",
        service_class_id: "executive_sedan",
      },
    },
    status_access: {
      customer_fingerprint: "limcf_p3j_owner",
      issued_at: now,
      expires_at: new Date(Date.now() + 30 * 24 * 3600_000).toISOString(),
      created_revision: 1,
    },
    ...extras,
  };
}

function jsonReq(path, { method = "POST", token = null, admin = false, body = null, query = "", headers = {} } = {}) {
  const next = { "content-type": "application/json", ...headers };
  if (token) next.authorization = `Bearer ${token}`;
  if (admin) next["x-admin-token"] = ADMIN;
  return new Request(`https://booking.internal${path}${query}`, {
    method,
    headers: next,
    body: body == null ? undefined : JSON.stringify(body),
  });
}

function envOf(kv, extra = {}) {
  const fetchCalls = extra.fetchCalls || [];
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    LIMOUSINE_QUOTE_ENABLED: "1",
    LIMOUSINE_MANUAL_QUOTE_ENABLED: "1",
    LIMOUSINE_BOOK_ENABLED: "1",
    LIMOUSINE_TEST_COMPANY_ALLOWLIST: `${COMPANY},${OTHER_COMPANY}`,
    LIMOUSINE_ACCEPTANCE_SECRET: SECRET,
    fetch: async (input) => {
      fetchCalls.push(String(input?.url || input));
      throw new Error(`blocked outbound ${input?.url || input}`);
    },
    fetchCalls,
    ...extra,
  };
}

async function setup({ quotes = [], renderPdf, failRender = false } = {}) {
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
  const renderer = renderPdf || (async (html) => {
    htmls.push(html);
    if (failRender) throw new Error("pdfshift_unavailable");
    return FAKE_PDF;
  });
  renderer.htmls = htmls;
  const fetchCalls = [];
  const env = envOf(kv, {
    PUBLIC_MEDIA: r2,
    LIMOUSINE_QUOTATION_RENDER_PDF: renderer,
    fetchCalls,
  });
  return { env, kv, r2, renderer, fetchCalls };
}

async function sendQuote(env, id, { expectedRevision = 1, terms = TERMS, total = 18500, extra = {} } = {}) {
  return worker.fetch(
    jsonReq("/admin/limousine/quote-requests/respond", {
      token: "co-p3j",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        quote_request_id: id,
        action: "quote",
        expected_revision: expectedRevision,
        total_incl_vat_cents: total,
        currency: "EUR",
        vat_rate: 0.06,
        terms,
        public_text: {
          nl: "Vaste prijs",
          en: "Fixed price",
          fr: "Prix fixe",
          es: "Precio fijo",
        },
        ...extra,
      },
    }),
    env,
    {},
  );
}

async function partnerPdf(env, id, { revision, token = "co-p3j", tenant = TENANT, company = COMPANY, admin = false } = {}) {
  const params = new URLSearchParams({ tenant_id: tenant, company_id: company });
  if (revision != null) params.set("revision", String(revision));
  return worker.fetch(
    jsonReq(`/admin/limousine/quote-requests/${id}/quotation.pdf`, {
      method: "GET",
      token: admin ? null : token,
      admin,
      query: `?${params}`,
    }),
    env,
    {},
  );
}

async function customerPdf(env, id, { revision, statusRef, query = "" } = {}) {
  const params = new URLSearchParams();
  if (revision != null) params.set("revision", String(revision));
  const extra = query ? `&${query.replace(/^\?/, "")}` : "";
  const qs = params.toString() ? `?${params}${extra}` : extra ? `?${extra.replace(/^&/, "")}` : "";
  const headers = {};
  if (statusRef) headers[LIMOUSINE_QUOTATION_STATUS_REF_HEADER] = statusRef;
  return worker.fetch(
    jsonReq(`/limousine/quote-requests/${id}/quotation.pdf`, {
      method: "GET",
      query: qs,
      headers,
    }),
    env,
    {},
  );
}

async function statusRefFor(record, overrides = {}) {
  return sealLimousineStatusRef({
    secret: SECRET,
    binding: {
      purpose: "customer_status",
      tenant_id: record.tenant_id,
      company_id: record.company_id,
      quote_request_id: record.quote_request_id,
      customer_fingerprint: record.status_access.customer_fingerprint,
      created_revision: record.status_access.created_revision,
      ...overrides,
    },
    issuedAtIso: new Date().toISOString(),
    ttlMinutes: 60,
  });
}

async function snapshotInput(locale = "nl") {
  return buildLimousineQuotationSnapshot({
    quoteRequestId: "limq_html",
    quoteRevision: 3,
    termsRevision: 3,
    issuedAt: "2026-08-22T08:00:00Z",
    expiresAt: "2026-08-24T08:00:00Z",
    locale,
    sellerSnapshot: {
      legal_name: "Coachline BV",
      vat_number: "BE0772931038",
      address_line: "Markt 1",
      city: "Gent",
    },
    requestSnapshot: {
      journey_type: "point_to_point",
      from: "Gent",
      to: "Brussel",
      stops: ["Aalst"],
      scheduled_pickup_iso: "2026-09-01T10:00:00Z",
      pax: 2,
      bags: 1,
    },
    vehicleSnapshot: { public_name: "Executive sedan" },
    offerSnapshot: {
      total_incl_vat_cents: 18500,
      currency: "EUR",
      vat_rate: 0.06,
      vat_treatment: "incl",
      public_text: {
        nl: "Vaste prijs",
        en: "Fixed price",
        fr: "Prix fixe",
        es: "Precio fijo",
      },
      terms: TERMS,
      terms_revision: 3,
    },
  });
}

function assertNoInvoiceDocumentWording(html) {
  const lower = html.toLowerCase();
  assert.ok(!lower.includes("factuurnummer"));
  assert.ok(!lower.includes("invoice number"));
  assert.ok(!lower.includes("due date"));
  assert.ok(!lower.includes("vervaldatum"));
  assert.ok(!lower.includes("payment status"));
  assert.ok(!html.includes("INV-"));
  assert.ok(!html.includes("source_booking_id"));
}

test("27-34) HTML renderer localizes, escapes, and never paints invoice state", async () => {
  const expected = {
    nl: { title: "Offerte", disclaimer: "geen factuur" },
    en: { title: "Quotation", disclaimer: "not an invoice" },
    fr: { title: "Devis", disclaimer: "pas une facture" },
    es: { title: "Presupuesto", disclaimer: "no es una factura" },
  };
  for (const locale of ["nl", "en", "fr", "es"]) {
    const snap = await snapshotInput(locale);
    snap.offer_snapshot.public_text[locale] = `<script>x</script> & "quotes" ${locale}`;
    const html = renderLimousineQuotationHtml(snap);
    assert.ok(html.includes(expected[locale].title), locale);
    assert.ok(html.toLowerCase().includes(expected[locale].disclaimer), locale);
    assert.ok(html.includes("@page"));
    assert.ok(html.includes("size: A4"));
    assert.ok(html.includes("limq_html"));
    assert.ok(html.includes("Coachline BV"));
    assert.ok(html.includes("Executive sedan"));
    assert.ok(!html.includes("<script>x</script>"));
    assert.ok(html.includes("&lt;script&gt;"));
    assert.ok(html.includes("&amp;"));
    assert.ok(html.includes("WORDWORDWORD"));
    assert.ok(html.includes("&quot;quotes&quot;") || html.includes("&#039;") || html.includes("&quot;"));
    assertNoInvoiceDocumentWording(html);
  }
});

test("document module reuses pdf_render and never imports Document Core/Billit/Peppol", () => {
  const src = readFileSync(join(__dirname, "limousine_quotation_document.mjs"), "utf8");
  assert.ok(src.includes('from "./pdf_render.mjs"'));
  assert.ok(!src.includes("document_core"));
  assert.ok(!/from ["'].*billit/i.test(src));
  assert.ok(!/from ["'].*peppol/i.test(src));
  assert.ok(!src.includes("DOCUMENT_REFERENCE_SEQUENCE"));
  assert.ok(!src.includes("source_booking_id"));
  assert.ok(!src.includes("invoice_pdf_customer_access"));
  const pdfRender = readFileSync(join(__dirname, "pdf_render.mjs"), "utf8");
  assert.ok(pdfRender.includes("api.pdfshift.io"));
  const workerSrc = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  assert.equal(
    workerSrc.includes("https://api.pdfshift.io/v3/convert/pdf"),
    false,
    "worker must not keep a second PDFShift client",
  );
});

test("1-18, 35-37) partner/customer PDF auth, R2, headers, and immutability", async () => {
  const originalFetch = globalThis.fetch;
  const outbound = [];
  globalThis.fetch = async (input) => {
    outbound.push(String(input?.url || input));
    throw new Error(`blocked outbound ${input?.url || input}`);
  };
  try {
    const requested = quoteRecord({ id: "limq_p3j_pdf" });
    const { env, kv, r2, renderer, fetchCalls } = await setup({ quotes: [requested] });
    const unauth = await partnerPdf(env, "limq_p3j_pdf", { token: null });
    assert.notEqual(unauth.status, 200);

    const quotedRes = await sendQuote(env, "limq_p3j_pdf");
    const quoted = await quotedRes.json();
    assert.equal(quotedRes.status, 200, JSON.stringify(quoted));
    assert.equal(quoted.quote_request.quotation_available, true);
    const revision = quoted.quote_request.quotation_revision;
    assert.ok(revision >= 1);
    const stored = await kv.get("limousine_quote_record:limq_p3j_pdf", { type: "json" });
    assert.ok(stored.quotation_snapshots[String(revision)]);
    assert.equal(stored.quotation_snapshots[String(revision)].seller_snapshot.legal_name, "Coachline BV");
    const hash = stored.quotation_snapshots[String(revision)].content_hash;

    const ok = await partnerPdf(env, "limq_p3j_pdf", { revision });
    assert.equal(ok.status, 200);
    assert.equal(ok.headers.get("content-type"), "application/pdf");
    assert.match(ok.headers.get("cache-control") || "", /private/);
    assert.match(ok.headers.get("cache-control") || "", /no-store/);
    const disposition = ok.headers.get("content-disposition") || "";
    assert.match(disposition, /inline/);
    assert.match(disposition, /quotation-limq_p3j_pdf-r\d+\.pdf/);
    assert.ok(!disposition.toLowerCase().includes("status_ref"));
    assert.ok(!disposition.toLowerCase().includes("@"));
    const firstBytes = new Uint8Array(await ok.arrayBuffer());
    assert.deepEqual(firstBytes, FAKE_PDF);
    assert.equal(renderer.htmls.length, 1);
    assert.ok(renderer.htmls[0].includes("Offerte") || renderer.htmls[0].includes("Quotation"));
    assertNoInvoiceDocumentWording(renderer.htmls[0]);
    assert.equal(r2.writes.length, 1);
    const key = r2.writes[0];
    assert.ok(key.startsWith("private-artifacts/"));
    assert.ok(key.includes(`/limousine-quotes/`));
    assert.ok(key.includes(`quotation-v2-${hash}.pdf`));
    assert.ok(!key.includes("limqs1"));
    assert.ok(!key.includes("status_ref"));
    assert.ok(!key.includes("Ada"));
    assert.ok(!key.includes("@"));
    assert.ok(!key.includes("Gent"));
    assert.equal(
      key,
      buildLimousineQuotationArtifactKey({
        tenantId: TENANT,
        companyId: COMPANY,
        quoteRequestId: "limq_p3j_pdf",
        revision,
        contentHash: hash,
        rendererVersion: stored.quotation_snapshots[String(revision)].renderer_version,
      }),
    );

    env.BOOKING_KV.store.set(`tenant:${TENANT}:company:${COMPANY}:business_profile:v1`, {
      business_profile: { legal_name: "Mutated BV", trading_name: "Mutated" },
    });
    stored.request.vehicle_snapshot.public_name = "Renamed limousine";
    await kv.put("limousine_quote_record:limq_p3j_pdf", JSON.stringify(stored));

    const second = await partnerPdf(env, "limq_p3j_pdf", { revision });
    assert.equal(second.status, 200);
    assert.equal(renderer.htmls.length, 1);
    const secondBytes = new Uint8Array(await second.arrayBuffer());
    assert.deepEqual(secondBytes, firstBytes);

    const crossCompany = await partnerPdf(env, "limq_p3j_pdf", {
      token: "co-other",
      tenant: OTHER_TENANT,
      company: OTHER_COMPANY,
      revision,
    });
    assert.equal(crossCompany.status, 404);
    const crossScope = await partnerPdf(env, "limq_p3j_pdf", {
      token: "co-other",
      tenant: TENANT,
      company: COMPANY,
      revision,
    });
    assert.equal(crossScope.status, 403);

    const missingRev = await partnerPdf(env, "limq_p3j_pdf", { revision: 99 });
    assert.equal(missingRev.status, 404);

    const sealed = await statusRefFor(stored);
    const bare = await customerPdf(env, "limq_p3j_pdf", { revision });
    assert.equal(bare.status, 404);
    const queryOnly = await customerPdf(env, "limq_p3j_pdf", {
      revision,
      query: `status_ref=${encodeURIComponent(sealed.reference)}`,
    });
    assert.equal(queryOnly.status, 404);
    const otherQuote = await statusRefFor(stored, { quote_request_id: "limq_other" });
    const wrongQuote = await customerPdf(env, "limq_p3j_pdf", {
      revision,
      statusRef: otherQuote.reference,
    });
    assert.equal(wrongQuote.status, 404);
    const wrongFp = await statusRefFor(stored, { customer_fingerprint: "limcf_other" });
    const wrongOwner = await customerPdf(env, "limq_p3j_pdf", {
      revision,
      statusRef: wrongFp.reference,
    });
    assert.equal(wrongOwner.status, 404);
    const customerOk = await customerPdf(env, "limq_p3j_pdf", {
      revision,
      statusRef: sealed.reference,
    });
    assert.equal(customerOk.status, 200);
    assert.equal(customerOk.headers.get("content-type"), "application/pdf");
    assert.equal(renderer.htmls.length, 1);

    const accept = await worker.fetch(
      jsonReq("/limousine/quote-requests/accept", {
        token: "cus-p3j",
        body: { quote_request_id: "limq_p3j_pdf", expected_revision: stored.revision },
      }),
      env,
      {},
    );
    const accepted = await accept.json();
    assert.equal(accept.status, 200, JSON.stringify(accepted));
    const opened = await unsealLimousineAcceptance({
      secret: SECRET,
      reference: accepted.acceptance_reference,
    });
    assert.equal(opened.ok, true);
    assert.equal(opened.binding.total_incl_vat_cents, stored.quotation_snapshots[String(revision)].totals_snapshot.total_incl_vat_cents);
    assert.equal(opened.binding.quotation_content_hash, hash);
    assert.equal(opened.binding.quotation_revision, revision);

    const afterAccept = await customerPdf(env, "limq_p3j_pdf", {
      revision,
      statusRef: sealed.reference,
    });
    assert.equal(afterAccept.status, 200);
    assert.deepEqual(new Uint8Array(await afterAccept.arrayBuffer()), firstBytes);
    assert.equal(renderer.htmls.length, 1);

    assert.equal(outbound.length, 0);
    assert.equal(fetchCalls.length, 0);
    assert.equal(r2.writes.length, 1);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("11, 19) legacy quotes have no PDF; renderer failure leaves quote state intact", async () => {
  const legacy = quoteRecord({
    id: "limq_p3j_legacy",
    state: "customer_acceptance_required",
    extras: {
      revision: 3,
      quote: {
        total_incl_vat_cents: 18500,
        currency: "EUR",
        vat_rate: 0.06,
        vat_treatment: "incl",
        terms: TERMS,
        terms_revision: 3,
        expires_at: new Date(Date.now() + 48 * 3600_000).toISOString(),
      },
    },
  });
  const { env } = await setup({ quotes: [legacy] });
  const missing = await partnerPdf(env, "limq_p3j_legacy", { revision: 3 });
  assert.equal(missing.status, 404);
  const body = await missing.json();
  assert.equal(body.ok, false);

  const live = quoteRecord({ id: "limq_p3j_fail" });
  const failing = await setup({ quotes: [live], failRender: true });
  const quotedRes = await sendQuote(failing.env, "limq_p3j_fail");
  assert.equal(quotedRes.status, 200);
  const before = await failing.kv.get("limousine_quote_record:limq_p3j_fail", { type: "json" });
  const failPdf = await partnerPdf(failing.env, "limq_p3j_fail", {
    revision: before.quotation_revision,
  });
  assert.equal(failPdf.status, 503);
  const after = await failing.kv.get("limousine_quote_record:limq_p3j_fail", { type: "json" });
  assert.equal(after.state, before.state);
  assert.equal(after.revision, before.revision);
  assert.equal(after.quotation_snapshots[String(before.quotation_revision)].content_hash, before.quotation_snapshots[String(before.quotation_revision)].content_hash);
  assert.equal(failing.r2.writes.length, 0);
});

test("quote-send write creates the snapshot; decline/viewed/withdraw do not; requote appends", async () => {
  const { env, kv } = await setup({
    quotes: [
      quoteRecord({ id: "limq_p3j_send" }),
      quoteRecord({ id: "limq_p3j_view" }),
      quoteRecord({ id: "limq_p3j_decline" }),
    ],
  });
  const quotedRes = await sendQuote(env, "limq_p3j_send");
  const quoted = await quotedRes.json();
  assert.equal(quotedRes.status, 200, JSON.stringify(quoted));
  const sent = await kv.get("limousine_quote_record:limq_p3j_send", { type: "json" });
  assert.ok(sent.quotation_snapshots[String(sent.quotation_revision)]);
  const firstHash = sent.quotation_snapshots[String(sent.quotation_revision)].content_hash;

  const requote = await sendQuote(env, "limq_p3j_send", {
    expectedRevision: sent.revision,
    terms: TERMS_V4,
    total: 22000,
  });
  assert.equal(requote.status, 200, JSON.stringify(await requote.clone().json()));
  const after = await kv.get("limousine_quote_record:limq_p3j_send", { type: "json" });
  assert.equal(after.quotation_snapshots[String(sent.quotation_revision)].content_hash, firstHash);
  assert.ok(after.quotation_snapshots[String(after.quotation_revision)]);
  assert.notEqual(after.quotation_revision, sent.quotation_revision);
  assert.equal(after.quotation_snapshots[String(after.quotation_revision)].totals_snapshot.total_incl_vat_cents, 22000);

  const viewed = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests/respond", {
      token: "co-p3j",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        quote_request_id: "limq_p3j_view",
        action: "viewed",
        expected_revision: 1,
      },
    }),
    env,
    {},
  );
  assert.equal(viewed.status, 200);
  const viewedRec = await kv.get("limousine_quote_record:limq_p3j_view", { type: "json" });
  assert.equal(viewedRec.quotation_snapshots, undefined);

  const declined = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests/respond", {
      token: "co-p3j",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        quote_request_id: "limq_p3j_decline",
        action: "decline",
        expected_revision: 1,
        reason_code: "company_declined",
      },
    }),
    env,
    {},
  );
  assert.equal(declined.status, 200);
  const declinedRec = await kv.get("limousine_quote_record:limq_p3j_decline", { type: "json" });
  assert.equal(declinedRec.quotation_snapshots, undefined);

  const unknown = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests/respond", {
      token: "co-p3j",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        quote_request_id: "limq_p3j_send",
        action: "withdraw",
        expected_revision: after.revision,
      },
    }),
    env,
    {},
  );
  const unknownBody = await unknown.json();
  assert.notEqual(unknown.status, 500);
  assert.notEqual(unknownBody.action, "customer_reject");
});

test("legacy re-quote creates only the new revision snapshot", async () => {
  const legacy = quoteRecord({
    id: "limq_p3j_legacy_requote",
    state: "customer_acceptance_required",
    extras: {
      revision: 3,
      quote: {
        total_incl_vat_cents: 18500,
        currency: "EUR",
        vat_rate: 0.06,
        vat_treatment: "incl",
        terms: TERMS,
        terms_revision: 3,
        expires_at: new Date(Date.now() + 48 * 3600_000).toISOString(),
        quoted_at: new Date().toISOString(),
      },
    },
  });
  const { env, kv } = await setup({ quotes: [legacy] });
  const requote = await sendQuote(env, "limq_p3j_legacy_requote", {
    expectedRevision: 3,
    terms: TERMS_V4,
    total: 19900,
  });
  assert.equal(requote.status, 200, JSON.stringify(await requote.clone().json()));
  const rec = await kv.get("limousine_quote_record:limq_p3j_legacy_requote", { type: "json" });
  const keys = Object.keys(rec.quotation_snapshots || {});
  assert.equal(keys.length, 1);
  assert.equal(keys[0], String(rec.quotation_revision));
  assert.equal(rec.quotation_snapshots[keys[0]].totals_snapshot.total_incl_vat_cents, 19900);
});

test("historical PDF remains after expire/decline/withdraw mutations and never rewrites bytes", async () => {
  const { env, kv, r2, renderer } = await setup({ quotes: [quoteRecord({ id: "limq_p3j_hist" })] });
  const quotedRes = await sendQuote(env, "limq_p3j_hist");
  const quoted = await quotedRes.json();
  const revision = quoted.quote_request.quotation_revision;
  const first = await partnerPdf(env, "limq_p3j_hist", { revision });
  assert.equal(first.status, 200);
  const firstBytes = new Uint8Array(await first.arrayBuffer());
  for (const state of ["expired", "declined", "withdrawn"]) {
    const rec = await kv.get("limousine_quote_record:limq_p3j_hist", { type: "json" });
    rec.state = state;
    await kv.put("limousine_quote_record:limq_p3j_hist", JSON.stringify(rec));
    const again = await partnerPdf(env, "limq_p3j_hist", { revision });
    assert.equal(again.status, 200, state);
    assert.deepEqual(new Uint8Array(await again.arrayBuffer()), firstBytes);
  }
  assert.equal(renderer.htmls.length, 1);
  assert.equal(r2.writes.length, 1);
});

test("20-26) quotation PDF routes never issue invoices, numbers, Billit, Peppol, or credits", () => {
  const workerSrc = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  const partnerStart = workerSrc.indexOf("LIMOUSINE-QUOTE-DOCUMENT-P3J — partner quotation PDF");
  const customerStart = workerSrc.indexOf("LIMOUSINE-QUOTE-DOCUMENT-P3J — customer quotation PDF");
  const nearby = workerSrc.indexOf('url.pathname === "/partners/nearby"');
  assert.ok(partnerStart > 0 && customerStart > partnerStart && nearby > customerStart);
  const slice = workerSrc.slice(partnerStart, nearby);
  for (const forbidden of [
    "buildIssuedDocumentRegistryRecord",
    "_issueInvoiceCore",
    "DOCUMENT_REFERENCE_SEQUENCE",
    "allocateScopedInvoiceSequence",
    "source_booking_id",
    "handleBookingInvoicePdfGet",
    "createBillit",
    "billit",
    "peppol",
    "pdf_credits",
    "consumeInvoicePdf",
    "INV-",
    "FLX-",
    "FCN-",
    "FRP-",
  ]) {
    assert.ok(!slice.toLowerCase().includes(forbidden.toLowerCase()) || forbidden === "INV-" || forbidden === "FLX-" || forbidden === "FCN-" || forbidden === "FRP-", forbidden);
    if (["INV-", "FLX-", "FCN-", "FRP-"].includes(forbidden)) {
      assert.ok(!slice.includes(forbidden), forbidden);
    }
  }
  assert.ok(slice.includes("_requireAdminOrCompanySessionForExplicitScope"));
  assert.ok(slice.includes("_authorizeLimousineCustomerQuotationPdf"));
  assert.ok(workerSrc.includes("_readLimousineStatusRefHeader"));
  assert.ok(!slice.includes("searchParams.get(\"status_ref\")"));
  const headerSrc = readFileSync(join(__dirname, "limousine_quotation_document.mjs"), "utf8");
  assert.ok(headerSrc.includes("X-Fluxidi-Status-Ref"));
});
