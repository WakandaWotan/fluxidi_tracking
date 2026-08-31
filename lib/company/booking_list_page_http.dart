// BOOKINGS-LIST-PAGINATION-CLIENT-P0C
//
// Production GET transport for booking list pages. Resolves headers at
// call-time and never stores tokens. URLs are not logged.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';

Future<Map<String, dynamic>> loadBookingListPageHttp({
  required BookingListPageRequest request,
  required int limit,
  required Future<Map<String, String>> Function() headers,
}) async {
  final query = buildBookingListPageQuery(request: request, limit: limit);
  final uri = Uri.parse(
    '$kBookingBaseUrl${request.path}',
  ).replace(queryParameters: query);
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
    final apiError = (decoded is Map<String, dynamic>)
        ? (decoded['error']?.toString().trim() ?? '')
        : '';
    if (apiError.isNotEmpty) {
      throw BookingListPageException(apiError);
    }
    throw BookingListPageException('http_${res.statusCode}');
  }
  if (decoded is! Map) {
    throw BookingListPageException('invalid_payload');
  }
  return Map<String, dynamic>.from(decoded);
}

/// Binds the process-wide repository to the HTTP transport.
void bindBookingListPageHttpTransport() {
  loadBookingListPageUncached = loadBookingListPageHttp;
}

final bool kBookingListHttpTransportBound = () {
  bindBookingListPageHttpTransport();
  return true;
}();
