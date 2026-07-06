import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:http/http.dart' as http;

const String _diagTag = 'CLOUD_NAV_2';
const Duration _defaultTimeout = Duration(seconds: 15);
const Set<String> _allowedCountries = {'BE', 'NL', 'FR', 'ES', 'PT'};
const Set<String> _allowedRerouteReasons = {
  'off_route',
  'manual',
  'traffic',
  'unknown',
};

String _safeToken(dynamic value, int maxLen) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (text.isEmpty) return '';
  return text.length > maxLen ? text.substring(0, maxLen) : text;
}

double? _safeDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

int? _safeInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Parsed Navigation Worker country profile (safe subset).
class NavigationWorkerCountryProfile {
  final String code;
  final String defaultLanguage;
  final String drivingProfile;
  final int maxCacheTtlSeconds;
  final int offlineCorridorBufferMeters;
  final String maneuverLanguageHint;

  const NavigationWorkerCountryProfile({
    required this.code,
    required this.defaultLanguage,
    required this.drivingProfile,
    required this.maxCacheTtlSeconds,
    required this.offlineCorridorBufferMeters,
    required this.maneuverLanguageHint,
  });

  factory NavigationWorkerCountryProfile.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return NavigationWorkerCountryProfile(
      code: _safeToken(map['code'], 4).toUpperCase(),
      defaultLanguage: _safeToken(map['defaultLanguage'], 8),
      drivingProfile: _safeToken(map['drivingProfile'], 32),
      maxCacheTtlSeconds: _safeInt(map['maxCacheTtlSeconds']) ?? 300,
      offlineCorridorBufferMeters:
          _safeInt(map['offlineCorridorBufferMeters']) ?? 800,
      maneuverLanguageHint: _safeToken(map['maneuverLanguageHint'], 8),
    );
  }
}

/// Route/reroute response from Navigation Worker.
class NavigationWorkerRouteResult {
  final double distanceMeters;
  final int durationSeconds;
  final List<DriverLonLat> coords;
  final List<Map<String, dynamic>> maneuvers;
  final String cache;
  final String? routeHash;
  final NavigationWorkerCountryProfile? countryProfile;
  final bool routeSessionUpdated;

  const NavigationWorkerRouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.coords,
    required this.maneuvers,
    required this.cache,
    this.routeHash,
    this.countryProfile,
    this.routeSessionUpdated = false,
  });

  bool get isValid => coords.length >= 2;

  Map<String, dynamic> toMapboxDirectionsShape() {
    final steps = <Map<String, dynamic>>[];
    for (final maneuver in maneuvers) {
      final location = maneuver['location'];
      List<dynamic>? locationPair;
      if (location is Map) {
        final lng = _safeDouble(location['lng']);
        final lat = _safeDouble(location['lat']);
        if (lng != null && lat != null) {
          locationPair = [lng, lat];
        }
      } else if (location is List && location.length >= 2) {
        locationPair = location;
      }
      if (locationPair == null) continue;
      steps.add({
        'distance': _safeDouble(maneuver['distance_m']) ?? 0,
        'duration': _safeInt(maneuver['duration_s']) ?? 0,
        'name': '',
        'maneuver': {
          'type': _safeToken(maneuver['type'], 32),
          'modifier': _safeToken(maneuver['modifier'], 32),
          'instruction': _safeToken(maneuver['instruction'], 256),
          'location': locationPair,
        },
      });
    }

    final geometry = <String, dynamic>{
      'type': 'LineString',
      'coordinates': coords.map((c) => [c.lon, c.lat]).toList(growable: false),
    };

    return {
      'routes': [
        {
          'distance': distanceMeters,
          'duration': durationSeconds,
          'geometry': geometry,
          'legs': [
            {'steps': steps},
          ],
        },
      ],
    };
  }
}

