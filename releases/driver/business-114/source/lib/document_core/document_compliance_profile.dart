// Provider-neutral Document Core compliance profile (Patch 2B foundation).
//
// PURE Dart only (imports only the Document Core models). No Flutter, no PDF,
// no network, no provider, no main.dart dependency.
//
// IMPORTANT — PRODUCT GUIDANCE, NOT LEGAL ADVICE.
// All country/customer data below is an internal, configurable product profile
// used to plan future document behaviour. It is intentionally coarse, marked as
// placeholder/product-guidance, and MUST be easy to update when laws/providers
// change. It does not encode final legal certainty and triggers no sending.

import 'document_core_models.dart';

/// A resolved (or default) compliance profile for a country/customer/document
/// combination. Treat as product guidance only.
class DocumentCoreComplianceProfile {
  final String? countryCode;
  final DocumentCoreCustomerType customerType;
  final DocumentCoreDocumentType documentType;
  final DocumentCoreStructuredRequirement structuredRequirement;
  final DocumentCorePreferredStandard preferredStandard;
  final DocumentCoreProviderChannel providerChannel;

  /// Whether e-reporting could be relevant. `null` means unknown-safe.
  final bool? eReportingRelevant;

  /// Optional phase-in / effective date for the guidance.
  final DateTime? effectiveFrom;

  /// Short internal key (not long legal text).
  final String? notesKey;

  /// Always true here: these profiles are product guidance, not legal advice.
  final bool isProductGuidanceOnly;

  /// True when the entry is a coarse placeholder pending human confirmation.
  final bool isPlaceholderProfile;

  const DocumentCoreComplianceProfile({
    required this.countryCode,
    required this.customerType,
    required this.documentType,
    required this.structuredRequirement,
    required this.preferredStandard,
    required this.providerChannel,
    required this.eReportingRelevant,
    this.effectiveFrom,
    this.notesKey,
    this.isProductGuidanceOnly = true,
    this.isPlaceholderProfile = true,
  });
}

/// Unknown-safe default used whenever no specific guidance applies.
DocumentCoreComplianceProfile _unknownProfile({
  required String? countryCode,
  required DocumentCoreCustomerType customerType,
  required DocumentCoreDocumentType documentType,
  String notesKey = 'unknown_default',
}) {
  return DocumentCoreComplianceProfile(
    countryCode: countryCode,
    customerType: customerType,
    documentType: documentType,
    structuredRequirement: DocumentCoreStructuredRequirement.unknown,
    preferredStandard: DocumentCorePreferredStandard.unknown,
    providerChannel: DocumentCoreProviderChannel.unknown,
    eReportingRelevant: null,
    notesKey: notesKey,
  );
}

/// B2C is generally receipt/PDF-oriented: not required, no structured channel.
DocumentCoreComplianceProfile _b2cNotRequired({
  required String? countryCode,
  required DocumentCoreDocumentType documentType,
}) {
  return DocumentCoreComplianceProfile(
    countryCode: countryCode,
    customerType: DocumentCoreCustomerType.b2c,
    documentType: documentType,
    structuredRequirement: DocumentCoreStructuredRequirement.notRequired,
    preferredStandard: DocumentCorePreferredStandard.none,
    providerChannel: DocumentCoreProviderChannel.none,
    eReportingRelevant: false,
    notesKey: 'b2c_receipt_oriented',
  );
}

bool _isStructuredDocumentType(DocumentCoreDocumentType documentType) {
  return documentType == DocumentCoreDocumentType.invoice ||
      documentType == DocumentCoreDocumentType.creditNote;
}

