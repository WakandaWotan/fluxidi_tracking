// CONSUMER-BILLIT-DOCUMENT-UI-1 / CONSUMER-SALE-DOCUMENT-PRESENTATION-P0-1
//
// Pure presentation contract for private/consumer Billit sales.
// Internally Billit may store OrderType Invoice; Fluxidi must never show
// "Factuur" for a consumer sale, and Peppol is never applicable.
//
// Classification uses ONLY:
// 1) explicit booking invoice intent
// 2) canonical document kind (consumer_sale / business_invoice / credit_note)
// 3) conversion state
// Never: Billit OrderType, INV-* numbers, filled company/VAT/Peppol fields,
// or presence of a Billit order id.

const String kConsumerSaleKind = 'consumer_sale';
const String kBusinessInvoiceKind = 'business_invoice';
const String kCreditNoteKind = 'credit_note';

enum FluxidiDocumentPresentationKind {
  consumerSale,
  businessInvoice,
  creditNote,
  invoiceNeutral,
}

bool isConsumerSaleKind(Object? raw) {
  final s = (raw ?? '').toString().trim().toLowerCase();
  return s == kConsumerSaleKind ||
      s == 'private_sale' ||
      s == 'particuliere_verkoop' ||
      s == 'ontvangstbewijs' ||
      s == 'ritbon';
}

bool isBusinessInvoiceKind(Object? raw) {
  final s = (raw ?? '').toString().trim().toLowerCase();
  return s == kBusinessInvoiceKind || s == 'zakelijke_factuur';
}

bool isCreditNoteKind(Object? raw) {
  final s = (raw ?? '').toString().trim().toLowerCase();
  return s == kCreditNoteKind ||
      s == 'creditnote' ||
      s == 'credit-note' ||
      s == 'consumer_conversion_credit';
}

bool hasExplicitBusinessInvoiceIntent({
  Object? invoiceIntent,
  bool businessInvoiceIntent = false,
}) {
  if (businessInvoiceIntent) return true;
  final intent = (invoiceIntent ?? '').toString().trim().toLowerCase();
  return intent == 'business_invoice' || intent == kBusinessInvoiceKind;
}

/// Historical / repaired consumer sales without full UI metadata.
bool hasHistoricalConsumerSaleSignals({
  Object? saleKind,
  Object? bookingConsumerSaleKind,
  Object? createdByRole,
  bool? peppolApplicable,
  Object? billingCustomerType,
}) {
  if (isConsumerSaleKind(saleKind) ||
      isConsumerSaleKind(bookingConsumerSaleKind)) {
    return true;
  }
  final role = (createdByRole ?? '').toString().trim().toLowerCase();
  if (role == 'system_consumer_sale' || role.contains('consumer_sale')) {
    return true;
  }
  // peppol_applicable=false alone is not consumer evidence.
  final customerType =
      (billingCustomerType ?? '').toString().trim().toLowerCase();
  if (customerType == 'private' || customerType == 'consumer') return true;
  return false;
}

FluxidiDocumentPresentationKind? presentationKindFromWorkerMetadata({
  Object? presentationLabelKey,
  Object? fiscalKind,
}) {
  switch ((presentationLabelKey ?? '').toString().trim()) {
    case 'consumerSale':
    case 'refundProof':
      return FluxidiDocumentPresentationKind.consumerSale;
    case 'invoice':
      return FluxidiDocumentPresentationKind.businessInvoice;
    case 'creditNote':
      return FluxidiDocumentPresentationKind.creditNote;
    case 'invoiceNeutral':
      return FluxidiDocumentPresentationKind.invoiceNeutral;
  }
  switch ((fiscalKind ?? '').toString().trim().toLowerCase()) {
    case 'consumer_sale':
    case 'private_sale':
      return FluxidiDocumentPresentationKind.consumerSale;
    case 'business_invoice':
      return FluxidiDocumentPresentationKind.businessInvoice;
    case 'credit_note':
    case 'creditnote':
      return FluxidiDocumentPresentationKind.creditNote;
    case 'unspecified':
      return FluxidiDocumentPresentationKind.invoiceNeutral;
  }
  return null;
}

