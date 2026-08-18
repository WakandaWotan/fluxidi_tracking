// LIMOUSINE-MARKETPLACE-P2D4C1A — address lookup.
// Reuses the proven Mapbox Geocoding v5 seam from CalculatorPage._searchPlaces,
// CalculatorPage._reverseGeocode and airport forward/reverse geocode.
// Not a second provider, key, or pricing engine.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';

const int kLimousineAddressMinQueryLength = 3;
const Duration kLimousineAddressDebounce = Duration(milliseconds: 220);
const int kLimousineAddressMaxSuggestions = 6;
const Duration kLimousineAddressLookupTimeout = Duration(seconds: 7);

const String kLimousineMapboxGeocodingV5Host = 'api.mapbox.com';
const String kLimousineMapboxGeocodingV5PathPrefix =
    '/geocoding/v5/mapbox.places/';

enum LimousineAddressAcceptance { empty, incomplete, selected, manualFallback }

class LimousinePlaceSuggestion {
  const LimousinePlaceSuggestion({
    required this.label,
    this.lat,
    this.lon,
    this.placeId,
  });

  final String label;
  final double? lat;
  final double? lon;
  final String? placeId;

  bool get hasCoordinates =>
      lat != null && lon != null && lat!.isFinite && lon!.isFinite;
}

class LimousinePlaceLookupResult {
  const LimousinePlaceLookupResult({
    this.suggestions = const <LimousinePlaceSuggestion>[],
    this.hadError = false,
  });

  final List<LimousinePlaceSuggestion> suggestions;
  final bool hadError;
}

class LimousineAddressValue {
  const LimousineAddressValue({
    this.displayText = '',
    this.canonicalLabel = '',
    this.lat,
    this.lon,
    this.placeId,
    this.acceptance = LimousineAddressAcceptance.empty,
  });

  final String displayText;
  final String canonicalLabel;
  final double? lat;
  final double? lon;
  final String? placeId;
  final LimousineAddressAcceptance acceptance;

  bool get isEmpty => displayText.trim().isEmpty;

  bool get isRouteReady =>
      acceptance == LimousineAddressAcceptance.selected ||
      acceptance == LimousineAddressAcceptance.manualFallback;

  String get routeText {
    if (!isRouteReady) return '';
    final canonical = canonicalLabel.trim();
    if (canonical.isNotEmpty) return canonical;
    return displayText.trim();
  }
}

typedef LimousinePlaceSearch =
    Future<LimousinePlaceLookupResult> Function(
      String query,
      String language,
    );

typedef LimousinePlaceReverse =
    Future<LimousinePlaceLookupResult> Function(
      double lat,
      double lon,
      String language,
    );

bool limousineLooksLikeBelgianPostcode(String input) =>
    RegExp(r'^[1-9]\d{3}$').hasMatch(input.trim());

String limousineNormalizeAddressQuery(String rawInput) {
  final compact = rawInput.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (compact.isEmpty) return '';
  if (limousineLooksLikeBelgianPostcode(compact)) {
    return '$compact Belgium';
  }
  return compact;
}

bool limousineAddressLooksLikeIncompleteFragment(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return true;
  if (text.length < kLimousineAddressMinQueryLength) return true;
  if (limousineLooksLikeBelgianPostcode(text)) return true;
  if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(text)) return true;
  if (!RegExp(r'[\s,]').hasMatch(text) && text.length < 12) return true;
  return false;
}

bool limousineAddressAllowsManualFallback(String raw) {
  if (limousineAddressLooksLikeIncompleteFragment(raw)) return false;
  final text = raw.trim();
  if (text.length < 8) return false;
  return RegExp(r'[\s,]').hasMatch(text);
}

Uri limousineMapboxPlacesUri({
  required String query,
  required String token,
  String language = 'nl',
}) {
  final encoded = Uri.encodeComponent(query);
  return Uri.parse(
    'https://$kLimousineMapboxGeocodingV5Host$kLimousineMapboxGeocodingV5PathPrefix$encoded.json'
    '?access_token=${Uri.encodeComponent(token)}'
    '&autocomplete=true'
    '&country=be'
    '&language=${Uri.encodeComponent(language)}'
    '&limit=$kLimousineAddressMaxSuggestions',
  );
}

Uri limousineMapboxReverseGeocodeUri({
  required double lat,
  required double lon,
  required String token,
  String language = 'nl',
}) {
  final path = '${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}';
  return Uri.parse(
    'https://$kLimousineMapboxGeocodingV5Host$kLimousineMapboxGeocodingV5PathPrefix$path.json'
    '?access_token=${Uri.encodeComponent(token)}'
    '&language=${Uri.encodeComponent(language)}'
    '&country=be'
    '&limit=1',
  );
}

bool limousineCoordinatesAreValid(double lat, double lon) {
  return lat.isFinite &&
      lon.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;
}

