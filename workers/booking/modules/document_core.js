/* Fluxidi Document Core helpers (BW-M6).
 *
 * Verbatim extraction from workers/booking/fluxidi_booking_worker.js — no
 * behavior change. Only strictly-acyclic helpers were moved here:
 *
 *   - document type / prefix / sequence-type constants,
 *   - pure registry key builders,
 *   - read-only KV lookups (idempotency, registry-record-by-id, per-booking
 *     list projections),
 *   - pure replay-safe projection helpers,
 *   - pure snapshot canonicalizer / stable JSON / content hash,
 *   - DOCUMENT_REFERENCE_SEQUENCE allocator + doc_ref index + typed wrappers.
 *
 * All lifecycle orchestrators (invoice-after-paid, credit-note issue core,
 * export preview, export readiness classifier, registry write plan, billit-
 * export projection helper, etc.) intentionally REMAIN in the main worker
 * because they cross-cut into booking core, payment lifecycle, Chiron/
 * compliance, or Billit lifecycle. See BW-M6 audit report for the STOP list.
 *
 * This module is acyclic:
 *   - imports only from ./parsing_utils.js, ./crypto_utils.js and
 *     ./billit_provider.js (which itself does not import from document_core.js),
 *   - performs KV reads/writes and Durable Object calls where the original
 *     helpers already did — the WebCrypto / KV / DO surfaces used here are the
 *     same runtime surfaces exposed to Cloudflare Workers.
 */

import {
  safeStr,
  bookingReferenceScopePart,
  documentReferenceTypePart,
} from "./parsing_utils.js";
import { sha256Hex } from "./crypto_utils.js";
import { buildSafeBillitExportProjection, buildSafeBillitLinkStatusProjection } from "./billit_provider.js";

// Internal masking helper — behavior-identical clone of the main worker's
// `_bookingIntentMask` used for PII-free log lines emitted by
// listIssuedDocumentsForBooking / listIssuedDocumentRecordsForBooking. Kept
// private to this module to avoid pulling the whole booking-mask surface out
// of main; log output shape is byte-for-byte identical.
function _maskDocumentBookingId(value) {
  const raw = safeStr(value);
  if (!raw) return "";
  if (raw.length <= 6) return raw;
  return `${raw.slice(0, 3)}...${raw.slice(-3)}`;
}

/* ===================== DOCUMENT REGISTRY KEY SPACE (Patch 2G-E) =====================
 * Pure constants + key builders for the FUTURE provider-neutral document
 * registry/numbering recommended by the 2G-D audit. This block is intentionally
 * inert:
 *   - no KV reads/writes
 *   - no Durable Object calls
 *   - no number allocation
 *   - no routes / endpoints
 *   - no persistence / no behavior change
 * It only standardizes the registry key vocabulary so later patches stay
 * consistent. Scope/type segments reuse the existing normalization
 * (bookingReferenceScopePart / documentReferenceTypePart). Opaque id segments in
 * the NEW keys are normalized the same way for KV-key safety; because reads and
 * writes will both go through these builders, the normalization stays symmetric.
 */
export const DOCUMENT_TYPE_CREDIT_NOTE = "credit_note";
export const DOCUMENT_TYPE_REFUND_PROOF = "refund_proof";
// Patch 2G-W: Document Core invoice type. DRY-RUN + ADDITIVE-SHAPE only in this
// patch — there is NO real invoice issue route, NO real INV allocation, and NO
// KV persistence yet. This is the future official accounting/e-invoice (Peppol)
// document type, kept SEPARATE from the legacy FLX-YYYY-MM-#### invoice/PDF
// pipeline (renderInvoiceHtml / nextInvoiceNumber / INVOICE_KV), which this
// patch does not touch.
export const DOCUMENT_TYPE_INVOICE = "invoice";

// Human-facing reference prefixes (used ONLY by future sequence allocation).
export const DOCUMENT_PREFIX_CREDIT_NOTE = "FCN"; // Fluxidi Credit Note
export const DOCUMENT_PREFIX_REFUND_PROOF = "FRP"; // Fluxidi Refund Proof
// Patch 2G-W: Document Core invoice prefix. Real numbers will be INV-YYYY-######
// when a real allocator/issue route lands LATER; this patch only ever emits the
// fixed dry-run literal DRYRUN-INV-000000 and never allocates a real INV number.
export const DOCUMENT_PREFIX_INVOICE = "INV"; // Fluxidi Document Core Invoice

// Base sequence-type tokens for DOCUMENT_REFERENCE_SEQUENCE. Future allocation
// appends year/month, mirroring the existing invoice sequence pattern.
export const DOCUMENT_SEQUENCE_TYPE_CREDIT_NOTE = "credit_note";
export const DOCUMENT_SEQUENCE_TYPE_REFUND_PROOF = "refund_proof";
// Patch 2G-W: Document Core invoice sequence type. Its own counter, never shared
// with credit_note / refund_proof and never the legacy FLX invoice sequence.
export const DOCUMENT_SEQUENCE_TYPE_INVOICE = "invoice";

