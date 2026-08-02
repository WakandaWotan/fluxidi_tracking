/* Document Core invoice number source-of-truth helpers.
 *
 * Pure / side-effect free. Used by street business invoice issue/reuse,
 * PDF projection, and generateAndSendInvoice so INV-* wins over legacy FLX-*.
 *
 * Rules:
 *  - Document Core document_number is canonical when an issued invoice exists.
 *  - Never mint a third number when INV and FLX disagree.
 *  - Never overwrite an INV binding with FLX.
 *  - Tenant/company/booking scope must match before linking.
 *  - Legacy FLX allocator remains available only when no Document Core invoice
 *    exists and none is being issued.
 */

import { safeStr } from "./parsing_utils.js";

function _norm(value, max = 200) {
  return safeStr(value, max);
}

/** Legacy PDF/email sequence: FLX-YYYY-MM-#### */
export function isLegacyFlxInvoiceNumber(value) {
  const n = _norm(value, 120);
  return /^FLX-\d{4}-\d{2}-\d{1,8}$/i.test(n);
}

/** Document Core official invoice sequence: INV-… */
export function isDocumentCoreInvoiceNumber(value) {
  const n = _norm(value, 120);
  return /^INV-/i.test(n);
}

/**
 * Fail-closed ownership checks before binding a Document Core invoice to a booking.
 */
export function assertInvoiceDocumentLinkScope({
  scope = null,
  issuedDocument = null,
  bookingId = "",
  bookingRecord = null,
  documentId = "",
} = {}) {
  const tenant = _norm(scope?.tenant_id ?? scope?.tenantId, 120);
  const company = _norm(scope?.company_id ?? scope?.companyId, 120);
  if (!tenant || !company) {
    return { ok: false, error: "missing_tenant_scope" };
  }
  if (!issuedDocument || typeof issuedDocument !== "object") {
    return { ok: false, error: "missing_issued_document" };
  }

  const docTenant = _norm(
    issuedDocument.tenant_id ?? issuedDocument.tenantId,
    120,
  );
  const docCompany = _norm(
    issuedDocument.company_id ?? issuedDocument.companyId,
    120,
  );
  if (docTenant && docTenant !== tenant) {
    return { ok: false, error: "document_tenant_mismatch" };
  }
  if (docCompany && docCompany !== company) {
    return { ok: false, error: "document_company_mismatch" };
  }

  const safeBookingId = _norm(bookingId, 200);
  const sourceBooking = _norm(
    issuedDocument.source_booking_id ?? issuedDocument.sourceBookingId,
    200,
  );
  if (safeBookingId && sourceBooking && safeBookingId !== sourceBooking) {
    return { ok: false, error: "document_booking_mismatch" };
  }

  const rec =
    bookingRecord && typeof bookingRecord === "object" ? bookingRecord : null;
  if (rec) {
    const bookingTenant = _norm(rec.tenant_id ?? rec.tenantId, 120);
    const bookingCompany = _norm(rec.company_id ?? rec.companyId, 120);
    if (bookingTenant && bookingTenant !== tenant) {
      return { ok: false, error: "booking_tenant_mismatch" };
    }
    if (bookingCompany && bookingCompany !== company) {
      return { ok: false, error: "booking_company_mismatch" };
    }
  }

  const expectedDocId = _norm(documentId, 200);
  const actualDocId = _norm(
    issuedDocument.document_id ?? issuedDocument.documentId,
    200,
  );
  if (expectedDocId && actualDocId && expectedDocId !== actualDocId) {
    return { ok: false, error: "document_id_mismatch" };
  }
  if (!actualDocId) {
    return { ok: false, error: "document_id_missing" };
  }

  const documentNumber = _norm(
    issuedDocument.document_number ?? issuedDocument.documentNumber,
    120,
  );
  if (!documentNumber) {
    return { ok: false, error: "document_number_missing" };
  }

  return {
    ok: true,
    document_id: actualDocId,
    document_number: documentNumber,
    tenant_id: tenant,
    company_id: company,
  };
}

