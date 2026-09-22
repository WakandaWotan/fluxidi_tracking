/// Address lookup that gives a confirmed address real coordinates.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// `lib/limousine/limousine_address_lookup.dart` — `LimousinePlaceSuggestion`,
/// `LimousinePlaceLookup.search` / `_searchMapbox`,
/// `limousineNormalizeAddressQuery`, `kLimousineAddressMinQueryLength`.
///
/// Same provider and the same Mapbox Geocoding v5 places endpoint as the
/// existing customer flow. No second geocoder is introduced.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'address_label_language.dart';
import 'address_value.dart';

const Duration kFluxidiAddressLookupTimeout = Duration(seconds: 7);
const int kFluxidiAddressMaxSuggestions = 6;

typedef FluxidiAddressHttpGet = Future<http.Response> Function(Uri url);

class FluxidiAddressSuggestion {
  const FluxidiAddressSuggestion({
    required this.label,
    this.identityLabel = '',
    this.lat,
    this.lon,
    this.placeId,
    this.placeType = '',
  });

  /// Localized label shown in the field, including house number when present.
  final String label;

  /// Provider identity text. Language changes never rewrite this or the coords.
  final String identityLabel;

  final double? lat;
  final double? lon;
  final String? placeId;
  final String placeType;

  String get stableIdentity {
    final identity = identityLabel.trim();
    return identity.isEmpty ? label : identity;
  }

  bool get hasCoordinates =>
      lat != null && lon != null && lat!.isFinite && lon!.isFinite;

  bool get isStreetLevel =>
      placeType == 'address' || (placeId ?? '').startsWith('address.');

  /// Address value for the ride. Display can be localized; identity stays put.
  FluxidiAddressValue toAddressValue() => FluxidiAddressValue(
    displayText: label,
    canonicalLabel: stableIdentity,
    lat: lat,
    lon: lon,
    placeId: placeId,
    acceptance: FluxidiAddressAcceptance.selected,
  );
}

/// Normalizes a query. Country is already sent as a Mapbox `country=` filter,
/// so a bare Belgian postcode is not rewritten into English "Belgium".
String fluxidiNormalizeAddressQuery(String rawInput) {
  return rawInput.trim().replaceAll(RegExp(r'\s+'), ' ');
}

String fluxidiAddressCacheKey(String query, String language) {
  return '${fluxidiNormalizeAddressLanguage(language)}\u0001'
      '${fluxidiNormalizeAddressQuery(query)}';
}

class FluxidiAddressSearchClient {
  FluxidiAddressSearchClient({
    required this.token,
    this.httpGet,
    this.country = 'be',
    this.language = 'nl',
  });

  /// Mapbox access token. Never logged.
  final String token;

  final FluxidiAddressHttpGet? httpGet;
  final String country;
  final String language;

  final Map<String, List<FluxidiAddressSuggestion>> _cache =
      <String, List<FluxidiAddressSuggestion>>{};
  final Map<String, FluxidiAddressSuggestion> _reverseCache =
      <String, FluxidiAddressSuggestion>{};
  int _searchGeneration = 0;
  int _reverseGeneration = 0;

  bool get canSearch => token.trim().isNotEmpty || httpGet != null;

  Future<List<FluxidiAddressSuggestion>> search(
    String rawQuery, {
    String? language,
  }) async {
    final query = fluxidiNormalizeAddressQuery(rawQuery);
    final lang = fluxidiNormalizeAddressLanguage(language ?? this.language);
    if (query.length < kFluxidiAddressMinQueryLength) {
      return const <FluxidiAddressSuggestion>[];
    }
    final cacheKey = fluxidiAddressCacheKey(query, lang);
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    if (!canSearch) return const <FluxidiAddressSuggestion>[];

    final generation = ++_searchGeneration;

    // A bare postcode or place name also needs place-level hits; anything else
    // stays address-level so a house number is preserved.
    final types =
        fluxidiLooksLikeBelgianPostcode(rawQuery.trim()) ||
            !RegExp(r'\d').hasMatch(rawQuery)
        ? 'address,place,postcode'
        : 'address';

    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/'
      '${Uri.encodeComponent(query)}.json'
      '?autocomplete=true&limit=$kFluxidiAddressMaxSuggestions'
      '&types=$types&language=${Uri.encodeComponent(lang)}&country=$country'
      '&access_token=${token.trim()}',
    );