/// Offline corridor metadata response (estimates only).
class NavigationWorkerOfflineCorridorMetadata {
  final String supportedStatus;
  final String message;
  final String? routeId;
  final String country;
  final int corridorBufferMeters;
  final int zoomMin;
  final int zoomMax;
  final int routeLengthEstimateM;
  final int estimatedTileCountMin;
  final int estimatedTileCountMax;
  final int estimatedSizeBytesMin;
  final int estimatedSizeBytesMax;
  final NavigationWorkerCountryProfile? countryProfile;

  const NavigationWorkerOfflineCorridorMetadata({
    required this.supportedStatus,
    required this.message,
    required this.country,
    required this.corridorBufferMeters,
    required this.zoomMin,
    required this.zoomMax,
    required this.routeLengthEstimateM,
    required this.estimatedTileCountMin,
    required this.estimatedTileCountMax,
    required this.estimatedSizeBytesMin,
    required this.estimatedSizeBytesMax,
    this.routeId,
    this.countryProfile,
  });

  factory NavigationWorkerOfflineCorridorMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    final tileRange = json['estimated_tile_count_range'];
    final sizeRange = json['estimated_size_bytes_range'];
    return NavigationWorkerOfflineCorridorMetadata(
      supportedStatus: _safeToken(json['supported_status'], 32),
      message: _safeToken(json['message'], 512),
      routeId: _safeToken(json['route_id'], 64).isEmpty
          ? null
          : _safeToken(json['route_id'], 64),
      country: _safeToken(json['country'], 4).toUpperCase(),
      corridorBufferMeters: _safeInt(json['corridor_buffer_meters']) ?? 0,
      zoomMin: _safeInt(json['zoom_min']) ?? 0,
      zoomMax: _safeInt(json['zoom_max']) ?? 0,
      routeLengthEstimateM: _safeInt(json['route_length_m_estimate']) ?? 0,
      estimatedTileCountMin: tileRange is Map
          ? (_safeInt(tileRange['min']) ?? 0)
          : 0,
      estimatedTileCountMax: tileRange is Map
          ? (_safeInt(tileRange['max']) ?? 0)
          : 0,
      estimatedSizeBytesMin: sizeRange is Map
          ? (_safeInt(sizeRange['min']) ?? 0)
          : 0,
      estimatedSizeBytesMax: sizeRange is Map
          ? (_safeInt(sizeRange['max']) ?? 0)
          : 0,
      countryProfile: NavigationWorkerCountryProfile.fromJson(
        json['country_profile'] is Map<String, dynamic>
            ? json['country_profile'] as Map<String, dynamic>
            : null,
      ),
    );
  }
}

class NavigationWorkerHealthResult {
  final bool ok;
  final String service;
  final String version;

  const NavigationWorkerHealthResult({
    required this.ok,
    required this.service,
    required this.version,
  });
}

/// HTTP client for CLOUD-NAV-1 Navigation Worker.
class DriverNavigationWorkerClient {
  DriverNavigationWorkerClient({
    required String baseUrl,
    http.Client? httpClient,
    Duration timeout = _defaultTimeout,
  }) : _baseUrl = _trimBaseUrl(baseUrl),
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

  static String _normalizeCountry(String country) {
    final code = country.trim().toUpperCase();
    return _allowedCountries.contains(code) ? code : 'BE';
  }

  void _logDiag({
    required String endpoint,
    required String result,
    String reason = 'ok',
    String country = 'na',
    int intervalMs = 2500,
  }) {
    final key = '$endpoint|$result|$reason';
    final now = DateTime.now();
    final last = _lastDiagAt[key];
    if (last != null && now.difference(last).inMilliseconds < intervalMs) {
      return;
    }
    _lastDiagAt[key] = now;
    debugPrint(
      '[$_diagTag] endpoint=$endpoint result=$result reason=$reason country=$country',
    );
  }

  bool get isConfigured => _baseUrl.isNotEmpty;

  Uri _endpointUri(String path) => Uri.parse('$_baseUrl$path');