/**
 * Resolve the single canonical invoice number for PDF / booking binding.
 * Document Core wins over booking FLX / explicit legacy references.
 */
export function resolveCanonicalInvoiceNumberBinding({
  scope = null,
  bookingId = "",
  bookingRecord = null,
  issuedDocument = null,
  invoiceReference = "",
  documentId = "",
  requireDocumentCore = false,
} = {}) {
  const bookingNumber = _norm(
    findBookingInvoiceNumber(bookingRecord) || invoiceReference,
    120,
  );
  const explicitReference = _norm(invoiceReference, 120);

  if (issuedDocument && typeof issuedDocument === "object") {
    const link = assertInvoiceDocumentLinkScope({
      scope,
      issuedDocument,
      bookingId,
      bookingRecord,
      documentId,
    });
    if (!link.ok) {
      return {
        ok: false,
        error: link.error || "document_link_invalid",
        allocate_legacy_flx: false,
      };
    }

    const mismatch =
      !!bookingNumber &&
      bookingNumber !== link.document_number;

    return {
      ok: true,
      document_id: link.document_id,
      document_number: link.document_number,
      invoice_number: link.document_number,
      source: "document_core",
      mismatch,
      booking_invoice_number: bookingNumber || null,
      explicit_invoice_number: explicitReference || null,
      allocate_legacy_flx: false,
      should_stamp_booking: true,
      // Upgrade FLX→INV or fill empty; never stamp FLX over INV.
      stamp_overwrites_legacy_flx:
        !bookingNumber ||
        isLegacyFlxInvoiceNumber(bookingNumber) ||
        bookingNumber === link.document_number,
    };
  }

  if (requireDocumentCore) {
    return {
      ok: false,
      error: "missing_issued_document",
      allocate_legacy_flx: false,
    };
  }

  // Prefer an already-known Document Core number on the booking / explicit ref
  // over allocating a new FLX.
  const preferred =
    (isDocumentCoreInvoiceNumber(explicitReference) && explicitReference) ||
    (isDocumentCoreInvoiceNumber(bookingNumber) && bookingNumber) ||
    explicitReference ||
    bookingNumber ||
    "";

  if (preferred) {
    return {
      ok: true,
      document_id: _norm(documentId, 200) || null,
      document_number: isDocumentCoreInvoiceNumber(preferred)
        ? preferred
        : null,
      invoice_number: preferred,
      source: isDocumentCoreInvoiceNumber(preferred)
        ? "booking_or_explicit_inv"
        : "booking_or_explicit_legacy",
      mismatch: false,
      booking_invoice_number: bookingNumber || null,
      explicit_invoice_number: explicitReference || null,
      allocate_legacy_flx: false,
      should_stamp_booking: false,
      stamp_overwrites_legacy_flx: false,
    };
  }

  return {
    ok: true,
    document_id: null,
    document_number: null,
    invoice_number: "",
    source: "none",
    mismatch: false,
    booking_invoice_number: null,
    explicit_invoice_number: null,
    allocate_legacy_flx: true,
    should_stamp_booking: false,
    stamp_overwrites_legacy_flx: false,
  };
}

export function findBookingInvoiceNumber(source) {
  if (!source || typeof source !== "object") return "";
  return _norm(
    source.invoice_number ||
      source.invoiceNumber ||
      source.invoice?.invoice_number ||
      source.invoice?.invoiceNumber ||
      source.invoice?.number ||
      source.booking?.invoice_number ||
      source.booking?.invoiceNumber ||
      source.booking?.invoice?.number,
    120,
  );
}

/**
 * In-memory stamp of Document Core binding onto a booking record.
 * Never overwrites an existing INV with FLX. May upgrade FLX → INV.
 */
