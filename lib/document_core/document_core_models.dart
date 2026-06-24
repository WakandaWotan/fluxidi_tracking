// Provider-neutral Document Core models (Patch 2B foundation).
//
// PURE Dart only. This file intentionally has:
//   * no Flutter imports
//   * no PDF imports
//   * no network imports
//   * no provider (Billit/Peppol/Mollie) imports
//   * no dependency on main.dart
//
// These are internal draft value objects. They do NOT generate UBL/XML, do not
// send anything, and do not call external APIs. They only describe what a
// document draft could contain so later patches can build on a stable shape.

/// High-level document categories Fluxidi can describe.
enum DocumentCoreDocumentType { receipt, invoice, creditNote, refundProof }

/// Customer classification. Defaults to [unknown]; never assume [b2c].
enum DocumentCoreCustomerType { b2c, b2b, b2g, unknown }

/// Whether a structured (machine-readable) document is required.
/// Product guidance only, not final legal advice.
enum DocumentCoreStructuredRequirement {
  notRequired,
  optional,
  required,
  phaseIn,
  unknown,
}

/// Preferred structured standard when one applies. Product guidance only.
enum DocumentCorePreferredStandard {
  none,
  ubl,
  peppolBis,
  xrechnung,
  zugferd,
  facturae,
  platformDependent,
  unknown,
}

/// How a structured document could eventually be delivered.
/// No channel is exercised in this patch.
enum DocumentCoreProviderChannel {
  none,
  peppol,
  approvedPlatform,
  localExport,
  providerLater,
  unknown,
}

/// Lifecycle state of a draft from a local/export point of view.
enum DocumentCoreExportState {
  none,
  draftReady,
  incomplete,
  queuedLocalExport,
  providerLater,
}

/// A party (seller or buyer). Fields are nullable where they may be absent.
class DocumentCoreParty {
  final String? name;
  final String? legalName;
  final String? vatNumber;
  final String? registrationNumber;
  final String? email;
  final String? phone;
  final String? addressLine;
  final String? postalCode;
  final String? city;
  final String? countryCode;
  final String? iban;
  final String? website;

  const DocumentCoreParty({
    this.name,
    this.legalName,
    this.vatNumber,
    this.registrationNumber,
    this.email,
    this.phone,
    this.addressLine,
    this.postalCode,
    this.city,
    this.countryCode,
    this.iban,
    this.website,
  });

  /// True when no field is populated.
  bool get isEmpty =>
      (name == null || name!.isEmpty) &&
      (legalName == null || legalName!.isEmpty) &&
      (vatNumber == null || vatNumber!.isEmpty) &&
      (registrationNumber == null || registrationNumber!.isEmpty) &&
      (email == null || email!.isEmpty) &&
      (phone == null || phone!.isEmpty) &&
      (addressLine == null || addressLine!.isEmpty) &&
      (postalCode == null || postalCode!.isEmpty) &&
      (city == null || city!.isEmpty) &&
      (countryCode == null || countryCode!.isEmpty) &&
      (iban == null || iban!.isEmpty) &&
      (website == null || website!.isEmpty);

  /// True when the minimum tax-party fields for a structured document exist.
  bool get hasStructuredTaxIdentity =>
      (vatNumber != null && vatNumber!.isNotEmpty) &&
      (addressLine != null && addressLine!.isNotEmpty) &&
      (countryCode != null && countryCode!.isNotEmpty);
}

/// Monetary totals. All amounts are nullable; only populate what is known.
/// Amounts are expressed in major currency units (e.g. EUR, not cents).
class DocumentCoreMonetaryTotals {
  final String currency;
  final num? totalInclVat;
  final num? subtotalExVat;
  final num? vatAmount;
  final num? vatRatePercent;
  final num? creditedAmountInclVat;
  final num? refundedAmountInclVat;