/// Canonical presentation kind. Never infer business from OrderType/INV/billing.
FluxidiDocumentPresentationKind resolveDocumentPresentationKind({
  Object? saleKind,
  Object? documentType,
  Object? invoiceIntent,
  Object? bookingConsumerSaleKind,
  Object? createdByRole,
  Object? billingCustomerType,
  bool? peppolApplicable,
  bool businessInvoiceIntent = false,
  bool conversionToBusinessSucceeded = false,
  bool consumerSaleSuperseded = false,
  Object? presentationLabelKey,
  Object? fiscalKind,
}) {
  final type = (documentType ?? '').toString().trim().toLowerCase();
  if (isCreditNoteKind(saleKind) ||
      type == 'credit_note' ||
      type == 'creditnote') {
    return FluxidiDocumentPresentationKind.creditNote;
  }

  // After conversion the active revenue document is the new business invoice.
  if (conversionToBusinessSucceeded && !consumerSaleSuperseded) {
    return FluxidiDocumentPresentationKind.businessInvoice;
  }

  final fromWorker = presentationKindFromWorkerMetadata(
    presentationLabelKey: presentationLabelKey,
    fiscalKind: fiscalKind,
  );
  if (fromWorker != null) return fromWorker;

  if (hasExplicitBusinessInvoiceIntent(
        invoiceIntent: invoiceIntent,
        businessInvoiceIntent: businessInvoiceIntent,
      ) ||
      isBusinessInvoiceKind(saleKind) ||
      peppolApplicable == true) {
    return FluxidiDocumentPresentationKind.businessInvoice;
  }

  if (hasHistoricalConsumerSaleSignals(
    saleKind: saleKind,
    bookingConsumerSaleKind: bookingConsumerSaleKind,
    createdByRole: createdByRole,
    peppolApplicable: peppolApplicable,
    billingCustomerType: billingCustomerType,
  )) {
    return FluxidiDocumentPresentationKind.consumerSale;
  }

  if (type == 'credit_note' || type == 'creditnote') {
    return FluxidiDocumentPresentationKind.creditNote;
  }
  if (type == 'refund_proof') {
    return FluxidiDocumentPresentationKind.consumerSale;
  }
  // Bare document_type=invoice without business evidence is never automatically
  // "Zakelijke factuur".
  return FluxidiDocumentPresentationKind.invoiceNeutral;
}

bool documentForbidsInvoiceLabel({
  Object? saleKind,
  Object? documentType,
  Object? invoiceIntent,
  Object? bookingConsumerSaleKind,
  Object? createdByRole,
  bool? peppolApplicable,
  bool businessInvoiceIntent = false,
  bool conversionToBusinessSucceeded = false,
  Object? presentationLabelKey,
  Object? fiscalKind,
}) {
  final kind = resolveDocumentPresentationKind(
    saleKind: saleKind,
    documentType: documentType,
    invoiceIntent: invoiceIntent,
    bookingConsumerSaleKind: bookingConsumerSaleKind,
    createdByRole: createdByRole,
    peppolApplicable: peppolApplicable,
    businessInvoiceIntent: businessInvoiceIntent,
    conversionToBusinessSucceeded: conversionToBusinessSucceeded,
    presentationLabelKey: presentationLabelKey,
    fiscalKind: fiscalKind,
  );
  return kind == FluxidiDocumentPresentationKind.consumerSale;
}

