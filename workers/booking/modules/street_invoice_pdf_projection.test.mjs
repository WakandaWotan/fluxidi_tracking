import { test } from "node:test";
import assert from "node:assert/strict";
import { mapFluxidiPaymentMethodToBillitPaymentMethod } from "./billit_provider.js";
import {
  euroAmountToCents,
  centsToEuroFixed,
  normalizeVatRatePercent,
  resolveInvoiceVatRatePercent,
  resolveInvoiceFinancialCents,
  resolveInvoiceSellerCommProfile,
  resolveInvoiceRideProjection,
  formatFluxidiPaymentMethodLabel,
  buildStreetInvoicePdfProjection,
  shouldRefreshStreetInvoicePdfArtifact,
  assertStreetInvoicePdfOwnership,
  buildStreetInvoicePdfProjectionRevision,
  readStoredStreetInvoicePdfProjectionRevision,
} from "./street_invoice_pdf_projection.js";

const SCOPE = { tenant_id: "t1", company_id: "c1" };

function issuedDoc({
  vatRatePercent = 6,
  total = 5,
  vat = 0.3,
  ex = 4.7,
  sellerName = "Issued Seller BV",
  sellerLegal = "Issued Seller Legal",
  sellerVat = "BE0123456789",
  documentId = "doc-1",
  documentNumber = "INV-2026-000034",
  bookingId = "street_1",
} = {}) {
  return {
    tenant_id: "t1",
    company_id: "c1",
    document_id: documentId,
    document_number: documentNumber,
    source_booking_id: bookingId,
    seller_snapshot: {
      name: sellerName,
      legal_name: sellerLegal,
      vat_number: sellerVat,
      street: "Teststraat 1",
      postal_code: "9000",
      city: "Gent",
      country: "BE",
    },
    totals: {
      total_incl_vat: total,
      vat_amount: vat,
      subtotal_ex_vat: ex,
      vat_rate_percent: vatRatePercent,
    },
  };
}

function bookingRec({
  payment_status = "unpaid",
  payment_method = "qr_code",
  price_incl_vat = 5,
  price_vat = 0.3,
  price_ex_vat = 4.7,
  vat_rate_percent = null,
  tier = "comfort",
  service = "private",
  pickup = "2026-08-02T10:30:00.000Z",
  started = "2026-08-02T10:35:00.000Z",
} = {}) {
  return {
    tenant_id: "t1",
    company_id: "c1",
    booking_id: "street_1",
    payment_status,
    payment_method,
    price_incl_vat,
    price_vat,
    price_ex_vat,
    vat_rate_percent,
    status: "COMPLETED",
    ride_started_at: started,
    booking: {
      from: "A",
      to: "B",
      tier,
      service,
      pickup_iso: pickup,
      pickupStartIso: pickup,
    },
  };
}

test("A1) issued 6% wins when booking VAT missing — never 21", () => {
  const vat = resolveInvoiceVatRatePercent({
    issuedDocument: issuedDoc({ vatRatePercent: 6 }),
    bookingRecord: bookingRec({ vat_rate_percent: null }),
    companyVatRatePercent: 21,
  });
  assert.equal(vat.ok, true);
  assert.equal(vat.ratePercent, 6);
  assert.equal(vat.source, "document_core_issued");
});

test("A2) issued alternate rate preserved exactly", () => {
  const vat = resolveInvoiceVatRatePercent({
    issuedDocument: issuedDoc({ vatRatePercent: 12 }),
    bookingRecord: bookingRec({ vat_rate_percent: 6 }),
  });
  assert.equal(vat.ratePercent, 12);
  assert.equal(vat.source, "document_core_issued");
});

test("A3) booking snapshot used when issued VAT absent", () => {
  const doc = issuedDoc();
  delete doc.totals.vat_rate_percent;
  const vat = resolveInvoiceVatRatePercent({
    issuedDocument: doc,
    bookingRecord: bookingRec({ vat_rate_percent: 6 }),
    companyVatRatePercent: 21,
  });
  assert.equal(vat.ok, true);
  assert.equal(vat.ratePercent, 6);
  assert.equal(vat.source, "booking_snapshot");
});

test("A4) company config only when issued+booking absent", () => {
  const vat = resolveInvoiceVatRatePercent({
    issuedDocument: null,
    bookingRecord: bookingRec({ vat_rate_percent: null }),
    companyVatRatePercent: 6,
  });
  assert.equal(vat.ok, true);
  assert.equal(vat.ratePercent, 6);
  assert.equal(vat.source, "company_vat_config");
});

test("A5) fail closed — no invented VAT", () => {
  const vat = resolveInvoiceVatRatePercent({
    issuedDocument: null,
    bookingRecord: bookingRec({ vat_rate_percent: null }),
    companyVatRatePercent: null,
  });
  assert.equal(vat.ok, false);
  assert.equal(vat.error, "missing_vat_rate");
});

