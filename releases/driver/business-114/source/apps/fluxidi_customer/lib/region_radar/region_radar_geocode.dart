import 'dart:convert';

import 'package:fluxidi_tracking/business/regional_demand_consistency.dart';
import 'package:http/http.dart' as http;

/// One verified postcode location. Never a nearby street or leftover city.
class RegionRadarPlace {
  const RegionRadarPlace({
    required this.country,
    required this.postcode,
    required this.placeName,
    required this.lat,
    required this.lon,
    required this.label,
  });

  final String country;
  final String postcode;
  final String placeName;
  final double lat;
  final double lon;
  final String label;
}

typedef RegionRadarGeocodeHttpGet = Future<http.Response> Function(Uri uri);

typedef RegionRadarPlaceLookup =
    Future<RegionRadarPlace?> Function({
      required String country,
      required String postcode,
      required String language,
    });

/// Picks only a postcode feature that matches [country] and [postcode].
///
/// Address and place hits are ignored, even when they appear first. The
/// previous Mapbox address search for `9688 België` returned a Limburg street
/// and moved the camera to Hasselt / Herk-de-Stad.
RegionRadarPlace? pickRegionRadarPlace({
  required String country,
  required String postcode,
  required List<Object?> features,
}) {
  final wantedCountry = parseDemandRadarCountryCode(country);
  final wantedPostcode = normalizeDemandRadarPostcode(postcode);
  if (wantedCountry.isEmpty || wantedPostcode.isEmpty) return null;

  for (final raw in features) {
    if (raw is! Map) continue;
    final feature = Map<String, dynamic>.from(raw);
    if (!_isPostcodeFeature(feature)) continue;
    if (!_featureMatchesPostcode(feature, wantedPostcode)) continue;
    if (!_featureMatchesCountry(feature, wantedCountry)) continue;
    final center = feature['center'];
    if (center is! List || center.length < 2) continue;
    final lon = (center[0] as num?)?.toDouble();
    final lat = (center[1] as num?)?.toDouble();
    if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
      continue;
    }
    final placeName = _placeNameFrom(feature, wantedPostcode);
    return RegionRadarPlace(
      country: wantedCountry,
      postcode: wantedPostcode,
      placeName: placeName,
      lat: lat,
      lon: lon,
      label: placeName.isEmpty
          ? wantedPostcode
          : '$wantedPostcode · $placeName',
    );
  }
  return null;
}

/// Mapbox postcode lookup, scoped to the selected country.
Future<RegionRadarPlace?> lookupRegionRadarPlace({
  required String token,
  required String country,
  required String postcode,
  String language = 'nl',
  RegionRadarGeocodeHttpGet? httpGet,
}) async {
  final wantedCountry = parseDemandRadarCountryCode(country);
  final wantedPostcode = normalizeDemandRadarPostcode(postcode);
  if (wantedCountry.isEmpty || wantedPostcode.isEmpty) return null;
  if (token.trim().isEmpty && httpGet == null) return null;

  final uri = Uri.parse(
    'https://api.mapbox.com/geocoding/v5/mapbox.places/'
    '${Uri.encodeComponent(wantedPostcode)}.json'
    '?types=postcode'
    '&country=${wantedCountry.toLowerCase()}'
    '&autocomplete=false'
    '&limit=5'
    '&language=$language'
    '&access_token=${token.trim()}',
  );
  try {
    final res = httpGet != null
        ? await httpGet(uri)
        : await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) return null;
    final features = decoded['features'];
    if (features is! List) return null;
    return pickRegionRadarPlace(
      country: wantedCountry,
      postcode: wantedPostcode,
      features: features,
    );
  } catch (_) {
    return null;
  }
}

bool _isPostcodeFeature(Map<String, dynamic> feature) {
  final types = feature['place_type'];
  if (types is List &&
      types.any((type) => type.toString().toLowerCase() == 'postcode')) {
    return true;
  }
  final id = (feature['id'] ?? '').toString().toLowerCase();
  return id.startsWith('postcode.');
}

bool _featureMatchesPostcode(Map<String, dynamic> feature, String postcode) {
  final candidates = <String>{
    (feature['text'] ?? '').toString(),
    (feature['place_name'] ?? '').toString(),
  };
  for (final context in _contextList(feature)) {
    candidates.add((context['text'] ?? '').toString());
  }
  for (final raw in candidates) {
    if (normalizeDemandRadarPostcode(raw) == postcode) return true;
    final match = RegExp(
      r'(^|[^A-Z0-9])' + RegExp.escape(postcode) + r'([^A-Z0-9]|$)',
      caseSensitive: false,
    ).hasMatch(raw.toUpperCase());
    if (match) return true;
  }
  return false;
}

bool _featureMatchesCountry(Map<String, dynamic> feature, String country) {
  for (final context in _contextList(feature)) {
    final id = (context['id'] ?? '').toString().toLowerCase();
    final short = (context['short_code'] ?? '').toString();
    final parsed = parseDemandRadarCountryCode(short);
    if (parsed == country) return true;
    if (id.startsWith('country.') && parsed == country) return true;
  }
  final placeName = (feature['place_name'] ?? '').toString().toUpperCase();
  return placeName.contains(', $country') || placeName.endsWith(country);
}

String _placeNameFrom(Map<String, dynamic> feature, String postcode) {
  for (final context in _contextList(feature)) {
    final id = (context['id'] ?? '').toString().toLowerCase();
    if (id.startsWith('place.') ||
        id.startsWith('locality.') ||
        id.startsWith('district.')) {
      final text = (context['text'] ?? '').toString().trim();
      if (text.isNotEmpty && normalizeDemandRadarPostcode(text) != postcode) {
        return text;
      }
    }
  }
  final placeName = (feature['place_name'] ?? '').toString();
  final parts = placeName
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .where((part) => normalizeDemandRadarPostcode(part) != postcode)
      .toList(growable: false);
  if (parts.isEmpty) return '';
  return parts.first;
}

List<Map<String, dynamic>> _contextList(Map<String, dynamic> feature) {
  final raw = feature['context'];
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}