// Requires a tenant AND company scope, consistent with nextInvoiceNumber /
// allocateScopedInvoiceSequence (which throw "missing_tenant_scope").
export function documentRegistryScopeParts(scope) {
  const tenantRaw = safeStr(scope?.tenant_id ?? scope?.tenantId);
  const companyRaw = safeStr(scope?.company_id ?? scope?.companyId);
  if (!tenantRaw || !companyRaw) {
    throw new Error("missing_tenant_scope");
  }
  const tenantPart = bookingReferenceScopePart(tenantRaw, "fluxidi");
  const companyPart = bookingReferenceScopePart(companyRaw, tenantPart);
  return { tenantPart, companyPart };
}

// Normalizes an opaque id/number segment for a NEW registry key. Throws a
// descriptive "missing_<label>" error when empty.
export function documentRegistrySegment(value, label) {
  const part = bookingReferenceScopePart(value, "");
  if (!part) throw new Error(`missing_${label}`);
  return part;
}

export function documentRegistryTypePart(documentType) {
  const typePart = documentReferenceTypePart(documentType, "");
  if (!typePart) throw new Error("missing_document_type");
  return typePart;
}

// doc_registry:<tenant>:<company>:<documentId> — canonical registry record key.
export function buildDocumentRegistryKey(scope, documentId) {
  const { tenantPart, companyPart } = documentRegistryScopeParts(scope);
  const docPart = documentRegistrySegment(documentId, "document_id");
  return `doc_registry:${tenantPart}:${companyPart}:${docPart}`;
}

// doc_number_idx:<tenant>:<company>:<type>:<documentNumber> — number lookup.
export function buildDocumentNumberIndexKey(scope, documentType, documentNumber) {
  const { tenantPart, companyPart } = documentRegistryScopeParts(scope);
  const typePart = documentRegistryTypePart(documentType);
  const numberPart = documentRegistrySegment(documentNumber, "document_number");
  return `doc_number_idx:${tenantPart}:${companyPart}:${typePart}:${numberPart}`;
}

// doc_by_booking:<tenant>:<company>:<canonicalBookingId>:<type>:<documentId>
export function buildDocumentsByBookingKey(
  scope,
  canonicalBookingId,
  documentType,
  documentId,
) {
  const { tenantPart, companyPart } = documentRegistryScopeParts(scope);
  const bookingPart = documentRegistrySegment(
    canonicalBookingId,
    "canonical_booking_id",
  );
  const typePart = documentRegistryTypePart(documentType);
  const docPart = documentRegistrySegment(documentId, "document_id");
  return `doc_by_booking:${tenantPart}:${companyPart}:${bookingPart}:${typePart}:${docPart}`;
}

// doc_by_leg:<tenant>:<company>:<canonicalBookingId>:<legId>:<type>:<documentId>
// Leg-first: leg-scoped documents index under their own leg id so a roundtrip
// parent never aggregates leg documents.
export function buildDocumentsByLegKey(
  scope,
  canonicalBookingId,
  legId,
  documentType,
  documentId,
) {
  const { tenantPart, companyPart } = documentRegistryScopeParts(scope);
  const bookingPart = documentRegistrySegment(
    canonicalBookingId,
    "canonical_booking_id",
  );
  const legPart = documentRegistrySegment(legId, "leg_id");
  const typePart = documentRegistryTypePart(documentType);
  const docPart = documentRegistrySegment(documentId, "document_id");
  return `doc_by_leg:${tenantPart}:${companyPart}:${bookingPart}:${legPart}:${typePart}:${docPart}`;
}

// doc_by_refund:<tenant>:<company>:<refundId>:<documentId>
export function buildDocumentsByRefundKey(scope, refundId, documentId) {
  const { tenantPart, companyPart } = documentRegistryScopeParts(scope);
  const refundPart = documentRegistrySegment(refundId, "refund_id");
  const docPart = documentRegistrySegment(documentId, "document_id");
  return `doc_by_refund:${tenantPart}:${companyPart}:${refundPart}:${docPart}`;
}

// doc_idempotency:<tenant>:<company>:<type>:<idempotencyKey> — future issue dedup.
export function buildDocumentIdempotencyKey(scope, documentType, idempotencyKey) {
  const { tenantPart, companyPart } = documentRegistryScopeParts(scope);
  const typePart = documentRegistryTypePart(documentType);
  const idemPart = documentRegistrySegment(idempotencyKey, "idempotency_key");
  return `doc_idempotency:${tenantPart}:${companyPart}:${typePart}:${idemPart}`;
}

// doc_ref:<tenant>:<company>:<type>:<documentReference> — READ-SIDE mirror of the
// EXISTING putDocumentReferenceIndex() key. Uses the same case-preserving
// safeStr() for the reference so, for properly tenant/company-scoped input, it
// returns a byte-identical key. Do NOT normalize the reference here or it would
// diverge from the existing writes.
export function buildDocumentReferenceIndexKey(scope, sequenceType, documentReference) {
  const { tenantPart, companyPart } = documentRegistryScopeParts(scope);
  const typePart = documentReferenceTypePart(sequenceType, "");
  const reference = safeStr(documentReference);
  if (!typePart) throw new Error("missing_sequence_type");
  if (!reference) throw new Error("missing_document_reference");
  return `doc_ref:${tenantPart}:${companyPart}:${typePart}:${reference}`;
}

