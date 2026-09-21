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

import 'address_value.dart';

const Duration kFluxidiAddressLookupTimeout = Duration(seconds: 7);
const int kFluxidiAddressMaxSuggestions = 6;

typedef FluxidiAddressHttpGet = Future<http.Response> Function(Uri url);

class FluxidiAddressSuggestion {
  const FluxidiAddressSuggestion({
    required this.label,
    this.lat,
    this.lon,
    this.placeId,
    this.placeType = '',
  });

  /// Full label including house number when the provider returned one.
  final String label;

  final double? lat;
  final double? lon;
  final String? placeId;
  final String placeType;

  bool get hasCoordinates =>
      lat != null && lon != null && lat!.isFinite && lon!.isFinite;

  bool get isStreetLevel =>
      placeType == 'address' || (placeId ?? '').startsWith('address.');

  /// Address value for the ride, with the label kept as canonical text.
  FluxidiAddressValue toAddressValue() => FluxidiAddressValue(
    displayText: label,
    canonicalLabel: label,
    lat: lat,
    lon: lon,
    placeId: placeId,
    acceptance: FluxidiAddressAcceptance.selected,
  );
}

/// Normalizes a query the same way the existing flow does.
String fluxidiNormalizeAddressQuery(String rawInput) {
  final compact = rawInput.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (compact.isEmpty) return '';
  if (fluxidiLooksLikeBelgianPostcode(compact)) return '$compact Belgium';
  return compact;
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

  bool get canSearch => token.trim().isNotEmpty || httpGet != null;

  Future<List<FluxidiAddressSuggestion>> search(String rawQuery) async {
    final query = fluxidiNormalizeAddressQuery(rawQuery);
    if (query.length < kFluxidiAddressMinQueryLength) {
      return const <FluxidiAddressSuggestion>[];
    }
    final cached = _cache[query];
    if (cached != null) return cached;
    if (!canSearch) return const <FluxidiAddressSuggestion>[];

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
      '&types=$types&language=$language&country=$country'
      '&access_token=${token.trim()}',
    );

    try {
      final res = httpGet != null
          ? await httpGet!(uri)
          : await http.get(uri).timeout(kFluxidiAddressLookupTimeout);
      if (res.statusCode != 200) return const <FluxidiAddressSuggestion>[];
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return const <FluxidiAddressSuggestion>[];
      final parsed = parseFluxidiAddressFeatures(decoded['features']);
      _cache[query] = parsed;
      return parsed;
    } catch (_) {
      return const <FluxidiAddressSuggestion>[];
    }
  }
}

/// Reads Mapbox places features into suggestions, keeping the full label.
List<FluxidiAddressSuggestion> parseFluxidiAddressFeatures(Object? raw) {
  if (raw is! List) return const <FluxidiAddressSuggestion>[];
  final out = <FluxidiAddressSuggestion>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final feature = Map<String, dynamic>.from(item);
    final label = (feature['place_name'] ?? feature['text'] ?? '')
        .toString()
        .trim();
    if (label.isEmpty) continue;
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
        label: label,
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
