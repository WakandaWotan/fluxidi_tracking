import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_book_result.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';

typedef CustomerBookingHttpPost =
    Future<http.Response> Function(
      Uri url,
      Map<String, String> headers,
      String body,
    );

class CustomerBookingQuoteClient {
  CustomerBookingQuoteClient({
    this.bookingBaseUrl = '',
    this.httpPost,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final String bookingBaseUrl;
  final CustomerBookingHttpPost? httpPost;
  final DateTime Function() clock;

  String get _base {
    final raw = bookingBaseUrl.trim().isEmpty
        ? kBookingBaseUrl
        : bookingBaseUrl.trim();
    return raw.replaceAll(RegExp(r'/+$'), '');
  }

  Future<http.Response> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) {
    final url = Uri.parse('$_base$path');
    final encoded = jsonEncode(body);
    final nextHeaders = <String, String>{
      'content-type': 'application/json',
      ...?headers,
    };
    if (httpPost != null) {
      return httpPost!(url, nextHeaders, encoded);
    }
    return http.post(url, headers: nextHeaders, body: encoded).timeout(timeout);
  }

  Map<String, dynamic> decorateBody(
    Map<String, dynamic> body,
    CustomerBookingEntryContext entry,
  ) {
    final next = Map<String, dynamic>.from(body);
    final company = entry.company;
    if (company.routingPartnerId.isNotEmpty) {
      next['public_partner_id'] = company.routingPartnerId;
      next['publicPartnerId'] = company.routingPartnerId;
      next['partner_id'] = company.routingPartnerId;
      next['partnerId'] = company.routingPartnerId;
    }
    if (company.tenantId.trim().isNotEmpty) {
      next['tenant_id'] = company.tenantId.trim();
      next['tenantId'] = company.tenantId.trim();
    }
    if (company.companyId.trim().isNotEmpty) {
      next['company_id'] = company.companyId.trim();
      next['companyId'] = company.companyId.trim();
    }
    if (company.companyName.trim().isNotEmpty) {
      next['public_partner_name'] = company.companyName.trim();
    }
    if (entry.campaignId.trim().isNotEmpty) {
      next['campaign_id'] = entry.campaignId.trim();
    }
    if (entry.affiliateId.trim().isNotEmpty) {
      next['affiliate_id'] = entry.affiliateId.trim();
    }
    if (entry.sourceLabel.trim().isNotEmpty) {
      next['source_label'] = entry.sourceLabel.trim();
    }
    final dest = entry.destination;
    if (dest != null) {
      if (dest.id.trim().isNotEmpty) next['source_place_id'] = dest.id.trim();
      if (dest.name.trim().isNotEmpty) next['source_place_name'] = dest.name.trim();
      if (dest.attribution.trim().isNotEmpty) {
        next['source_attribution'] = dest.attribution.trim();
      }
    }
    next['entry_kind'] = entry.kind.name;
    customerBookingEnsurePublicScheduleFields(next, clock: clock);
    return next;
  }

  Future<CompanyPlanQuoteResult> quote({
    required CompanyPlanQuoteRequest request,
    required CustomerBookingEntryContext entry,
  }) async {
    final res = await _post('/quote', decorateBody(request.body, entry));
    final decoded = _decode(res.body);
    if (decoded == null) {
      throw StateError('quote_http_${res.statusCode}');
    }
    final error = (decoded['error'] ?? decoded['message'] ?? '').toString();
    final failed =
        res.statusCode < 200 ||
        res.statusCode >= 300 ||
        decoded['ok'] == false;
    if (failed) {
      throw StateError(error.trim().isEmpty ? 'quote_failed' : error.trim());
    }
    if (decoded['ok'] != true) {
      decoded['ok'] = true;
    }
    return parseCompanyPlanQuote(decoded, fingerprint: request.fingerprint);
  }

  Future<Map<String, dynamic>> book({
    required Map<String, dynamic> body,
    required CustomerBookingEntryContext entry,
    Map<String, String>? headers,
  }) async {
    final res = await _post(
      '/book',
      decorateBody(body, entry),
      headers: headers,
      timeout: const Duration(seconds: 45),
    );
    final decoded = _decode(res.body) ?? <String, dynamic>{};
    final ok =
        res.statusCode >= 200 &&
        res.statusCode < 300 &&
        (decoded['ok'] == null || decoded['ok'] == true);
    if (!ok) {
      throw customerBookingBookExceptionFromResponse(res: res, decoded: decoded);
    }
    return decoded;
  }

  Map<String, dynamic>? _decode(String raw) {
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }
}

String customerBookingIdFromResponse(Map<String, dynamic> body) {
  String read(dynamic value) => (value ?? '').toString().trim();
  final booking = body['booking'] is Map
      ? Map<String, dynamic>.from(body['booking'] as Map)
      : const <String, dynamic>{};
  for (final value in <dynamic>[
    body['bookingId'],
    body['booking_id'],
    body['public_booking_id'],
    body['publicBookingId'],
    body['id'],
    booking['bookingId'],
    booking['booking_id'],
    booking['public_booking_id'],
    booking['publicBookingId'],
    booking['id'],
  ]) {
    final text = read(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}