/* Read-only document idempotency lookup (Patch 2G-G).
 *
 * For FUTURE document issue endpoints ONLY. Idempotency MUST be checked BEFORE
 * any sequence allocation: a duplicate retry (same tenant/company + document
 * type + idempotency key) must return the already-issued document instead of
 * allocating a NEW number. This helper is intentionally inert in this patch:
 *   - read-only (one BOOKING_KV.get); no writes
 *   - no DOCUMENT_REFERENCE_SEQUENCE / Durable Object calls
 *   - no number allocation, no registry create/update, no audit events
 *   - no routes; it is not invoked from any existing runtime path.
 *
 * Returns null when not found / not resolvable, or a small neutral result when
 * found. Never throws on missing scope or malformed stored data.
 */
export async function findDocumentByIdempotency(env, scope, documentType, idempotencyKey) {
  if (!env?.BOOKING_KV) return null;

  let key;
  try {
    key = buildDocumentIdempotencyKey(scope, documentType, idempotencyKey);
  } catch (_) {
    // Missing tenant/company scope, document type, or idempotency key.
    return null;
  }

  // Read as text so a plain document_id string is tolerated as a future
  // fallback (KV { type: "json" } would throw on a non-JSON value).
  const raw = await env.BOOKING_KV.get(key);
  const stored = safeStr(raw);
  if (!stored) return null;

  let record = null;
  if (stored.startsWith("{")) {
    try {
      record = JSON.parse(stored);
    } catch (_) {
      // Tolerate malformed data: log a PII-free diagnostic and treat as miss.
      console.log(
        `[DOCUMENT_IDEMPOTENCY][PARSE_WARN] malformed json (type=${documentReferenceTypePart(documentType, "")})`,
      );
      return null;
    }
  }

  if (record && typeof record === "object") {
    const documentId = safeStr(record.document_id || record.documentId);
    if (!documentId) return null;
    return {
      document_id: documentId,
      document_number:
        safeStr(record.document_number || record.documentNumber) || null,
      proof_reference:
        safeStr(record.proof_reference || record.proofReference) || null,
      document_type:
        safeStr(record.document_type || record.documentType) ||
        safeStr(documentType) ||
        null,
      idempotent_replay: true,
    };
  }

  // Plain document_id string fallback.
  return {
    document_id: stored,
    document_number: null,
    proof_reference: null,
    document_type: safeStr(documentType) || null,
    idempotent_replay: true,
  };
}

// 2G-N-I: read-only loader for the canonical issued registry record by
// document_id. Used by the credit-note issue route's idempotent-replay branch
// so the replay response can mirror the original success contract
// (lifecycle_state / issue_timestamp / currency / content_hash) without
// re-deriving anything. Pure read: no allocation, no write, no compliance emit.
// Returns the parsed registry record object or null when missing/unreadable.
export async function loadIssuedDocumentRegistryRecordById(env, scope, documentId) {
  if (!env?.BOOKING_KV) return null;
  const safeDocumentId = safeStr(documentId, 200);
  if (!safeDocumentId) return null;
  let key;
  try {
    key = buildDocumentRegistryKey(scope, safeDocumentId);
  } catch (_) {
    return null;
  }
  let record = null;
  try {
    record = await env.BOOKING_KV.get(key, { type: "json" });
  } catch (_) {
    return null;
  }
  if (!record || typeof record !== "object" || Array.isArray(record)) return null;
  return record;
}

// 2G-N-I: build the safe public replay field set from the idempotency hit and
// (optionally) the canonical registry record. Mirrors the original success
// response contract for POST /admin/documents/credit-note/issue. Any field that
// is genuinely absent on an older stored record is returned as null rather than
// guessed. No PII (buyer/seller snapshots) is ever surfaced here.
export function buildCreditNoteReplaySafeFields(idemHit, registryRecord) {
  const rec =
    registryRecord && typeof registryRecord === "object" ? registryRecord : {};
  const documentId =
    safeStr(idemHit?.document_id, 200) ||
    safeStr(rec.document_id ?? rec.documentId, 200) ||
    null;
  const documentNumber =
    safeStr(idemHit?.document_number, 80) ||
    safeStr(rec.document_number ?? rec.documentNumber, 80) ||
    null;
  const lifecycleState =
    safeStr(rec.lifecycle_state ?? rec.lifecycleState ?? rec.document_status, 40) ||
    null;
  const issueTimestamp =
    safeStr(rec.issue_timestamp ?? rec.issueTimestamp, 80) || null;
  const currency = safeStr(rec.currency, 8).toUpperCase() || null;
  const contentHash = safeStr(rec.content_hash ?? rec.contentHash, 128) || null;
  return {
    document_id: documentId,
    document_number: documentNumber,
    lifecycle_state: lifecycleState,
    issue_timestamp: issueTimestamp,
    currency,
    content_hash: contentHash,
  };
}

