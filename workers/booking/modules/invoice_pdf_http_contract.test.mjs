/* INVOICE-PDF-PENDING-CONTRACT-P0C
 *
 *   node --test workers/booking/modules/invoice_pdf_http_contract.test.mjs
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  buildInvoicePdfStatusResponse,
  hasIssuedFiscalDocumentForPdf,
  resolveInvoicePdfServeDecision,
} from "./invoice_pdf_http_contract.js";

test("pending when a fiscal document exists but the artifact is not ready", () => {
  const decision = resolveInvoicePdfServeDecision({
    metadataExists: false,
    hasIssuedFiscalDocument: true,
    storageAvailable: true,
  });
  assert.equal(decision.status, 202);
  assert.equal(decision.state, "pending");
  assert.equal(decision.error, "invoice_pdf_pending");
  assert.equal(decision.retryAfterSeconds, 2);
});

test("pending after an ensure attempt that has not persisted bytes yet", () => {
  const decision = resolveInvoicePdfServeDecision({
    metadataExists: false,
    ensureAttempted: true,
    storageAvailable: true,
  });
  assert.equal(decision.status, 202);
  assert.equal(decision.state, "pending");
});

test("ready when metadata and object bytes exist", () => {
  const decision = resolveInvoicePdfServeDecision({
    metadataExists: true,
    objectFound: true,
    objectEmpty: false,
    storageAvailable: true,
  });
  assert.equal(decision.status, 200);
  assert.equal(decision.state, "ready");
  assert.equal(decision.ok, true);
});

test("permanent missing when no fiscal document and no artifact", () => {
  const decision = resolveInvoicePdfServeDecision({
    metadataExists: false,
    hasIssuedFiscalDocument: false,
    storageAvailable: true,
  });
  assert.equal(decision.status, 404);
  assert.equal(decision.error, "invoice_pdf_not_available");
  assert.equal(decision.state, "missing");
});

test("permanent missing when metadata exists but the object is gone", () => {
  const decision = resolveInvoicePdfServeDecision({
    metadataExists: true,
    objectFound: false,
    storageAvailable: true,
  });
  assert.equal(decision.status, 404);
  assert.equal(decision.error, "invoice_pdf_not_found");
});

test("upstream failure when generation failed before an artifact exists", () => {
  const decision = resolveInvoicePdfServeDecision({
    metadataExists: false,
    hasIssuedFiscalDocument: true,
    ensureFailed: true,
    storageAvailable: true,
  });
  assert.equal(decision.status, 503);
  assert.equal(decision.state, "failure");
  assert.equal(decision.error, "invoice_pdf_generation_failed");
});

test("upstream failure when storage is unavailable", () => {
  const decision = resolveInvoicePdfServeDecision({
    metadataExists: true,
    storageAvailable: false,
  });
  assert.equal(decision.status, 500);
  assert.equal(decision.error, "invoice_storage_unavailable");
});

test("JSON pending response exposes Retry-After and machine-readable state", async () => {
  const response = buildInvoicePdfStatusResponse(
    resolveInvoicePdfServeDecision({
      metadataExists: false,
      hasIssuedFiscalDocument: true,
    }),
  );
  assert.equal(response.status, 202);
  assert.equal(response.headers.get("Retry-After"), "2");
  assert.equal(
    response.headers.get("X-Fluxidi-Invoice-Artifact-State"),
    "pending",
  );
  const body = await response.json();
  assert.equal(body.ok, false);
  assert.equal(body.error, "invoice_pdf_pending");
  assert.equal(body.invoice_pdf_state, "pending");
});

test("fiscal-document detector stays identity-safe", () => {
  assert.equal(
    hasIssuedFiscalDocumentForPdf({ invoiceDocumentId: "doc_1" }),
    true,
  );
  assert.equal(
    hasIssuedFiscalDocumentForPdf({ consumerSaleDocumentId: "doc_c" }),
    true,
  );
  assert.equal(
    hasIssuedFiscalDocumentForPdf({ saleKind: "consumer_sale" }),
    true,
  );
  assert.equal(hasIssuedFiscalDocumentForPdf({}), false);
});
