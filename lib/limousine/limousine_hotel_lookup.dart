// Live hotel search on the existing Mapbox places seam.
// RateHawk is never required and is not called.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import 'limousine_address_lookup.dart';
import 'limousine_transfer_endpoint.dart';

const int kLimousineHotelMinQueryLength = 3;
const Duration kLimousineHotelDebounce = Duration(milliseconds: 220);
const int kLimousineHotelMaxSuggestions = 6;

const Set<String> kLimousineHotelCategoryTokens = <String>{
  'hotel',
  'lodging',
  'accommodation',
  'motel',
  'hostel',
  'resort',
  'inn',
  'guesthouse',
  'guest_house',
  'bed_and_breakfast',
  'bnb',
};

class LimousineHotelSuggestion {
  const LimousineHotelSuggestion({
    required this.name,
    required this.formattedAddress,
    this.latitude,
    this.longitude,
    this.providerPlaceId,
    this.city,
    this.postcode,
    this.countryCode,
  });

  final String name;
  final String formattedAddress;
  final double? latitude;
  final double? longitude;
  final String? providerPlaceId;
  final String? city;
  final String? postcode;
  final String? countryCode;

  bool get isUsable =>
      name.trim().isNotEmpty &&
      formattedAddress.trim().isNotEmpty &&
      latitude != null &&
      longitude != null &&
      limousineCoordinatesAreValid(latitude!, longitude!);

  LimousineTransferEndpoint toEndpoint() {
    return LimousineTransferEndpoint(
      kind: LimousineTransferEndpointKind.hotel,
      displayName: name.trim(),
      formattedAddress: formattedAddress.trim(),
      latitude: latitude,
      longitude: longitude,
      providerPlaceId: providerPlaceId,
      hotelName: name.trim(),
      city: city,
      postcode: postcode,
      countryCode: countryCode,
      ratehawkHotelId: null,
    );
  }
}

class LimousineHotelLookupResult {
  const LimousineHotelLookupResult({
    this.suggestions = const <LimousineHotelSuggestion>[],
    this.hadError = false,
  });

  final List<LimousineHotelSuggestion> suggestions;
  final bool hadError;
}

typedef LimousineHotelSearch =
    Future<LimousineHotelLookupResult> Function(String query, String language);

Uri limousineMapboxHotelPlacesUri({
  required String query,
  required String token,
  String language = 'nl',
}) {
  final encoded = Uri.encodeComponent(query);
  return Uri.parse(
    'https://$kLimousineMapboxGeocodingV5Host$kLimousineMapboxGeocodingV5PathPrefix$encoded.json'
    '?access_token=${Uri.encodeComponent(token)}'
    '&autocomplete=true'
    '&types=poi'
    '&language=${Uri.encodeComponent(language)}'
    '&limit=$kLimousineHotelMaxSuggestions',
  );
}

bool limousineLooksLikeHotelCategory(String raw) {
  final tokens = raw
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9_]+'))
      .where((part) => part.isNotEmpty);
  return tokens.any(kLimousineHotelCategoryTokens.contains);
}

bool limousineMapboxFeatureLooksLikeHotel(Map<String, dynamic> feature) {
  final properties = feature['properties'];
  if (properties is Map) {
    final category = (properties['category'] ?? properties['maki'] ?? '')
        .toString();
    if (limousineLooksLikeHotelCategory(category)) return true;
  }
  final text = '${feature['text'] ?? ''} ${feature['place_name'] ?? ''}';
  return limousineLooksLikeHotelCategory(text);
}

