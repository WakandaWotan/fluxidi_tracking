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
    this.placeType = '',
    this.text = '',
    this.matchingText = '',
  });

  final String label;
  final double? lat;
  final double? lon;
  final String? placeId;
  final String placeType;
  final String text;
  final String matchingText;

  bool get hasCoordinates =>
      lat != null && lon != null && lat!.isFinite && lon!.isFinite;

  bool get isStreetLevel {
    final type = placeType.trim().toLowerCase();
    final id = (placeId ?? '').toLowerCase();
    return type == 'address' || id.startsWith('address.');
  }
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
    this.fromCurrentLocation = false,
  });

  final String displayText;
  final String canonicalLabel;
  final double? lat;
  final double? lon;
  final String? placeId;
  final LimousineAddressAcceptance acceptance;
  final bool fromCurrentLocation;

  bool get isEmpty => displayText.trim().isEmpty;

  bool get hasCoordinates =>
      lat != null && lon != null && lat!.isFinite && lon!.isFinite;

  bool get isRouteReady =>
      acceptance == LimousineAddressAcceptance.selected ||
      acceptance == LimousineAddressAcceptance.manualFallback;

  LimousineAddressValue copyWith({
    String? displayText,
    String? canonicalLabel,
    double? lat,
    double? lon,
    String? placeId,
    LimousineAddressAcceptance? acceptance,
    bool? fromCurrentLocation,
    bool clearCoordinates = false,
  }) {
    return LimousineAddressValue(
      displayText: displayText ?? this.displayText,
      canonicalLabel: canonicalLabel ?? this.canonicalLabel,
      lat: clearCoordinates ? null : (lat ?? this.lat),
      lon: clearCoordinates ? null : (lon ?? this.lon),
      placeId: placeId ?? this.placeId,
      acceptance: acceptance ?? this.acceptance,
      fromCurrentLocation: fromCurrentLocation ?? this.fromCurrentLocation,
    );
  }

  String get routeText {
    if (!isRouteReady) return '';
    final canonical = canonicalLabel.trim();
    if (canonical.isNotEmpty) return canonical;
    return displayText.trim();
  }
}

typedef LimousinePlaceSearch =
    Future<LimousinePlaceLookupResult> Function(String query, String language);

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

final RegExp _streetNumber = RegExp(r'\d+[A-Za-z]?\b');
final RegExp _localityOnly = RegExp(
  r'^\d{4}\b[^A-Za-zÀ-ÿ]*[A-Za-zÀ-ÿ].*$',
);

bool limousineAddressHasStreetNumber(String raw) =>
    _streetNumber.hasMatch(raw.trim());

bool limousineAddressLooksLikePlaceName(String raw) {
  final text = raw.trim();
  if (text.length < kLimousineAddressMinQueryLength) return false;
  if (RegExp(r'\d').hasMatch(text)) return false;
  return RegExp(
    r"^[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'\-]+(?:\s+[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'\-]+)?$",
  ).hasMatch(text);
}

bool limousineAddressLooksLikeLocalityOnly(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return true;
  if (limousineAddressLooksLikePlaceName(text)) return true;
  if (limousineAddressHasStreetNumber(text) &&
      RegExp(r'[A-Za-zÀ-ÿ]{3,}').hasMatch(text.split(RegExp(r'\d')).first)) {
    return false;
  }
  return _localityOnly.hasMatch(text) &&
      !RegExp(r'[A-Za-zÀ-ÿ]{3,}.+\d').hasMatch(text);
}

bool limousineAddressIsMoreSpecific(String original, String candidate) {
  final left = original.trim();
  final right = candidate.trim();
  if (left.isEmpty) return false;
  if (right.isEmpty) return true;
  final leftStreet = limousineAddressHasStreetNumber(left) &&
      !limousineAddressLooksLikeLocalityOnly(left);
  final rightStreet = limousineAddressHasStreetNumber(right) &&
      !limousineAddressLooksLikeLocalityOnly(right);
  if (leftStreet && !rightStreet) return true;
  return false;
}

String limousinePreferCanonicalLabel({
  required String original,
  required String suggestion,
}) {
  if (limousineAddressIsMoreSpecific(original, suggestion)) {
    return original.trim();
  }
  return suggestion.trim().isEmpty ? original.trim() : suggestion.trim();
}

LimousinePlaceSuggestion? limousinePreferStreetLevelSuggestion(
  String query,
  List<LimousinePlaceSuggestion> suggestions,
) {
  if (suggestions.isEmpty) return null;
  final needle = query.trim().toLowerCase();
  final street = [
    for (final item in suggestions)
      if (item.isStreetLevel) item,
  ];
  if (street.isEmpty) {
    if (limousineAddressLooksLikeLocalityOnly(query)) {
      return suggestions.first;
    }
    return null;
  }
  for (final item in street) {
    if (needle.isNotEmpty && item.label.toLowerCase().contains(needle.split(',').first.trim())) {
      return item;
    }
  }
  return street.first;
}

/// UI language must not hide local toponyms such as Gent, Kortrijk or Ronse.
/// Place-name queries omit Mapbox `language=` so Dutch names stay findable
/// when the app itself is English.
String limousineMapboxForwardLanguage({
  required String query,
  required String uiLanguage,
}) {
  if (limousineAddressLooksLikePlaceName(query) ||
      limousineAddressLooksLikeLocalityOnly(query)) {
    return '';
  }
  return uiLanguage.trim();
}

