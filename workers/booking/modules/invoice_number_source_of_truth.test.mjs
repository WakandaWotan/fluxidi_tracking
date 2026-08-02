import { test } from "node:test";
import assert from "node:assert/strict";
import {
  isLegacyFlxInvoiceNumber,
  isDocumentCoreInvoiceNumber,
  assertInvoiceDocumentLinkScope,
  resolveCanonicalInvoiceNumberBinding,
  applyCanonicalInvoiceBindingToBookingRecord,
  shouldAllocateLegacyFlxInvoiceNumber,
  pickReusableInvoiceNumberForGenerator,
  canPersistInvoiceNumberOnBooking,
  buildInvoiceNumberMismatchDiag,
  formatInvoiceNumberMismatchLog,
} from "./invoice_number_source_of_truth.js";
import { buildStreetInvoicePdfProjection } from "./street_invoice_pdf_projection.js";

const SCOPE = {
  tenant_id: "fluxidi_fluxidi_ddmh9g",
  company_id: "fluxidi_fluxidi_ddmh9g",
};
const BOOKING_ID = "street_1785684244820_97ofs7tm";
const DOC_ID = "5244df21-d4d8-4fbe-b2f1-72986504cead";
const INV = "INV-2026-000035";
const FLX = "FLX-2026-08-0001";

function issuedDoc(overrides = {}) {
  return {
    document_id: DOC_ID,
    document_number: INV,
    document_type: "invoice",
    tenant_id: SCOPE.tenant_id,
    company_id: SCOPE.company_id,
    source_booking_id: BOOKING_ID,
    seller_snapshot: {
      trading_name: "Fluxidi",
      legal_name: "Christophe Vanrokeghem",
      vat_number: "BE0772931038",
    },
    totals: {
      total_incl_vat: 5.3,
      vat_amount: 0.3,
      subtotal_ex_vat: 5.0,
      vat_rate_percent: 6,
    },
    ...overrides,
  };
}

function bookingRec(overrides = {}) {
  return {
    tenant_id: SCOPE.tenant_id,
    company_id: SCOPE.company_id,
    booking_id: BOOKING_ID,
    invoice_number: FLX,
    invoice_document_id: null,
    payment_status: "paid",
    booking: {
      booking_id: BOOKING_ID,
      invoice_number: FLX,
      payment_status: "paid",
      from: "A",
      to: "B",
    },
    ...overrides,
  };
}

test("detects INV vs FLX number shapes", () => {
  assert.equal(isDocumentCoreInvoiceNumber(INV), true);
  assert.equal(isLegacyFlxInvoiceNumber(FLX), true);
  assert.equal(isDocumentCoreInvoiceNumber(FLX), false);
  assert.equal(isLegacyFlxInvoiceNumber(INV), false);
});

test("new issue binding stamps document_id + INV on booking", () => {
  const rec = bookingRec({ invoice_number: null, booking: { booking_id: BOOKING_ID } });
  const resolved = resolveCanonicalInvoiceNumberBinding({
    scope: SCOPE,
    bookingId: BOOKING_ID,
    bookingRecord: rec,
    issuedDocument: issuedDoc(),
  });
  assert.equal(resolved.ok, true);
  assert.equal(resolved.document_number, INV);
  assert.equal(resolved.document_id, DOC_ID);
  assert.equal(resolved.allocate_legacy_flx, false);

  const stamped = applyCanonicalInvoiceBindingToBookingRecord(rec, {
    documentId: resolved.document_id,
    documentNumber: resolved.document_number,
  });
  assert.equal(stamped.ok, true);
  assert.equal(rec.invoice_number, INV);
  assert.equal(rec.invoice_document_id, DOC_ID);
  assert.equal(rec.booking.invoice_number, INV);
});

test("idempotent retry reuses exact same INV binding", () => {
  const rec = bookingRec({
    invoice_number: INV,
    invoice_document_id: DOC_ID,
    booking: { booking_id: BOOKING_ID, invoice_number: INV, invoice_document_id: DOC_ID },
  });
  const first = resolveCanonicalInvoiceNumberBinding({
    scope: SCOPE,
    bookingId: BOOKING_ID,
    bookingRecord: rec,
    issuedDocument: issuedDoc(),
  });
  const second = resolveCanonicalInvoiceNumberBinding({
    scope: SCOPE,
    bookingId: BOOKING_ID,
    bookingRecord: rec,
    issuedDocument: issuedDoc(),
    invoiceReference: INV,
    documentId: DOC_ID,
  });
  assert.equal(first.invoice_number, INV);
  assert.equal(second.invoice_number, INV);
  assert.equal(first.document_id, second.document_id);
  assert.equal(shouldAllocateLegacyFlxInvoiceNumber({
    businessInvoiceIntent: true,
    hasDocumentCoreInvoice: true,
    existingInvoiceNumber: INV,
  }), false);

  const stamped = applyCanonicalInvoiceBindingToBookingRecord(rec, {
    documentId: DOC_ID,
    documentNumber: INV,
  });
  assert.equal(stamped.ok, true);
  assert.equal(rec.invoice_number, INV);
  assert.equal(rec.invoice_document_id, DOC_ID);
  const stampedAgain = applyCanonicalInvoiceBindingToBookingRecord(rec, {
    documentId: DOC_ID,
    documentNumber: INV,
  });
  assert.equal(stampedAgain.ok, true);
  assert.equal(stampedAgain.mutated, false);
  assert.equal(rec.invoice_number, INV);
  assert.equal(rec.invoice_document_id, DOC_ID);
});

