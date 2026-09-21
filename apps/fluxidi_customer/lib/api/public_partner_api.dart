/// Thin client for the public partner endpoints of the booking API.
///
/// Read-only. No authentication, no quote, no booking, no payment. The base URL
/// must be configured explicitly; there is no production fallback.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'public_partner_models.dart';

/// Injectable GET transport, shaped so `http.get` can be passed directly.
typedef PublicApiHttpGet =
    Future<http.Response> Function(Uri url, {Map<String, String>? headers});

enum PublicApiFailure {
  /// No base URL was configured at build time.
  notConfigured,

  /// The caller left a required search input empty.
  missingInput,

  /// Transport failed or timed out.
  network,

  /// Server answered with a non-2xx status.
  badStatus,

  /// Server answered with something this app cannot read.
  invalidResponse,
}

class PublicApiException implements Exception {
  const PublicApiException(this.failure, {this.statusCode});

  final PublicApiFailure failure;
  final int? statusCode;

  @override
  String toString() =>
      'PublicApiException(${failure.name}${statusCode == null ? '' : ', http $statusCode'})';
}

/// Normalizes a postcode the same way the existing customer flow does.
String normalizePublicSearchPostcode(String raw) =>
    raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

class PublicPartnerApi {
  PublicPartnerApi({
    required this.baseUrl,
    PublicApiHttpGet? httpGet,
    this.timeout = const Duration(seconds: 12),
  }) : _httpGet = httpGet ?? http.get;

  /// Configured base URL, without trailing slash.
  final String baseUrl;
  final Duration timeout;
  final PublicApiHttpGet _httpGet;

  static const Map<String, String> _headers = <String, String>{
    'Accept': 'application/json',
  };

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  String get _base => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  /// `GET /partners/nearby?postcode=...`
  ///
  /// The endpoint also accepts `lat` + `lng` (both required together) with an
  /// optional `radius_km`, and an optional `service` filter. Those variants are
  /// not used yet: location search needs a permission flow that this phase does
  /// not add.
  Future<PublicPartnerSearchResult> searchByPostcode(String postcode) async {
    final normalized = normalizePublicSearchPostcode(postcode);
    if (normalized.isEmpty) {
      throw const PublicApiException(PublicApiFailure.missingInput);
    }
    final uri = Uri.parse('$_base/partners/nearby').replace(
      queryParameters: <String, String>{'postcode': normalized},
    );
    final body = await _getJson(uri);
    return PublicPartnerSearchResult.fromJson(body);
  }

  /// `GET /partners/profile?partner_id=...`
  Future<PublicPartnerProfile> loadProfile(String partnerId) async {
    final id = partnerId.trim();
    if (id.isEmpty) {
      throw const PublicApiException(PublicApiFailure.missingInput);
    }
    final uri = Uri.parse('$_base/partners/profile').replace(
      queryParameters: <String, String>{'partner_id': id},
    );
    final body = await _getJson(uri);
    final profile = asStringKeyedMap(body['profile']);
    if (profile.isEmpty) {
      throw const PublicApiException(PublicApiFailure.invalidResponse);
    }
    return PublicPartnerProfile.fromJson(profile, partnerId: id);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    if (!isConfigured) {
      throw const PublicApiException(PublicApiFailure.notConfigured);
    }
    final http.Response response;
    try {
      response = await _httpGet(uri, headers: _headers).timeout(timeout);
    } on PublicApiException {
      rethrow;
    } catch (_) {
      throw const PublicApiException(PublicApiFailure.network);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PublicApiException(
        PublicApiFailure.badStatus,
        statusCode: response.statusCode,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const PublicApiException(PublicApiFailure.invalidResponse);
    }
    if (decoded is! Map) {
      throw const PublicApiException(PublicApiFailure.invalidResponse);
    }
    final body = asStringKeyedMap(decoded);
    if (body['ok'] == false) {
      throw const PublicApiException(PublicApiFailure.invalidResponse);
    }
    return body;
  }
}
