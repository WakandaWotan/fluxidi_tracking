import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/compliance_ledger_reader.dart';
import 'package:fluxidi_tracking/compliance_register_receipt_bridge.dart';
import 'package:fluxidi_tracking/payment/invoice_pdf_pending.dart';
import 'package:fluxidi_tracking/receipt/register_receipt_compat.dart';

void main() {
  group('register receipt compat — anonymized live shapes', () {
    test('working PDF ride still classifies as open-existing', () {
      final c = registerReceiptWorkingPdfCase();
      expect(registerReceiptDetailsShouldOpen(c.tripHistory), isTrue);
      expect(
        classifyReceiptAsLegItem(
          legToken: 'outbound',
          bookingId: 'BK-ANON-021',
          itemTotalEur: 42,
          parentBookingTotalEur: 42,
        ),
        isTrue,
      );
      expect(
        classifyRegisterPdfView(
          backendState: InvoicePdfFetchState.ready,
          generatedLocalPdf: false,
        ),
        RegisterPdfViewOutcome.openExisting,
      );
      expect(
        registerPdfViewCopiesText(RegisterPdfViewOutcome.openExisting),
        isFalse,
      );
    });

    test('11 Sep 15:52-shaped street ride does not treat copy as PDF', () {
      final c = registerReceiptPendingInvoicePdfCase();
      expect(c.tripHistory['booking_id'], 'street_anon_1152');
      expect(c.tripHistory['total_eur'], 5.30);
      expect(registerReceiptDetailsShouldOpen(c.tripHistory), isTrue);
      expect(
        classifyRegisterPdfView(
          backendState: classifyInvoicePdfHttpStatus(202),
          generatedLocalPdf: false,
        ),
        RegisterPdfViewOutcome.pending,
      );
      expect(
        classifyRegisterPdfView(
          backendState: classifyInvoicePdfHttpStatus(202),
          generatedLocalPdf: true,
        ),
        RegisterPdfViewOutcome.generateLocal,
      );
      for (final outcome in RegisterPdfViewOutcome.values) {
        expect(registerPdfViewCopiesText(outcome), isFalse);
      }
    });

    test('12 Sep-shaped planned row classifies details without recursion', () {
      final c = registerReceiptHistoricalPlannedCase();
      expect(c.tripHistory['trip_id'], 'trip_anon_0912');
      expect(c.tripHistory['kind'], 'planned');
      expect((c.tripHistory['booking_details'] as Map)['leg_type'], isNull);
      var calls = 0;
      bool probe() {
        calls += 1;
        if (calls > 8) {
          fail('leg detection recursed on the historical planned shape');
        }
        return classifyReceiptAsLegItem(
          legToken: null,
          bookingId: c.tripHistory['booking_id']?.toString(),
          itemTotalEur: null,
          parentBookingTotalEur: 80,
        );
      }

      expect(probe(), isFalse);
      expect(calls, 1);
      expect(registerReceiptDetailsShouldOpen(c.tripHistory), isTrue);
    });

    test('ledger bridge keeps amounts and payment on historical planned', () {
      final c = registerReceiptHistoricalPlannedCase();
      final entry = ComplianceLedgerEntry.fromRaw(c.ledger, sourceLineIndex: 12);
      final json = tripHistoryJsonFromLedgerEntry(entry);
      expect(json['booking_id'], 'BK-ANON-011');
      expect(json['kind'], 'planned');
      expect(json['payment_status'], 'unpaid');
      expect(json['payment_method'], 'QR');
    });

    test('ledger bridge keeps street fare and does not invent a receipt no.', () {
      final c = registerReceiptPendingInvoicePdfCase();
      final entry = ComplianceLedgerEntry.fromRaw(c.ledger, sourceLineIndex: 11);
      final json = tripHistoryJsonFromLedgerEntry(entry);
      expect(json['booking_id'], 'street_anon_1152');
      expect(json['kind'], 'direct');
      expect(json['total_eur'], 5.30);
      expect(json['payment_status'], 'unknown');
    });

    test('missing or unreachable PDF is reported, never copied as success', () {
      expect(
        classifyRegisterPdfView(
          backendState: InvoicePdfFetchState.missing,
          generatedLocalPdf: false,
        ),
        RegisterPdfViewOutcome.missing,
      );
      expect(
        classifyRegisterPdfView(
          backendState: InvoicePdfFetchState.failure,
          generatedLocalPdf: false,
        ),
        RegisterPdfViewOutcome.unreachable,
      );
      expect(
        classifyInvoicePdfHttpStatus(200),
        InvoicePdfFetchState.ready,
      );
      expect(
        classifyInvoicePdfHttpStatus(404),
        InvoicePdfFetchState.missing,
      );
      expect(
        classifyInvoicePdfHttpStatus(503),
        InvoicePdfFetchState.failure,
      );
      expect(
        registerPdfViewCopiesText(RegisterPdfViewOutcome.missing),
        isFalse,
      );
      expect(
        registerPdfViewCopiesText(RegisterPdfViewOutcome.unreachable),
        isFalse,
      );
    });
  });
}
