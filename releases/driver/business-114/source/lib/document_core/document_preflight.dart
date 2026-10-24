// Provider-neutral Document Core preflight validation (Patch 2F-A).
//
// PURE Dart only. This file intentionally has:
//   * no Flutter imports
//   * no PDF imports
//   * no network imports
//   * no provider (Billit/Peppol/Mollie) imports
//   * no dependency on main.dart
//
// It is a non-destructive read of a provider-neutral draft:
//   * no writes / no persistence
//   * no backend calls
//   * no document numbering / no registry
//   * no UBL/XML
//   * no send/share side effects
//
// It only inspects an already-built draft and reports blocking issues and
// warnings so the caller can decide whether it is safe to render a local PDF.

import 'document_core_models.dart';

/// Severity of a single preflight finding.
enum DocumentPreflightSeverity { warning, blocking }

/// A single, provider-neutral preflight finding. [code] is a stable,
/// PII-free token (e.g. `missing_original_amount`).
class DocumentPreflightIssue {
  final String code;
  final DocumentPreflightSeverity severity;

  const DocumentPreflightIssue(this.code, this.severity);

  const DocumentPreflightIssue.blocking(this.code)
    : severity = DocumentPreflightSeverity.blocking;

  const DocumentPreflightIssue.warning(this.code)
    : severity = DocumentPreflightSeverity.warning;

  bool get isBlocking => severity == DocumentPreflightSeverity.blocking;
}

/// Aggregated preflight outcome for a single document draft.
class DocumentPreflightResult {
  final List<DocumentPreflightIssue> issues;

  const DocumentPreflightResult(this.issues);

  List<DocumentPreflightIssue> get blockingIssues =>
      issues.where((i) => i.isBlocking).toList(growable: false);

  List<DocumentPreflightIssue> get warnings =>
      issues.where((i) => !i.isBlocking).toList(growable: false);

  /// True when at least one blocking issue exists; the PDF must not open.
  bool get isBlocked => issues.any((i) => i.isBlocking);

  bool get hasWarnings => issues.any((i) => !i.isBlocking);

  String get blockingCodes => blockingIssues.map((i) => i.code).join(',');

  String get warningCodes => warnings.map((i) => i.code).join(',');