/// Customer-facing document type label key.
String consumerOrBusinessDocumentLabelKey({
  Object? saleKind,
  Object? documentType,
  Object? invoiceIntent,
  Object? bookingConsumerSaleKind,
  Object? createdByRole,
  bool? peppolApplicable,
  bool businessInvoiceIntent = false,
  bool conversionToBusinessSucceeded = false,
  Object? presentationLabelKey,
  Object? fiscalKind,
}) {
  final kind = resolveDocumentPresentationKind(
    saleKind: saleKind,
    documentType: documentType,
    invoiceIntent: invoiceIntent,
    bookingConsumerSaleKind: bookingConsumerSaleKind,
    createdByRole: createdByRole,
    peppolApplicable: peppolApplicable,
    businessInvoiceIntent: businessInvoiceIntent,
    conversionToBusinessSucceeded: conversionToBusinessSucceeded,
    presentationLabelKey: presentationLabelKey,
    fiscalKind: fiscalKind,
  );
  switch (kind) {
    case FluxidiDocumentPresentationKind.businessInvoice:
      return 'invoice';
    case FluxidiDocumentPresentationKind.creditNote:
      return 'creditNote';
    case FluxidiDocumentPresentationKind.invoiceNeutral:
      return 'invoiceNeutral';
    case FluxidiDocumentPresentationKind.consumerSale:
      final type = (documentType ?? '').toString().trim().toLowerCase();
      if (type == 'refund_proof') return 'refundProof';
      return 'consumerSale';
  }
}

String consumerSaleStatusLabelKey({
  Object? saleKind,
  Object? bookingConsumerSaleKind,
  Object? createdByRole,
  bool? peppolApplicable,
  bool registeredInBillit = false,
  Object? billitOrderId,
}) {
  final isConsumer = resolveDocumentPresentationKind(
        saleKind: saleKind,
        bookingConsumerSaleKind: bookingConsumerSaleKind,
        createdByRole: createdByRole,
        peppolApplicable: peppolApplicable,
      ) ==
      FluxidiDocumentPresentationKind.consumerSale;
  if (!isConsumer) return 'unknown';
  final order = (billitOrderId ?? '').toString().trim();
  if (registeredInBillit || order.isNotEmpty) return 'registeredInBillit';
  return 'pendingBillitRegistration';
}

/// Peppol UI policy for a document.
class PeppolUiPolicy {
  const PeppolUiPolicy({
    required this.applicable,
    required this.showNotApplicable,
    required this.showMissingEndpointWarning,
    required this.showSettingsRequiredWarning,
    required this.showSendAction,
  });

  final bool applicable;
  final bool showNotApplicable;
  final bool showMissingEndpointWarning;
  final bool showSettingsRequiredWarning;
  final bool showSendAction;
}

PeppolUiPolicy resolvePeppolUiPolicy({
  Object? saleKind,
  Object? documentType,
  Object? invoiceIntent,
  Object? bookingConsumerSaleKind,
  Object? createdByRole,
  bool? peppolApplicable,
  bool businessInvoiceIntent = false,
  bool conversionToBusinessSucceeded = false,
  Object? presentationLabelKey,
  Object? fiscalKind,
}) {
  final kind = resolveDocumentPresentationKind(
    saleKind: saleKind,
    documentType: documentType,
    invoiceIntent: invoiceIntent,
    bookingConsumerSaleKind: bookingConsumerSaleKind,
    createdByRole: createdByRole,
    peppolApplicable: peppolApplicable,
    businessInvoiceIntent: businessInvoiceIntent,
    conversionToBusinessSucceeded: conversionToBusinessSucceeded,
    presentationLabelKey: presentationLabelKey,
    fiscalKind: fiscalKind,
  );
  if (kind != FluxidiDocumentPresentationKind.businessInvoice ||
      peppolApplicable == false) {
    return const PeppolUiPolicy(
      applicable: false,
      showNotApplicable: true,
      showMissingEndpointWarning: false,
      showSettingsRequiredWarning: false,
      showSendAction: false,
    );
  }
  return const PeppolUiPolicy(
    applicable: true,
    showNotApplicable: false,
    showMissingEndpointWarning: true,
    showSettingsRequiredWarning: true,
    showSendAction: true,
  );
}

/// After conversion, UI should switch to business invoice presentation.
String documentLabelKeyAfterConversion({required bool conversionSucceeded}) {
  return conversionSucceeded ? 'invoice' : 'consumerSale';
}

/// Planned and street consumer rides share one presentation contract.
String consumerSalePresentationContractId({required bool isStreetRide}) {
  final _ = isStreetRide;
  return 'fluxidi_consumer_sale_v1';
}