String? _mapboxContextText(List<dynamic>? context, String prefix) {
  if (context == null) return null;
  for (final item in context) {
    if (item is! Map) continue;
    final id = (item['id'] ?? '').toString();
    if (!id.startsWith(prefix)) continue;
    final text = (item['text'] ?? '').toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

String? _mapboxCountryCode(List<dynamic>? context) {
  if (context == null) return null;
  for (final item in context) {
    if (item is! Map) continue;
    final id = (item['id'] ?? '').toString();
    if (!id.startsWith('country')) continue;
    final short = (item['short_code'] ?? '').toString().trim().toUpperCase();
    return short.isEmpty ? null : short;
  }
  return null;
}

List<LimousineHotelSuggestion> parseLimousineHotelPlaceFeatures(
  Object? rawFeatures,
) {
  if (rawFeatures is! List) return const <LimousineHotelSuggestion>[];
  final preferred = <LimousineHotelSuggestion>[];
  final fallback = <LimousineHotelSuggestion>[];
  for (final feature in rawFeatures) {
    if (feature is! Map) continue;
    final map = feature.map((key, value) => MapEntry(key.toString(), value));
    final formatted = (map['place_name'] ?? '').toString().trim();
    final name = (map['text'] ?? '').toString().trim();
    if (formatted.isEmpty || name.isEmpty) continue;
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
    final context = map['context'] is List ? map['context'] as List : null;
    final suggestion = LimousineHotelSuggestion(
      name: name,
      formattedAddress: formatted,
      latitude: lat,
      longitude: lon,
      providerPlaceId: (map['id'] ?? '').toString().trim().isEmpty
          ? null
          : (map['id'] ?? '').toString().trim(),
      city: _mapboxContextText(context, 'place'),
      postcode: _mapboxContextText(context, 'postcode'),
      countryCode: _mapboxCountryCode(context),
    );
    if (!suggestion.isUsable) continue;
    if (limousineMapboxFeatureLooksLikeHotel(map)) {
      preferred.add(suggestion);
    } else {
      fallback.add(suggestion);
    }
  }
  final chosen = preferred.isNotEmpty ? preferred : fallback;
  return List<LimousineHotelSuggestion>.unmodifiable(
    chosen.take(kLimousineHotelMaxSuggestions),
  );
}

LimousineTransferEndpoint limousineManualHotelEndpoint(String raw) {
  final text = raw.trim();
  return LimousineTransferEndpoint(
    kind: LimousineTransferEndpointKind.hotel,
    displayName: text,
    formattedAddress: text,
    hotelName: text,
    ratehawkHotelId: null,
    manual: true,
  );
}

class LimousineHotelLookup {
  LimousineHotelLookup({
    String? token,
    http.Client? client,
    LimousineHotelSearch? searchOverride,
  }) : token = (token ?? kMapboxToken).trim(),
       _client = client,
       _searchOverride = searchOverride,
       _ownsClient = client == null && searchOverride == null;

  final String token;
  final http.Client? _client;
  final LimousineHotelSearch? _searchOverride;
  final bool _ownsClient;
  int searchesStarted = 0;

  Future<LimousineHotelLookupResult> search(
    String rawQuery, {
    String language = 'nl',
  }) async {
    final query = rawQuery.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.length < kLimousineHotelMinQueryLength) {
      return const LimousineHotelLookupResult();
    }
    searchesStarted += 1;
    final override = _searchOverride;
    if (override != null) return override(query, language);
    return _searchMapbox(query, language);
  }

  Future<LimousineHotelLookupResult> _searchMapbox(
    String query,
    String language,
  ) async {
    if (token.isEmpty) return const LimousineHotelLookupResult();
    final uri = limousineMapboxHotelPlacesUri(
      query: query,
      token: token,
      language: language,
    );
    final client = _client ?? http.Client();
    try {
      final res = await client.get(uri).timeout(kLimousineAddressLookupTimeout);
      if (res.statusCode != 200) {
        return const LimousineHotelLookupResult(hadError: true);
      }
      final data = jsonDecode(res.body);
      if (data is! Map) {
        return const LimousineHotelLookupResult(hadError: true);
      }
      return LimousineHotelLookupResult(
        suggestions: parseLimousineHotelPlaceFeatures(data['features']),
      );
    } catch (_) {
      return const LimousineHotelLookupResult(hadError: true);
    } finally {
      if (_ownsClient && _client == null) {
        client.close();
      }
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client?.close();
    }
  }
}
