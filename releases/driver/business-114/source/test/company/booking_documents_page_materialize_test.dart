import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/booking_documents_page_repository.dart';
import 'package:fluxidi_tracking/company/booking_documents_presentation.dart';
import 'package:fluxidi_tracking/driver/trip_history_booking_detail_repository.dart';
import 'package:fluxidi_tracking/payment/consumer_sale_presentation.dart';

BookingDocumentsPageRequest _req() {
  return const BookingDocumentsPageRequest(
    tenantId: 't-a',
    companyId: 'c-a',
    bookingId: 'b-1',
  );
}

Map<String, dynamic> _workerEnvelope(String json) {
  return Map<String, dynamic>.from(jsonDecode(json) as Map);
}

void main() {
  test('1. Worker-style ok/documents/count with two valid rows keeps both', () {
    final result = parseBookingDocumentsPagePayload(
      _workerEnvelope('''
{
  "ok": true,
  "documents": [
    {
      "document_id": "doc_a",
      "fluxidi_sale_kind": "consumer_sale",
      "presentation_label_key": "consumerSale",
      "fiscal_kind": "consumer_sale",
      "active_payable_revenue": true
    },
    {
      "document_id": "doc_b",
      "document_type": "invoice",
      "fiscal_kind": "unspecified",
      "presentation_label_key": "invoiceNeutral",
      "active_payable_revenue": true
    }
  ],
  "count": 2,
  "warnings": [],
  "invoice_pdf": {"ready": true, "exists": true}
}
'''),
      request: _req(),
    );
    expect(result.documents, hasLength(2));
    expect(result.count, 2);
    expect(result.omittedRowCount, 0);
    expect(result.documents.first['fluxidi_sale_kind'], 'consumer_sale');
    expect(result.documents.last['presentation_label_key'], 'invoiceNeutral');
  });

  test('2. additive active_payable_count and review_required parse safely', () {
    final result = parseBookingDocumentsPagePayload(
      _workerEnvelope('''
{
  "ok": true,
  "documents": [
    {"document_id": "doc_a", "fluxidi_sale_kind": "consumer_sale", "active_payable_revenue": true},
    {"document_id": "doc_b", "document_type": "invoice", "active_payable_revenue": true}
  ],
  "count": "2",
  "active_payable_count": 2,
  "review_required": true,
  "warnings": [],
  "unknown_fiscal_flag": true
}
'''),
      request: _req(),
    );
    expect(result.activePayableCount, 2);
    expect(result.reviewRequired, isTrue);
    expect(result.documents, hasLength(2));
  });

  test('3. one recoverable bad field does not fail the section', () {
    final result = parseBookingDocumentsPagePayload({
      'ok': true,
      'documents': <Object?>[
        <String, dynamic>{
          'document_id': 'doc_good',
          'fluxidi_sale_kind': 'consumer_sale',
          'active_payable_revenue': true,
        },
        <String, dynamic>{
          'document_id': 'doc_recoverable',
          'document_type': 'invoice',
          'document_number': <String, dynamic>{'nested': true},
          'billit_export': <String>['not-a-map'],
          'peppol_applicable': 'yes',
          'unknown_additive_fiscal': <String, dynamic>{'extra': 1},
        },
      ],
      'count': 2,
      'warnings': <dynamic>[],
    }, request: _req());
    expect(result.documents, hasLength(2));
    expect(result.omittedRowCount, 0);
    final recovered = result.documents.last;
    expect(recovered['document_id'], 'doc_recoverable');
    expect(recovered['document_number'], '');
    expect(recovered.containsKey('billit_export'), isFalse);
    expect(recovered['presentation_label_key'], 'invoiceNeutral');
  });

  test('4. one impossible row does not remove another valid row', () {
    final result = parseBookingDocumentsPagePayload({
      'ok': true,
      'documents': <Object?>[
        <String, dynamic>{
          'document_id': 'doc_keep',
          'fluxidi_sale_kind': 'consumer_sale',
          'active_payable_revenue': true,
        },
        'not-a-document',
        <String, dynamic>{
          'document_type': 'invoice',
          'document_number': <int>[1, 2],
        },
      ],
      'count': 3,
      'warnings': <dynamic>[],
    }, request: _req());
    expect(result.documents, hasLength(1));
    expect(result.documents.single['document_id'], 'doc_keep');
    expect(result.omittedRowCount, 2);
    expect(result.warnings, contains('row_omitted'));
  });

  test('5. consumer-sale metadata remains consumer sale', () {
    final row = materializeBookingDocumentRow(<String, dynamic>{
      'document_id': 'doc_sale',
      'fluxidi_sale_kind': 'consumer_sale',
      'document_type': 'invoice',
      'presentation_label_key': 'consumerSale',
      'fiscal_kind': 'consumer_sale',
      'peppol_applicable': false,
    });
    expect(row, isNotNull);
    expect(row!['fluxidi_sale_kind'], 'consumer_sale');
    expect(row['fiscal_kind'], 'consumer_sale');
    expect(row['presentation_label_key'], 'consumerSale');
    expect(
      resolveDocumentPresentationKind(
        saleKind: row['fluxidi_sale_kind'],
        documentType: row['document_type'],
        presentationLabelKey: row['presentation_label_key'],
        fiscalKind: row['fiscal_kind'],
        peppolApplicable: row['peppol_applicable'] as bool?,
      ),
      FluxidiDocumentPresentationKind.consumerSale,
    );
    expect(
      consumerOrBusinessDocumentLabelKey(
        saleKind: row['fluxidi_sale_kind'],
        presentationLabelKey: row['presentation_label_key'],
        fiscalKind: row['fiscal_kind'],
      ),
      'consumerSale',
    );
  });

  test(
    '6. bare legacy invoice uses neutral Factuur, not Zakelijke factuur',
    () {
      final row = materializeBookingDocumentRow(<String, dynamic>{
        'document_id': 'doc_legacy',
        'document_type': 'invoice',
      });
      expect(row, isNotNull);
      expect(row!['fiscal_kind'], 'unspecified');
      expect(row['presentation_label_key'], 'invoiceNeutral');
      expect(row['fluxidi_sale_kind'], '');
      expect(
        consumerOrBusinessDocumentLabelKey(
          saleKind: row['fluxidi_sale_kind'],
          documentType: row['document_type'],
          presentationLabelKey: row['presentation_label_key'],
          fiscalKind: row['fiscal_kind'],
        ),
        'invoiceNeutral',
      );
      expect(
        resolveDocumentPresentationKind(
          saleKind: row['fluxidi_sale_kind'],
          documentType: row['document_type'],
          fiscalKind: row['fiscal_kind'],
        ),
        FluxidiDocumentPresentationKind.invoiceNeutral,
      );
    },
  );

  test(
    'optional field absent, null, numeric/string, and billit_export shapes',
    () {
      final absent = materializeBookingDocumentRow(<String, dynamic>{
        'document_id': 'doc_absent',
        'document_type': 'invoice',
      });
      final withNulls = materializeBookingDocumentRow(<String, dynamic>{
        'document_id': 'doc_nulls',
        'document_type': 'invoice',
        'document_number': null,
        'fiscal_kind': null,
        'billit_export': null,
        'peppol_applicable': null,
        'active_payable_revenue': null,
      });
      final numeric = materializeBookingDocumentRow(<String, dynamic>{
        'document_id': 17,
        'document_number': 42,
        'document_type': 'invoice',
      });
      final exportMap = materializeBookingDocumentRow(<String, dynamic>{
        'document_id': 'doc_export',
        'document_type': 'invoice',
        'billit_export': <String, dynamic>{'status': 'linked'},
      });
      final exportNonMap = materializeBookingDocumentRow(<String, dynamic>{
        'document_id': 'doc_export_bad',
        'document_type': 'invoice',
        'billit_export': 3,
      });
      expect(absent!['document_number'], '');
      expect(withNulls!['document_number'], '');
      expect(withNulls.containsKey('billit_export'), isFalse);
      expect(numeric!['document_id'], '17');
      expect(numeric['document_number'], '42');
      expect(exportMap!['billit_export'], isA<Map<String, dynamic>>());
      expect(exportNonMap!.containsKey('billit_export'), isFalse);
    },
  );

  test('two payable materialized rows still require Controle vereist', () {
    final result = parseBookingDocumentsPagePayload({
      'ok': true,
      'documents': <Map<String, dynamic>>[
        <String, dynamic>{
          'document_id': 'doc_a',
          'fluxidi_sale_kind': 'consumer_sale',
          'active_payable_revenue': true,
        },
        <String, dynamic>{
          'document_id': 'doc_b',
          'document_type': 'invoice',
          'active_payable_revenue': true,
        },
      ],
      'count': 2,
      'active_payable_count': 2,
      'review_required': true,
      'warnings': <dynamic>[],
    }, request: _req());
    expect(result.reviewRequired, isTrue);
    expect(
      bookingDocumentsRequireReview(
        documents: result.documents,
        activePayableCount: result.activePayableCount,
        reviewRequiredFlag: result.reviewRequired,
      ),
      isTrue,
    );
    final split = splitBookingDocumentsForDisplay(
      result.documents,
      activePayableCount: result.activePayableCount,
      reviewRequiredFlag: result.reviewRequired,
    );
    expect(split.reviewRequired, isTrue);
  });

  test('non-list documents remains a controlled envelope error', () {
    expect(
      () => parseBookingDocumentsPagePayload(<String, dynamic>{
        'ok': true,
        'documents': <String, dynamic>{},
      }, request: _req()),
      throwsA(
        isA<BookingDocumentsPageException>().having(
          (error) => error.code,
          'code',
          'invalid_payload',
        ),
      ),
    );
  });

  test('13. no new automatic document, PDF, or history-detail fan-out', () {
    expect(bookingDocumentsFetchOnListMount(), isFalse);
    expect(tripHistoryAllowsAutomaticDetailHydration(), isFalse);
  });
}
