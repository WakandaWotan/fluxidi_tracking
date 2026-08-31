import 'package:fluxidi_tracking/payment/consumer_sale_presentation.dart';

String bookingDocumentFiscalIdentity(Map<String, dynamic> doc) {
  final fiscal = (doc['fiscal_identity'] ?? doc['fiscalIdentity'] ?? '')
      .toString()
      .trim();
  if (fiscal.isNotEmpty) return fiscal;
  return (doc['document_id'] ?? doc['documentId'] ?? '').toString().trim();
}

List<Map<String, dynamic>> mergeBookingDocumentsByFiscalIdentity(
  Iterable<Map<String, dynamic>> docs,
) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final doc in docs) {
    final key = bookingDocumentFiscalIdentity(doc);
    if (key.isEmpty) continue;
    if (!seen.add(key)) continue;
    out.add(doc);
  }
  return List<Map<String, dynamic>>.unmodifiable(out);
}

bool bookingDocumentIsActivePayable(Map<String, dynamic> doc) {
  if (doc['active_payable_revenue'] == false) return false;
  if (doc['superseded'] == true) return false;
  final life = (doc['lifecycle_state'] ?? doc['lifecycleState'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  if (life == 'superseded' ||
      life == 'void' ||
      life == 'voided' ||
      life == 'cancelled' ||
      life == 'canceled' ||
      life == 'credited') {
    return false;
  }
  final kind = resolveDocumentPresentationKind(
    saleKind: doc['fluxidi_sale_kind'] ?? doc['sale_kind'] ?? doc['saleKind'],
    documentType: doc['document_type'] ?? doc['documentType'],
    invoiceIntent: doc['invoice_intent'] ?? doc['invoiceIntent'],
    createdByRole: doc['created_by_role'] ?? doc['createdByRole'],
    peppolApplicable: doc['peppol_applicable'] is bool
        ? doc['peppol_applicable'] as bool
        : (doc['peppolApplicable'] is bool
              ? doc['peppolApplicable'] as bool
              : null),
    presentationLabelKey:
        doc['presentation_label_key'] ?? doc['presentationLabelKey'],
    fiscalKind: doc['fiscal_kind'] ?? doc['fiscalKind'],
    consumerSaleSuperseded: doc['superseded'] == true,
  );
  return kind != FluxidiDocumentPresentationKind.creditNote;
}

int countActivePayableBookingDocuments(Iterable<Map<String, dynamic>> docs) {
  var count = 0;
  for (final doc in mergeBookingDocumentsByFiscalIdentity(docs)) {
    if (bookingDocumentIsActivePayable(doc)) count += 1;
  }
  return count;
}

bool shouldInjectLocalIssuedDocument({
  required String localDocumentId,
  required String localSaleKind,
  required Iterable<Map<String, dynamic>> visibleDocuments,
}) {
  final id = localDocumentId.trim();
  if (id.isEmpty) return false;
  final localKind = localSaleKind.trim().toLowerCase();
  for (final doc in visibleDocuments) {
    final existingId = bookingDocumentFiscalIdentity(doc);
    if (existingId == id) return false;
    final existingKind =
        (doc['fluxidi_sale_kind'] ?? doc['sale_kind'] ?? '').toString().trim();
    if (localKind == 'business_invoice' &&
        (existingKind == 'consumer_sale' || existingKind == 'private_sale') &&
        doc['superseded'] != true) {
      // A live consumer sale must not grow a second business-looking card
      // unless an explicit converted business identity already exists.
      return false;
    }
  }
  return true;
}
