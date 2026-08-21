// Live event-venue search on the existing Mapbox places seam.
// Same host/path as hotel and address lookup. Not a second catalog.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import 'limousine_address_lookup.dart';
import 'limousine_transfer_endpoint.dart';

const int kLimousineEventMinQueryLength = 2;
const String kLimousineEventNearbyQuery = 'venue';
const Duration kLimousineEventDebounce = Duration(milliseconds: 220);
const int kLimousineEventMaxSuggestions = 6;

const Set<String> kLimousineEventVenueCategoryTokens = <String>{
  'concert',
  'concert_hall',
  'music',
  'theatre',
  'theater',
  'stadium',
  'arena',
  'venue',
  'event',
  'event_hall',
  'wedding',
  'wedding_venue',
  'congress',
  'conference',
  'convention',
  'expo',
  'exhibition',
  'festival',
  'fair',
  'fairground',
  'auditorium',
  'opera',
  'civic',
  'hall',
  'amphitheater',
  'amphitheatre',
  'cinema',
  'performing_arts',
};

class LimousineEventVenueSuggestion {
  const LimousineEventVenueSuggestion({
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

  LimousineTransferEndpoint toEndpoint({String eventName = ''}) {
    return LimousineTransferEndpoint(
      kind: LimousineTransferEndpointKind.event,
      displayName: name.trim(),
      formattedAddress: formattedAddress.trim(),
      latitude: latitude,
      longitude: longitude,
      providerPlaceId: providerPlaceId,
      venueName: name.trim(),
      eventName: eventName.trim().isEmpty ? null : eventName.trim(),
      city: city,
      postcode: postcode,
      countryCode: countryCode,
    );
  }
}

class LimousineEventLookupResult {
  const LimousineEventLookupResult({
    this.suggestions = const <LimousineEventVenueSuggestion>[],
    this.hadError = false,
  });

  final List<LimousineEventVenueSuggestion> suggestions;
  final bool hadError;
}

typedef LimousineEventSearch =
    Future<LimousineEventLookupResult> Function(String query, String language);

typedef LimousineEventManualGeocode =
    Future<LimousineTransferEndpoint> Function(String query, String language);

Uri limousineMapboxEventPlacesUri({
  required String query,
  required String token,
  String language = 'nl',
  double? proximityLat,
  double? proximityLng,
}) {
  final encoded = Uri.encodeComponent(query);
  final proximity = limousineMapboxProximitySuffix(
    latitude: proximityLat,
    longitude: proximityLng,
  );
  return Uri.parse(
    'https://$kLimousineMapboxGeocodingV5Host$kLimousineMapboxGeocodingV5PathPrefix$encoded.json'
    '?access_token=${Uri.encodeComponent(token)}'
    '&autocomplete=true'
    '&types=poi'
    '&language=${Uri.encodeComponent(language)}'
    '&limit=$kLimousineEventMaxSuggestions$proximity',
  );
}

bool limousineLooksLikeEventVenueCategory(String raw) {
  final tokens = raw
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9_]+'))
      .where((part) => part.isNotEmpty);
  return tokens.any(kLimousineEventVenueCategoryTokens.contains);
}

bool limousineMapboxFeatureLooksLikeEventVenue(Map<String, dynamic> feature) {
  final properties = feature['properties'];
  if (properties is Map) {
    final category = (properties['category'] ?? properties['maki'] ?? '')
        .toString();
    if (limousineLooksLikeEventVenueCategory(category)) return true;
  }
  final text = '${feature['text'] ?? ''} ${feature['place_name'] ?? ''}';
  return limousineLooksLikeEventVenueCategory(text);
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

List<LimousineEventVenueSuggestion> parseLimousineEventPlaceFeatures(
  Object? rawFeatures,
) {
  if (rawFeatures is! List) return const <LimousineEventVenueSuggestion>[];
  final preferred = <LimousineEventVenueSuggestion>[];
  final fallback = <LimousineEventVenueSuggestion>[];
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
    final suggestion = LimousineEventVenueSuggestion(
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
    if (limousineMapboxFeatureLooksLikeEventVenue(map)) {
      preferred.add(suggestion);
    } else {
      fallback.add(suggestion);
    }
  }
  final chosen = preferred.isNotEmpty ? preferred : fallback;
  return List<LimousineEventVenueSuggestion>.unmodifiable(
    chosen.take(kLimousineEventMaxSuggestions),
  );
}

LimousineTransferEndpoint limousineManualEventEndpoint(
  String raw, {
  String eventName = '',
}) {
  final text = raw.trim();
  return LimousineTransferEndpoint(
    kind: LimousineTransferEndpointKind.event,
    displayName: text,
    formattedAddress: text,
    venueName: text,
    eventName: eventName.trim().isEmpty ? null : eventName.trim(),
    manual: true,
  );
}

class LimousineEventLookup {
  LimousineEventLookup({
    String? token,
    http.Client? client,
    LimousineEventSearch? searchOverride,
    LimousineEventManualGeocode? manualGeocodeOverride,
  }) : token = (token ?? kMapboxToken).trim(),
       _client = client,
       _searchOverride = searchOverride,
       _manualGeocodeOverride = manualGeocodeOverride,
       _ownsClient = client == null && searchOverride == null;

  final String token;
  final http.Client? _client;
  final LimousineEventSearch? _searchOverride;
  final LimousineEventManualGeocode? _manualGeocodeOverride;
  final bool _ownsClient;
  int searchesStarted = 0;
  int manualGeocodesStarted = 0;

  Future<LimousineEventLookupResult> search(
    String rawQuery, {
    String language = 'nl',
    double? proximityLat,
    double? proximityLng,
  }) async {
    final query = rawQuery.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.length < kLimousineEventMinQueryLength) {
      return const LimousineEventLookupResult();
    }
    searchesStarted += 1;
    final override = _searchOverride;
    if (override != null) return override(query, language);
    return _searchMapbox(
      query,
      language,
      proximityLat: proximityLat,
      proximityLng: proximityLng,
    );
  }

  Future<LimousineEventLookupResult> _searchMapbox(
    String query,
    String language, {
    double? proximityLat,
    double? proximityLng,
  }) async {
    if (token.isEmpty) return const LimousineEventLookupResult();
    final uri = limousineMapboxEventPlacesUri(
      query: query,
      token: token,
      language: language,
      proximityLat: proximityLat,
      proximityLng: proximityLng,
    );
    final client = _client ?? http.Client();
    try {
      final res = await client.get(uri).timeout(kLimousineAddressLookupTimeout);
      if (res.statusCode != 200) {
        return const LimousineEventLookupResult(hadError: true);
      }
      final data = jsonDecode(res.body);
      if (data is! Map) {
        return const LimousineEventLookupResult(hadError: true);
      }
      return LimousineEventLookupResult(
        suggestions: parseLimousineEventPlaceFeatures(data['features']),
      );
    } catch (_) {
      return const LimousineEventLookupResult(hadError: true);
    } finally {
      if (_ownsClient && _client == null) {
        client.close();
      }
    }
  }

  Future<LimousineTransferEndpoint> resolveManual(
    String raw, {
    String language = 'nl',
    String eventName = '',
  }) async {
    final fallback = limousineManualEventEndpoint(raw, eventName: eventName);
    manualGeocodesStarted += 1;
    final override = _manualGeocodeOverride;
    if (override != null) {
      final resolved = await override(raw, language);
      return resolved.copyWith(
        eventName: eventName.trim().isEmpty ? resolved.eventName : eventName.trim(),
        manual: true,
      );
    }
    return _geocodeManualAddress(fallback, language);
  }

  Future<LimousineTransferEndpoint> _geocodeManualAddress(
    LimousineTransferEndpoint fallback,
    String language,
  ) async {
    final query = limousineNormalizeAddressQuery(fallback.formattedAddress);
    if (query.length < kLimousineAddressMinQueryLength || token.isEmpty) {
      return fallback;
    }
    final uri = limousineMapboxPlacesUri(
      query: query,
      token: token,
      language: language,
    );
    final client = _client ?? http.Client();
    try {
      final res = await client.get(uri).timeout(kLimousineAddressLookupTimeout);
      if (res.statusCode != 200) return fallback;
      final data = jsonDecode(res.body);
      if (data is! Map) return fallback;
      final suggestions = parseLimousineMapboxPlaceFeatures(data['features']);
      if (suggestions.isEmpty) return fallback;
      final hit = suggestions.first;
      return fallback.copyWith(
        formattedAddress: hit.label.trim().isEmpty
            ? fallback.formattedAddress
            : hit.label.trim(),
        latitude: hit.lat,
        longitude: hit.lon,
        providerPlaceId: hit.placeId,
        manual: true,
      );
    } catch (_) {
      return fallback;
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
