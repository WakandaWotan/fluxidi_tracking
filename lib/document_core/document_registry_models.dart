// Provider-neutral Document Core lifecycle + registry DTO models (Patch 2G-B).
//
// PURE Dart only. This file intentionally has:
//   * no Flutter imports
//   * no PDF imports
//   * no network imports
//   * no provider (Billit/Peppol/Mollie) imports
//   * no dependency on main.dart
//
// IMPORTANT — SHAPE ONLY.
// These are read-only DTOs and a lifecycle enum that describe what a future
// document registry record COULD contain. This patch does NOT:
//   * allocate document numbers
//   * persist anything
//   * call any backend
//   * generate UBL/XML
//   * send anything via Peppol/Billit
//   * change PDF output, visibility gates or preflight logic
//
// Official number allocation, persistence, and idempotency MUST be backend
// authoritative when implemented. This file only fixes the in-memory shape so
// Flutter and a future backend can agree on the same vocabulary.

import 'document_core_models.dart';

/// Provider-neutral document lifecycle state.
///
/// Separate from [DocumentCoreExportState] on purpose: lifecycle describes the
/// document's accounting/issuance state, while [DocumentCoreExportState]
/// describes a draft's local/export readiness. A future registry record uses
/// this enum; the existing draft builders are NOT changed by this patch.
enum DocumentCoreLifecycleState {
  /// Local preview only; no number, no persistence.
  draftPreview,

  /// Preflight reported blocking issues; the document must not be issued.
  preflightFailed,

  /// Preflight clean and structurally complete; safe for a future backend to
  /// allocate a number and issue. NOT issued yet.
  readyToIssue,

  /// Backend has allocated an official number and stored an immutable snapshot.
  issued,

  /// A previously issued document has been voided/cancelled. The original
  /// number is never reused; a correction document supersedes it.
  voided,

  /// Issued document has been exported to a structured provider (e.g. Peppol /
  /// Billit / approved platform), awaiting acceptance.
  exportedToProvider,

  /// Provider acknowledged acceptance of the exported document.
  providerAccepted,

  /// Provider rejected the exported document. Requires a correction flow.
  providerRejected,
}

/// Provider-neutral, read-only registry DTO.
///
/// Every field is nullable when the corresponding backend data is not yet
/// available; this patch does NOT populate them anywhere. The shape exists so
/// later patches (and a future backend registry endpoint) can converge on the
/// same vocabulary without churn.
///
/// Notes:
///   * No Billit-specific or Peppol-specific fields are present. The generic
///     provider* fields can be populated by any future provider integration.
///   * [issueTimestamp] must be backend time on real issuance; this DTO does
///     not enforce that, but the field is intentionally separate from a draft
///     issue date.
///   * [contentHash] is reserved for an immutable snapshot hash of the issued
///     document content; never compute or persist it in Flutter.
class DocumentCoreRegistryRecord {
  // Identity / scoping.
  final String? tenantId;
  final String? companyId;
  final String? documentId;
  final DocumentCoreDocumentType? documentType;
  final String? documentNumber;
  final DocumentCoreLifecycleState lifecycleState;

  // Source booking context (leg-first preserved).
  final String? sourceBookingId;
  final String? sourceParentBookingId;
  final String? sourceLegId;
  final String? sourceLegType;
  final bool isLegScoped;

  // Source correction/refund context.
  final String? sourceRefundId;
  final String? sourceCreditDecision;

  // Totals snapshot (major currency units; never cents).
  final String? currency;
  final num? totalInclVat;
  final num? subtotalExVat;
  final num? vatAmount;
  final num? vatRatePercent;
  final num? creditedAmountInclVat;
  final num? refundedAmountInclVat;

  // Buyer identity snapshot at issuance time.
  final String? buyerName;
  final String? buyerLegalName;
  final String? buyerVatNumber;
  final String? buyerEmail;
  final String? buyerAddressLine;
  final String? buyerPostalCode;
  final String? buyerCity;
  final String? buyerCountryCode;

  // Seller identity snapshot at issuance time.
  final String? sellerName;
  final String? sellerLegalName;
  final String? sellerVatNumber;
  final String? sellerRegistrationNumber;
  final String? sellerEmail;
  final String? sellerAddressLine;
  final String? sellerPostalCode;
  final String? sellerCity;
  final String? sellerCountryCode;