  Future<Map<String, dynamic>?> _postJson(
    String path,
    Map<String, dynamic> body, {
    required String endpoint,
    String country = 'na',
  }) async {
    if (!isConfigured) {
      _logDiag(endpoint: endpoint, result: 'disabled', reason: 'no_base_url');
      return null;
    }
    try {
      final response = await _httpClient
          .post(
            _endpointUri(path),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logDiag(
          endpoint: endpoint,
          result: 'error',
          reason: 'http_${response.statusCode}',
          country: country,
        );
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        _logDiag(
          endpoint: endpoint,
          result: 'error',
          reason: 'invalid_json_shape',
          country: country,
        );
        return null;
      }
      if (decoded['ok'] != true) {
        _logDiag(
          endpoint: endpoint,
          result: 'error',
          reason: 'worker_not_ok',
          country: country,
        );
        return null;
      }
      return decoded;
    } on Exception {
      _logDiag(
        endpoint: endpoint,
        result: 'error',
        reason: 'request_failed',
        country: country,
      );
      return null;
    }
  }

  Future<NavigationWorkerHealthResult?> health() async {
    if (!isConfigured) {
      _logDiag(endpoint: 'health', result: 'disabled', reason: 'no_base_url');
      return null;
    }
    try {
      final response = await _httpClient
          .get(_endpointUri('/health'))
          .timeout(_timeout);
      if (response.statusCode != 200) {
        _logDiag(
          endpoint: 'health',
          result: 'error',
          reason: 'http_${response.statusCode}',
        );
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        _logDiag(endpoint: 'health', result: 'error', reason: 'invalid_body');
        return null;
      }
      _logDiag(endpoint: 'health', result: 'hit', reason: 'ok');
      return NavigationWorkerHealthResult(
        ok: true,
        service: _safeToken(decoded['service'], 64),
        version: _safeToken(decoded['version'], 32),
      );
    } on Exception {
      _logDiag(endpoint: 'health', result: 'error', reason: 'request_failed');
      return null;
    }
  }

  Future<NavigationWorkerRouteResult?> route({
    required DriverLonLat origin,
    required DriverLonLat destination,
    required String country,
    String profile = 'driving',
    String? tripId,
  }) async {
    final countryCode = _normalizeCountry(country);
    final body = <String, dynamic>{
      'origin': {'lat': origin.lat, 'lng': origin.lon},
      'destination': {'lat': destination.lat, 'lng': destination.lon},
      'country': countryCode,
      'profile': profile,
      if (tripId != null && tripId.trim().isNotEmpty) 'trip_id': tripId.trim(),
    };
    final json = await _postJson(
      '/route',
      body,
      endpoint: 'route',
      country: countryCode,
    );
    if (json == null) return null;
    final parsed = _parseRouteResult(
      json,
      routeSessionUpdated: tripId != null && tripId.trim().isNotEmpty,
    );
    if (parsed == null || !parsed.isValid) {
      _logDiag(
        endpoint: 'route',
        result: 'error',
        reason: 'invalid_route_payload',
        country: countryCode,
      );
      return null;
    }
    _logDiag(
      endpoint: 'route',
      result: _cacheResultLabel(parsed.cache),
      reason: 'ok',
      country: countryCode,
    );
    return parsed;
  }

  Future<NavigationWorkerRouteResult?> reroute({
    required DriverLonLat current,
    required DriverLonLat destination,
    required String country,
    String profile = 'driving',
    String? tripId,
    String reason = 'unknown',
  }) async {
    final countryCode = _normalizeCountry(country);
    final rerouteReason = _allowedRerouteReasons.contains(reason)
        ? reason
        : 'unknown';
    final body = <String, dynamic>{
      'current': {'lat': current.lat, 'lng': current.lon},
      'destination': {'lat': destination.lat, 'lng': destination.lon},
      'country': countryCode,
      'profile': profile,
      'reason': rerouteReason,
      if (tripId != null && tripId.trim().isNotEmpty) 'trip_id': tripId.trim(),
    };
    final json = await _postJson(
      '/reroute',
      body,
      endpoint: 'reroute',
      country: countryCode,
    );
    if (json == null) return null;
    final parsed = _parseRouteResult(
      json,
      routeSessionUpdated: tripId != null && tripId.trim().isNotEmpty,
    );
    if (parsed == null || !parsed.isValid) {
      _logDiag(
        endpoint: 'reroute',
        result: 'error',
        reason: 'invalid_route_payload',
        country: countryCode,
      );
      return null;
    }
    _logDiag(
      endpoint: 'reroute',
      result: _cacheResultLabel(parsed.cache),
      reason: rerouteReason,
      country: countryCode,
    );
    return parsed;
  }

