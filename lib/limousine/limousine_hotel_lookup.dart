// Shared Mapbox Search Box pipeline for limousine hotel endpoints.
// RateHawk is never required and is not called. The existing MAPBOX_TOKEN
// is reused fail-closed. URLs and tokens are never logged.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import 'limousine_address_lookup.dart';
import 'limousine_transfer_endpoint.dart';

const int kLimousineHotelMinQueryLength = 2;
const String kLimousineHotelNearbyQuery = 'hotel';
const Duration kLimousineHotelDebounce = Duration(milliseconds: 220);
const int kLimousineHotelMaxSuggestions = 8;
const String kLimousineMapboxSearchHost = 'api.mapbox.com';
const String kLimousineMapboxSearchBoxPrefix = '/search/searchbox/v1';

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

const List<String> kLimousineHotelNameHints = <String>[
  'hotel',
  'hotels',
  'lodging',
  'motel',
  'hostel',
  'resort',
  'inn',
  'b&b',
  'bnb',
];

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
    this.countryName,
    this.distanceMeters,
    this.sessionToken,
    this.needsRetrieve = false,
  });

  final String name;
  final String formattedAddress;
  final double? latitude;
  final double? longitude;
  final String? providerPlaceId;
  final String? city;
  final String? postcode;
  final String? countryCode;
  final String? countryName;
  final double? distanceMeters;
  final String? sessionToken;
  final bool needsRetrieve;

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
      manual: false,
    );
  }
}

class LimousineHotelPlaceAnchor {
  const LimousineHotelPlaceAnchor({
    required this.latitude,
    required this.longitude,
    this.bbox,
    this.countryCode,
    this.label = '',
  });

  final double latitude;
  final double longitude;
  final List<double>? bbox;
  final String? countryCode;
  final String label;
}

class LimousineHotelLookupResult {
  const LimousineHotelLookupResult({
    this.suggestions = const <LimousineHotelSuggestion>[],
    this.hadError = false,
    this.errorCode = '',
    this.sessionToken = '',
    this.completed = true,
  });

  final List<LimousineHotelSuggestion> suggestions;
  final bool hadError;
  final String errorCode;
  final String sessionToken;
  final bool completed;

  LimousineHotelLookupResult copyWith({
    List<LimousineHotelSuggestion>? suggestions,
    bool? hadError,
    String? errorCode,
    String? sessionToken,
    bool? completed,
  }) {
    return LimousineHotelLookupResult(
      suggestions: suggestions ?? this.suggestions,
      hadError: hadError ?? this.hadError,
      errorCode: errorCode ?? this.errorCode,
      sessionToken: sessionToken ?? this.sessionToken,
      completed: completed ?? this.completed,
    );
  }
}

class LimousineHotelSearchLog {
  const LimousineHotelSearchLog({
    required this.phase,
    required this.httpStatus,
    required this.featureCount,
    required this.hotelCount,
  });

  final String phase;
  final int httpStatus;
  final int featureCount;
  final int hotelCount;
}

typedef LimousineHotelSearch =
    Future<LimousineHotelLookupResult> Function(String query, String language);

typedef LimousineHotelRetrieve =
    Future<LimousineHotelSuggestion?> Function(LimousineHotelSuggestion suggestion);

bool limousineHotelQueryLooksLikeHotelName(String raw) {
  final query = raw.trim().toLowerCase();
  if (query.isEmpty) return false;
  return kLimousineHotelNameHints.any(query.contains);
}

bool limousineLooksLikeHotelCategory(String raw) {
  final tokens = raw
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9_]+'))
      .where((part) => part.isNotEmpty);
  return tokens.any(kLimousineHotelCategoryTokens.contains);
}

