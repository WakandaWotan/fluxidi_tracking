// CLOUD-AI-2: Flutter client for the Dispatch Intelligence Worker.
//
// Disabled by default (kUseDispatchIntelligenceWorker). Advice-only: this
// client never mutates bookings or assignment decisions.
//
// PII policy — the request payloads may ONLY contain:
//   country, airport_code, timing (ISO timestamps), confidence values,
//   ETA/duration seconds, route/gps state flags, luggage/passenger counts,
//   flight number/status, and coarse region labels.
// Never send names, phone numbers, emails, exact addresses, booking IDs,
// lat/lng coordinates, or any customer identity.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';

const String _diagTag = 'CLOUD_AI_2';
const Duration _defaultTimeout = Duration(seconds: 8);
const Set<String> _allowedCountries = {'BE', 'NL', 'FR', 'ES', 'PT'};
const Set<String> _allowedAirportCodes = {
  'BRU', 'CRL', 'AMS', 'CDG', 'ORY', 'LIL',
  'MAD', 'BCN', 'VLC', 'AGP', 'LIS', 'OPO', 'FAO',
};
const Set<String> _allowedRideTypes = {'taxi', 'airport', 'direct', 'scheduled'};

String _safeToken(dynamic value, int maxLen) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (text.isEmpty) return '';
  return text.length > maxLen ? text.substring(0, maxLen) : text;
}

int? _safeInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

List<String> _safeStringList(dynamic value, {int maxItems = 16, int maxLen = 64}) {
  if (value is! List) return const <String>[];
  final out = <String>[];
  for (final item in value) {
    if (out.length >= maxItems) break;
    final token = _safeToken(item, maxLen);
    if (token.isNotEmpty) out.add(token);
  }
  return out;
}

/// GET /health result.
class DispatchIntelligenceHealthResult {
  final bool ok;
  final String service;
  final String version;
  final String failureReason;

  const DispatchIntelligenceHealthResult({
    required this.ok,
    this.service = '',
    this.version = '',
    this.failureReason = '',
  });

  factory DispatchIntelligenceHealthResult.failure(String reason) =>
      DispatchIntelligenceHealthResult(ok: false, failureReason: reason);
}

/// POST /airport/pickup-advice result.
class AirportPickupAdviceResult {
  final bool ok;
  final String action;
  final int recommendedWaitMinutes;
  final int pickupBufferMinutes;
  final String riskLevel;
  final List<String> reasons;
  final bool aiUsed;
  final String failureReason;

  const AirportPickupAdviceResult({
    required this.ok,
    this.action = '',
    this.recommendedWaitMinutes = 0,
    this.pickupBufferMinutes = 0,
    this.riskLevel = '',
    this.reasons = const <String>[],
    this.aiUsed = false,
    this.failureReason = '',
  });

  factory AirportPickupAdviceResult.failure(String reason) =>
      AirportPickupAdviceResult(ok: false, failureReason: reason);

  factory AirportPickupAdviceResult.fromJson(Map<String, dynamic> json) {
    final advice = json['advice'];
    final adviceMap = advice is Map<String, dynamic>
        ? advice
        : const <String, dynamic>{};
    final ai = json['ai'];
    final aiMap = ai is Map<String, dynamic> ? ai : const <String, dynamic>{};
    return AirportPickupAdviceResult(
      ok: true,
      action: _safeToken(adviceMap['action'], 32),
      recommendedWaitMinutes:
          _safeInt(adviceMap['recommended_wait_minutes']) ?? 0,
      pickupBufferMinutes: _safeInt(adviceMap['pickup_buffer_minutes']) ?? 0,
      riskLevel: _safeToken(adviceMap['risk_level'], 12),
      reasons: _safeStringList(adviceMap['reasons']),
      aiUsed: aiMap['used'] == true,
    );
  }
}

/// POST /ride-risk result.
class RideRiskResult {
  final bool ok;
  final String riskLevel;
  final int score;
  final List<String> reasons;
  final List<String> recommendedActions;
  final String failureReason;

  const RideRiskResult({
    required this.ok,
    this.riskLevel = '',
    this.score = 0,
    this.reasons = const <String>[],
    this.recommendedActions = const <String>[],
    this.failureReason = '',
  });

  factory RideRiskResult.failure(String reason) =>
      RideRiskResult(ok: false, failureReason: reason);

