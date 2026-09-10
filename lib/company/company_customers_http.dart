// COMPANY-CUSTOMER-OPS-P0A
//
// Production HTTP transport. Headers are resolved at call-time and never
// stored. Failed writes are not cached as local successes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';

bool companyCustomerErrorLooksOffline(Object error) {
  if (error is TimeoutException || error is SocketException) return true;
  if (error is http.ClientException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('socket') ||
      text.contains('failed host lookup') ||
      text.contains('timed out') ||
      text.contains('timeout');
}

Never throwCompanyCustomerHttpError(Object error) {
  if (error is CompanyCustomerException) throw error;
  throw CompanyCustomerException(
    'transport_failed',
    offline: companyCustomerErrorLooksOffline(error),
  );
}

Map<String, dynamic> decodeCompanyCustomerJson(List<int> bytes) {
  dynamic decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    decoded = null;
  }
  if (decoded is! Map) {
    throw const CompanyCustomerException('invalid_payload');
  }
  return Map<String, dynamic>.from(decoded);
}

CompanyCustomerException exceptionFromCustomerPayload(
  Map<String, dynamic> decoded,
  int statusCode,
) {
  final error = decoded['error']?.toString().trim() ?? '';
  final fields = <String, String>{};
  final rawFields = decoded['fields'];
  if (rawFields is Map) {
    rawFields.forEach((key, value) {
      final name = key.toString().trim();
      final code = value?.toString().trim() ?? '';
      if (name.isNotEmpty && code.isNotEmpty) fields[name] = code;
    });
  }
  int? revision;
  final rawRevision = decoded['revision'];
  if (rawRevision is int && rawRevision >= 0) revision = rawRevision;
  return CompanyCustomerException(
    error.isEmpty ? 'http_$statusCode' : error,
    fields: fields,
    revision: revision,
  );
}

Future<Map<String, dynamic>> companyCustomersHttpGet({
  required String path,
  required Map<String, String> query,
  required Future<Map<String, String>> Function() headers,
}) async {
  try {
    final uri = Uri.parse('$kBookingBaseUrl$path').replace(queryParameters: query);
    final res = await http
        .get(uri, headers: await headers())
        .timeout(const Duration(seconds: 12));
    final decoded = decodeCompanyCustomerJson(res.bodyBytes);
    if (res.statusCode != 200) {
      throw exceptionFromCustomerPayload(decoded, res.statusCode);
    }
    return decoded;
  } catch (error) {
    throwCompanyCustomerHttpError(error);
  }
}

Future<Map<String, dynamic>> companyCustomersHttpSend({
  required String method,
  required String path,
  required Map<String, String> query,
  required Map<String, dynamic> body,
  required Future<Map<String, String>> Function() headers,
  String? idempotencyKey,
}) async {
  try {
    final uri = Uri.parse('$kBookingBaseUrl$path').replace(queryParameters: query);
    final resolved = Map<String, String>.from(await headers());
    if ((idempotencyKey ?? '').trim().isNotEmpty) {
      resolved['Idempotency-Key'] = idempotencyKey!.trim();
    }
    late final http.Response res;
    final encoded = jsonEncode(body);
    switch (method) {
      case 'POST':
        res = await http
            .post(uri, headers: resolved, body: encoded)
            .timeout(const Duration(seconds: 12));
        break;
      case 'PATCH':
        res = await http
            .patch(uri, headers: resolved, body: encoded)
            .timeout(const Duration(seconds: 12));
        break;
      default:
        throw const CompanyCustomerException('method_not_allowed');
    }
    final decoded = decodeCompanyCustomerJson(res.bodyBytes);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw exceptionFromCustomerPayload(decoded, res.statusCode);
    }
    return decoded;
  } catch (error) {
    throwCompanyCustomerHttpError(error);
  }
}
