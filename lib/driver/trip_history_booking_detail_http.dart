import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/driver/trip_history_booking_detail_repository.dart';

Future<Map<String, dynamic>> loadTripHistoryBookingDetailHttp({
  required TripHistoryBookingDetailRequest request,
  required Future<Map<String, String>> Function() headers,
}) async {
  final uri = Uri.parse(
    '$kBookingBaseUrl${request.path}',
  ).replace(queryParameters: request.scopeQuery);
  final res = await http
      .get(uri, headers: await headers())
      .timeout(const Duration(seconds: 10));
  dynamic decoded;
  try {
    decoded = jsonDecode(utf8.decode(res.bodyBytes));
  } catch (_) {
    decoded = null;
  }
  if (res.statusCode != 200) {
    throw TripHistoryBookingDetailException('http_${res.statusCode}');
  }
  if (decoded is! Map || decoded['ok'] != true) {
    throw TripHistoryBookingDetailException('invalid_payload');
  }
  return Map<String, dynamic>.from(decoded);
}

void bindTripHistoryBookingDetailHttpTransport() {
  loadTripHistoryBookingDetailUncached = loadTripHistoryBookingDetailHttp;
}

final bool kTripHistoryBookingDetailHttpTransportBound = () {
  bindTripHistoryBookingDetailHttpTransport();
  return true;
}();