String createLimousineHotelSessionToken([Random? random]) {
  final rng = random ?? Random();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Uri limousineMapboxSearchBoxUri({
  required String path,
  required String token,
  Map<String, String> query = const <String, String>{},
}) {
  return Uri.https(kLimousineMapboxSearchHost, path, <String, String>{
    ...query,
    'access_token': token,
  });
}

Uri limousineMapboxSearchForwardUri({
  required String query,
  required String token,
  String language = 'nl',
}) {
  return limousineMapboxSearchBoxUri(
    path: '$kLimousineMapboxSearchBoxPrefix/forward',
    token: token,
    query: <String, String>{
      'q': query,
      'language': language,
      'limit': '1',
      'types': 'place,locality,postcode,address',
    },
  );
}

Uri limousineMapboxSearchSuggestUri({
  required String query,
  required String token,
  required String sessionToken,
  String language = 'nl',
  double? proximityLat,
  double? proximityLng,
  String? countryCode,
}) {
  final queryMap = <String, String>{
    'q': query,
    'language': language,
    'limit': '$kLimousineHotelMaxSuggestions',
    'session_token': sessionToken,
    'types': 'poi',
  };
  if (proximityLat != null &&
      proximityLng != null &&
      limousineCoordinatesAreValid(proximityLat, proximityLng)) {
    queryMap['proximity'] = '$proximityLng,$proximityLat';
  }
  if ((countryCode ?? '').trim().isNotEmpty) {
    queryMap['country'] = countryCode!.trim().toLowerCase();
  }
  return limousineMapboxSearchBoxUri(
    path: '$kLimousineMapboxSearchBoxPrefix/suggest',
    token: token,
    query: queryMap,
  );
}

Uri limousineMapboxSearchRetrieveUri({
  required String mapboxId,
  required String token,
  required String sessionToken,
}) {
  return limousineMapboxSearchBoxUri(
    path: '$kLimousineMapboxSearchBoxPrefix/retrieve/${Uri.encodeComponent(mapboxId)}',
    token: token,
    query: <String, String>{'session_token': sessionToken},
  );
}

Uri limousineMapboxSearchCategoryUri({
  required String category,
  required String token,
  required double latitude,
  required double longitude,
  String language = 'nl',
  String? countryCode,
  List<double>? bbox,
  int limit = kLimousineHotelMaxSuggestions,
}) {
  final query = <String, String>{
    'language': language,
    'limit': '$limit',
    'proximity': '$longitude,$latitude',
  };
  if ((countryCode ?? '').trim().isNotEmpty) {
    query['country'] = countryCode!.trim().toLowerCase();
  }
  if (bbox != null && bbox.length == 4) {
    query['bbox'] = bbox.map((n) => n.toString()).join(',');
  }
  return limousineMapboxSearchBoxUri(
    path: '$kLimousineMapboxSearchBoxPrefix/category/$category',
    token: token,
    query: query,
  );
}

Uri limousineMapboxGeocodingHotelNearbyUri({
  required String token,
  required double latitude,
  required double longitude,
  String language = 'nl',
  String country = 'BE',
}) {
  return Uri.https('api.mapbox.com', '/geocoding/v5/mapbox.places/hotel.json', {
    'access_token': token,
    'types': 'poi',
    'limit': '$kLimousineHotelMaxSuggestions',
    'language': language,
    'country': country,
    'proximity': '$longitude,$latitude',
  });
}

List<double> limousineHotelExpandedBbox({
  required double latitude,
  required double longitude,
  required double radiusKm,
}) {
  final latDelta = radiusKm / 111.0;
  final lonDelta = radiusKm / (111.0 * cos(latitude * pi / 180)).abs().clamp(0.2, 1.0);
  return <double>[
    longitude - lonDelta,
    latitude - latDelta,
    longitude + lonDelta,
    latitude + latDelta,
  ];
}

String? _contextName(Object? context, String key) {
  if (context is! Map) return null;
  final item = context[key];
  if (item is Map) {
    final name = (item['name'] ?? item['text'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
  }
  return null;
}

String? _contextCountryCode(Object? context) {
  if (context is! Map) return null;
  final country = context['country'];
  if (country is Map) {
    final code = (country['country_code'] ?? country['short_code'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (code.isNotEmpty) return code;
  }
  return null;
}

({double? lat, double? lon}) _readCoordinates(Map<String, dynamic> map) {
  final geometry = map['geometry'];
  if (geometry is Map) {
    final coords = geometry['coordinates'];
    if (coords is List && coords.length >= 2) {
      final lon = coords[0] is num
          ? (coords[0] as num).toDouble()
          : double.tryParse('${coords[0]}');
      final lat = coords[1] is num
          ? (coords[1] as num).toDouble()
          : double.tryParse('${coords[1]}');
      return (lat: lat, lon: lon);
    }
  }
  final props = map['properties'];
  if (props is Map) {
    final coordinates = props['coordinates'];
    if (coordinates is Map) {
      final lat = coordinates['latitude'] is num
          ? (coordinates['latitude'] as num).toDouble()
          : double.tryParse('${coordinates['latitude']}');
      final lon = coordinates['longitude'] is num
          ? (coordinates['longitude'] as num).toDouble()
          : double.tryParse('${coordinates['longitude']}');
      return (lat: lat, lon: lon);
    }
  }
  final center = map['center'];
  if (center is List && center.length >= 2) {
    final lon = center[0] is num
        ? (center[0] as num).toDouble()
        : double.tryParse('${center[0]}');
    final lat = center[1] is num
        ? (center[1] as num).toDouble()
        : double.tryParse('${center[1]}');
    return (lat: lat, lon: lon);
  }
  return (lat: null, lon: null);
}

LimousineHotelSuggestion? parseLimousineSearchBoxFeature(
  Object? raw, {
  String? sessionToken,
  bool needsRetrieve = false,
}) {
  if (raw is! Map) return null;
  final map = raw.map((key, value) => MapEntry(key.toString(), value));
  final properties = map['properties'] is Map
      ? (map['properties'] as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        )
      : map;
  final name = (properties['name'] ?? map['name'] ?? map['text'] ?? '')
      .toString()
      .trim();
  final formatted =
      (properties['full_address'] ??
              properties['place_formatted'] ??
              properties['address'] ??
              map['full_address'] ??
              map['place_formatted'] ??
              map['place_name'] ??
              '')
          .toString()
          .trim();
  if (name.isEmpty) return null;
  final coords = _readCoordinates(map);
  final context = properties['context'] ?? map['context'];
  final mapboxId =
      (properties['mapbox_id'] ?? map['mapbox_id'] ?? map['id'] ?? '')
          .toString()
          .trim();
  final distanceRaw = properties['distance'] ?? map['distance'];
  final distance = distanceRaw is num
      ? distanceRaw.toDouble()
      : double.tryParse('$distanceRaw');
  final suggestion = LimousineHotelSuggestion(
    name: name,
    formattedAddress: formatted.isEmpty ? name : formatted,
    latitude: coords.lat,
    longitude: coords.lon,
    providerPlaceId: mapboxId.isEmpty ? null : mapboxId,
    city: _contextName(context, 'place') ?? _contextName(context, 'locality'),
    postcode: _contextName(context, 'postcode'),
    countryCode: _contextCountryCode(context),
    countryName: _contextName(context, 'country'),
    distanceMeters: distance,
    sessionToken: sessionToken,
    needsRetrieve: needsRetrieve && (coords.lat == null || coords.lon == null),
  );
  if (needsRetrieve && (suggestion.providerPlaceId ?? '').isNotEmpty) {
    return suggestion;
  }
  return suggestion.isUsable ? suggestion : null;
}

List<LimousineHotelSuggestion> parseLimousineSearchBoxFeatures(
  Object? rawFeatures, {
  String? sessionToken,
  bool needsRetrieve = false,
}) {
  if (rawFeatures is! List) return const <LimousineHotelSuggestion>[];
  final out = <LimousineHotelSuggestion>[];
  for (final feature in rawFeatures) {
    final parsed = parseLimousineSearchBoxFeature(
      feature,
      sessionToken: sessionToken,
      needsRetrieve: needsRetrieve,
    );
    if (parsed != null) out.add(parsed);
  }
  return out;
}

List<LimousineHotelSuggestion> parseLimousineSearchBoxSuggestions(
  Object? rawSuggestions, {
  required String sessionToken,
}) {
  if (rawSuggestions is! List) return const <LimousineHotelSuggestion>[];
  final out = <LimousineHotelSuggestion>[];
  for (final item in rawSuggestions) {
    if (item is! Map) continue;
    final map = item.map((key, value) => MapEntry(key.toString(), value));
    final featureType = (map['feature_type'] ?? '').toString().toLowerCase();
    if (featureType.isNotEmpty &&
        featureType != 'poi' &&
        featureType != 'category') {
      continue;
    }
    final category = '${map['poi_category'] ?? ''} ${map['name'] ?? ''}';
    if (featureType == 'poi' &&
        category.trim().isNotEmpty &&
        !limousineLooksLikeHotelCategory(category) &&
        !limousineHotelQueryLooksLikeHotelName(map['name']?.toString() ?? '')) {
      continue;
    }
    final parsed = parseLimousineSearchBoxFeature(
      map,
      sessionToken: sessionToken,
      needsRetrieve: true,
    );
    if (parsed != null) out.add(parsed);
  }
  return out;
}

LimousineHotelPlaceAnchor? parseLimousineSearchBoxPlaceAnchor(Object? rawFeatures) {
  if (rawFeatures is! List || rawFeatures.isEmpty) return null;
  final first = rawFeatures.first;
  if (first is! Map) return null;
  final map = first.map((key, value) => MapEntry(key.toString(), value));
  final coords = _readCoordinates(map);
  if (coords.lat == null ||
      coords.lon == null ||
      !limousineCoordinatesAreValid(coords.lat!, coords.lon!)) {
    return null;
  }
  final properties = map['properties'] is Map
      ? (map['properties'] as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        )
      : map;
  final bboxRaw = properties['bbox'] ?? map['bbox'];
  List<double>? bbox;
  if (bboxRaw is List && bboxRaw.length == 4) {
    bbox = bboxRaw
        .map((n) => n is num ? n.toDouble() : double.tryParse('$n') ?? 0)
        .toList(growable: false);
  }
  return LimousineHotelPlaceAnchor(
    latitude: coords.lat!,
    longitude: coords.lon!,
    bbox: bbox,
    countryCode: _contextCountryCode(properties['context'] ?? map['context']),
    label: (properties['name'] ?? properties['place_formatted'] ?? '')
        .toString(),
  );
}

List<LimousineHotelSuggestion> mergeLimousineHotelSuggestions(
  Iterable<LimousineHotelSuggestion> incoming,
) {
  final byId = <String, LimousineHotelSuggestion>{};
  final byNameCoord = <String, LimousineHotelSuggestion>{};
  final out = <LimousineHotelSuggestion>[];
  for (final item in incoming) {
    final id = (item.providerPlaceId ?? '').trim();
    if (id.isNotEmpty) {
      if (byId.containsKey(id)) continue;
      byId[id] = item;
      out.add(item);
      continue;
    }
    final lat = item.latitude?.toStringAsFixed(4) ?? '';
    final lon = item.longitude?.toStringAsFixed(4) ?? '';
    final key = '${item.name.trim().toLowerCase()}|$lat|$lon';
    if (byNameCoord.containsKey(key)) continue;
    byNameCoord[key] = item;
    out.add(item);
  }
  return List<LimousineHotelSuggestion>.unmodifiable(
    out.take(kLimousineHotelMaxSuggestions),
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

void logLimousineHotelSearch(LimousineHotelSearchLog event) {
  if (!kDebugMode) return;
  debugPrint(
    '[LIMOUSINE_HOTEL_SEARCH] phase=${event.phase} '
    'http=${event.httpStatus} features=${event.featureCount} '
    'hotels=${event.hotelCount}',
  );
}

class LimousineHotelLookup {
  LimousineHotelLookup({
    String? token,
    http.Client? client,
    LimousineHotelSearch? searchOverride,
    LimousineHotelRetrieve? retrieveOverride,
    Random? random,
  }) : token = (token ?? kMapboxToken).trim(),
       _client = client,
       _searchOverride = searchOverride,
       _retrieveOverride = retrieveOverride,
       _random = random,
       _ownsClient = client == null && searchOverride == null;

  final String token;
  final http.Client? _client;
  final LimousineHotelSearch? _searchOverride;
  final LimousineHotelRetrieve? _retrieveOverride;
  final Random? _random;
  final bool _ownsClient;
  int searchesStarted = 0;
  final List<LimousineHotelSearchLog> debugEvents = <LimousineHotelSearchLog>[];

  void _record(LimousineHotelSearchLog event) {
    debugEvents.add(event);
    logLimousineHotelSearch(event);
  }

  Future<LimousineHotelLookupResult> search(
    String rawQuery, {
    String language = 'nl',
    double? proximityLat,
    double? proximityLng,
  }) async {
    final query = rawQuery.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.length < kLimousineHotelMinQueryLength) {
      return const LimousineHotelLookupResult();
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

  Future<LimousineHotelSuggestion?> resolveSuggestion(
    LimousineHotelSuggestion suggestion,
  ) async {
    if (!suggestion.needsRetrieve && suggestion.isUsable) return suggestion;
    final override = _retrieveOverride;
    if (override != null) return override(suggestion);
    return _retrieveMapbox(suggestion);
  }

  Future<LimousineHotelLookupResult> _searchMapbox(
    String query,
    String language, {
    double? proximityLat,
    double? proximityLng,
  }) async {
    if (token.isEmpty) {
      _record(
        const LimousineHotelSearchLog(
          phase: 'token',
          httpStatus: 0,
          featureCount: 0,
          hotelCount: 0,
        ),
      );
      return const LimousineHotelLookupResult(
        hadError: true,
        errorCode: 'token_missing',
      );
    }
    final sessionToken = createLimousineHotelSessionToken(_random);
    final hotels = <LimousineHotelSuggestion>[];
    var hadError = false;

    final place = await _forwardPlace(query, language);
    if (place.hadError) hadError = true;
    final anchor = place.anchor;
    if (anchor != null) {
      final nearby = await _categoryHotels(
        anchor: anchor,
        language: language,
        sessionToken: sessionToken,
      );
      if (nearby.hadError) hadError = true;
      hotels.addAll(nearby.suggestions);
    }

    if (limousineHotelQueryLooksLikeHotelName(query) || hotels.isEmpty) {
      final suggested = await _suggestHotels(
        query: query,
        language: language,
        sessionToken: sessionToken,
        proximityLat: anchor?.latitude ?? proximityLat,
        proximityLng: anchor?.longitude ?? proximityLng,
        countryCode: anchor?.countryCode,
      );
      if (suggested.hadError) hadError = true;
      hotels.addAll(suggested.suggestions);
    }

    final merged = mergeLimousineHotelSuggestions(hotels);
    if (merged.isNotEmpty) {
      return LimousineHotelLookupResult(
        suggestions: merged,
        sessionToken: sessionToken,
      );
    }
    final fallback = await _searchGeocodingFallback(query, language);
    if (fallback.suggestions.isNotEmpty) {
      return fallback.copyWith(sessionToken: sessionToken);
    }
    if (hadError || fallback.hadError) {
      return LimousineHotelLookupResult(
        hadError: true,
        errorCode: fallback.errorCode.isNotEmpty
            ? fallback.errorCode
            : 'search_failed',
        sessionToken: sessionToken,
      );
    }
    return LimousineHotelLookupResult(sessionToken: sessionToken);
  }

  Future<LimousineHotelLookupResult> _searchGeocodingFallback(
    String query,
    String language,
  ) async {
    final placeUri = limousineMapboxPlacesUri(
      query: query,
      token: token,
      language: language,
    );
    final placeRes = await _get(placeUri);
    if (placeRes == null) {
      _record(
        const LimousineHotelSearchLog(
          phase: 'geocoding_place',
          httpStatus: 0,
          featureCount: 0,
          hotelCount: 0,
        ),
      );
      return const LimousineHotelLookupResult(
        hadError: true,
        errorCode: 'search_failed',
      );
    }
    if (placeRes.statusCode == 401 || placeRes.statusCode == 403) {
      _record(
        LimousineHotelSearchLog(
          phase: 'geocoding_place',
          httpStatus: placeRes.statusCode,
          featureCount: 0,
          hotelCount: 0,
        ),
      );
      return const LimousineHotelLookupResult(
        hadError: true,
        errorCode: 'authorization',
      );
    }
    if (placeRes.statusCode != 200) {
      _record(
        LimousineHotelSearchLog(
          phase: 'geocoding_place',
          httpStatus: placeRes.statusCode,
          featureCount: 0,
          hotelCount: 0,
        ),
      );
      return const LimousineHotelLookupResult(
        hadError: true,
        errorCode: 'search_failed',
      );
    }
    final placeData = _decodeMap(placeRes.body);
    final placeFeatures = placeData?['features'];
    final anchor = parseLimousineSearchBoxPlaceAnchor(placeFeatures);
    _record(
      LimousineHotelSearchLog(
        phase: 'geocoding_place',
        httpStatus: placeRes.statusCode,
        featureCount: placeFeatures is List ? placeFeatures.length : 0,
        hotelCount: 0,
      ),
    );
    if (anchor == null) {
      return const LimousineHotelLookupResult();
    }
    final nearbyUri = limousineMapboxGeocodingHotelNearbyUri(
      token: token,
      latitude: anchor.latitude,
      longitude: anchor.longitude,
      language: language,
      country: (anchor.countryCode ?? 'BE').toLowerCase(),
    );
    final nearbyRes = await _get(nearbyUri);
    if (nearbyRes == null || nearbyRes.statusCode != 200) {
      _record(
        LimousineHotelSearchLog(
          phase: 'geocoding_hotel',
          httpStatus: nearbyRes?.statusCode ?? 0,
          featureCount: 0,
          hotelCount: 0,
        ),
      );
      return LimousineHotelLookupResult(
        hadError: true,
        errorCode: nearbyRes?.statusCode == 401 || nearbyRes?.statusCode == 403
            ? 'authorization'
            : 'search_failed',
      );
    }
    final nearbyData = _decodeMap(nearbyRes.body);
    final nearbyFeatures = nearbyData?['features'];
    final parsed = parseLimousineSearchBoxFeatures(nearbyFeatures);
    _record(
      LimousineHotelSearchLog(
        phase: 'geocoding_hotel',
        httpStatus: nearbyRes.statusCode,
        featureCount: nearbyFeatures is List ? nearbyFeatures.length : 0,
        hotelCount: parsed.length,
      ),
    );
    return LimousineHotelLookupResult(suggestions: parsed);
  }

  Future<({LimousineHotelPlaceAnchor? anchor, bool hadError})> _forwardPlace(
    String query,
    String language,
  ) async {
    final uri = limousineMapboxSearchForwardUri(
      query: query,
      token: token,
      language: language,
    );
    final res = await _get(uri);
    if (res == null) {
      _record(
        const LimousineHotelSearchLog(
          phase: 'place',
          httpStatus: 0,
          featureCount: 0,
          hotelCount: 0,
        ),
      );
      return (anchor: null, hadError: true);
    }
    if (res.statusCode != 200) {
      _record(
        LimousineHotelSearchLog(
          phase: 'place',
          httpStatus: res.statusCode,
          featureCount: 0,
          hotelCount: 0,
        ),
      );
      return (anchor: null, hadError: true);
    }
    final data = _decodeMap(res.body);
    final features = data?['features'];
    final featureCount = features is List ? features.length : 0;
    final anchor = parseLimousineSearchBoxPlaceAnchor(features);
    _record(
      LimousineHotelSearchLog(
        phase: 'place',
        httpStatus: res.statusCode,
        featureCount: featureCount,
        hotelCount: 0,
      ),
    );
    return (anchor: anchor, hadError: false);
  }

  Future<LimousineHotelLookupResult> _categoryHotels({
    required LimousineHotelPlaceAnchor anchor,
    required String language,
    required String sessionToken,
  }) async {
    final attempts = <List<double>?>[
      anchor.bbox,
      null,
      limousineHotelExpandedBbox(
        latitude: anchor.latitude,
        longitude: anchor.longitude,
        radiusKm: 15,
      ),
      limousineHotelExpandedBbox(
        latitude: anchor.latitude,
        longitude: anchor.longitude,
        radiusKm: 30,
      ),
    ];
    final collected = <LimousineHotelSuggestion>[];
    var hadError = false;
    for (final bbox in attempts) {
      for (final category in <String>['hotel', 'lodging']) {
        final uri = limousineMapboxSearchCategoryUri(
          category: category,
          token: token,
          latitude: anchor.latitude,
          longitude: anchor.longitude,
          language: language,
          countryCode: anchor.countryCode,
          bbox: bbox,
        );
        final res = await _get(uri);
        if (res == null) {
          hadError = true;
          _record(
            LimousineHotelSearchLog(
              phase: 'category_$category',
              httpStatus: 0,
              featureCount: 0,
              hotelCount: collected.length,
            ),
          );
          continue;
        }
        if (res.statusCode != 200) {
          hadError = true;
          _record(
            LimousineHotelSearchLog(
              phase: 'category_$category',
              httpStatus: res.statusCode,
              featureCount: 0,
              hotelCount: collected.length,
            ),
          );
          continue;
        }
        final data = _decodeMap(res.body);
        final features = data?['features'];
        final parsed = parseLimousineSearchBoxFeatures(
          features,
          sessionToken: sessionToken,
        );
        collected.addAll(parsed);
        _record(
          LimousineHotelSearchLog(
            phase: 'category_$category',
            httpStatus: res.statusCode,
            featureCount: features is List ? features.length : 0,
            hotelCount: parsed.length,
          ),
        );
      }
      if (collected.isNotEmpty) break;
    }
    return LimousineHotelLookupResult(
      suggestions: collected,
      hadError: hadError && collected.isEmpty,
      sessionToken: sessionToken,
    );
  }

  Future<LimousineHotelLookupResult> _suggestHotels({
    required String query,
    required String language,
    required String sessionToken,
    double? proximityLat,
    double? proximityLng,
    String? countryCode,
  }) async {
    final uri = limousineMapboxSearchSuggestUri(
      query: query,
      token: token,
      sessionToken: sessionToken,
      language: language,
      proximityLat: proximityLat,
      proximityLng: proximityLng,
      countryCode: countryCode,
    );
    final res = await _get(uri);
    if (res == null) {
      _record(
        const LimousineHotelSearchLog(
          phase: 'suggest',
          httpStatus: 0,
          featureCount: 0,
          hotelCount: 0,
        ),
      );
      return LimousineHotelLookupResult(
        hadError: true,
        sessionToken: sessionToken,
      );
    }
    if (res.statusCode != 200) {
      _record(
        LimousineHotelSearchLog(
          phase: 'suggest',
          httpStatus: res.statusCode,
          featureCount: 0,
          hotelCount: 0,
        ),
      );
      return LimousineHotelLookupResult(
        hadError: true,
        sessionToken: sessionToken,
      );
    }
    final data = _decodeMap(res.body);
    final suggestions = parseLimousineSearchBoxSuggestions(
      data?['suggestions'],
      sessionToken: sessionToken,
    );
    _record(
      LimousineHotelSearchLog(
        phase: 'suggest',
        httpStatus: res.statusCode,
        featureCount: data?['suggestions'] is List
            ? (data!['suggestions'] as List).length
            : 0,
        hotelCount: suggestions.length,
      ),
    );
    return LimousineHotelLookupResult(
      suggestions: suggestions,
      sessionToken: sessionToken,
    );
  }

  Future<LimousineHotelSuggestion?> _retrieveMapbox(
    LimousineHotelSuggestion suggestion,
  ) async {
    final mapboxId = (suggestion.providerPlaceId ?? '').trim();
    final sessionToken = (suggestion.sessionToken ?? '').trim();
    if (mapboxId.isEmpty || sessionToken.isEmpty || token.isEmpty) {
      return suggestion.isUsable ? suggestion : null;
    }
    final uri = limousineMapboxSearchRetrieveUri(
      mapboxId: mapboxId,
      token: token,
      sessionToken: sessionToken,
    );
    final res = await _get(uri);
    if (res == null || res.statusCode != 200) {
      _record(
        LimousineHotelSearchLog(
          phase: 'retrieve',
          httpStatus: res?.statusCode ?? 0,
          featureCount: 0,
          hotelCount: 0,
        ),
      );
      return suggestion.isUsable ? suggestion : null;
    }
    final data = _decodeMap(res.body);
    final parsed = parseLimousineSearchBoxFeatures(
      data?['features'],
      sessionToken: sessionToken,
    );
    _record(
      LimousineHotelSearchLog(
        phase: 'retrieve',
        httpStatus: res.statusCode,
        featureCount: data?['features'] is List
            ? (data!['features'] as List).length
            : 0,
        hotelCount: parsed.length,
      ),
    );
    if (parsed.isEmpty) return suggestion.isUsable ? suggestion : null;
    return parsed.first;
  }

  Map<String, dynamic>? _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
  }

  Future<http.Response?> _get(Uri uri) async {
    final client = _client ?? http.Client();
    try {
      return await client.get(uri).timeout(kLimousineAddressLookupTimeout);
    } catch (_) {
      return null;
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
