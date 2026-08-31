// BOOKINGS-DOCUMENTS-BOUND-CLIENT-P0C
//
// Production GET transport for booking documents. Resolves headers at
// call-time and never stores tokens. URLs and identifiers are not logged.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/booking_documents_page_repository.dart';

Future<Map<String, dynamic>> loadBookingDocumentsPageHttp({
  required BookingDocumentsPageRequest request,
  required Future<Map<String, String>> Function() headers,
}) async {
  final uri = Uri.parse(
    '$kBookingBaseUrl${request.path}',
  ).replace(queryParameters: request.scopeQuery);
  final res = await http
      .get(uri, headers: await headers())
      .timeout(const Duration(seconds: 12));
  dynamic decoded;
  try {
    decoded = jsonDecode(utf8.decode(res.bodyBytes));
  } catch (_) {
    decoded = null;
  }
  if (res.statusCode != 200) {
    final apiError = (decoded is Map)
        ? (decoded['error']?.toString().trim() ?? '')
        : '';
    if (apiError.isNotEmpty) {
      throw BookingDocumentsPageException(apiError);
    }
    throw BookingDocumentsPageException('http_${res.statusCode}');
  }
  if (decoded is! Map) {
    throw BookingDocumentsPageException('invalid_payload');
  }
  return Map<String, dynamic>.from(decoded);
}

void bindBookingDocumentsPageHttpTransport() {
  loadBookingDocumentsPageUncached = loadBookingDocumentsPageHttp;
}

final bool kBookingDocumentsHttpTransportBound = () {
  bindBookingDocumentsPageHttpTransport();
  return true;
}();
