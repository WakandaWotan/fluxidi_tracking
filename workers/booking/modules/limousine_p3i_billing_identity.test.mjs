// LIMOUSINE-P3I-PHASE-4 — prove the existing Worker already accepts the
// canonical `billing_customer` fragment and reuses Document Core / Billit /
// Peppol. No Worker code is changed here.
//
// Run: node --test workers/booking/modules/limousine_p3i_billing_identity.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import { safeStr } from "./parsing_utils.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const streetInvoice = readFileSync(join(__dirname, "street_business_invoice.js"), "utf8");
const consumerSale = readFileSync(join(__dirname, "consumer_billit_sale.mjs"), "utf8");
const invoiceServiceLine = readFileSync(join(__dirname, "invoice_service_line.mjs"), "utf8");
const sellerIdentity = readFileSync(join(__dirname, "seller_identity.js"), "utf8");

function loadNormalizeBillingCustomerIdentityInput() {
  const start = worker.indexOf("function normalizeBillingCustomerIdentityInput(input)");
  const end = worker.indexOf("\nfunction buildBillingCustomerIdentityReadiness", start);
  assert.ok(start > 0 && end > start, "normalizer must still exist as a pure helper");
  const fnSrc = worker.slice(start, end);
  function normalizeVatNumber(v) {
    let s = String(v || "").trim().toUpperCase();
    if (!s) return "";
    s = s.replace(/[.\s]/g, "");
    if (/^\d{9,12}$/.test(s)) s = "BE" + s;
    return s;
  }
  return new Function(
    "safeStr",
    "normalizeVatNumber",
    `${fnSrc}\nreturn normalizeBillingCustomerIdentityInput;`,
  )(safeStr, normalizeVatNumber);
}

const canonicalBuyerFragment = {
  customer_type: "business",
  display_name: "Acme Events BVBA",
  contact_email: "ada@example.com",
  contact_phone: "+32470000000",
  legal_name: "Acme Events BVBA",
  vat_number: "BE0123456789",
  company_registration_number: null,
  billing_address: {
    street: "Meir 1",
    postal_code: "2000",
    city: "Antwerpen",
    country: "be",
  },
  peppol: { endpoint_id: null, scheme: null },
};

test("1) /book still normalizes billing_customer and derives intent/snapshot", () => {
  const handleIdx = worker.indexOf("async function handleBooking");
  const normalizeIdx = worker.indexOf(
    "normalizeBillingCustomerIdentityInput(payload)",
    handleIdx,
  );
  const snapshotIdx = worker.indexOf("billingCustomerSnapshotForBooking", normalizeIdx);
  const intentIdx = worker.indexOf(
    'const invoice_intent = business_detected ? "business_invoice" : "none"',
    snapshotIdx,
  );
  assert.ok(handleIdx > 0);
  assert.ok(normalizeIdx > handleIdx, "handleBooking must call the normalizer");
  assert.ok(snapshotIdx > normalizeIdx, "snapshot is derived from the normalizer");
  assert.ok(intentIdx > snapshotIdx, "invoice_intent is derived server-side");
  assert.ok(worker.includes("_billingCustomerImpliesBusinessInvoice"));
  assert.ok(worker.includes("billing_customer_snapshot"));
  assert.ok(!worker.includes("/limousine/invoice"));
  assert.ok(!worker.includes("/limousine/billit"));
  assert.ok(!worker.includes("/limousine/peppol"));
});

test("2) canonical billing_customer fragment normalizes into a buyer snapshot", () => {
  const normalize = loadNormalizeBillingCustomerIdentityInput();
  const out = normalize({
    billing_customer: canonicalBuyerFragment,
    customer: { name: "Ada", email: "ada@example.com", phone: "+32470000000" },
    name: "Ada",
  });
  assert.equal(out.customer_type, "business");
  assert.equal(out.legal_name, "Acme Events BVBA");
  assert.equal(out.vat_number, "BE0123456789");
  assert.equal(out.billing_address.street, "Meir 1");
  assert.equal(out.billing_address.postal_code, "2000");
  assert.equal(out.billing_address.city, "Antwerpen");
  assert.equal(out.billing_address.country, "BE");
  assert.equal(out.contact_email, "ada@example.com");
  assert.equal(out.source.legal_identity, "billing_customer");
  assert.equal(out.source.billing_address, "billing_customer");
  assert.equal(out.display_name, "Acme Events BVBA");
});