// R2 — Refund-proof analogue of buildCreditNoteReplaySafeFields. Returned to
// the issue-route replay branch so an idempotent retry surfaces the SAME safe
// public envelope the original issue did, without surfacing buyer/seller PII
// or the immutable snapshot. Mirrors the credit-note shape but uses
// proof_reference (FRP-*) instead of document_number, and additionally exposes
// the refund-proof–specific source fields (source_refund_id, source_leg_*).
// Absent fields on older stored records stay null rather than being guessed.
export function buildRefundProofReplaySafeFields(idemHit, registryRecord) {
  const rec =
    registryRecord && typeof registryRecord === "object" ? registryRecord : {};
  const documentId =
    safeStr(idemHit?.document_id, 200) ||
    safeStr(rec.document_id ?? rec.documentId, 200) ||
    null;
  const proofReference =
    safeStr(idemHit?.proof_reference, 80) ||
    safeStr(rec.proof_reference ?? rec.proofReference, 80) ||
    null;
  const lifecycleState =
    safeStr(rec.lifecycle_state ?? rec.lifecycleState ?? rec.document_status, 40) ||
    null;
  const issueTimestamp =
    safeStr(rec.issue_timestamp ?? rec.issueTimestamp, 80) || null;
  const currency = safeStr(rec.currency, 8).toUpperCase() || null;
  const contentHash = safeStr(rec.content_hash ?? rec.contentHash, 128) || null;
  const sourceBookingId =
    safeStr(rec.source_booking_id ?? rec.sourceBookingId, 200) || null;
  const sourceLegId =
    safeStr(rec.source_leg_id ?? rec.sourceLegId, 200) || null;
  const sourceLegType =
    safeStr(rec.source_leg_type ?? rec.sourceLegType, 24) || null;
  const sourceRefundId =
    safeStr(rec.source_refund_id ?? rec.sourceRefundId, 200) || null;
  return {
    document_id: documentId,
    proof_reference: proofReference,
    lifecycle_state: lifecycleState,
    issue_timestamp: issueTimestamp,
    currency,
    content_hash: contentHash,
    source_booking_id: sourceBookingId,
    source_leg_id: sourceLegId,
    source_leg_type: sourceLegType,
    source_refund_id: sourceRefundId,
  };
}

// 2G-Y-A — Invoice analogue of buildCreditNoteReplaySafeFields. Returned to the
// invoice issue-route replay branch so an idempotent retry surfaces the SAME
// safe public envelope the original issue did, without surfacing buyer/seller
// PII or the immutable snapshot. Uses document_number (INV-*) like credit_note,
// and additionally exposes the source binding (source_booking_id / source_leg_*)
// the invoice success response returns. Absent fields on older stored records
// stay null rather than being guessed.
export function buildInvoiceReplaySafeFields(idemHit, registryRecord) {
  const rec =
    registryRecord && typeof registryRecord === "object" ? registryRecord : {};
  const documentId =
    safeStr(idemHit?.document_id, 200) ||
    safeStr(rec.document_id ?? rec.documentId, 200) ||
    null;
  const documentNumber =
    safeStr(idemHit?.document_number, 80) ||
    safeStr(rec.document_number ?? rec.documentNumber, 80) ||
    null;
  const lifecycleState =
    safeStr(rec.lifecycle_state ?? rec.lifecycleState ?? rec.document_status, 40) ||
    null;
  const issueTimestamp =
    safeStr(rec.issue_timestamp ?? rec.issueTimestamp, 80) || null;
  const currency = safeStr(rec.currency, 8).toUpperCase() || null;
  const contentHash = safeStr(rec.content_hash ?? rec.contentHash, 128) || null;
  const sourceBookingId =
    safeStr(rec.source_booking_id ?? rec.sourceBookingId, 200) || null;
  const sourceLegId =
    safeStr(rec.source_leg_id ?? rec.sourceLegId, 200) || null;
  const sourceLegType =
    safeStr(rec.source_leg_type ?? rec.sourceLegType, 24) || null;
  return {
    document_id: documentId,
    document_number: documentNumber,
    lifecycle_state: lifecycleState,
    issue_timestamp: issueTimestamp,
    currency,
    content_hash: contentHash,
    source_booking_id: sourceBookingId,
    source_leg_id: sourceLegId,
    source_leg_type: sourceLegType,
  };
}

