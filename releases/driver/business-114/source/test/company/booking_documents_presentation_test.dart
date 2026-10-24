import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/booking_documents_page_repository.dart';
import 'package:fluxidi_tracking/company/booking_documents_presentation.dart';
import 'package:fluxidi_tracking/driver/trip_history_booking_detail_repository.dart';
import 'package:fluxidi_tracking/payment/consumer_sale_presentation.dart';

void main() {
  test('8. worker document plus local synthetic merges to one current row', () {
    final visible = mergeBookingDocumentsByFiscalIdentity([
      <String, dynamic>{
        'document_id': 'doc_one',
        'fiscal_identity': 'doc_one',
        'fluxidi_sale_kind': 'consumer_sale',
        'active_payable_revenue': true,
      },
      <String, dynamic>{
        'document_id': 'doc_one',
        'fiscal_identity': 'doc_one',
        'fluxidi_sale_kind': 'business_invoice',
      },
    ]);
    expect(visible, hasLength(1));
    expect(
      shouldInjectLocalIssuedDocument(
        localDocumentId: 'doc_one',
        localSaleKind: 'business_invoice',
        visibleDocuments: visible,
      ),
      isFalse,
    );
  });

  test('9. two truly active payable documents require Controle vereist', () {
    final docs = [
      <String, dynamic>{
        'document_id': 'doc_a',
        'fiscal_identity': 'doc_a',
        'fluxidi_sale_kind': 'consumer_sale',
        'active_payable_revenue': true,
      },
      <String, dynamic>{
        'document_id': 'doc_b',
        'fiscal_identity': 'doc_b',
        'document_type': 'invoice',
        'active_payable_revenue': true,
      },
    ];
    final split = splitBookingDocumentsForDisplay(docs);
    expect(split.reviewRequired, isTrue);
    expect(split.current, isEmpty);
    expect(split.history, hasLength(2));
    expect(
      bookingDocumentsRequireReview(documents: docs, activePayableCount: 2),
      isTrue,
    );
  });

  test('6. superseded consumer plus current business keeps one current row', () {
    final split = splitBookingDocumentsForDisplay([
      <String, dynamic>{
        'document_id': 'doc_old',
        'fiscal_identity': 'doc_old',
        'fluxidi_sale_kind': 'consumer_sale',
        'superseded': true,
        'lifecycle_state': 'superseded',
        'active_payable_revenue': false,
      },
      <String, dynamic>{
        'document_id': 'doc_new',
        'fiscal_identity': 'doc_new',
        'fluxidi_sale_kind': 'business_invoice',
        'invoice_intent': 'business_invoice',
        'active_payable_revenue': true,
      },
    ]);
    expect(split.reviewRequired, isFalse);
    expect(split.current, hasLength(1));
    expect(split.history, hasLength(1));
    expect(split.current.single['document_id'], 'doc_new');
  });

  test('7. PDF title key equals list presentation for consumer sale', () {
    expect(
      consumerOrBusinessPdfTitleKey(
        saleKind: 'consumer_sale',
        presentationLabelKey: 'consumerSale',
        fiscalKind: 'consumer_sale',
      ),
      'ritbon',
    );
    expect(
      consumerOrBusinessDocumentLabelKey(
        saleKind: 'consumer_sale',
        presentationLabelKey: 'consumerSale',
        fiscalKind: 'consumer_sale',
      ),
      'consumerSale',
    );
  });

  test('13. no new automatic document, PDF, or history-detail fan-out', () {
    expect(bookingDocumentsFetchOnListMount(), isFalse);
    expect(tripHistoryAllowsAutomaticDetailHydration(), isFalse);
  });
}