test("3) passenger name is never synthesized into a legal buyer identity", () => {
  const normalize = loadNormalizeBillingCustomerIdentityInput();
  const out = normalize({
    customer: { name: "Ada Passenger", email: "ada@example.com" },
    name: "Ada Passenger",
  });
  assert.equal(out.legal_name, null);
  assert.equal(out.vat_number, null);
  assert.equal(out.company_registration_number, null);
  assert.equal(out.customer_type, null);
  assert.equal(out.display_name, "Ada Passenger");
  assert.equal(out.source.legal_identity, null);
  assert.equal(out.source.display_name, "payload_customer_fallback");
});

test("4) seller identity stays on the bound company profile, never the buyer", () => {
  const issueIdx = worker.indexOf("async function _issueInvoiceCore");
  const sellerIdx = worker.indexOf(
    "resolveSellerSnapshotForNewInvoiceIssue",
    issueIdx,
  );
  assert.ok(issueIdx > 0);
  assert.ok(sellerIdx > issueIdx, "_issueInvoiceCore still resolves the seller server-side");
  assert.ok(worker.includes("function resolveSellerSnapshotForNewInvoiceIssue"));
  assert.ok(worker.includes("buildSellerSnapshotFromBusinessProfile"));
  assert.ok(sellerIdentity.includes("export function resolveCanonicalSellerIdentity"));
  const normalize = loadNormalizeBillingCustomerIdentityInput();
  const buyer = normalize({ billing_customer: canonicalBuyerFragment });
  assert.equal(buyer.legal_name, "Acme Events BVBA");
  assert.equal(buyer.seller, undefined);
  assert.equal(buyer.seller_snapshot, undefined);
  assert.equal(buyer.tenant_id, undefined);
  assert.equal(buyer.company_id, undefined);
});

test("5) paid business bookings still enter existing Document Core then Billit", () => {
  assert.ok(worker.includes("async function ensureDocumentCoreInvoiceForPaidBusinessBooking"));
  assert.ok(worker.includes("async function ensureBillitOrderForPaidBusinessBooking"));
  assert.ok(worker.includes("async function maybeRunBillitAutoCreateAfterPaidLifecycle"));
  assert.ok(worker.includes("async function _maybeGenerateBusinessInvoiceForPaidBooking"));
  const billitIdx = worker.indexOf("async function ensureBillitOrderForPaidBusinessBooking");
  const nestedCoreIdx = worker.indexOf(
    "ensureDocumentCoreInvoiceForPaidBusinessBooking",
    billitIdx,
  );
  assert.ok(nestedCoreIdx > billitIdx, "Billit still waits for Document Core");
  assert.ok(worker.includes("reused_existing_invoice"));
  assert.ok(worker.includes("findExistingInvoiceDocumentForBooking"));
});

test("6) invoice amount for a limousine booking still uses the stored accepted snapshot", () => {
  assert.ok(worker.includes("limousine_accepted_price: _limousineAccepted.snapshot"));
  assert.ok(worker.includes("_limousineDocumentLinesFromSnapshot"));
  assert.ok(invoiceServiceLine.includes("limousine_accepted_price") || worker.includes("limousine_accepted_price"));
  assert.ok(worker.includes("const limousineDocLines = _limousineDocumentLinesFromSnapshot(limousineSnapshot)"));
});

test("7) Peppol send, consumer-sale and credit-note paths are the existing ones", () => {
  assert.ok(worker.includes("async function performBillitSandboxPeppolSend"));
  assert.ok(worker.includes("/v1/orders/commands/send"));
  assert.ok(consumerSale.includes("export const CONSUMER_SALE_KIND = \"consumer_sale\""));
  assert.ok(consumerSale.includes("requires_credit_note"));
  assert.ok(streetInvoice.includes("export function billingIdentityConflict"));
  assert.ok(streetInvoice.includes("export function shouldRejectForBillingReadiness"));
  assert.ok(streetInvoice.includes("export function streetRideInvoiceIdempotencyKey"));
  assert.ok(invoiceServiceLine.includes("credit") || worker.includes("credit_note"));
});

test("8) incomplete / conflicting buyer identity is still rejected by the existing street/document gates", () => {
  assert.ok(streetInvoice.includes("shouldRejectForBillingReadiness"));
  assert.ok(streetInvoice.includes("billingIdentityConflict"));
  assert.ok(worker.includes("billing_customer_not_ready") || streetInvoice.includes("billing_customer_not_ready") || worker.includes("billit_auto_billing_customer_missing"));
  assert.ok(worker.includes("billit_auto_billing_customer_missing"));
  assert.ok(worker.includes("not_business_invoice_intent"));
});