test("B) financial cents preserved for €5 / €0.30 / €4.70", () => {
  const money = resolveInvoiceFinancialCents({
    issuedDocument: issuedDoc({ total: 5, vat: 0.3, ex: 4.7 }),
  });
  assert.equal(money.ok, true);
  assert.equal(money.totalInclCents, 500);
  assert.equal(money.vatCents, 30);
  assert.equal(money.subtotalExCents, 470);
  assert.equal(centsToEuroFixed(money.totalInclCents), "5.00");
  assert.equal(centsToEuroFixed(money.vatCents), "0.30");
  assert.equal(centsToEuroFixed(money.subtotalExCents), "4.70");
  assert.equal(euroAmountToCents("5.00"), 500);
});

test("B2) integer-cent issued totals preferred without float recompute", () => {
  const doc = issuedDoc();
  doc.totals = {
    total_incl_vat_cents: 500,
    vat_amount_cents: 30,
    subtotal_ex_vat_cents: 470,
    vat_rate_percent: 6,
    // Deliberately wrong float companions — cents must win.
    total_incl_vat: 5.01,
    vat_amount: 0.31,
    subtotal_ex_vat: 4.71,
  };
  const money = resolveInvoiceFinancialCents({ issuedDocument: doc });
  assert.equal(money.totalInclCents, 500);
  assert.equal(money.vatCents, 30);
  assert.equal(money.subtotalExCents, 470);
  const built = buildStreetInvoicePdfProjection({
    scope: SCOPE,
    bookingId: "street_1",
    bookingRecord: bookingRec({ payment_status: "paid" }),
    issuedDocument: doc,
    invoiceNumber: "INV-2026-000034",
    documentId: "doc-1",
  });
  assert.equal(built.ok, true);
  assert.equal(built.invoiceInput.totalFixed, "5.00");
  assert.equal(built.invoiceInput.vatAmountFixed, "0.30");
  assert.equal(built.invoiceInput.subtotalExFixed, "4.70");
  assert.equal(built.invoiceInput.require_explicit_vat, true);
});

test("C) seller_snapshot wins over stale communication profile", () => {
  const seller = resolveInvoiceSellerCommProfile({
    issuedDocument: issuedDoc({ sellerName: "Issued Co", sellerLegal: "Issued Legal" }),
    communicationProfile: {
      brandName: "VC Construct & Graphics",
      legalName: "VC Construct & Graphics",
      vatNumber: "BE000",
    },
  });
  assert.equal(seller.source, "document_core_seller_snapshot");
  assert.equal(seller.brandName, "Issued Co");
  assert.equal(seller.legalName, "Issued Legal");
  assert.match(seller.legalName, /Issued/);
});

test("C3) sole-prop seller snapshot presents entrepreneur and trading name separately", () => {
  const seller = resolveInvoiceSellerCommProfile({
    issuedDocument: {
      tenant_id: "t1",
      company_id: "c1",
      document_id: "doc-1",
      document_number: "INV-X",
      source_booking_id: "street_1",
      seller_snapshot: {
        name: "Fluxidi",
        trading_name: "Fluxidi",
        legal_name: "Christophe Vanrokeghem",
        legal_entrepreneur_name: "Christophe Vanrokeghem",
        legal_form: "eenmanszaak",
        legal_form_label_nl: "Eenmanszaak",
        vat_number: "BE0772931038",
        enterprise_number: "0772931038",
        registration_number: "0772931038",
        address_line: "Koekamerstraat 48A",
        postal_code: "9688",
        city: "Schorisse",
        country_code: "BE",
      },
      totals: {
        total_incl_vat: 5.3,
        vat_amount: 0.3,
        subtotal_ex_vat: 5,
        vat_rate_percent: 6,
      },
    },
  });
  const text = (seller.sellerPresentationLines || []).join("\n");
  assert.match(text, /Christophe Vanrokeghem/);
  assert.match(text, /handelend onder de naam Fluxidi/);
  assert.match(text, /Eenmanszaak/);
  assert.match(text, /0772\.931\.038/);
  assert.doesNotMatch(text, /\bBV\b/);
});

test("C2) new invoice without seller snapshot may use profile", () => {
  const seller = resolveInvoiceSellerCommProfile({
    issuedDocument: null,
    communicationProfile: {
      brandName: "Profile Brand",
      legalName: "Profile Legal",
      vatNumber: "BE111",
    },
  });
  assert.equal(seller.source, "company_communication_profile");
  assert.equal(seller.brandName, "Profile Brand");
});

test("D) ride details mapped from booking", () => {
  const ride = resolveInvoiceRideProjection(
    bookingRec({
      pickup: "2026-08-02T10:30:00.000Z",
      started: "2026-08-02T10:35:00.000Z",
      tier: "comfort",
      service: "private",
    }),
  );
  assert.equal(ride.from, "A");
  assert.equal(ride.to, "B");
  assert.equal(ride.tier, "comfort");
  assert.equal(ride.service, "private");
  assert.ok(ride.tripDate);
  assert.ok(ride.pickupTime);
  assert.ok(ride.rideStartTime);
});

