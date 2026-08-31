import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/invoice_pdf_pending.dart';

void main() {
  test('classifies pending, ready, missing and failure', () {
    expect(classifyInvoicePdfHttpStatus(200), InvoicePdfFetchState.ready);
    expect(classifyInvoicePdfHttpStatus(202), InvoicePdfFetchState.pending);
    expect(classifyInvoicePdfHttpStatus(404), InvoicePdfFetchState.missing);
    expect(classifyInvoicePdfHttpStatus(503), InvoicePdfFetchState.failure);
  });

  test('bounded retry respects Retry-After and does not storm', () {
    expect(
      shouldRetryInvoicePdf(
        state: InvoicePdfFetchState.pending,
        pendingAttempts: 0,
      ),
      isTrue,
    );
    expect(
      shouldRetryInvoicePdf(
        state: InvoicePdfFetchState.pending,
        pendingAttempts: InvoicePdfPendingPolicy.maxPendingRetries,
      ),
      isFalse,
    );
    expect(
      shouldRetryInvoicePdf(
        state: InvoicePdfFetchState.missing,
        pendingAttempts: 0,
      ),
      isFalse,
    );
    expect(
      parseInvoicePdfRetryAfter(<String, String>{'retry-after': '9'}),
      InvoicePdfPendingPolicy.maxRetry,
    );
    expect(
      parseInvoicePdfRetryAfter(<String, String>{'Retry-After': '2'}),
      const Duration(seconds: 2),
    );
  });

  test('preparing label key is stable for NL/FR/EN/ES wiring', () {
    expect(invoicePdfPreparingLabelKey(), 'documentPreparing');
  });
}