  /// PII-free one-line diagnostic for debug logs.
  String get diagnostic =>
      'blocked=$isBlocked blocking=[$blockingCodes] warnings=[$warningCodes]';
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

bool _hasIdentity(DocumentCoreReferenceContext refs) =>
    _hasText(refs.bookingId) || _hasText(refs.bookingReference);

bool _isPositive(num? value) => value != null && value > 0;

/// Patch 2G-C: non-blocking tenant/company scope warnings. These never block a
/// local PDF preview; they only surface PII-free diagnostic codes so a future
/// registry/numbering layer can detect missing scope early.
void _addCompanyScopeWarnings(
  List<DocumentPreflightIssue> issues,
  DocumentCoreCompanyScopeSnapshot scope,
) {
  if (!scope.hasTenantId) {
    issues.add(const DocumentPreflightIssue.warning('missing_tenant_id'));
  }
  if (!scope.hasCompanyId) {
    issues.add(const DocumentPreflightIssue.warning('missing_company_id'));
  }
}

/// Validates a provider-neutral credit note draft before local PDF rendering.
///
/// [creditContextValid] is computed by the caller from existing visibility
/// helpers (cancelled + paid + an effective credit/refund correction), so this
/// pure validator does not duplicate that business logic.
DocumentPreflightResult validateCreditNoteDraft(
  DocumentCoreCreditNoteDraft draft, {
  required bool creditContextValid,
}) {
  final issues = <DocumentPreflightIssue>[];
  final refs = draft.references;
  final totals = draft.totals;

  // Blocking: cannot make a safe correction document without these.
  if (!_hasIdentity(refs)) {
    issues.add(
      const DocumentPreflightIssue.blocking('missing_booking_identity'),
    );
  }
  if (!creditContextValid) {
    issues.add(const DocumentPreflightIssue.blocking('credit_context_invalid'));
  }
  if (!_isPositive(totals.totalInclVat)) {
    issues.add(
      const DocumentPreflightIssue.blocking('missing_original_amount'),
    );
  }
  // Blocking (Patch 2F-A.1): a credit note must display an effective credited
  // amount > 0. [totals.creditedAmountInclVat] mirrors exactly what the PDF
  // renders: the credit note builder sets it to `creditedAmountCents / 100`
  // only when `creditedAmountCents > 0` (otherwise null), and the PDF only
  // renders the "credited amount" row under that same condition. Neither the
  // builder nor the PDF derives this value from any other (leg/refund/credit)
  // amount, so there is no safe fallback: a missing, zero, or negative value
  // means no credited amount would be shown and the preview must not open.
  if (!_isPositive(totals.creditedAmountInclVat)) {
    issues.add(
      const DocumentPreflightIssue.blocking('missing_credited_amount'),
    );
  }
  // Leg-first structural guard: a leg-scoped draft must keep the parent as
  // context only, so the parent total is never used as the leg amount.
  if (refs.isLegScoped && !refs.isParentContextOnly) {
    issues.add(const DocumentPreflightIssue.blocking('leg_first_violation'));
  }

  // Warnings: document can still be generated safely with existing fallbacks.
  if (!totals.hasVatBreakdown) {
    issues.add(const DocumentPreflightIssue.warning('vat_breakdown_missing'));
  }
  if (!_hasText(draft.buyer.name)) {
    issues.add(const DocumentPreflightIssue.warning('customer_name_missing'));
  }
  if (!_hasText(draft.seller.name)) {
    issues.add(
      const DocumentPreflightIssue.warning('seller_company_name_missing'),
    );
  }
  if (!_hasText(draft.seller.vatNumber)) {
    issues.add(const DocumentPreflightIssue.warning('seller_vat_missing'));
  }
  if (refs.isLegScoped) {
    if (!_hasText(refs.legType)) {
      issues.add(const DocumentPreflightIssue.warning('leg_type_missing'));
    }
    if (!_hasText(refs.parentBookingReference) &&
        !_hasText(refs.parentBookingId)) {
      issues.add(
        const DocumentPreflightIssue.warning('parent_reference_missing'),
      );
    }
  }
  _addCompanyScopeWarnings(issues, draft.companyScope);

  return DocumentPreflightResult(
    List<DocumentPreflightIssue>.unmodifiable(issues),
  );
}

/// Validates a provider-neutral refund proof draft before local PDF rendering.
///
/// [refundLifecycleRefunded] is computed by the caller from the existing refund
/// lifecycle helper; a missing refund id is a warning (never blocking) per
/// product requirements.
DocumentPreflightResult validateRefundProofDraft(
  DocumentCoreRefundProofDraft draft, {
  required bool refundLifecycleRefunded,
}) {
  final issues = <DocumentPreflightIssue>[];
  final refs = draft.references;
  final totals = draft.totals;

  // Blocking: a refund proof must reference a refunded, identifiable amount.
  if (!_hasIdentity(refs)) {
    issues.add(
      const DocumentPreflightIssue.blocking('missing_booking_identity'),
    );
  }
  if (!refundLifecycleRefunded) {
    issues.add(const DocumentPreflightIssue.blocking('refund_not_finalized'));
  }
  if (!_isPositive(totals.refundedAmountInclVat)) {
    issues.add(
      const DocumentPreflightIssue.blocking('missing_refunded_amount'),
    );
  }
  if (refs.isLegScoped && !refs.isParentContextOnly) {
    issues.add(const DocumentPreflightIssue.blocking('leg_first_violation'));
  }

  // Warnings: optional evidence fields with safe omission in the PDF.
  if (!_hasText(draft.refundStatus)) {
    issues.add(const DocumentPreflightIssue.warning('refund_status_missing'));
  }
  if (!_hasText(draft.refundProvider)) {
    issues.add(const DocumentPreflightIssue.warning('refund_provider_missing'));
  }
  if (!_hasText(draft.refundId)) {
    issues.add(const DocumentPreflightIssue.warning('refund_id_missing'));
  }
  if (draft.refundedAt == null) {
    issues.add(const DocumentPreflightIssue.warning('refunded_at_missing'));
  }
  if (!_hasText(draft.buyer.name)) {
    issues.add(const DocumentPreflightIssue.warning('customer_name_missing'));
  }
  if (!_hasText(draft.seller.name)) {
    issues.add(
      const DocumentPreflightIssue.warning('seller_company_name_missing'),
    );
  }
  if (refs.isLegScoped) {
    if (!_hasText(refs.legType)) {
      issues.add(const DocumentPreflightIssue.warning('leg_type_missing'));
    }
    if (!_hasText(refs.parentBookingReference) &&
        !_hasText(refs.parentBookingId)) {
      issues.add(
        const DocumentPreflightIssue.warning('parent_reference_missing'),
      );
    }
  }
  _addCompanyScopeWarnings(issues, draft.companyScope);

  return DocumentPreflightResult(
    List<DocumentPreflightIssue>.unmodifiable(issues),
  );
}