  factory RideRiskResult.fromJson(Map<String, dynamic> json) {
    return RideRiskResult(
      ok: true,
      riskLevel: _safeToken(json['risk_level'], 12),
      score: _safeInt(json['score']) ?? 0,
      reasons: _safeStringList(json['reasons']),
      recommendedActions: _safeStringList(json['recommended_actions']),
    );
  }
}

/// Single offline map region suggestion.
class OfflineMapRegionSuggestion {
  final String regionId;
  final String label;
  final String country;
  final int priority;
  final String reason;

  const OfflineMapRegionSuggestion({
    required this.regionId,
    required this.label,
    required this.country,
    required this.priority,
    required this.reason,
  });
}

/// POST /offline-map-suggestions result.
class OfflineMapSuggestionsResult {
  final bool ok;
  final List<OfflineMapRegionSuggestion> suggestions;
  final String failureReason;

  const OfflineMapSuggestionsResult({
    required this.ok,
    this.suggestions = const <OfflineMapRegionSuggestion>[],
    this.failureReason = '',
  });

  factory OfflineMapSuggestionsResult.failure(String reason) =>
      OfflineMapSuggestionsResult(ok: false, failureReason: reason);

  factory OfflineMapSuggestionsResult.fromJson(Map<String, dynamic> json) {
    final raw = json['suggestions'];
    final suggestions = <OfflineMapRegionSuggestion>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final regionId = _safeToken(item['region_id'], 48);
        if (regionId.isEmpty) continue;
        suggestions.add(
          OfflineMapRegionSuggestion(
            regionId: regionId,
            label: _safeToken(item['label'], 64),
            country: _safeToken(item['country'], 4).toUpperCase(),
            priority: _safeInt(item['priority']) ?? 99,
            reason: _safeToken(item['reason'], 48),
          ),
        );
      }
    }
    return OfflineMapSuggestionsResult(ok: true, suggestions: suggestions);
  }
}

/// HTTP client for the CLOUD-AI-1 Dispatch Intelligence Worker.
///
/// Every method checks [kUseDispatchIntelligenceWorker] first and returns a
/// safe `disabled` failure without any network activity when the flag is off.
/// Errors never throw into the UI: all failures come back as result objects.
class DispatchIntelligenceClient {
  DispatchIntelligenceClient({
    String? baseUrl,
    http.Client? httpClient,
    Duration timeout = _defaultTimeout,
  })  : _baseUrl = _trimBaseUrl(baseUrl ?? kDispatchIntelligenceWorkerBaseUrl),
        _httpClient = httpClient ?? http.Client(),
        _timeout = timeout;

  final String _baseUrl;
  final http.Client _httpClient;
  final Duration _timeout;
  final Map<String, DateTime> _lastDiagAt = <String, DateTime>{};

  static String _trimBaseUrl(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    return text.endsWith('/') ? text.substring(0, text.length - 1) : text;
  }

  bool get isEnabled => kUseDispatchIntelligenceWorker && _baseUrl.isNotEmpty;

  Uri _endpointUri(String path) => Uri.parse('$_baseUrl$path');

  void _logDiag({
    required String endpoint,
    required String result,
    String reason = 'ok',
    int intervalMs = 2500,
  }) {
    final key = '$endpoint|$result|$reason';
    final now = DateTime.now();
    final last = _lastDiagAt[key];
    if (last != null && now.difference(last).inMilliseconds < intervalMs) {
      return;
    }
    _lastDiagAt[key] = now;
    debugPrint('[$_diagTag] endpoint=$endpoint result=$result reason=$reason');
  }

  String? _normalizeCountry(String country) {
    final code = country.trim().toUpperCase();
    return _allowedCountries.contains(code) ? code : null;
  }

  String? _normalizeAirportCode(String? airportCode) {
    if (airportCode == null) return null;
    final code = airportCode.trim().toUpperCase();
    return _allowedAirportCodes.contains(code) ? code : null;
  }

