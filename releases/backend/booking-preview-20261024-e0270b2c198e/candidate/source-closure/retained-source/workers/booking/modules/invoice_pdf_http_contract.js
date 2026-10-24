/* INVOICE-PDF-PENDING-CONTRACT-P0C
 *
 * Pure HTTP decision for GET /bookings/:id/invoice/pdf.
 * Distinguishes pending generation, permanent absence, and upstream failure.
 * No background retry loops and no scheduled work.
 */

import { corsHeaders } from "./http_response.js";

export const INVOICE_PDF_DEFAULT_RETRY_AFTER_SECONDS = 2;

export function hasIssuedFiscalDocumentForPdf({
  invoiceDocumentId = "",
  consumerSaleDocumentId = "",
  invoiceNumber = "",
  saleKind = "",
} = {}) {
  if (String(invoiceDocumentId ?? "").trim()) return true;
  if (String(consumerSaleDocumentId ?? "").trim()) return true;
  if (String(invoiceNumber ?? "").trim()) return true;
  const kind = String(saleKind ?? "").trim().toLowerCase();
  return kind === "consumer_sale" || kind === "business_invoice";
}

export function resolveInvoicePdfServeDecision({
  metadataExists = false,
  objectFound = false,
  objectEmpty = false,
  storageAvailable = true,
  hasIssuedFiscalDocument = false,
  ensureAttempted = false,
  ensureFailed = false,
  ensurePending = false,
  readFailed = false,
} = {}) {
  if (readFailed) {
    return {
      status: 500,
      ok: false,
      error: "invoice_pdf_read_failed",
      state: "failure",
    };
  }
  if (metadataExists && objectFound && !objectEmpty) {
    return { status: 200, ok: true, state: "ready" };
  }
  if (!storageAvailable) {
    return {
      status: 500,
      ok: false,
      error: "invoice_storage_unavailable",
      state: "failure",
    };
  }
  if (metadataExists && objectEmpty) {
    return {
      status: 404,
      ok: false,
      error: "invoice_pdf_empty",
      state: "missing",
    };
  }
  if (metadataExists && !objectFound) {
    return {
      status: 404,
      ok: false,
      error: "invoice_pdf_not_found",
      state: "missing",
    };
  }
  if (ensureFailed) {
    return {
      status: 503,
      ok: false,
      error: "invoice_pdf_generation_failed",
      state: "failure",
    };
  }
  if (
    ensurePending ||
    hasIssuedFiscalDocument ||
    ensureAttempted
  ) {
    return {
      status: 202,
      ok: false,
      error: "invoice_pdf_pending",
      state: "pending",
      retryAfterSeconds: INVOICE_PDF_DEFAULT_RETRY_AFTER_SECONDS,
    };
  }
  return {
    status: 404,
    ok: false,
    error: "invoice_pdf_not_available",
    state: "missing",
  };
}

export function buildInvoicePdfStatusResponse(decision) {
  const headers = {
    "Content-Type": "application/json; charset=utf-8",
    ...corsHeaders(),
    "X-Fluxidi-Invoice-Artifact-State": decision.state || "missing",
  };
  if (decision.state === "pending") {
    headers["Retry-After"] = String(
      decision.retryAfterSeconds || INVOICE_PDF_DEFAULT_RETRY_AFTER_SECONDS,
    );
  }
  return new Response(
    JSON.stringify({
      ok: decision.ok === true,
      error: decision.error || undefined,
      status: decision.state,
      invoice_pdf_state: decision.state,
      retry_after:
        decision.state === "pending"
          ? decision.retryAfterSeconds || INVOICE_PDF_DEFAULT_RETRY_AFTER_SECONDS
          : undefined,
    }),
    { status: decision.status, headers },
  );
}