export function applyCanonicalInvoiceBindingToBookingRecord(
  rec,
  { documentId = "", documentNumber = "", forceUpgradeFromLegacyFlx = true } = {},
) {
  if (!rec || typeof rec !== "object" || Array.isArray(rec)) {
    return { ok: false, error: "missing_booking_record", mutated: false };
  }
  const safeDocId = _norm(documentId, 200);
  const safeNumber = _norm(documentNumber, 120);
  if (!safeDocId || !safeNumber) {
    return { ok: false, error: "missing_binding_fields", mutated: false };
  }
  if (isLegacyFlxInvoiceNumber(safeNumber)) {
    return { ok: false, error: "refuse_stamp_legacy_flx_as_core", mutated: false };
  }

  const existingNumber = findBookingInvoiceNumber(rec);
  if (
    existingNumber &&
    isDocumentCoreInvoiceNumber(existingNumber) &&
    existingNumber !== safeNumber
  ) {
    return {
      ok: false,
      error: "refuse_overwrite_existing_inv",
      mutated: false,
      existing_invoice_number: existingNumber,
    };
  }
  if (
    existingNumber &&
    isLegacyFlxInvoiceNumber(existingNumber) &&
    forceUpgradeFromLegacyFlx !== true
  ) {
    return {
      ok: false,
      error: "legacy_flx_present_upgrade_disabled",
      mutated: false,
      existing_invoice_number: existingNumber,
    };
  }

  let mutated = false;
  if (rec.invoice_number !== safeNumber || rec.invoiceNumber !== safeNumber) {
    rec.invoice_number = safeNumber;
    rec.invoiceNumber = safeNumber;
    mutated = true;
  }
  if (
    rec.invoice_document_id !== safeDocId ||
    rec.invoiceDocumentId !== safeDocId
  ) {
    rec.invoice_document_id = safeDocId;
    rec.invoiceDocumentId = safeDocId;
    mutated = true;
  }
  if (rec.booking && typeof rec.booking === "object") {
    if (
      rec.booking.invoice_number !== safeNumber ||
      rec.booking.invoiceNumber !== safeNumber
    ) {
      rec.booking.invoice_number = safeNumber;
      rec.booking.invoiceNumber = safeNumber;
      mutated = true;
    }
    if (
      rec.booking.invoice_document_id !== safeDocId ||
      rec.booking.invoiceDocumentId !== safeDocId
    ) {
      rec.booking.invoice_document_id = safeDocId;
      rec.booking.invoiceDocumentId = safeDocId;
      mutated = true;
    }
  }

  return {
    ok: true,
    mutated,
    document_id: safeDocId,
    document_number: safeNumber,
    previous_invoice_number: existingNumber || null,
  };
}

/**
 * Whether generateAndSendInvoice may call the legacy FLX allocator.
 */
export function shouldAllocateLegacyFlxInvoiceNumber({
  businessInvoiceIntent = false,
  hasDocumentCoreInvoice = false,
  existingInvoiceNumber = "",
  explicitInvoiceNumber = "",
} = {}) {
  if (hasDocumentCoreInvoice) return false;
  if (isDocumentCoreInvoiceNumber(existingInvoiceNumber)) return false;
  if (isDocumentCoreInvoiceNumber(explicitInvoiceNumber)) return false;
  if (existingInvoiceNumber || explicitInvoiceNumber) return false;
  // Business invoices must come from Document Core; do not mint FLX preemptively.
  if (businessInvoiceIntent === true) return false;
  return true;
}

/**
 * Choose which number generateAndSendInvoice should reuse (no allocation yet).
 * Document Core / explicit INV beats stale booking FLX.
 */