String paymentMethodDisplayKey({
  Object? paymentMethod,
  Object? paymentProvider,
  Object? paymentSource,
}) {
  final method = (paymentMethod ?? '').toString().trim().toLowerCase();
  final provider = (paymentProvider ?? '').toString().trim().toLowerCase();
  final source = (paymentSource ?? '').toString().trim().toLowerCase();
  if (method == 'pointofsale' ||
      method == 'tap_to_pay' ||
      source == 'tap_to_pay' ||
      method == 'in_vehicle_card') {
    return 'tapToPay';
  }
  if (method == 'bancontact') return 'bancontactManual';
  if (method == 'cash' || method == 'contant') return 'cash';
  if (method == 'qr' || method == 'qr_code') return 'qr';
  if (provider == 'mollie' && (method.isEmpty || method == 'mollie')) {
    return 'onlineMollie';
  }
  if (provider == 'mollie') return 'onlineMollie';
  if (method == 'bank_transfer' || method == 'bank_transfer_bacs') {
    return 'bankTransfer';
  }
  // Never surface technical payment_source tokens like in_car as the method.
  if (method == 'in_car' || method == 'incar') return 'cash';
  if (method.isEmpty && (source == 'in_car' || source == 'incar')) {
    return 'cash';
  }
  return method.isEmpty ? 'unknown' : method;
}

/// Whether the technical payment_source row should be shown on consumer PDFs.
bool shouldShowPaymentSourceOnDocument({
  required FluxidiDocumentPresentationKind presentationKind,
  Object? paymentSource,
}) {
  if (presentationKind == FluxidiDocumentPresentationKind.consumerSale) {
    return false;
  }
  final source = (paymentSource ?? '').toString().trim().toLowerCase();
  if (source.isEmpty || source == 'in_car' || source == 'incar') return false;
  return true;
}

/// Short ride reference for consumer PDFs (never full booking id).
String consumerSaleShortRideReference(Object? bookingId) {
  final raw = (bookingId ?? '').toString().trim();
  if (raw.isEmpty) return '';
  final withoutStreet = raw.startsWith('street_')
      ? raw.substring('street_'.length)
      : raw;
  final compact = withoutStreet.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (compact.isEmpty) {
    return raw.length <= 10 ? raw : raw.substring(raw.length - 10);
  }
  return compact.length <= 10
      ? compact.toUpperCase()
      : compact.substring(compact.length - 10).toUpperCase();
}

/// Local/server PDF title key.
String consumerOrBusinessPdfTitleKey({
  Object? saleKind,
  Object? documentType,
  Object? invoiceIntent,
  Object? bookingConsumerSaleKind,
  Object? createdByRole,
  bool? peppolApplicable,
  bool businessInvoiceIntent = false,
  bool conversionToBusinessSucceeded = false,
  Object? presentationLabelKey,
  Object? fiscalKind,
}) {
  final kind = resolveDocumentPresentationKind(
    saleKind: saleKind,
    documentType: documentType,
    invoiceIntent: invoiceIntent,
    bookingConsumerSaleKind: bookingConsumerSaleKind,
    createdByRole: createdByRole,
    peppolApplicable: peppolApplicable,
    businessInvoiceIntent: businessInvoiceIntent,
    conversionToBusinessSucceeded: conversionToBusinessSucceeded,
    presentationLabelKey: presentationLabelKey,
    fiscalKind: fiscalKind,
  );
  switch (kind) {
    case FluxidiDocumentPresentationKind.businessInvoice:
      return 'invoice';
    case FluxidiDocumentPresentationKind.creditNote:
      return 'creditNote';
    case FluxidiDocumentPresentationKind.invoiceNeutral:
      return 'invoiceNeutral';
    case FluxidiDocumentPresentationKind.consumerSale:
      return 'ritbon';
  }
}

