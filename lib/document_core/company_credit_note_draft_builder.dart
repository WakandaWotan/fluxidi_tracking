part of '../main.dart';

// These builders are part of the main library and intentionally accept the
// private _CompanyBookingOverviewItem type; external callers cannot use them.
// ignore_for_file: library_private_types_in_public_api

// Provider-neutral Document Core bridge (Patch 2B foundation).
//
// This file is `part of '../main.dart';` because it reads private app types
// (e.g. _CompanyBookingOverviewItem) and existing leg-first helpers. It builds
// pure, provider-neutral draft objects only.
//
// It does NOT: generate UBL/XML, send anything, call external APIs, change UI,
// or alter PDF output. The pure Document Core models/compliance profile are
// imported by main.dart so they are visible here.

String _documentCoreLanguageCode() {
  switch (appConfig.currentLanguage) {
    case AppLanguage.en:
      return 'en';
    case AppLanguage.fr:
      return 'fr';
    case AppLanguage.es:
      return 'es';
    case AppLanguage.nl:
      return 'nl';
  }
}

String? _nullIfEmpty(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _documentCoreParseDate(String? iso) {
  final trimmed = iso?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return DateTime.tryParse(trimmed);
}

String _documentCoreCreditReason(_CompanyBookingOverviewItem item) {
  final decision = item.creditDecision.trim();
  if (decision.isNotEmpty) return 'credit_decision_recorded';
  return 'cancellation_or_credit_correction';
}

DocumentCoreParty _documentCoreSellerFromProfile(
  BackendBusinessProfile? profile,
) {
  if (profile == null) return const DocumentCoreParty();
  final postcodeCity = <String>[
    profile.postcode.trim(),
    profile.city.trim(),
  ].where((e) => e.isNotEmpty).join(' ');
  final addressLine = <String>[
    profile.address.trim(),
    if (postcodeCity.isNotEmpty) postcodeCity,
  ].where((e) => e.isNotEmpty).join(', ');
  final email = profile.email.trim().isNotEmpty
      ? profile.email.trim()
      : profile.invoiceEmail.trim();
  return DocumentCoreParty(
    name: _nullIfEmpty(profile.companyName),
    legalName: _nullIfEmpty(profile.legalName),
    vatNumber: _nullIfEmpty(profile.vatNumber),
    registrationNumber: _nullIfEmpty(profile.companyRegistrationNumber),
    email: _nullIfEmpty(email),
    phone: _nullIfEmpty(profile.phone),
    addressLine: _nullIfEmpty(addressLine),
    postalCode: _nullIfEmpty(profile.postcode),
    city: _nullIfEmpty(profile.city),
    countryCode: _nullIfEmpty(profile.country),
    iban: _nullIfEmpty(profile.iban),
    website: _nullIfEmpty(profile.website),
  );
}

DocumentCoreParty _documentCoreBuyerFromItem(_CompanyBookingOverviewItem item) {
  final name = item.customerName.trim();
  // Only the customer name is reliably available on the company overview item.
  // Buyer VAT/address/country/email are intentionally left null (not guessed).
  return DocumentCoreParty(name: (name.isEmpty || name == '—') ? null : name);
}

DocumentCoreReferenceContext _documentCoreReferences(
  _CompanyBookingOverviewItem item, {
  required bool legScoped,
}) {
  return DocumentCoreReferenceContext(
    bookingId: _nullIfEmpty(item.bookingId),
    parentBookingId: _nullIfEmpty(item.parentBookingId),
    bookingReference: _nullIfEmpty(item.referenceText),
    parentBookingReference: _nullIfEmpty(item.parentReferenceText),
    legId: _nullIfEmpty(item.legId),
    legType: _nullIfEmpty(item.legType),
    isLegScoped: legScoped,
    // When leg-scoped, the parent booking is context only and its total must
    // never be used as the document total.
    isParentContextOnly: legScoped,
  );
}

/// Builds a provider-neutral credit note draft from a company booking item.
///
/// Leg-first: for a roundtrip operational leg row the document total uses
/// [_CompanyBookingOverviewItem.amount]; [parentAmount] is never used directly
/// for a leg-scoped document. For parent/full rows the safe existing
/// [creditDecisionMaxAmount] helper is used.
DocumentCoreCreditNoteDraft buildCompanyCreditNoteDraftFromOverviewItem(
  _CompanyBookingOverviewItem item, {
  BackendBusinessProfile? companyProfile,
  DateTime? issueDate,
  String? languageCode,
}) {
  final legScoped = _CompanyBookingOverviewItem.isRoundtripOperationalLegRow(
    item,
  );
  final num? totalIncl = legScoped
      ? item.amount
      : _CompanyBookingOverviewItem.creditDecisionMaxAmount(item);
  final currency = item.currency.trim().isNotEmpty
      ? item.currency.trim().toUpperCase()
      : 'EUR';
  final creditedIncl =
      (item.creditedAmountCents != null && item.creditedAmountCents! > 0)
      ? item.creditedAmountCents! / 100
      : null;

  final seller = _documentCoreSellerFromProfile(companyProfile);
  final buyer = _documentCoreBuyerFromItem(item);
  final totals = DocumentCoreMonetaryTotals(
    currency: currency,
    totalInclVat: totalIncl,
    creditedAmountInclVat: creditedIncl,
    // VAT split (subtotal/vat/rate) is not available on the company item.
  );
  final references = _documentCoreReferences(item, legScoped: legScoped);

  const customerType = DocumentCoreCustomerType.unknown; // never assume B2C

  final missing = <String>[];
  if (buyer.vatNumber == null) missing.add('buyer_vat_number');
  if (buyer.addressLine == null) missing.add('buyer_address');
  if (buyer.countryCode == null) missing.add('buyer_country');
  if (!totals.hasVatBreakdown) missing.add('vat_breakdown');
  if (references.originalInvoiceReference == null) {
    missing.add('original_invoice_reference');
  }

  // Coarse product guidance only (buyer country unknown here -> unknown-safe).
  final profile = resolveDocumentCoreComplianceProfile(
    countryCode: buyer.countryCode,
    customerType: customerType,
    documentType: DocumentCoreDocumentType.creditNote,
  );

  // Incomplete whenever structured fields are missing, or the customer/country
  // context cannot rule structured documents out.
  final incomplete =
      missing.isNotEmpty ||
      profile.structuredRequirement ==
          DocumentCoreStructuredRequirement.unknown;

  return DocumentCoreCreditNoteDraft(
    issueDate: issueDate ?? DateTime.now(),
    seller: seller,
    buyer: buyer,
    totals: totals,
    references: references,
    customerType: customerType,
    countryCode: buyer.countryCode,
    languageCode: languageCode ?? _documentCoreLanguageCode(),
    reason: _documentCoreCreditReason(item),
    creditDecision: _nullIfEmpty(item.creditDecision),
    incompleteForStructured: incomplete,
    missingStructuredFields: List<String>.unmodifiable(missing),
    exportState: incomplete
        ? DocumentCoreExportState.incomplete
        : DocumentCoreExportState.draftReady,
  );
}

/// Builds a provider-neutral refund proof draft from a company booking item.
///
/// Refund proof is an evidence document (not an e-invoice), so it is never
/// marked structured-incomplete. Leg-first amount rules still apply.
DocumentCoreRefundProofDraft buildCompanyRefundProofDraftFromOverviewItem(
  _CompanyBookingOverviewItem item, {
  BackendBusinessProfile? companyProfile,
  DateTime? issueDate,
  String? languageCode,
}) {
  final legScoped = _CompanyBookingOverviewItem.isRoundtripOperationalLegRow(
    item,
  );
  final num? legFirstAmount = legScoped
      ? item.amount
      : _CompanyBookingOverviewItem.creditDecisionMaxAmount(item);
  final currency = item.currency.trim().isNotEmpty
      ? item.currency.trim().toUpperCase()
      : 'EUR';
  final refundedIncl =
      (item.refundedAmountCents != null && item.refundedAmountCents! > 0)
      ? item.refundedAmountCents! / 100
      : legFirstAmount;

  final seller = _documentCoreSellerFromProfile(companyProfile);
  final buyer = _documentCoreBuyerFromItem(item);
  final totals = DocumentCoreMonetaryTotals(
    currency: currency,
    totalInclVat: legFirstAmount,
    refundedAmountInclVat: refundedIncl,
  );
  final references = _documentCoreReferences(item, legScoped: legScoped);

  final refundId = _nullIfEmpty(item.mollieRefundId);
  final refundStatus = _nullIfEmpty(
    item.refundStatus.trim().isNotEmpty
        ? item.refundStatus
        : item.mollieRefundStatus,
  );
  final refundedAt = _documentCoreParseDate(item.refundedAt);

  final missing = <String>[];
  if (refundId == null) missing.add('refund_id');
  if (refundedAt == null) missing.add('refunded_at');

  return DocumentCoreRefundProofDraft(
    issueDate: issueDate ?? DateTime.now(),
    seller: seller,
    buyer: buyer,
    totals: totals,
    references: references,
    customerType: DocumentCoreCustomerType.unknown,
    countryCode: buyer.countryCode,
    languageCode: languageCode ?? _documentCoreLanguageCode(),
    refundProvider: _nullIfEmpty(item.refundProvider),
    refundStatus: refundStatus,
    refundId: refundId,
    refundedAt: refundedAt,
    incompleteForStructured: false,
    missingStructuredFields: List<String>.unmodifiable(missing),
    exportState: refundedIncl != null
        ? DocumentCoreExportState.draftReady
        : DocumentCoreExportState.incomplete,
  );
}
