// INVOICE-PDF-PENDING-CLIENT-P0C
//
// Bounded client handling for Worker PDF 202 pending vs permanent 404.

enum InvoicePdfFetchState { ready, pending, missing, failure }

class InvoicePdfPendingPolicy {
  static const int maxPendingRetries = 2;
  static const Duration defaultRetry = Duration(seconds: 2);
  static const Duration maxRetry = Duration(seconds: 5);
}

InvoicePdfFetchState classifyInvoicePdfHttpStatus(
  int status, {
  String? error,
}) {
  if (status == 200) return InvoicePdfFetchState.ready;
  if (status == 202) return InvoicePdfFetchState.pending;
  final token = (error ?? '').trim().toLowerCase();
  if (status == 404) {
    if (token == 'invoice_pdf_pending') return InvoicePdfFetchState.pending;
    return InvoicePdfFetchState.missing;
  }
  if (status >= 500 && status < 600) return InvoicePdfFetchState.failure;
  return InvoicePdfFetchState.failure;
}

Duration parseInvoicePdfRetryAfter(Map<String, String> headers) {
  final raw =
      headers['retry-after'] ??
      headers['Retry-After'] ??
      headers['retry_after'] ??
      '';
  final seconds = int.tryParse(raw.trim());
  if (seconds == null || seconds <= 0) {
    return InvoicePdfPendingPolicy.defaultRetry;
  }
  final bounded = Duration(seconds: seconds);
  if (bounded > InvoicePdfPendingPolicy.maxRetry) {
    return InvoicePdfPendingPolicy.maxRetry;
  }
  return bounded;
}

bool shouldRetryInvoicePdf({
  required InvoicePdfFetchState state,
  required int pendingAttempts,
}) {
  if (state != InvoicePdfFetchState.pending) return false;
  return pendingAttempts < InvoicePdfPendingPolicy.maxPendingRetries;
}

String invoicePdfPreparingLabelKey() => 'documentPreparing';