/// Resolves a coarse, provider-neutral compliance profile.
///
/// Pure function: no side effects, no I/O. Returns unknown-safe defaults for
/// anything not explicitly described. Refund proofs are treated as evidence
/// documents (never structured-required here). All results are product
/// guidance only.
DocumentCoreComplianceProfile resolveDocumentCoreComplianceProfile({
  required String? countryCode,
  required DocumentCoreCustomerType customerType,
  required DocumentCoreDocumentType documentType,
  DateTime? asOf,
}) {
  final cc = (countryCode ?? '').trim().toUpperCase();

  // Refund proof is an evidence document, not an e-invoice.
  if (documentType == DocumentCoreDocumentType.refundProof) {
    return DocumentCoreComplianceProfile(
      countryCode: cc.isEmpty ? null : cc,
      customerType: customerType,
      documentType: documentType,
      structuredRequirement: DocumentCoreStructuredRequirement.notRequired,
      preferredStandard: DocumentCorePreferredStandard.none,
      providerChannel: DocumentCoreProviderChannel.none,
      eReportingRelevant: false,
      notesKey: 'refund_proof_evidence_only',
    );
  }

  // B2C is generally receipt-oriented for all document types here.
  if (customerType == DocumentCoreCustomerType.b2c) {
    return _b2cNotRequired(
      countryCode: cc.isEmpty ? null : cc,
      documentType: documentType,
    );
  }

  // Unknown customer type stays unknown-safe (never assume B2C).
  if (customerType == DocumentCoreCustomerType.unknown) {
    return _unknownProfile(
      countryCode: cc.isEmpty ? null : cc,
      customerType: customerType,
      documentType: documentType,
      notesKey: 'unknown_customer_type',
    );
  }

  if (cc.isEmpty) {
    return _unknownProfile(
      countryCode: null,
      customerType: customerType,
      documentType: documentType,
      notesKey: 'unknown_country',
    );
  }

  // Only structured document types (invoice / creditNote) get country guidance.
  if (!_isStructuredDocumentType(documentType)) {
    return _unknownProfile(
      countryCode: cc,
      customerType: customerType,
      documentType: documentType,
      notesKey: 'non_structured_document',
    );
  }

  // Coarse B2B/B2G country placeholders. Product guidance only.
  switch (cc) {
    case 'BE':
      return DocumentCoreComplianceProfile(
        countryCode: cc,
        customerType: customerType,
        documentType: documentType,
        structuredRequirement: DocumentCoreStructuredRequirement.required,
        preferredStandard: DocumentCorePreferredStandard.peppolBis,
        providerChannel: DocumentCoreProviderChannel.peppol,
        eReportingRelevant: true,
        effectiveFrom: DateTime.utc(2026, 1, 1),
        notesKey: 'be_b2b_b2g_peppol_placeholder',
      );
    case 'FR':
      return DocumentCoreComplianceProfile(
        countryCode: cc,
        customerType: customerType,
        documentType: documentType,
        structuredRequirement: DocumentCoreStructuredRequirement.phaseIn,
        preferredStandard: DocumentCorePreferredStandard.platformDependent,
        providerChannel: DocumentCoreProviderChannel.approvedPlatform,
        eReportingRelevant: true,
        effectiveFrom: DateTime.utc(2026, 9, 1),
        notesKey: 'fr_b2b_phasein_platform_placeholder',
      );
    case 'NL':
      return DocumentCoreComplianceProfile(
        countryCode: cc,
        customerType: customerType,
        documentType: documentType,
        structuredRequirement: customerType == DocumentCoreCustomerType.b2g
            ? DocumentCoreStructuredRequirement.required
            : DocumentCoreStructuredRequirement.optional,
        preferredStandard: DocumentCorePreferredStandard.peppolBis,
        providerChannel: DocumentCoreProviderChannel.peppol,
        eReportingRelevant: false,
        notesKey: 'nl_b2g_peppol_b2b_optional_placeholder',
      );
    case 'DE':
      return DocumentCoreComplianceProfile(
        countryCode: cc,
        customerType: customerType,
        documentType: documentType,
        structuredRequirement: customerType == DocumentCoreCustomerType.b2g
            ? DocumentCoreStructuredRequirement.required
            : DocumentCoreStructuredRequirement.phaseIn,
        preferredStandard: customerType == DocumentCoreCustomerType.b2g
            ? DocumentCorePreferredStandard.xrechnung
            : DocumentCorePreferredStandard.zugferd,
        providerChannel: DocumentCoreProviderChannel.approvedPlatform,
        eReportingRelevant: true,
        effectiveFrom: DateTime.utc(2025, 1, 1),
        notesKey: 'de_b2g_xrechnung_b2b_phasein_placeholder',
      );
    case 'ES':
      return DocumentCoreComplianceProfile(
        countryCode: cc,
        customerType: customerType,
        documentType: documentType,
        structuredRequirement: customerType == DocumentCoreCustomerType.b2g
            ? DocumentCoreStructuredRequirement.required
            : DocumentCoreStructuredRequirement.phaseIn,
        preferredStandard: customerType == DocumentCoreCustomerType.b2g
            ? DocumentCorePreferredStandard.facturae
            : DocumentCorePreferredStandard.platformDependent,
        providerChannel: DocumentCoreProviderChannel.approvedPlatform,
        eReportingRelevant: true,
        notesKey: 'es_b2g_facturae_b2b_phasein_placeholder',
      );
    case 'LU':
      return DocumentCoreComplianceProfile(
        countryCode: cc,
        customerType: customerType,
        documentType: documentType,
        structuredRequirement: customerType == DocumentCoreCustomerType.b2g
            ? DocumentCoreStructuredRequirement.required
            : DocumentCoreStructuredRequirement.optional,
        preferredStandard: DocumentCorePreferredStandard.peppolBis,
        providerChannel: DocumentCoreProviderChannel.peppol,
        eReportingRelevant: false,
        notesKey: 'lu_b2g_peppol_b2b_optional_placeholder',
      );
    case 'UK':
    case 'GB':
      return DocumentCoreComplianceProfile(
        countryCode: cc,
        customerType: customerType,
        documentType: documentType,
        structuredRequirement: DocumentCoreStructuredRequirement.notRequired,
        preferredStandard: DocumentCorePreferredStandard.none,
        providerChannel: DocumentCoreProviderChannel.none,
        eReportingRelevant: false,
        notesKey: 'uk_no_domestic_mandate_placeholder',
      );
    default:
      return _unknownProfile(
        countryCode: cc,
        customerType: customerType,
        documentType: documentType,
        notesKey: 'country_not_profiled',
      );
  }
}