  /// Returns the parsed JSON map on success, or a failure reason string.
  Future<({Map<String, dynamic>? json, String reason})> _postJson(
    String path,
    Map<String, dynamic> body, {
    required String endpoint,
  }) async {
    try {
      final response = await _httpClient
          .post(
            _endpointUri(path),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final reason = 'http_${response.statusCode}';
        _logDiag(endpoint: endpoint, result: 'error', reason: reason);
        return (json: null, reason: reason);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        _logDiag(endpoint: endpoint, result: 'error', reason: 'invalid_json_shape');
        return (json: null, reason: 'invalid_json_shape');
      }
      if (decoded['ok'] != true) {
        _logDiag(endpoint: endpoint, result: 'error', reason: 'worker_not_ok');
        return (json: null, reason: 'worker_not_ok');
      }
      _logDiag(endpoint: endpoint, result: 'ok');
      return (json: decoded, reason: 'ok');
    } on Exception {
      _logDiag(endpoint: endpoint, result: 'error', reason: 'request_failed');
      return (json: null, reason: 'request_failed');
    }
  }

  Future<DispatchIntelligenceHealthResult> health() async {
    if (!isEnabled) {
      _logDiag(endpoint: 'health', result: 'disabled', reason: 'flag_off');
      return DispatchIntelligenceHealthResult.failure('disabled');
    }
    try {
      final response =
          await _httpClient.get(_endpointUri('/health')).timeout(_timeout);
      if (response.statusCode != 200) {
        _logDiag(
          endpoint: 'health',
          result: 'error',
          reason: 'http_${response.statusCode}',
        );
        return DispatchIntelligenceHealthResult.failure(
          'http_${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        _logDiag(endpoint: 'health', result: 'error', reason: 'invalid_body');
        return DispatchIntelligenceHealthResult.failure('invalid_body');
      }
      _logDiag(endpoint: 'health', result: 'ok');
      return DispatchIntelligenceHealthResult(
        ok: true,
        service: _safeToken(decoded['service'], 64),
        version: _safeToken(decoded['version'], 32),
      );
    } on Exception {
      _logDiag(endpoint: 'health', result: 'error', reason: 'request_failed');
      return DispatchIntelligenceHealthResult.failure('request_failed');
    }
  }

  /// Deterministic airport pickup advice. [scheduledPickupUtc] is the only
  /// timing sent; areas/addresses/identities are never part of this payload.
  Future<AirportPickupAdviceResult> airportPickupAdvice({
    required String country,
    required String airportCode,
    required DateTime scheduledPickupUtc,
    String? flightNumber,
    String? flightStatus,
    int? driverEtaSeconds,
    int? routeDurationSeconds,
    int? routeConfidence,
    int? gpsConfidence,
    int? passengerCount,
    int? luggageCount,
  }) async {
    if (!isEnabled) {
      _logDiag(endpoint: 'pickup-advice', result: 'disabled', reason: 'flag_off');
      return AirportPickupAdviceResult.failure('disabled');
    }
    final countryCode = _normalizeCountry(country);
    if (countryCode == null) {
      _logDiag(endpoint: 'pickup-advice', result: 'error', reason: 'invalid_country');
      return AirportPickupAdviceResult.failure('invalid_country');
    }
    final airport = _normalizeAirportCode(airportCode);
    if (airport == null) {
      _logDiag(endpoint: 'pickup-advice', result: 'error', reason: 'invalid_airport');
      return AirportPickupAdviceResult.failure('invalid_airport');
    }

    final safeFlightNumber = _safeToken(flightNumber, 8);
    final safeFlightStatus = _safeToken(flightStatus, 24).toLowerCase();
    final body = <String, dynamic>{
      'country': countryCode,
      'airport_code': airport,
      'scheduled_pickup_iso': scheduledPickupUtc.toUtc().toIso8601String(),
      if (safeFlightNumber.isNotEmpty) 'flight_number': safeFlightNumber,
      if (safeFlightStatus.isNotEmpty) 'flight_status': safeFlightStatus,
      if (driverEtaSeconds != null && driverEtaSeconds >= 0)
        'driver_eta_seconds': driverEtaSeconds,
      if (routeDurationSeconds != null && routeDurationSeconds >= 0)
        'route_duration_seconds': routeDurationSeconds,
      if (routeConfidence != null) 'route_confidence': routeConfidence,
      if (gpsConfidence != null) 'gps_confidence': gpsConfidence,
      if (passengerCount != null && passengerCount >= 0)
        'passenger_count': passengerCount,
      if (luggageCount != null && luggageCount >= 0)
        'luggage_count': luggageCount,
    };

    final result = await _postJson(
      '/airport/pickup-advice',
      body,
      endpoint: 'pickup-advice',
    );
    if (result.json == null) {
      return AirportPickupAdviceResult.failure(result.reason);
    }
    return AirportPickupAdviceResult.fromJson(result.json!);
  }

  /// Deterministic ride risk score from timing and nav-state signals only.
  Future<RideRiskResult> rideRisk({
    required String country,
    required String rideType,
    required DateTime pickupUtc,
    int? driverEtaSeconds,
    int? routeConfidence,
    int? gpsConfidence,
    bool? offRouteLikely,
    bool? predictionActive,
    int? rerouteCount,
    String? airportCode,
  }) async {
    if (!isEnabled) {
      _logDiag(endpoint: 'ride-risk', result: 'disabled', reason: 'flag_off');
      return RideRiskResult.failure('disabled');
    }
    final countryCode = _normalizeCountry(country);
    if (countryCode == null) {
      _logDiag(endpoint: 'ride-risk', result: 'error', reason: 'invalid_country');
      return RideRiskResult.failure('invalid_country');
    }
    final type = rideType.trim().toLowerCase();
    if (!_allowedRideTypes.contains(type)) {
      _logDiag(endpoint: 'ride-risk', result: 'error', reason: 'invalid_ride_type');
      return RideRiskResult.failure('invalid_ride_type');
    }
    final airport = _normalizeAirportCode(airportCode);

    final body = <String, dynamic>{
      'country': countryCode,
      'ride_type': type,
      'pickup_iso': pickupUtc.toUtc().toIso8601String(),
      if (driverEtaSeconds != null && driverEtaSeconds >= 0)
        'driver_eta_seconds': driverEtaSeconds,
      if (routeConfidence != null) 'route_confidence': routeConfidence,
      if (gpsConfidence != null) 'gps_confidence': gpsConfidence,
      if (offRouteLikely != null) 'off_route_likely': offRouteLikely,
      if (predictionActive != null) 'prediction_active': predictionActive,
      if (rerouteCount != null && rerouteCount >= 0)
        'reroute_count': rerouteCount,
      if (airport != null) 'airport_code': airport,
    };

    final result = await _postJson('/ride-risk', body, endpoint: 'ride-risk');
    if (result.json == null) {
      return RideRiskResult.failure(result.reason);
    }
    return RideRiskResult.fromJson(result.json!);
  }

  /// Offline map region suggestions. [pickupArea] and [dropoffArea] must be
  /// coarse region/city labels only (e.g. "Antwerpen") — never street
  /// addresses. They are truncated defensively before sending.
  Future<OfflineMapSuggestionsResult> offlineMapSuggestions({
    required String country,
    String? pickupArea,
    String? dropoffArea,
    String? airportCode,
    List<String> frequentRegions = const <String>[],
  }) async {
    if (!isEnabled) {
      _logDiag(endpoint: 'offline-maps', result: 'disabled', reason: 'flag_off');
      return OfflineMapSuggestionsResult.failure('disabled');
    }
    final countryCode = _normalizeCountry(country);
    if (countryCode == null) {
      _logDiag(endpoint: 'offline-maps', result: 'error', reason: 'invalid_country');
      return OfflineMapSuggestionsResult.failure('invalid_country');
    }
    final airport = _normalizeAirportCode(airportCode);

    final safePickupArea = _safeToken(pickupArea, 64);
    final safeDropoffArea = _safeToken(dropoffArea, 64);
    final safeFrequentRegions = frequentRegions
        .map((r) => _safeToken(r, 48))
        .where((r) => r.isNotEmpty)
        .take(12)
        .toList(growable: false);

    final body = <String, dynamic>{
      'country': countryCode,
      if (safePickupArea.isNotEmpty) 'pickup_area': safePickupArea,
      if (safeDropoffArea.isNotEmpty) 'dropoff_area': safeDropoffArea,
      if (airport != null) 'airport_code': airport,
      if (safeFrequentRegions.isNotEmpty)
        'frequent_regions': safeFrequentRegions,
    };

    final result = await _postJson(
      '/offline-map-suggestions',
      body,
      endpoint: 'offline-maps',
    );
    if (result.json == null) {
      return OfflineMapSuggestionsResult.failure(result.reason);
    }
    return OfflineMapSuggestionsResult.fromJson(result.json!);
  }
}