  Future<NavigationWorkerOfflineCorridorMetadata?> offlineCorridorMetadata({
    String? routeId,
    Object? geometry,
    String? polyline,
    required String country,
    int? zoomMin,
    int? zoomMax,
  }) async {
    final countryCode = _normalizeCountry(country);
    final body = <String, dynamic>{
      'country': countryCode,
      if (routeId != null && routeId.trim().isNotEmpty) 'route_id': routeId.trim(),
      if (geometry != null) 'geometry': geometry,
      if (polyline != null && polyline.trim().isNotEmpty) 'polyline': polyline.trim(),
      if (zoomMin != null) 'zoom_min': zoomMin,
      if (zoomMax != null) 'zoom_max': zoomMax,
    };
    final json = await _postJson(
      '/offline-corridor/metadata',
      body,
      endpoint: 'offline',
      country: countryCode,
    );
    if (json == null) return null;
    _logDiag(
      endpoint: 'offline',
      result: 'hit',
      reason: _safeToken(json['supported_status'], 32),
      country: countryCode,
    );
    return NavigationWorkerOfflineCorridorMetadata.fromJson(json);
  }

  static String _cacheResultLabel(String cache) {
    final normalized = cache.trim().toLowerCase();
    if (normalized == 'hit' ||
        normalized == 'miss' ||
        normalized == 'bypass' ||
        normalized == 'fallback' ||
        normalized == 'disabled' ||
        normalized == 'error') {
      return normalized;
    }
    return 'error';
  }

  static NavigationWorkerRouteResult? _parseRouteResult(
    Map<String, dynamic> json, {
    required bool routeSessionUpdated,
  }) {
    final geometry = json['geometry'];
    final coords = <DriverLonLat>[];
    if (geometry is Map<String, dynamic>) {
      final line = geometry['coordinates'];
      if (line is List) {
        for (final pair in line) {
          if (pair is List && pair.length >= 2) {
            final lon = _safeDouble(pair[0]);
            final lat = _safeDouble(pair[1]);
            if (lon != null && lat != null) {
              coords.add(DriverLonLat(lon, lat));
            }
          }
        }
      }
    }

    final maneuversRaw = json['maneuvers'];
    final maneuvers = <Map<String, dynamic>>[];
    if (maneuversRaw is List) {
      for (final item in maneuversRaw) {
        if (item is Map<String, dynamic>) {
          maneuvers.add(item);
        } else if (item is Map) {
          maneuvers.add(Map<String, dynamic>.from(item));
        }
      }
    }

    return NavigationWorkerRouteResult(
      distanceMeters: _safeDouble(json['distance_m']) ?? 0,
      durationSeconds: _safeInt(json['duration_s']) ?? 0,
      coords: coords,
      maneuvers: maneuvers,
      cache: _safeToken(json['cache'], 12),
      routeHash: _safeToken(json['route_hash'], 64).isEmpty
          ? null
          : _safeToken(json['route_hash'], 64),
      countryProfile: NavigationWorkerCountryProfile.fromJson(
        json['country_profile'] is Map<String, dynamic>
            ? json['country_profile'] as Map<String, dynamic>
            : null,
      ),
      routeSessionUpdated: routeSessionUpdated,
    );
  }
}