test("D2) missing optional ride fields do not crash", () => {
  const ride = resolveInvoiceRideProjection({ booking: { from: "X", to: "Y" } });
  assert.equal(ride.from, "X");
  assert.equal(ride.tier, "");
  assert.equal(ride.pickupTime, "");
});

test("E1) projection paid refresh decision after unpaid artifact", () => {
  const unpaid = buildStreetInvoicePdfProjectionRevision({
    paymentStatus: "unpaid",
    vatRatePercent: 6,
    totalInclCents: 500,
    vatCents: 30,
    subtotalExCents: 470,
    sellerSource: "document_core_seller_snapshot",
    paymentMethodLabel: "QR-betaling",
  });
  const paid = buildStreetInvoicePdfProjectionRevision({
    paymentStatus: "paid",
    vatRatePercent: 6,
    totalInclCents: 500,
    vatCents: 30,
    subtotalExCents: 470,
    sellerSource: "document_core_seller_snapshot",
    paymentMethodLabel: "QR-betaling",
  });
  const decision = shouldRefreshStreetInvoicePdfArtifact({
    existingPdfExists: true,
    storedProjectionRevision: unpaid,
    nextProjectionRevision: paid,
    reason: "paid_refresh",
  });
  assert.equal(decision.refresh, true);
});

test("E2) qr_code displays as QR payment label", () => {
  assert.equal(formatFluxidiPaymentMethodLabel("qr_code"), "QR-betaling");
});

test("E3) Billit mapper unchanged for qr_code → Wired", () => {
  assert.equal(
    mapFluxidiPaymentMethodToBillitPaymentMethod("qr_code", "manual", "qr"),
    "Wired",
  );
});

test("F1) ownership rejects cross-tenant document", () => {
  const check = assertStreetInvoicePdfOwnership({
    scope: SCOPE,
    bookingRecord: bookingRec(),
    issuedDocument: { ...issuedDoc(), tenant_id: "other" },
    bookingId: "street_1",
    documentId: "doc-1",
    invoiceNumber: "INV-2026-000034",
  });
  assert.equal(check.ok, false);
  assert.equal(check.error, "document_tenant_mismatch");
});

test("F2) unchanged projection skips rewrite", () => {
  const rev = buildStreetInvoicePdfProjectionRevision({
    paymentStatus: "paid",
    vatRatePercent: 6,
    totalInclCents: 500,
    vatCents: 30,
    subtotalExCents: 470,
    sellerSource: "document_core_seller_snapshot",
    paymentMethodLabel: "QR-betaling",
  });
  const decision = shouldRefreshStreetInvoicePdfArtifact({
    existingPdfExists: true,
    storedProjectionRevision: rev,
    nextProjectionRevision: rev,
    reason: "paid_refresh",
  });
  assert.equal(decision.refresh, false);
  assert.equal(decision.reason, "projection_unchanged");
});

test("F3) full projection build keeps invoice number and exact money", () => {
  const built = buildStreetInvoicePdfProjection({
    scope: SCOPE,
    bookingId: "street_1",
    bookingRecord: bookingRec({ payment_status: "paid" }),
    issuedDocument: issuedDoc(),
    invoiceNumber: "INV-2026-000034",
    documentId: "doc-1",
    communicationProfile: {
      brandName: "Stale Profile",
      legalName: "Stale Profile",
    },
  });
  assert.equal(built.ok, true);
  assert.equal(built.invoiceNumber, "INV-2026-000034");
  assert.equal(built.documentId, "doc-1");
  assert.equal(built.vatRatePercent, 6);
  assert.equal(built.totalInclCents, 500);
  assert.equal(built.vatCents, 30);
  assert.equal(built.subtotalExCents, 470);
  assert.equal(built.paymentStatus, "paid");
  assert.equal(built.paymentMethodLabel, "QR-betaling");
  assert.equal(built.sellerSource, "document_core_seller_snapshot");
  assert.equal(built.invoiceInput.vat_rate, 0.06);
  assert.equal(built.invoiceInput.total, 5);
  assert.equal(built.invoiceInput.tier, "comfort");
  assert.ok(built.invoiceInput.pickupTime);
  assert.equal(built.invoiceInput.seller_source, "document_core_seller_snapshot");
  assert.equal(built.invoiceInput.paymentMethod, "QR-betaling");
  assert.notEqual(normalizeVatRatePercent(0.21), 6);
});

test("F4) stored revision reader", () => {
  assert.equal(
    readStoredStreetInvoicePdfProjectionRevision({
      invoice_pdf_projection_revision: "abc",
    }),
    "abc",
  );
});