    try {
      final res = httpGet != null
          ? await httpGet!(uri)
          : await http.get(uri).timeout(kFluxidiAddressLookupTimeout);
      if (res.statusCode != 200) return const <FluxidiAddressSuggestion>[];
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return const <FluxidiAddressSuggestion>[];
      final parsed = parseFluxidiAddressFeatures(
        decoded['features'],
        language: lang,
      );
      _cache[cacheKey] = parsed;
      if (generation != _searchGeneration) {
        return const <FluxidiAddressSuggestion>[];
      }
      return parsed;
    } catch (_) {
      if (generation != _searchGeneration) {
        return const <FluxidiAddressSuggestion>[];
      }
      return const <FluxidiAddressSuggestion>[];
    }
  }

  Future<FluxidiAddressSuggestion?> reverse({
    required double lat,
    required double lon,
    String? language,
  }) async {
    if (!lat.isFinite || !lon.isFinite) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    final lang = fluxidiNormalizeAddressLanguage(language ?? this.language);
    final cacheKey =
        'rev\u0001$lang\u0001${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
    final cached = _reverseCache[cacheKey];
    if (cached != null) return cached;
    if (!canSearch) return null;

    final generation = ++_reverseGeneration;
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/'
      '${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}.json'
      '?limit=1&types=address&language=${Uri.encodeComponent(lang)}'
      '&country=$country&access_token=${token.trim()}',
    );
    try {
      final res = httpGet != null
          ? await httpGet!(uri)
          : await http.get(uri).timeout(kFluxidiAddressLookupTimeout);
      if (generation != _reverseGeneration) return null;
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final parsed = parseFluxidiAddressFeatures(
        decoded['features'],
        language: lang,
      );
      if (parsed.isEmpty) return null;
      _reverseCache[cacheKey] = parsed.first;
      return parsed.first;
    } catch (_) {
      return null;
    }
  }
}

/// Reads Mapbox places features into suggestions, keeping identity separate
/// from the localized display label.
List<FluxidiAddressSuggestion> parseFluxidiAddressFeatures(
  Object? raw, {
  String language = 'nl',
}) {
  if (raw is! List) return const <FluxidiAddressSuggestion>[];
  final lang = fluxidiNormalizeAddressLanguage(language);
  final out = <FluxidiAddressSuggestion>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final feature = Map<String, dynamic>.from(item);
    final identity = fluxidiMapboxFeatureIdentityLabel(feature);
    final label = fluxidiMapboxFeatureDisplayLabel(feature, lang);
    if (label.isEmpty && identity.isEmpty) continue;
    final center = feature['center'];
    double? lon;
    double? lat;
    if (center is List && center.length >= 2) {
      lon = (center[0] as num?)?.toDouble();
      lat = (center[1] as num?)?.toDouble();
    }
    final types = feature['place_type'];
    out.add(
      FluxidiAddressSuggestion(
        label: label.isEmpty ? identity : label,
        identityLabel: identity.isEmpty ? label : identity,
        lat: lat,
        lon: lon,
        placeId: (feature['id'] ?? '').toString().trim().isEmpty
            ? null
            : feature['id'].toString().trim(),
        placeType: types is List && types.isNotEmpty
            ? types.first.toString().trim()
            : '',
      ),
    );
    if (out.length >= kFluxidiAddressMaxSuggestions) break;
  }
  return List<FluxidiAddressSuggestion>.unmodifiable(out);
}