// DOCUMENT-PRESENTATION-CONTRACT-P0C: derive additive fiscal/presentation
// fields from an issued registry record. Never invents a second identity,
// never exposes idempotency keys, and never rewrites stored documents.
export function deriveIssuedDocumentPresentationContract(record) {
  const rec = record && typeof record === "object" ? record : {};
  const documentId = safeStr(rec.document_id ?? rec.documentId, 200) || "";
  const saleKind = safeStr(
    rec.fluxidi_sale_kind ?? rec.fluxidiSaleKind ?? rec.sale_kind ?? rec.saleKind,
    40,
  ).toLowerCase();
  const documentType = safeStr(
    rec.document_type ?? rec.documentType,
    40,
  ).toLowerCase();
  const invoiceIntent = safeStr(
    rec.invoice_intent ?? rec.invoiceIntent,
    40,
  ).toLowerCase();
  const createdByRole = safeStr(
    rec.created_by_role ?? rec.createdByRole,
    64,
  ).toLowerCase();
  const lifecycle = safeStr(
    rec.lifecycle_state ?? rec.lifecycleState,
    40,
  ).toLowerCase();
  const billingCustomerType = safeStr(
    rec.billing_customer_type ??
      rec.billingCustomerType ??
      rec.billing_customer_snapshot?.customer_type ??
      rec.billingCustomerSnapshot?.customer_type,
    40,
  ).toLowerCase();
  const superseded =
    rec.superseded === true ||
    rec.active_revenue === false ||
    lifecycle === "superseded";
  const voided =
    lifecycle === "void" ||
    lifecycle === "voided" ||
    lifecycle === "cancelled" ||
    lifecycle === "canceled" ||
    lifecycle === "credited";
  const isCredit =
    saleKind === "credit_note" ||
    saleKind === "creditnote" ||
    saleKind === "consumer_conversion_credit" ||
    documentType === "credit_note" ||
    documentType === "creditnote";
  const isConsumer =
    saleKind === "consumer_sale" ||
    saleKind === "private_sale" ||
    saleKind === "particuliere_verkoop" ||
    saleKind === "ritbon" ||
    createdByRole === "system_consumer_sale" ||
    createdByRole.includes("consumer_sale") ||
    billingCustomerType === "private" ||
    billingCustomerType === "consumer" ||
    documentType === "refund_proof";
  const explicitBusiness =
    saleKind === "business_invoice" ||
    saleKind === "zakelijke_factuur" ||
    invoiceIntent === "business_invoice" ||
    invoiceIntent === "business";
  let fiscalKind = "unspecified";
  let presentationLabelKey = "invoiceNeutral";
  let consumerSale = false;
  let explicitBusinessInvoice = false;
  let peppolApplicable = null;
  if (isCredit) {
    fiscalKind = "credit_note";
    presentationLabelKey = "creditNote";
    peppolApplicable = false;
  } else if (isConsumer && !explicitBusiness) {
    fiscalKind = "consumer_sale";
    presentationLabelKey =
      documentType === "refund_proof" ? "refundProof" : "consumerSale";
    consumerSale = true;
    peppolApplicable = false;
  } else if (explicitBusiness) {
    fiscalKind = "business_invoice";
    presentationLabelKey = "invoice";
    explicitBusinessInvoice = true;
    if (rec.peppol_applicable === false || rec.peppolApplicable === false) {
      peppolApplicable = false;
    } else {
      peppolApplicable = true;
    }
  } else if (documentType === "invoice") {
    fiscalKind = "unspecified";
    presentationLabelKey = "invoiceNeutral";
    peppolApplicable = null;
  }
  if (rec.peppol_applicable === true || rec.peppolApplicable === true) {
    peppolApplicable = true;
  } else if (rec.peppol_applicable === false || rec.peppolApplicable === false) {
    peppolApplicable = false;
  }
  const activePayableRevenue =
    !superseded &&
    !voided &&
    !isCredit &&
    (fiscalKind === "consumer_sale" ||
      fiscalKind === "business_invoice" ||
      fiscalKind === "unspecified");
  return {
    fiscal_kind: fiscalKind,
    fiscal_role: fiscalKind,
    consumer_sale: consumerSale === true,
    explicit_business_invoice: explicitBusinessInvoice === true,
    peppol_applicable: peppolApplicable,
    presentation_label_key: presentationLabelKey,
    fiscal_identity: documentId || null,
    active_payable_revenue: activePayableRevenue === true,
    superseded: superseded === true,
  };
}

export function projectIssuedDocumentsListEnvelope(documents) {
  const rows = Array.isArray(documents) ? documents : [];
  let activePayableCount = 0;
  for (const row of rows) {
    if (row && row.active_payable_revenue === true) activePayableCount += 1;
  }
  return {
    documents: rows,
    count: rows.length,
    active_payable_count: activePayableCount,
    review_required: activePayableCount > 1,
  };
}

// 2G-O: build the safe public metadata projection of a canonical issued
// registry record for GET /admin/documents/:documentId. Surfaces ONLY
// non-sensitive document/reference metadata. Never exposes buyer/seller
// snapshots, names, emails, phones, addresses, IBANs, idempotency keys,
// provider tokens, the immutable snapshot, or the raw registry object. Absent
// fields are returned as null rather than guessed.
export function buildIssuedDocumentPublicMetadata(record) {
  const rec = record && typeof record === "object" ? record : {};
  const derived = deriveIssuedDocumentPresentationContract(rec);
  // CONSUMER-SALE-DOCUMENT-PRESENTATION-P0-1: project Fluxidi sale presentation
  // fields so the company Documents UI never falls back to "Factuur"/Peppol
  // solely because Billit OrderType is Invoice.
  const saleKind =
    safeStr(
      rec.fluxidi_sale_kind ?? rec.fluxidiSaleKind ?? rec.sale_kind ?? rec.saleKind,
      40,
    ) || null;
  const invoiceIntent =
    safeStr(rec.invoice_intent ?? rec.invoiceIntent, 40) || null;
  const createdByRole =
    safeStr(rec.created_by_role ?? rec.createdByRole, 64) || null;
  return {
    document_id: safeStr(rec.document_id ?? rec.documentId, 200) || null,
    document_type: safeStr(rec.document_type ?? rec.documentType, 40) || null,
    document_number: safeStr(rec.document_number ?? rec.documentNumber, 80) || null,
    proof_reference: safeStr(rec.proof_reference ?? rec.proofReference, 80) || null,
    lifecycle_state:
      safeStr(rec.lifecycle_state ?? rec.lifecycleState, 40) || null,
    document_status:
      safeStr(rec.document_status ?? rec.documentStatus, 40) || null,
    issue_timestamp: safeStr(rec.issue_timestamp ?? rec.issueTimestamp, 80) || null,
    currency: safeStr(rec.currency, 8).toUpperCase() || null,
    content_hash: safeStr(rec.content_hash ?? rec.contentHash, 128) || null,
    source_booking_id:
      safeStr(rec.source_booking_id ?? rec.sourceBookingId, 200) || null,
    source_leg_id: safeStr(rec.source_leg_id ?? rec.sourceLegId, 200) || null,
    source_leg_type: safeStr(rec.source_leg_type ?? rec.sourceLegType, 24) || null,
    fluxidi_sale_kind: saleKind,
    sale_kind: saleKind,
    presentation_label_key: derived.presentation_label_key,
    invoice_intent: invoiceIntent,
    created_by_role: createdByRole,
    peppol_applicable: derived.peppol_applicable,
    superseded: derived.superseded === true,
    fiscal_kind: derived.fiscal_kind,
    fiscal_role: derived.fiscal_role,
    consumer_sale: derived.consumer_sale === true,
    explicit_business_invoice: derived.explicit_business_invoice === true,
    fiscal_identity: derived.fiscal_identity,
    active_payable_revenue: derived.active_payable_revenue === true,
    // B6b: safe Billit export link projection (envelope-only; null when absent).
    // Never exposes tokens, the raw OAuth record, or the raw Billit response.
    billit_export: buildSafeBillitExportProjection(rec),
    // RELEASE-P0: durable pre-link / attempt status (safe; no secrets).
    billit_link_status: buildSafeBillitLinkStatusProjection(rec),
  };
}