export function pickReusableInvoiceNumberForGenerator({
  bookingRecordNumber = "",
  bookingInputNumber = "",
  documentCoreNumber = "",
} = {}) {
  const doc = _norm(documentCoreNumber, 120);
  const input = _norm(bookingInputNumber, 120);
  const rec = _norm(bookingRecordNumber, 120);

  if (doc) {
    return {
      invoice_number: doc,
      source: "document_core",
      mismatch: !!(rec && rec !== doc) || !!(input && input !== doc && !isLegacyFlxInvoiceNumber(input) && isDocumentCoreInvoiceNumber(input) && input !== doc),
      booking_invoice_number: rec || null,
    };
  }
  if (isDocumentCoreInvoiceNumber(input)) {
    return {
      invoice_number: input,
      source: "booking_input_inv",
      mismatch: !!(rec && rec !== input),
      booking_invoice_number: rec || null,
    };
  }
  if (isDocumentCoreInvoiceNumber(rec)) {
    return {
      invoice_number: rec,
      source: "booking_record_inv",
      mismatch: false,
      booking_invoice_number: rec,
    };
  }
  // Prefer explicit input (projection) over stale FLX on the record when input
  // is Document Core-shaped; for same-family legacy, prefer non-empty rec then input.
  if (input && isDocumentCoreInvoiceNumber(input)) {
    return {
      invoice_number: input,
      source: "booking_input",
      mismatch: !!(rec && rec !== input),
      booking_invoice_number: rec || null,
    };
  }
  if (rec) {
    return {
      invoice_number: rec,
      source: "booking_record",
      mismatch: false,
      booking_invoice_number: rec,
    };
  }
  if (input) {
    return {
      invoice_number: input,
      source: "booking_input",
      mismatch: false,
      booking_invoice_number: null,
    };
  }
  return {
    invoice_number: "",
    source: "none",
    mismatch: false,
    booking_invoice_number: null,
  };
}

/**
 * Persist decision: may we write `candidate` onto a booking that already has
 * `existing`? Never replace INV with FLX.
 */
export function canPersistInvoiceNumberOnBooking({
  existing = "",
  candidate = "",
} = {}) {
  const have = _norm(existing, 120);
  const next = _norm(candidate, 120);
  if (!next) {
    return { ok: false, error: "missing_candidate", persist: false };
  }
  if (!have) {
    return { ok: true, persist: true, reason: "empty_booking" };
  }
  if (have === next) {
    return { ok: true, persist: false, reason: "already_same", invoice_number: have };
  }
  if (isDocumentCoreInvoiceNumber(have) && isLegacyFlxInvoiceNumber(next)) {
    return {
      ok: true,
      persist: false,
      reason: "refuse_overwrite_inv_with_flx",
      invoice_number: have,
    };
  }
  if (isLegacyFlxInvoiceNumber(have) && isDocumentCoreInvoiceNumber(next)) {
    return {
      ok: true,
      persist: true,
      reason: "upgrade_flx_to_inv",
      invoice_number: next,
    };
  }
  // Distinct non-upgrade conflict: keep existing, do not mint a third number.
  return {
    ok: true,
    persist: false,
    reason: "keep_existing_conflict",
    invoice_number: have,
  };
}

/** PII-free mismatch log fields (no customer names/emails/addresses). */
export function buildInvoiceNumberMismatchDiag({
  bookingId = "",
  documentId = "",
  documentNumber = "",
  bookingInvoiceNumber = "",
  source = "",
} = {}) {
  return {
    event: "invoice_number_mismatch",
    booking_id_prefix: _norm(bookingId, 200).slice(0, 12) || "-",
    document_id_prefix: _norm(documentId, 200).slice(0, 8) || "-",
    document_number: _norm(documentNumber, 120) || "-",
    booking_invoice_number: _norm(bookingInvoiceNumber, 120) || "-",
    source: _norm(source, 40) || "-",
    winner: "document_core",
  };
}

export function formatInvoiceNumberMismatchLog(diag) {
  const d =
    diag && typeof diag === "object"
      ? diag
      : buildInvoiceNumberMismatchDiag({});
  return (
    `[INVOICE_NUMBER][MISMATCH] booking=${d.booking_id_prefix} doc=${d.document_id_prefix} ` +
    `core=${d.document_number} booking_num=${d.booking_invoice_number} ` +
    `source=${d.source} winner=${d.winner}`
  );
}