List<LimousinePlaceSuggestion> parseLimousineMapboxPlaceFeatures(
  Object? rawFeatures,
) {
  if (rawFeatures is! List) return const <LimousinePlaceSuggestion>[];
  final out = <LimousinePlaceSuggestion>[];
  for (final feature in rawFeatures) {
    if (feature is! Map) continue;
    final map = feature.map((key, value) => MapEntry(key.toString(), value));
    final label = (map['place_name'] ?? '').toString().trim();
    if (label.isEmpty) continue;
    final center = map['center'];
    double? lon;
    double? lat;
    if (center is List && center.isNotEmpty) {
      lon = center[0] is num
          ? (center[0] as num).toDouble()
          : double.tryParse('${center[0]}');
      if (center.length > 1) {
        lat = center[1] is num
            ? (center[1] as num).toDouble()
            : double.tryParse('${center[1]}');
      }
    }
    if (lat != null && (lat < -90 || lat > 90 || !lat.isFinite)) lat = null;
    if (lon != null && (lon < -180 || lon > 180 || !lon.isFinite)) lon = null;
    final placeId = (map['id'] ?? '').toString().trim();
    out.add(
      LimousinePlaceSuggestion(
        label: label,
        lat: lat,
        lon: lon,
        placeId: placeId.isEmpty ? null : placeId,
      ),
    );
    if (out.length >= kLimousineAddressMaxSuggestions) break;
  }
  return List<LimousinePlaceSuggestion>.unmodifiable(out);
}

class LimousinePlaceLookup {
  LimousinePlaceLookup({
    String? token,
    http.Client? client,
    LimousinePlaceSearch? searchOverride,
    LimousinePlaceReverse? reverseOverride,
  }) : token = (token ?? kMapboxToken).trim(),
       _client = client,
       _searchOverride = searchOverride,
       _reverseOverride = reverseOverride,
       _ownsClient = client == null && searchOverride == null;

  final String token;
  final http.Client? _client;
  final LimousinePlaceSearch? _searchOverride;
  final LimousinePlaceReverse? _reverseOverride;
  final bool _ownsClient;
  final Map<String, LimousinePlaceLookupResult> _sessionCache =
      <String, LimousinePlaceLookupResult>{};
  int searchesStarted = 0;
  int reverseGeocodesStarted = 0;

  String _cacheKey(String query, String language) =>
      '$language\u0001${limousineNormalizeAddressQuery(query)}';

  Future<LimousinePlaceLookupResult> search(
    String rawQuery, {
    String language = 'nl',
  }) async {
    final query = limousineNormalizeAddressQuery(rawQuery);
    if (query.length < kLimousineAddressMinQueryLength) {
      return const LimousinePlaceLookupResult();
    }
    final cached = _sessionCache[_cacheKey(rawQuery, language)];
    if (cached != null && !cached.hadError) {
      return cached;
    }
    searchesStarted += 1;
    final override = _searchOverride;
    final result = override != null
        ? await override(query, language)
        : await _searchMapbox(query, language);
    if (!result.hadError) {
      _sessionCache[_cacheKey(rawQuery, language)] = result;
    }
    return result;
  }

  Future<LimousinePlaceLookupResult> _searchMapbox(
    String query,
    String language,
  ) async {
    if (token.isEmpty) return const LimousinePlaceLookupResult();
    final uri = limousineMapboxPlacesUri(
      query: query,
      token: token,
      language: language,
    );
    final client = _client ?? http.Client();
    try {
      final res = await client.get(uri).timeout(kLimousineAddressLookupTimeout);
      if (res.statusCode != 200) {
        return const LimousinePlaceLookupResult(hadError: true);
      }
      final data = jsonDecode(res.body);
      if (data is! Map) {
        return const LimousinePlaceLookupResult(hadError: true);
      }
      return LimousinePlaceLookupResult(
        suggestions: parseLimousineMapboxPlaceFeatures(data['features']),
      );
    } catch (_) {
      return const LimousinePlaceLookupResult(hadError: true);
    } finally {
      if (_ownsClient) client.close();
    }
  }

  Future<LimousinePlaceLookupResult> reverseGeocode(
    double lat,
    double lon, {
    String language = 'nl',
  }) async {
    if (!limousineCoordinatesAreValid(lat, lon)) {
      return const LimousinePlaceLookupResult(hadError: true);
    }
    reverseGeocodesStarted += 1;
    final override = _reverseOverride;
    if (override != null) {
      return override(lat, lon, language);
    }
    return _reverseMapbox(lat, lon, language);
  }

  Future<LimousinePlaceLookupResult> _reverseMapbox(
    double lat,
    double lon,
    String language,
  ) async {
    if (token.isEmpty) {
      return const LimousinePlaceLookupResult(hadError: true);
    }
    final uri = limousineMapboxReverseGeocodeUri(
      lat: lat,
      lon: lon,
      token: token,
      language: language,
    );
    final owns = _client == null;
    final client = _client ?? http.Client();
    try {
      final res = await client.get(uri).timeout(kLimousineAddressLookupTimeout);
      if (res.statusCode != 200) {
        return const LimousinePlaceLookupResult(hadError: true);
      }
      final data = jsonDecode(res.body);
      if (data is! Map) {
        return const LimousinePlaceLookupResult(hadError: true);
      }
      final suggestions = parseLimousineMapboxPlaceFeatures(data['features']);
      if (suggestions.isEmpty) {
        return const LimousinePlaceLookupResult(hadError: true);
      }
      return LimousinePlaceLookupResult(
        suggestions: <LimousinePlaceSuggestion>[suggestions.first],
      );
    } on TimeoutException {
      rethrow;
    } catch (_) {
      return const LimousinePlaceLookupResult(hadError: true);
    } finally {
      if (owns) client.close();
    }
  }

  void dispose() {
    if (_ownsClient) _client?.close();
    _sessionCache.clear();
  }
}