// 2G-R: normalize a booking identifier for canonical-booking equality checks.
// Trims and strips any trailing operational-leg suffix (":OUTBOUND" / ":RETURN"
// or any ":<LEG>") so a leg id and its parent canonical booking compare equal.
// Performs NO fuzzy matching beyond canonical-booking equality.
export function _normalizeCanonicalBookingIdForMatch(value) {
  const base = safeStr(value, 200);
  if (!base) return "";
  const colon = base.indexOf(":");
  return colon > 0 ? base.slice(0, colon) : base;
}

// 2G-P: scoped prefix for the per-booking document index written at issue time
// (doc_by_booking:<tenant>:<company>:<bookingPart>:<type>:<documentId>). Pure
// key-string builder — performs no I/O. Throws missing_<field> on bad scope.
export function buildDocumentsByBookingPrefix(scope, canonicalBookingId) {
  const { tenantPart, companyPart } = documentRegistryScopeParts(scope);
  const bookingPart = documentRegistrySegment(
    canonicalBookingId,
    "canonical_booking_id",
  );
  return `doc_by_booking:${tenantPart}:${companyPart}:${bookingPart}:`;
}

// 2G-P: read-only listing of issued document metadata for one booking. Uses the
// existing scoped doc_by_booking index (no scan of unrelated keys, no writes).
// For each index entry it loads the canonical registry record and projects only
// the safe public metadata (buildIssuedDocumentPublicMetadata). Cross-tenant
// records are skipped defensively. Never allocates, writes, or emits events.
export async function listIssuedDocumentsForBooking(env, scope, canonicalBookingId) {
  if (!env?.BOOKING_KV) return { ok: false, error: "missing_binding" };
  let prefix;
  try {
    prefix = buildDocumentsByBookingPrefix(scope, canonicalBookingId);
  } catch (_) {
    return { ok: false, error: "missing_tenant_scope" };
  }
  const requestedCanonical = _normalizeCanonicalBookingIdForMatch(
    canonicalBookingId,
  );
  const seenDocumentIds = new Set();
  const documents = [];
  let staleSkippedCount = 0;
  let cursor = undefined;
  do {
    const listed = await env.BOOKING_KV.list({ prefix, limit: 1000, cursor });
    const keys = Array.isArray(listed?.keys) ? listed.keys : [];
    for (const item of keys) {
      const key = safeStr(item?.name, 320);
      if (!key || !key.startsWith(prefix)) continue;
      // The index value is the documentId; fall back to the trailing key
      // segment if the value is somehow empty.
      let documentId = safeStr(await env.BOOKING_KV.get(key), 200);
      if (!documentId) {
        const parts = key.split(":");
        documentId = safeStr(parts[parts.length - 1], 200);
      }
      if (!documentId || seenDocumentIds.has(documentId)) continue;
      seenDocumentIds.add(documentId);
      const record = await loadIssuedDocumentRegistryRecordById(
        env,
        scope,
        documentId,
      );
      if (!record) continue;
      const recTenant = safeStr(record?.tenant_id ?? record?.tenantId, 80);
      const recCompany = safeStr(record?.company_id ?? record?.companyId, 80);
      // TRUSTED-IDENTITY-P0: missing ownership fields must not authorize
      // cross-tenant lookup — fail closed on ambiguous registry rows.
      if (!recTenant || !recCompany) {
        continue;
      }
      if (recTenant !== scope.tenant_id || recCompany !== scope.company_id) {
        continue;
      }
      // 2G-R: defensive source-booking binding check. A stale or mis-indexed
      // doc_by_booking entry could surface a document whose stored source
      // booking is NOT the requested booking. buildIssuedDocumentRegistryRecord
      // ALWAYS persists source_booking_id at issue time, so a record that is
      // missing both source_booking_id and source_parent_booking_id is treated
      // as untrustworthy and skipped (conservative). Comparison is strict
      // canonical-booking equality (leg suffix stripped on both sides); tenant/
      // company matching above is NOT loosened by this check.
      const recordSourceBookingId =
        safeStr(record?.source_booking_id ?? record?.sourceBookingId, 200) ||
        safeStr(
          record?.source_parent_booking_id ?? record?.sourceParentBookingId,
          200,
        );
      const normalizedRecordSource = _normalizeCanonicalBookingIdForMatch(
        recordSourceBookingId,
      );
      if (
        !normalizedRecordSource ||
        normalizedRecordSource !== requestedCanonical
      ) {
        staleSkippedCount += 1;
        const docMask = documentId.slice(0, 8);
        console.log(
          `[DOCUMENT_LIST][STALE_INDEX_SKIP] requested=${_maskDocumentBookingId(canonicalBookingId)} doc=${docMask} reason=source_booking_mismatch`,
        );
        continue;
      }
      documents.push(buildIssuedDocumentPublicMetadata(record));
    }
    cursor = listed?.list_complete ? undefined : listed?.cursor;
  } while (cursor);
  const warnings = [];
  if (staleSkippedCount > 0) {
    warnings.push("stale_document_index_entry_skipped");
  }
  const projected = projectIssuedDocumentsListEnvelope(documents);
  return {
    ok: true,
    documents: projected.documents,
    warnings,
    active_payable_count: projected.active_payable_count,
    review_required: projected.review_required === true,
  };
}