  // Issuance / audit metadata.
  final DateTime? issueTimestamp;
  final String? createdByRole;
  final String? createdByDeviceId;
  final String? contentHash;

  // Generic, provider-neutral export metadata placeholders. Empty/null until a
  // future provider integration populates them.
  final String? providerName;
  final String? providerDocumentId;
  final String? providerExportStatus;
  final DateTime? providerAcceptedAt;
  final String? providerRejectedReason;

  /// Idempotency key for safe issuance retries. Allocated by the backend, not
  /// in Flutter.
  final String? idempotencyKey;

  const DocumentCoreRegistryRecord({
    this.tenantId,
    this.companyId,
    this.documentId,
    this.documentType,
    this.documentNumber,
    this.lifecycleState = DocumentCoreLifecycleState.draftPreview,
    this.sourceBookingId,
    this.sourceParentBookingId,
    this.sourceLegId,
    this.sourceLegType,
    this.isLegScoped = false,
    this.sourceRefundId,
    this.sourceCreditDecision,
    this.currency,
    this.totalInclVat,
    this.subtotalExVat,
    this.vatAmount,
    this.vatRatePercent,
    this.creditedAmountInclVat,
    this.refundedAmountInclVat,
    this.buyerName,
    this.buyerLegalName,
    this.buyerVatNumber,
    this.buyerEmail,
    this.buyerAddressLine,
    this.buyerPostalCode,
    this.buyerCity,
    this.buyerCountryCode,
    this.sellerName,
    this.sellerLegalName,
    this.sellerVatNumber,
    this.sellerRegistrationNumber,
    this.sellerEmail,
    this.sellerAddressLine,
    this.sellerPostalCode,
    this.sellerCity,
    this.sellerCountryCode,
    this.issueTimestamp,
    this.createdByRole,
    this.createdByDeviceId,
    this.contentHash,
    this.providerName,
    this.providerDocumentId,
    this.providerExportStatus,
    this.providerAcceptedAt,
    this.providerRejectedReason,
    this.idempotencyKey,
  });

  /// True for any state that represents an officially issued document
  /// (including post-issuance states such as voided/exported/accepted/rejected).
  bool get isOfficiallyIssued {
    switch (lifecycleState) {
      case DocumentCoreLifecycleState.issued:
      case DocumentCoreLifecycleState.voided:
      case DocumentCoreLifecycleState.exportedToProvider:
      case DocumentCoreLifecycleState.providerAccepted:
      case DocumentCoreLifecycleState.providerRejected:
        return true;
      case DocumentCoreLifecycleState.draftPreview:
      case DocumentCoreLifecycleState.preflightFailed:
      case DocumentCoreLifecycleState.readyToIssue:
        return false;
    }
  }

  /// True when an official document number has been allocated (must be
  /// backend-authoritative; never derived locally).
  bool get hasOfficialNumber =>
      documentNumber != null && documentNumber!.trim().isNotEmpty;

  /// True when the provider lifecycle has reached a final state.
  bool get isProviderFinal =>
      lifecycleState == DocumentCoreLifecycleState.providerAccepted ||
      lifecycleState == DocumentCoreLifecycleState.providerRejected;

  /// True when the record is still in a draft-like state (no official number,
  /// not issued).
  bool get isDraftLike {
    switch (lifecycleState) {
      case DocumentCoreLifecycleState.draftPreview:
      case DocumentCoreLifecycleState.preflightFailed:
      case DocumentCoreLifecycleState.readyToIssue:
        return true;
      case DocumentCoreLifecycleState.issued:
      case DocumentCoreLifecycleState.voided:
      case DocumentCoreLifecycleState.exportedToProvider:
      case DocumentCoreLifecycleState.providerAccepted:
      case DocumentCoreLifecycleState.providerRejected:
        return false;
    }
  }

  /// Credit notes require an official accounting number when issued.
  /// Refund proofs do NOT.
  bool get requiresAccountingNumber =>
      documentType == DocumentCoreDocumentType.creditNote;

  /// Refund proofs require a non-accounting proof/audit reference when issued.
  /// Credit notes do NOT use this concept.
  bool get requiresProofReference =>
      documentType == DocumentCoreDocumentType.refundProof;
}