/// Business document for local PDF — intent/kind only, never company/VAT fill.
bool isBusinessDocumentForPresentation({
  Object? saleKind,
  Object? documentType,
  Object? invoiceIntent,
  Object? bookingConsumerSaleKind,
  Object? createdByRole,
  Object? billingCustomerType,
  bool? peppolApplicable,
  bool businessInvoiceIntent = false,
  bool conversionToBusinessSucceeded = false,
  // Legacy inputs — accepted for call-site compatibility but ignored.
  Object? companyName,
  Object? vatNumber,
  Object? billitOrderType,
  Object? documentNumber,
}) {
  // Keep signatures stable for call sites that still pass billing/OrderType
  // fields; classification must ignore them.
  assert(() {
    companyName;
    vatNumber;
    billitOrderType;
    documentNumber;
    return true;
  }());

  return resolveDocumentPresentationKind(
        saleKind: saleKind,
        documentType: documentType,
        invoiceIntent: invoiceIntent,
        bookingConsumerSaleKind: bookingConsumerSaleKind,
        createdByRole: createdByRole,
        billingCustomerType: billingCustomerType,
        peppolApplicable: peppolApplicable,
        businessInvoiceIntent: businessInvoiceIntent,
        conversionToBusinessSucceeded: conversionToBusinessSucceeded,
      ) ==
      FluxidiDocumentPresentationKind.businessInvoice;
}

bool businessInvoiceActionStillAvailable({
  required bool consumerSalePresent,
  required bool businessInvoicePresent,
  required bool conversionAllowed,
}) {
  if (!consumerSalePresent) return false;
  if (businessInvoicePresent) return false;
  if (!conversionAllowed) return false;
  return true;
}

/// CONSUMER-SALE-LATE-INVOICE-ACTION-PLACEMENT-P1
///
/// Where the single company “Zakelijke factuur aanvragen” slot may appear
/// (always above Documenten — never on a document card).
enum CompanyLateInvoicePlacementKind {
  /// Do not mount the action.
  hidden,

  /// Canonical completed street ride: show the large existing action slot
  /// (request or issued view) without guessing a consumer-sale state.
  streetCanonicalSlot,

  /// Completed non-street (e.g. planned): probe documents; show the large
  /// slot only when a convertible consumer sale exists.
  consumerSaleProbeSlot,
}

CompanyLateInvoicePlacementKind resolveCompanyLateInvoicePlacement({
  required bool completedBucket,
  required bool streetRideBusinessInvoiceEligible,
}) {
  if (!completedBucket) return CompanyLateInvoicePlacementKind.hidden;
  if (streetRideBusinessInvoiceEligible) {
    return CompanyLateInvoicePlacementKind.streetCanonicalSlot;
  }
  return CompanyLateInvoicePlacementKind.consumerSaleProbeSlot;
}

/// CONSUMER-SALE-LATE-BUSINESS-INVOICE-ACTION-P0-3
///
/// Visibility for “Zakelijke factuur aanvragen” on an existing consumer sale.
/// Uses only canonical sale kind / conversion / linked business invoice —
/// never INV-prefix, Billit OrderType, or filled billing fields.
bool shouldShowLateBusinessInvoiceAction({
  Object? saleKind,
  Object? documentType,
  Object? createdByRole,
  bool? peppolApplicable,
  bool superseded = false,
  Object? lifecycleState,
  bool businessInvoicePresent = false,
  bool conversionInProgress = false,
  bool conversionAllowed = true,
}) {
  if (!conversionAllowed || conversionInProgress) return false;
  if (businessInvoicePresent) return false;
  if (superseded) return false;

  final life = (lifecycleState ?? '').toString().trim().toLowerCase();
  if (life == 'voided' ||
      life == 'cancelled' ||
      life == 'canceled' ||
      life == 'credited' ||
      life == 'superseded') {
    return false;
  }

  if (isCreditNoteKind(saleKind) ||
      isCreditNoteKind(documentType) ||
      isBusinessInvoiceKind(saleKind)) {
    return false;
  }

  final kind = resolveDocumentPresentationKind(
    saleKind: saleKind,
    documentType: documentType,
    createdByRole: createdByRole,
    peppolApplicable: peppolApplicable,
    consumerSaleSuperseded: superseded,
  );
  if (kind != FluxidiDocumentPresentationKind.consumerSale) return false;

  return businessInvoiceActionStillAvailable(
    consumerSalePresent: true,
    businessInvoicePresent: false,
    conversionAllowed: true,
  );
}
