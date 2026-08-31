// CONSUMER-BILLIT-DOCUMENT-UI-1 — source wiring

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late String docs;
  late String presentation;

  setUpAll(() {
    docs = _read('lib/main_parts/company_booking_documents_section.dart');
    presentation = _read('lib/payment/consumer_sale_presentation.dart');
  });

  test('documents section uses consumer sale presentation helpers', () {
    expect(docs, contains('consumerOrBusinessDocumentLabelKey'));
    expect(docs, contains('resolvePeppolUiPolicy'));
    expect(docs, contains('Particuliere verkoop'));
    expect(docs, contains('Factuur'));
    expect(docs, contains('invoiceNeutral'));
    expect(docs, contains('Geregistreerd in Billit'));
    expect(docs, contains('Peppol niet van toepassing'));
    expect(docs, contains('fluxidiSaleKind'));
    expect(docs, contains('createdByRole'));
    expect(docs, contains('Peppol niet van toepassing'));
    // Consumer rows must not keep the Peppol-not-sent secondary label.
    expect(docs, contains('doc.isConsumerSale'));
  });

  test('consumer sale forbids invoice label and Peppol send', () {
    expect(presentation, contains('documentForbidsInvoiceLabel'));
    expect(presentation, contains('showSendAction'));
    expect(presentation, contains('consumer_sale'));
    expect(presentation, contains('isBusinessDocumentForPresentation'));
    expect(presentation, contains('Billit OrderType'));
  });

  test('document_core projects sale kind for list UI', () {
    final core = _read('workers/booking/modules/document_core.js');
    expect(core, contains('fluxidi_sale_kind'));
    expect(core, contains('peppol_applicable'));
    expect(core, contains('created_by_role'));
    expect(core, contains('CONSUMER-SALE-DOCUMENT-PRESENTATION-P0-1'));
  });
}