test("booking FLX + existing INV document projects to INV", () => {
  const rec = bookingRec();
  const resolved = resolveCanonicalInvoiceNumberBinding({
    scope: SCOPE,
    bookingId: BOOKING_ID,
    bookingRecord: rec,
    issuedDocument: issuedDoc(),
    invoiceReference: FLX,
  });
  assert.equal(resolved.ok, true);
  assert.equal(resolved.mismatch, true);
  assert.equal(resolved.invoice_number, INV);
  assert.equal(resolved.booking_invoice_number, FLX);
  assert.equal(resolved.allocate_legacy_flx, false);

  const diag = buildInvoiceNumberMismatchDiag({
    bookingId: BOOKING_ID,
    documentId: DOC_ID,
    documentNumber: INV,
    bookingInvoiceNumber: FLX,
    source: "ensure",
  });
  const log = formatInvoiceNumberMismatchLog(diag);
  assert.match(log, /MISMATCH/);
  assert.match(log, /INV-2026-000035/);
  assert.match(log, /FLX-2026-08-0001/);
  assert.doesNotMatch(log, /@/);
});

test("PDF projection uses INV not FLX when issued document present", () => {
  const projection = buildStreetInvoicePdfProjection({
    scope: SCOPE,
    bookingId: BOOKING_ID,
    bookingRecord: bookingRec(),
    issuedDocument: issuedDoc(),
    invoiceNumber: FLX,
    documentId: DOC_ID,
    companyVatRatePercent: 6,
    communicationProfile: {
      brandName: "Fluxidi",
      legalName: "Christophe Vanrokeghem",
      vatNumber: "BE0772931038",
    },
    paymentStatusResolver: () => "paid",
  });
  assert.equal(projection.ok, true);
  assert.equal(projection.invoiceNumber, INV);
  assert.equal(projection.invoiceInput.invoice_number, INV);
  assert.equal(projection.invoiceInput.invoiceNumber, INV);
  assert.notEqual(projection.invoiceNumber, FLX);
});

test("generator pick prefers Document Core; no FLX allocate when INV present", () => {
  const picked = pickReusableInvoiceNumberForGenerator({
    bookingRecordNumber: FLX,
    bookingInputNumber: INV,
    documentCoreNumber: INV,
  });
  assert.equal(picked.invoice_number, INV);
  assert.equal(picked.source, "document_core");

  assert.equal(
    shouldAllocateLegacyFlxInvoiceNumber({
      businessInvoiceIntent: true,
      hasDocumentCoreInvoice: false,
      existingInvoiceNumber: "",
      explicitInvoiceNumber: "",
    }),
    false,
  );
  assert.equal(
    shouldAllocateLegacyFlxInvoiceNumber({
      businessInvoiceIntent: false,
      hasDocumentCoreInvoice: false,
      existingInvoiceNumber: "",
      explicitInvoiceNumber: "",
    }),
    true,
  );
  assert.equal(
    canPersistInvoiceNumberOnBooking({ existing: INV, candidate: FLX }).persist,
    false,
  );
  assert.equal(
    canPersistInvoiceNumberOnBooking({ existing: FLX, candidate: INV }).persist,
    true,
  );
});

test("cross-tenant document cannot be linked", () => {
  const link = assertInvoiceDocumentLinkScope({
    scope: SCOPE,
    bookingId: BOOKING_ID,
    bookingRecord: bookingRec(),
    issuedDocument: issuedDoc({ tenant_id: "other_tenant", company_id: "other_company" }),
  });
  assert.equal(link.ok, false);
  assert.equal(link.error, "document_tenant_mismatch");

  const resolved = resolveCanonicalInvoiceNumberBinding({
    scope: SCOPE,
    bookingId: BOOKING_ID,
    bookingRecord: bookingRec(),
    issuedDocument: issuedDoc({ tenant_id: "other_tenant" }),
    requireDocumentCore: true,
  });
  assert.equal(resolved.ok, false);
  assert.equal(resolved.error, "document_tenant_mismatch");
  assert.equal(resolved.allocate_legacy_flx, false);
});

test("document without valid link fails closed", () => {
  assert.equal(
    assertInvoiceDocumentLinkScope({
      scope: SCOPE,
      bookingId: BOOKING_ID,
      issuedDocument: null,
    }).error,
    "missing_issued_document",
  );
  assert.equal(
    assertInvoiceDocumentLinkScope({
      scope: SCOPE,
      bookingId: BOOKING_ID,
      issuedDocument: issuedDoc({ document_number: "" }),
    }).error,
    "document_number_missing",
  );
  assert.equal(
    assertInvoiceDocumentLinkScope({
      scope: SCOPE,
      bookingId: "other_booking",
      issuedDocument: issuedDoc(),
    }).error,
    "document_booking_mismatch",
  );
  assert.equal(
    applyCanonicalInvoiceBindingToBookingRecord(bookingRec({ invoice_number: INV }), {
      documentId: DOC_ID,
      documentNumber: FLX,
    }).error,
    "refuse_stamp_legacy_flx_as_core",
  );
  assert.equal(
    applyCanonicalInvoiceBindingToBookingRecord(
      bookingRec({ invoice_number: "INV-2026-000099", invoice_document_id: "aaaa" }),
      { documentId: DOC_ID, documentNumber: INV },
    ).error,
    "refuse_overwrite_existing_inv",
  );
});
