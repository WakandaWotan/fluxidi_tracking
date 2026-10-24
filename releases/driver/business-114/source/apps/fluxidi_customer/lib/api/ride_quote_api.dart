/// Quote and availability calls for a customer ride.
///
/// `POST /quote` prices a ride and `GET /partners/availability` lists the
/// company's vehicles for that moment. Neither creates a booking or a payment.
library;

import 'dart:async';
import 'dart:convert';

import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';
import 'package:http/http.dart' as http;

import 'public_partner_api.dart';

typedef RideApiHttpPost =
    Future<http.Response> Function(
      Uri url, {
      Map<String, String>? headers,
      Object? body,
    });

class RideQuoteApi {
  RideQuoteApi({
    required this.baseUrl,
    RideApiHttpPost? httpPost,
    PublicApiHttpGet? httpGet,
    this.timeout = const Duration(seconds: 20),
  }) : _httpPost = httpPost ?? http.post,
       _httpGet = httpGet ?? http.get;

  final String baseUrl;
  final Duration timeout;
  final RideApiHttpPost _httpPost;
  final PublicApiHttpGet _httpGet;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  String get _base => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  /// `POST /quote` for one partner. Returns the parsed server price.
  ///
  /// The request keeps its fingerprint so a late answer can be recognised and
  /// dropped by the caller.
  Future<FluxidiQuoteResult> quote({
    required FluxidiQuoteRequest request,
    required FluxidiPartnerScope scope,
  }) async {
    if (!isConfigured) {
      throw const PublicApiException(PublicApiFailure.notConfigured);
    }
    final body = scope.decorate(request.body);
    fluxidiEnsurePublicScheduleFields(body);

    final http.Response response;
    try {
      response = await _httpPost(
        Uri.parse('$_base/quote'),
        headers: const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(timeout);
    } catch (_) {
      throw const PublicApiException(PublicApiFailure.network);
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
    final map = Map<String, dynamic>.from(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // The server explains why it cannot price; keep its code.
      final error = (map['error'] ?? '').toString().trim();
      if (error.isNotEmpty) throw FluxidiQuoteException(error);
      throw PublicApiException(
        PublicApiFailure.badStatus,
        statusCode: response.statusCode,
      );
    }
    return parseFluxidiQuote(map, fingerprint: request.fingerprint);
  }

  /// `GET /partners/availability` for the chosen pickup moment.
  Future<FluxidiAvailabilitySnapshot> availability({
    required String partnerId,
    required DateTime pickupUtc,
    required int passengers,
    int durationMin = 30,
    int waitMin = 0,
    int returnDurationMin = 0,
  }) async {
    if (!isConfigured) {
      throw const PublicApiException(PublicApiFailure.notConfigured);
    }
    final id = partnerId.trim();
    if (id.isEmpty) {
      throw const PublicApiException(PublicApiFailure.missingInput);
    }
    final uri = Uri.parse('$_base/partners/availability').replace(
      queryParameters: <String, String>{
        'partner_id': id,
        'pickup_iso': pickupUtc.toUtc().toIso8601String(),
        'pax': '$passengers',
        'duration_min': '$durationMin',
        if (waitMin > 0) 'wait_min': '$waitMin',
        if (returnDurationMin > 0) 'return_duration_min': '$returnDurationMin',
      },
    );

    final http.Response response;
    try {
      response = await _httpGet(
        uri,
        headers: const <String, String>{'Accept': 'application/json'},
      ).timeout(timeout);
    } catch (_) {
      throw const PublicApiException(PublicApiFailure.network);
    }
    if (response.statusCode != 200) {
      return const FluxidiAvailabilitySnapshot(loadFailed: true, fetched: true);
    }
    try {
      return parseFluxidiAvailability(jsonDecode(response.body));
    } catch (_) {
      return const FluxidiAvailabilitySnapshot(loadFailed: true, fetched: true);
    }
  }
}