  const DocumentCoreMonetaryTotals({
    required this.currency,
    this.totalInclVat,
    this.subtotalExVat,
    this.vatAmount,
    this.vatRatePercent,
    this.creditedAmountInclVat,
    this.refundedAmountInclVat,
  });

  /// True when a full VAT split (subtotal + VAT) is available.
  bool get hasVatBreakdown => subtotalExVat != null && vatAmount != null;
}

/// Reference context for a document, including leg-first roundtrip metadata.
class DocumentCoreReferenceContext {
  final String? bookingId;
  final String? parentBookingId;
  final String? bookingReference;
  final String? parentBookingReference;
  final String? planningReference;
  final String? publicReference;
  final String? legId;
  final String? legType;

  /// True when this document is scoped to a single roundtrip leg.
  final bool isLegScoped;

  /// True when the parent booking is included for context only (leg-first),
  /// i.e. the parent total must NOT be used as the document total.
  final bool isParentContextOnly;

  final String? originalInvoiceReference;
  final DateTime? originalInvoiceDate;

  const DocumentCoreReferenceContext({
    this.bookingId,
    this.parentBookingId,
    this.bookingReference,
    this.parentBookingReference,
    this.planningReference,
    this.publicReference,
    this.legId,
    this.legType,
    this.isLegScoped = false,
    this.isParentContextOnly = false,
    this.originalInvoiceReference,
    this.originalInvoiceDate,
  });
}

/// Provider-neutral internal credit note draft. NOT a UBL document.
class DocumentCoreCreditNoteDraft {
  final DateTime issueDate;
  final DocumentCoreParty seller;
  final DocumentCoreParty buyer;
  final DocumentCoreMonetaryTotals totals;
  final DocumentCoreReferenceContext references;
  final DocumentCoreCustomerType customerType;
  final String? countryCode;
  final String? languageCode;
  final String? reason;
  final String? creditDecision;
  final bool incompleteForStructured;
  final List<String> missingStructuredFields;
  final DocumentCoreExportState exportState;

  const DocumentCoreCreditNoteDraft({
    required this.issueDate,
    required this.seller,
    required this.buyer,
    required this.totals,
    required this.references,
    this.customerType = DocumentCoreCustomerType.unknown,
    this.countryCode,
    this.languageCode,
    this.reason,
    this.creditDecision,
    this.incompleteForStructured = true,
    this.missingStructuredFields = const <String>[],
    this.exportState = DocumentCoreExportState.incomplete,
  });

  /// Fixed/expected document type for this draft.
  DocumentCoreDocumentType get documentType =>
      DocumentCoreDocumentType.creditNote;
}

/// Provider-neutral internal refund proof draft. Evidence document, NOT an
/// e-invoice and NOT a UBL document.
class DocumentCoreRefundProofDraft {
  final DateTime issueDate;
  final DocumentCoreParty seller;
  final DocumentCoreParty buyer;
  final DocumentCoreMonetaryTotals totals;
  final DocumentCoreReferenceContext references;
  final DocumentCoreCustomerType customerType;
  final String? countryCode;
  final String? languageCode;
  final String? refundProvider;
  final String? refundStatus;
  final String? refundId;
  final DateTime? refundedAt;
  final bool incompleteForStructured;
  final List<String> missingStructuredFields;
  final DocumentCoreExportState exportState;

  const DocumentCoreRefundProofDraft({
    required this.issueDate,
    required this.seller,
    required this.buyer,
    required this.totals,
    required this.references,
    this.customerType = DocumentCoreCustomerType.unknown,
    this.countryCode,
    this.languageCode,
    this.refundProvider,
    this.refundStatus,
    this.refundId,
    this.refundedAt,
    this.incompleteForStructured = false,
    this.missingStructuredFields = const <String>[],
    this.exportState = DocumentCoreExportState.draftReady,
  });

  /// Fixed/expected document type for this draft.
  DocumentCoreDocumentType get documentType =>
      DocumentCoreDocumentType.refundProof;
}
