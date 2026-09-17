// Structured /book outcome. Keeps HTTP status, server code and allocator
// reason without tokens or full customer payloads.

import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';

class CustomerBookingBookException implements Exception {
  const CustomerBookingBookException({
    required this.statusCode,
    required this.code,
    this.allocatorReason = '',
    this.requestId = '',
    this.raw = '',
    this.sent = true,
    this.uncertain = false,
  });

  final int statusCode;
  final String code;
  final String allocatorReason;
  final String requestId;
  final String raw;
  final bool sent;
  final bool uncertain;

  @override
  String toString() => raw.isEmpty ? code : raw;
}

CustomerBookingBookException customerBookingBookExceptionFromResponse({
  required http.Response res,
  required Map<String, dynamic> decoded,
}) {
  final error = (decoded['error'] ?? decoded['message'] ?? 'HTTP ${res.statusCode}')
      .toString()
      .trim();
  final availability = decoded['availability'] is Map
      ? Map<String, dynamic>.from(decoded['availability'] as Map)
      : const <String, dynamic>{};
  final code = (decoded['error_code'] ??
          decoded['code'] ??
          availability['reason_code'] ??
          availability['reason'] ??
          '')
      .toString()
      .trim();
  final allocator = (decoded['allocator_reason'] ??
          availability['allocator_reason'] ??
          availability['block_reason'] ??
          '')
      .toString()
      .trim();
  final requestId = (decoded['request_id'] ??
          decoded['requestId'] ??
          decoded['correlation_id'] ??
          decoded['correlationId'] ??
          res.headers['x-request-id'] ??
          '')
      .toString()
      .trim();
  return CustomerBookingBookException(
    statusCode: res.statusCode,
    code: code.isEmpty ? error : code,
    allocatorReason: allocator,
    requestId: requestId,
    raw: error,
    sent: true,
  );
}

CustomerBookingBookException customerBookingBookExceptionFromCaught(Object error) {
  if (error is CustomerBookingBookException) return error;
  final lower = error.toString().toLowerCase();
  final network = error is http.ClientException ||
      lower.contains('timeout') ||
      lower.contains('socket') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('network');
  return CustomerBookingBookException(
    statusCode: 0,
    code: network
        ? kCustomerBookingIssueNetwork
        : kCustomerBookingIssueBookFailed,
    raw: error.toString(),
    sent: !network,
    uncertain: network,
  );
}

String customerBookingBookIssueFromException(CustomerBookingBookException error) {
  if (error.uncertain || error.code == kCustomerBookingIssueNetwork) {
    return kCustomerBookingIssueNetwork;
  }
  return customerBookingBookIssueFromRaw(
    [
      error.code,
      error.allocatorReason,
      error.raw,
    ].where((part) => part.trim().isNotEmpty).join(' '),
  );
}

void customerBookingLogBookFailure(CustomerBookingBookException error) {
  // ignore: avoid_print
  print(
    '[CUSTOMER_BOOKING][BOOK] sent=${error.sent} status=${error.statusCode} '
    'code=${error.code} allocator=${error.allocatorReason} '
    'request_id=${error.requestId} uncertain=${error.uncertain}',
  );
}