String limousineFoldAddressToken(String raw) {
  const from = 'àáâäãåæçèéêëìíîïñòóôöõøùúûüýÿ';
  const to = 'aaaaaaeceeeeiiiinoooooouuuuyy';
  final buffer = StringBuffer();
  for (final rune in raw.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

bool limousinePlaceSuggestionMatchesQuery(
  LimousinePlaceSuggestion suggestion,
  String query,
) {
  final needle = limousineFoldAddressToken(query);
  if (needle.isEmpty) return true;
  final haystack = limousineFoldAddressToken(
    [
      suggestion.label,
      suggestion.text,
      suggestion.matchingText,
    ].where((part) => part.trim().isNotEmpty).join(' '),
  );
  return haystack.contains(needle);
}

int limousinePlaceSuggestionRank(
  LimousinePlaceSuggestion suggestion,
  String query,
) {
  final needle = limousineFoldAddressToken(query);
  if (needle.isEmpty) return 0;
  final text = limousineFoldAddressToken(suggestion.text);
  final matching = limousineFoldAddressToken(suggestion.matchingText);
  final label = limousineFoldAddressToken(suggestion.label);
  if (text == needle || matching == needle) return 0;
  if (label.startsWith(needle)) return 1;
  if (text.startsWith(needle) || matching.startsWith(needle)) return 2;
  if (label.contains(needle) ||
      text.contains(needle) ||
      matching.contains(needle)) {
    return 3;
  }
  return 8;
}

List<LimousinePlaceSuggestion> limousineRankPlaceSuggestions(
  String query,
  List<LimousinePlaceSuggestion> suggestions,
) {
  final ranked = List<LimousinePlaceSuggestion>.from(suggestions)
    ..sort((left, right) {
      final byRank = limousinePlaceSuggestionRank(left, query)
          .compareTo(limousinePlaceSuggestionRank(right, query));
      if (byRank != 0) return byRank;
      return left.label.compareTo(right.label);
    });
  return List<LimousinePlaceSuggestion>.unmodifiable(ranked);
}

Uri limousineMapboxPlacesUri({
  required String query,
  required String token,
  String language = 'nl',
  String? country = 'be',
  String types = 'address',
}) {
  final encoded = Uri.encodeComponent(query);
  final countryPart = (country ?? '').trim().isEmpty
      ? ''
      : '&country=${Uri.encodeComponent(country!.trim())}';
  final typesPart = types.trim().isEmpty
      ? ''
      : '&types=${Uri.encodeComponent(types.trim())}';
  final languagePart = language.trim().isEmpty
      ? ''
      : '&language=${Uri.encodeComponent(language.trim())}';
  return Uri.parse(
    'https://$kLimousineMapboxGeocodingV5Host$kLimousineMapboxGeocodingV5PathPrefix$encoded.json'
    '?access_token=${Uri.encodeComponent(token)}'
    '&autocomplete=true'
    '$countryPart'
    '$typesPart'
    '$languagePart'
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
    '&types=address'
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

String limousineMapboxProximitySuffix({
  double? latitude,
  double? longitude,
}) {
  if (latitude == null || longitude == null) return '';
  if (!limousineCoordinatesAreValid(latitude, longitude)) return '';
  return '&proximity=${longitude.toStringAsFixed(6)},${latitude.toStringAsFixed(6)}';
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
    final types = map['place_type'];
    final placeType = types is List && types.isNotEmpty
        ? types.first.toString().trim()
        : placeId.contains('.')
            ? placeId.split('.').first
            : '';
    final text = (map['text'] ?? '').toString().trim();
    final matchingText = [
      (map['matching_text'] ?? '').toString().trim(),
      (map['matching_place_name'] ?? '').toString().trim(),
    ].firstWhere((part) => part.isNotEmpty, orElse: () => '');
    out.add(
      LimousinePlaceSuggestion(
        label: label,
        lat: lat,
        lon: lon,
        placeId: placeId.isEmpty ? null : placeId,
        placeType: placeType,
        text: text,
        matchingText: matchingText,
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
    this.country = 'be',
  }) : token = (token ?? kMapboxToken).trim(),
       _client = client,
       _searchOverride = searchOverride,
       _reverseOverride = reverseOverride,
       _ownsClient = client == null && searchOverride == null;

  final String token;
  final String country;
  final http.Client? _client;
  final LimousinePlaceSearch? _searchOverride;
  final LimousinePlaceReverse? _reverseOverride;
  final bool _ownsClient;
  final Map<String, LimousinePlaceLookupResult> _sessionCache =
      <String, LimousinePlaceLookupResult>{};
  int searchesStarted = 0;
  int reverseGeocodesStarted = 0;

  String _cacheKey(String query, String language) =>
      '$language\u0001$country\u0001${limousineNormalizeAddressQuery(query)}';

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
    if (token.isEmpty) {
      return const LimousinePlaceLookupResult(hadError: true);
    }
    final types = limousineLooksLikeBelgianPostcode(query) ||
            limousineAddressLooksLikeLocalityOnly(query)
        ? 'address,place,postcode'
        : 'address';
    final searchLanguage = limousineMapboxForwardLanguage(
      query: query,
      uiLanguage: language,
    );
    final uri = limousineMapboxPlacesUri(
      query: query,
      token: token,
      language: searchLanguage,
      country: country,
      types: types,
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
        suggestions: limousineRankPlaceSuggestions(
          query,
          parseLimousineMapboxPlaceFeatures(data['features']),
        ),
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
