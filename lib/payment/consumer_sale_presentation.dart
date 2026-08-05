// CONSUMER-BILLIT-DOCUMENT-UI-1
//
// Pure presentation contract for private/consumer Billit sales.
// Internally Billit may store OrderType Invoice; Fluxidi must never show
// "Factuur" for a consumer sale, and Peppol is never applicable.

const String kConsumerSaleKind = 'consumer_sale';

bool isConsumerSaleKind(Object? raw) {
  final s = (raw ?? '').toString().trim().toLowerCase();
  return s == kConsumerSaleKind ||
      s == 'private_sale' ||
      s == 'particuliere_verkoop' ||
      s == 'ontvangstbewijs';
}

bool documentForbidsInvoiceLabel({
  Object? saleKind,
  Object? documentType,
  bool businessInvoiceIntent = false,
}) {
  if (businessInvoiceIntent) return false;
  if (isConsumerSaleKind(saleKind)) return true;
  return false;
}

/// Customer-facing document type label key.
String consumerOrBusinessDocumentLabelKey({
  Object? saleKind,
  Object? documentType,
  bool businessInvoiceIntent = false,
}) {
  if (businessInvoiceIntent) return 'invoice';
  if (isConsumerSaleKind(saleKind)) return 'consumerSale';
  final type = (documentType ?? '').toString().trim().toLowerCase();
  if (type == 'invoice') return 'invoice';
  if (type == 'credit_note') return 'creditNote';
  if (type == 'refund_proof') return 'refundProof';
  return type.isEmpty ? 'document' : type;
}

String consumerSaleStatusLabelKey({
  Object? saleKind,
  bool registeredInBillit = false,
  Object? billitOrderId,
}) {
  if (!isConsumerSaleKind(saleKind)) return 'unknown';
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
  bool? peppolApplicable,
  bool businessInvoiceIntent = false,
}) {
  if (isConsumerSaleKind(saleKind) || peppolApplicable == false) {
    return const PeppolUiPolicy(
      applicable: false,
      showNotApplicable: true,
      showMissingEndpointWarning: false,
      showSettingsRequiredWarning: false,
      showSendAction: false,
    );
  }
  if (businessInvoiceIntent) {
    return const PeppolUiPolicy(
      applicable: true,
      showNotApplicable: false,
      showMissingEndpointWarning: true,
      showSettingsRequiredWarning: true,
      showSendAction: true,
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
  if (method == 'cash') return 'cash';
  if (method == 'qr' || method == 'qr_code') return 'qr';
  if (provider == 'mollie') return 'onlineMollie';
  if (method == 'bank_transfer' || method == 'bank_transfer_bacs') {
    return 'bankTransfer';
  }
  return method.isEmpty ? 'unknown' : method;
}

bool businessInvoiceActionStillAvailable({
  required bool consumerSalePresent,
  required bool businessInvoicePresent,
  required bool conversionAllowed,
}) {
  if (businessInvoicePresent) return false;
  if (!conversionAllowed) return false;
  return true;
}