/* 2G-T — read-only list of issued document REGISTRY RECORDS for one booking.
 *
 * Sibling of `listIssuedDocumentsForBooking` (which projects safe public
 * metadata). The metadata projection intentionally omits buyer_snapshot /
 * seller_snapshot (PII) — fine for the public list route, but the export-
 * readiness classifier needs those fields to evaluate customer/business
 * identity completeness without fabricating data. This helper therefore
 * yields the FULL canonical registry record per match.
 *
 * Same iteration shape, same defensive guards, same masked log line family
 * — only the projection differs:
 *   - same scoped `doc_by_booking:` prefix (no broad scan)
 *   - same tenant/company cross-check (cross-tenant rows skipped silently)
 *   - same 2G-R `source_booking_id` defensive equality (stale index skipped)
 *   - same `seenDocumentIds` dedup
 *
 * READ-ONLY: no `BOOKING_KV.put/delete`, no allocation, no DO call, no
 * compliance event emit, no Mollie/Chiron/Peppol/Billit network call.
 * Safe to call repeatedly; never affects any existing route.
 */
export async function listIssuedDocumentRecordsForBooking(
  env,
  scope,
  canonicalBookingId,
) {
  if (!env?.BOOKING_KV) return { ok: false, error: "missing_binding" };
  let prefix;
  try {
    prefix = buildDocumentsByBookingPrefix(scope, canonicalBookingId);
  } catch (_) {
    return { ok: false, error: "missing_tenant_scope" };
  }
  const requestedCanonical = _normalizeCanonicalBookingIdForMatch(
    canonicalBookingId,
  );
  const seenDocumentIds = new Set();
  const records = [];
  let staleSkippedCount = 0;
  let cursor = undefined;
  do {
    const listed = await env.BOOKING_KV.list({ prefix, limit: 1000, cursor });
    const keys = Array.isArray(listed?.keys) ? listed.keys : [];
    for (const item of keys) {
      const key = safeStr(item?.name, 320);
      if (!key || !key.startsWith(prefix)) continue;
      let documentId = safeStr(await env.BOOKING_KV.get(key), 200);
      if (!documentId) {
        const parts = key.split(":");
        documentId = safeStr(parts[parts.length - 1], 200);
      }
      if (!documentId || seenDocumentIds.has(documentId)) continue;
      seenDocumentIds.add(documentId);
      const record = await loadIssuedDocumentRegistryRecordById(
        env,
        scope,
        documentId,
      );
      if (!record) continue;
      const recTenant = safeStr(record?.tenant_id ?? record?.tenantId, 80);
      const recCompany = safeStr(record?.company_id ?? record?.companyId, 80);
      // TRUSTED-IDENTITY-P0: missing ownership fields must not authorize
      // cross-tenant lookup — fail closed on ambiguous registry rows.
      if (!recTenant || !recCompany) {
        continue;
      }
      if (recTenant !== scope.tenant_id || recCompany !== scope.company_id) {
        continue;
      }
      const recordSourceBookingId =
        safeStr(record?.source_booking_id ?? record?.sourceBookingId, 200) ||
        safeStr(
          record?.source_parent_booking_id ?? record?.sourceParentBookingId,
          200,
        );
      const normalizedRecordSource = _normalizeCanonicalBookingIdForMatch(
        recordSourceBookingId,
      );
      if (
        !normalizedRecordSource ||
        normalizedRecordSource !== requestedCanonical
      ) {
        staleSkippedCount += 1;
        const docMask = documentId.slice(0, 8);
        console.log(
          `[DOCUMENT_EXPORT_READINESS][STALE_INDEX_SKIP] requested=${_maskDocumentBookingId(canonicalBookingId)} doc=${docMask} reason=source_booking_mismatch`,
        );
        continue;
      }
      records.push(record);
    }
    cursor = listed?.list_complete ? undefined : listed?.cursor;
  } while (cursor);
  const warnings = [];
  if (staleSkippedCount > 0) {
    warnings.push("stale_document_index_entry_skipped");
  }
  return { ok: true, records, warnings };
}

/* 2G-V — pure source-invoice-reference reader for Document Core.
 *
 * Read-only / inert. Conservatively probes the EXISTING canonical registry
 * record for a safe parent-invoice / original-invoice reference. Used by
 * BOTH `classifyDocumentExportReadiness` (Peppol gate for credit-note) AND
 * `buildDocumentExportPreview` (provider-neutral preview's
 * `source_binding.source_invoice_reference`) so the two flows agree.
 *
 * Purity / inertness contract:
 *   - no KV read/write, no DO call, no allocation, no compliance event,
 *     no Billit/Peppol/Mollie/Chiron network call,
 *   - never mutates the input record,
 *   - never invents data: only fields already present on the record are
 *     considered; absent → empty string,
 *   - never gates an existing issue/replay/list/preview/readiness/lookup/
 *     dry-run route.
 *
 * Candidate field order (first non-empty wins). All paths are top-level on
 * the registry envelope OR on a single nested `source_invoice` / `sourceInvoice`
 * object — no deep walks, no payload/booking/quote probing.
 */
export function getDocumentSourceInvoiceReference(record) {
  const rec = record && typeof record === "object" && !Array.isArray(record)
    ? record
    : {};
  const candidates = [
    rec.source_invoice_reference,
    rec.sourceInvoiceReference,
    rec.source_invoice_number,
    rec.sourceInvoiceNumber,
    rec.source_invoice_document_number,
    rec.sourceInvoiceDocumentNumber,
    rec.original_invoice_reference,
    rec.originalInvoiceReference,
    rec.credited_invoice_reference,
    rec.creditedInvoiceReference,
  ];
  // Nested `source_invoice` / `sourceInvoice` object — only the well-known
  // `number` / `reference` / `id` fields, never an arbitrary object spread.
  const nestedSnake =
    rec.source_invoice && typeof rec.source_invoice === "object" && !Array.isArray(rec.source_invoice)
      ? rec.source_invoice
      : null;
  const nestedCamel =
    rec.sourceInvoice && typeof rec.sourceInvoice === "object" && !Array.isArray(rec.sourceInvoice)
      ? rec.sourceInvoice
      : null;
  if (nestedSnake) {
    candidates.push(
      nestedSnake.number,
      nestedSnake.reference,
      nestedSnake.document_number,
      nestedSnake.documentNumber,
      nestedSnake.id,
    );
  }
  if (nestedCamel) {
    candidates.push(
      nestedCamel.number,
      nestedCamel.reference,
      nestedCamel.document_number,
      nestedCamel.documentNumber,
      nestedCamel.id,
    );
  }
  for (const candidate of candidates) {
    const value = safeStr(candidate, 80);
    if (value) return value;
  }
  return "";
}

/* Pure document snapshot canonicalizer + content hash (Patch 2G-I).
 *
 * For FUTURE issued (immutable) document snapshots ONLY. When a document is
 * issued, the backend freezes a snapshot together with its issue timestamp,
 * document reference and document number, then stores a content_hash so the
 * snapshot can later be verified as unchanged. These helpers are PURE and inert:
 *   - no KV read/write, no DOCUMENT_REFERENCE_SEQUENCE, no allocation
 *   - no registry records, no idempotency keys, no compliance events, no routes
 *   - not invoked anywhere in this patch.
 *
 * Rules for the future caller:
 *   - content_hash MUST be computed AFTER the backend issue timestamp /
 *     reference / number are known (they are part of the snapshot input).
 *   - An issued snapshot's hash MUST NOT be recalculated from mutable booking
 *     data later — persist the canonical JSON + hash at issue time and treat
 *     them as immutable.
 *   - These helpers do NOT allocate numbers and do NOT persist anything.
 *
 * Example (SHAPE ONLY — not runtime data) of a future snapshot input:
 *   {
 *     document_type, document_number, document_reference, issued_at,
 *     tenant_id, company_id, canonical_booking_id, leg_id,
 *     seller: {...}, buyer: {...}, totals: {...}, lines: [...]
 *   }
 */

// Recursively normalizes a snapshot into a deterministic structure: object keys
// sorted, arrays kept in order, `undefined` omitted (object keys) or coerced to
// null (array slots), `null` preserved. Does NOT mutate the input.
export function canonicalizeDocumentSnapshot(snapshot) {
  const normalize = (value) => {
    if (value === null) return null;
    if (Array.isArray(value)) {
      // Arrays keep their order; undefined slots become null for determinism.
      return value.map((item) =>
        item === undefined ? null : normalize(item),
      );
    }
    if (typeof value === "object") {
      const out = {};
      for (const key of Object.keys(value).sort()) {
        const child = normalize(value[key]);
        // Omit undefined-valued keys so output is stable regardless of input.
        if (child !== undefined) out[key] = child;
      }
      return out;
    }
    // Primitives pass through unchanged (undefined stays undefined → omitted).
    return value;
  };
  const root = normalize(snapshot);
  // A top-level undefined/primitive snapshot still canonicalizes consistently.
  return root === undefined ? null : root;
}

// Deterministic JSON string for a snapshot (stable, recursively-sorted keys).
export function stableDocumentJson(value) {
  return JSON.stringify(canonicalizeDocumentSnapshot(value));
}

// SHA-256 (lowercase hex) over the canonical JSON. Reuses the shared
// sha256Hex() crypto helper. Async because crypto.subtle.digest is async.
export async function hashDocumentSnapshot(snapshot) {
  return sha256Hex(stableDocumentJson(snapshot));
}
