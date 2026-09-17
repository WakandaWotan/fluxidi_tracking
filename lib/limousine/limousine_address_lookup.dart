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
    this.postcode = '',
    this.locality = '',
  });

  final String label;
  final double? lat;
  final double? lon;
  final String? placeId;
  final String placeType;
  final String text;
  final String matchingText;
  final String postcode;
  final String locality;

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

final RegExp _belgianPostcode = RegExp(r'\b([1-9]\d{3})\b');
final RegExp _localityAfterPostcode = RegExp(
  r'\b[1-9]\d{3}\s+([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ''\-\s]+)',
);

String? limousineAddressQueryPostcode(String raw) {
  final match = _belgianPostcode.firstMatch(raw.trim());
  return match?.group(1);
}

String? limousineAddressQueryLocality(String raw) {
  final match = _localityAfterPostcode.firstMatch(raw.trim());
  if (match == null) return null;
  final locality = match
      .group(1)!
      .split(',')
      .first
      .trim()
      .replaceAll(RegExp(r'\b(BE|België|Belgie|Belgium)\b', caseSensitive: false), '')
      .trim();
  return locality.isEmpty ? null : locality;
}

String limousineSuggestionResolvedPostcode(LimousinePlaceSuggestion suggestion) {
  final stored = suggestion.postcode.trim();
  if (_belgianPostcode.hasMatch(stored)) {
    return limousineAddressQueryPostcode(stored) ?? stored;
  }
  return limousineAddressQueryPostcode(suggestion.label) ?? '';
}

String limousineSuggestionResolvedLocality(LimousinePlaceSuggestion suggestion) {
  final stored = suggestion.locality.trim();
  if (stored.isNotEmpty) return stored;
  return limousineAddressQueryLocality(suggestion.label) ?? '';
}

const Map<String, Set<String>> kBelgianLocalityEquivalents = {
  'schorisse': {'maarkedal'},
  'maarkedal': {'schorisse'},
};

bool limousineLocalityNamesCompatible(String left, String right) {
  final a = limousineFoldAddressToken(left);
  final b = limousineFoldAddressToken(right);
  if (a.isEmpty || b.isEmpty) return true;
  if (a == b || a.contains(b) || b.contains(a)) return true;
  final aliases = kBelgianLocalityEquivalents[a];
  return aliases != null && aliases.contains(b);
}

class LimousineStreetHouse {
  const LimousineStreetHouse({
    this.street = '',
    this.number = '',
    this.letter = '',
  });

  final String street;
  final String number;
  final String letter;

  bool get hasNumber => number.isNotEmpty;
  bool get hasLetter => letter.isNotEmpty;
}

LimousineStreetHouse limousineParseStreetHouse(String raw) {
  var text = raw.trim();
  final postcode = limousineAddressQueryPostcode(text);
  if (postcode != null) {
    final index = text.indexOf(postcode);
    if (index > 0) {
      text = text.substring(0, index);
    }
  }
  text = text.replaceAll(RegExp(r'[\s,]+$'), '').trim();
  final matches = RegExp(r'(\d+)\s*([A-Za-z])?\b').allMatches(text).toList();
  if (matches.isEmpty) {
    return LimousineStreetHouse(street: text);
  }
  final match = matches.last;
  final street = text
      .substring(0, match.start)
      .replaceAll(RegExp(r'[\s,.\-]+$'), '')
      .trim();
  return LimousineStreetHouse(
    street: street,
    number: match.group(1) ?? '',
    letter: (match.group(2) ?? '').toUpperCase(),
  );
}

bool limousineStreetNamesCompatible(String left, String right) {
  final a = limousineFoldAddressToken(left);
  final b = limousineFoldAddressToken(right);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  if (a.contains(b) || b.contains(a)) return true;
  final firstA = a.split(' ').first;
  final firstB = b.split(' ').first;
  return firstA.length >= 4 && firstA == firstB;
}

bool limousineSuggestionAgreesWithQuery(
  LimousinePlaceSuggestion suggestion,
  String query,
) {
  final queryPostcode = limousineAddressQueryPostcode(query);
  final suggestionPostcode = limousineSuggestionResolvedPostcode(suggestion);
  if (queryPostcode != null) {
    if (suggestionPostcode.isEmpty || suggestionPostcode != queryPostcode) {
      return false;
    }
  }
  final queryParts = limousineParseStreetHouse(query);
  final suggestionParts = limousineParseStreetHouse(
    [
      suggestion.label,
      suggestion.text,
    ].where((part) => part.trim().isNotEmpty).join(' '),
  );
  if (queryParts.street.isNotEmpty &&
      !limousineStreetNamesCompatible(queryParts.street, suggestionParts.street) &&
      !limousineStreetNamesCompatible(queryParts.street, suggestion.label)) {
    return false;
  }
  if (queryParts.hasNumber) {
    if (suggestionParts.number != queryParts.number) return false;
    if (queryParts.hasLetter && suggestionParts.letter != queryParts.letter) {
      return false;
    }
  }
  final queryLocality = limousineAddressQueryLocality(query);
  final suggestionLocality = limousineSuggestionResolvedLocality(suggestion);
  if (queryLocality != null &&
      suggestionLocality.isNotEmpty &&
      !limousineLocalityNamesCompatible(queryLocality, suggestionLocality) &&
      (queryPostcode == null ||
          suggestionPostcode.isEmpty ||
          suggestionPostcode != queryPostcode)) {
    return false;
  }
  if (queryPostcode == null && queryParts.street.isEmpty) {
    final queryLocality = limousineAddressQueryLocality(query);
    if (queryLocality != null) {
      return limousineLocalityNamesCompatible(
        queryLocality,
        limousineSuggestionResolvedLocality(suggestion),
      );
    }
  }
  return true;
}

bool limousineSuggestionIsHouseNearMiss(
  LimousinePlaceSuggestion suggestion,
  String query,
) {
  final queryPostcode = limousineAddressQueryPostcode(query);
  final suggestionPostcode = limousineSuggestionResolvedPostcode(suggestion);
  if (queryPostcode == null ||
      suggestionPostcode.isEmpty ||
      suggestionPostcode != queryPostcode) {
    return false;
  }
  final queryParts = limousineParseStreetHouse(query);
  final suggestionParts = limousineParseStreetHouse(suggestion.label);
  if (!queryParts.hasNumber ||
      !queryParts.hasLetter ||
      suggestionParts.number != queryParts.number ||
      suggestionParts.letter == queryParts.letter) {
    return false;
  }
  if (queryParts.street.isEmpty ||
      (!limousineStreetNamesCompatible(
            queryParts.street,
            suggestionParts.street,
          ) &&
          !limousineStreetNamesCompatible(queryParts.street, suggestion.label))) {
    return false;
  }
  return suggestion.hasCoordinates && suggestion.isStreetLevel;
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
  final leftPostcode = limousineAddressQueryPostcode(left);
  final rightPostcode = limousineAddressQueryPostcode(right);
  if (leftPostcode != null &&
      rightPostcode != null &&
      leftPostcode != rightPostcode) {
    return true;
  }
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
  final agreeing = [
    for (final item in street)
      if (limousineSuggestionAgreesWithQuery(item, query)) item,
  ];
  final streetPostcodes = {
    for (final item in street)
      if (limousineSuggestionResolvedPostcode(item).isNotEmpty)
        limousineSuggestionResolvedPostcode(item),
  };
  if (limousineAddressQueryPostcode(query) == null &&
      limousineParseStreetHouse(query).street.isNotEmpty &&
      streetPostcodes.length > 1) {
    final agreeingPostcodes = {
      for (final item in agreeing)
        if (limousineSuggestionResolvedPostcode(item).isNotEmpty)
          limousineSuggestionResolvedPostcode(item),
    };
    if (agreeingPostcodes.length != 1) return null;
  }
  final pool = agreeing.isNotEmpty ? agreeing : street;
  if (agreeing.isEmpty &&
      (limousineAddressQueryPostcode(query) != null ||
          limousineAddressQueryLocality(query) != null ||
          limousineParseStreetHouse(query).hasNumber)) {
    return null;
  }
  for (final item in pool) {
    if (needle.isNotEmpty &&
        item.label.toLowerCase().contains(needle.split(',').first.trim())) {
      return item;
    }
  }
  return pool.first;
}

class LimousineOwnedAddressResolution {
  const LimousineOwnedAddressResolution({
    required this.value,
    this.needsConfirm = false,
    this.candidate,
  });

  final LimousineAddressValue value;
  final bool needsConfirm;
  final LimousinePlaceSuggestion? candidate;

  bool get houseProven => value.hasCoordinates && !needsConfirm;
}

LimousineAddressValue limousineOwnedAddressValue(
  String text, {
  double? latitude,
  double? longitude,
  bool selected = true,
}) {
  final label = text.trim();
  if (label.isEmpty) return const LimousineAddressValue();
  final hasCoords = latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite;
  return LimousineAddressValue(
    displayText: label,
    canonicalLabel: label,
    lat: hasCoords ? latitude : null,
    lon: hasCoords ? longitude : null,
    acceptance: hasCoords
        ? LimousineAddressAcceptance.selected
        : (selected
            ? LimousineAddressAcceptance.incomplete
            : LimousineAddressAcceptance.manualFallback),
  );
}

LimousineOwnedAddressResolution limousineResolveOwnedAddress({
  required String query,
  required LimousinePlaceLookupResult result,
}) {
  final owned = query.trim();
  if (owned.isEmpty) {
    return const LimousineOwnedAddressResolution(
      value: LimousineAddressValue(),
    );
  }
  if (result.hadError) {
    return LimousineOwnedAddressResolution(
      value: limousineOwnedAddressValue(owned, selected: false),
      needsConfirm: true,
    );
  }
  final proven = limousinePreferStreetLevelSuggestion(owned, result.suggestions);
  if (proven != null &&
      proven.hasCoordinates &&
      limousineSuggestionAgreesWithQuery(proven, owned)) {
    return LimousineOwnedAddressResolution(
      value: limousineOwnedAddressValue(
        owned,
        latitude: proven.lat,
        longitude: proven.lon,
      ),
    );
  }
  final nearMiss = [
    for (final item in result.suggestions)
      if (limousineSuggestionIsHouseNearMiss(item, owned)) item,
  ];
  if (nearMiss.isNotEmpty) {
    return LimousineOwnedAddressResolution(
      value: limousineOwnedAddressValue(owned, selected: true),
      needsConfirm: true,
      candidate: nearMiss.first,
    );
  }
  return LimousineOwnedAddressResolution(
    value: limousineOwnedAddressValue(owned, selected: true),
    needsConfirm: true,
  );
}

/// UI language must not hide local toponyms such as Gent, Kortrijk or Ronse.
/// Place-name queries omit Mapbox `language=` so Dutch names stay findable
/// when the app itself is English.
String limousineMapboxForwardLanguage({
  required String query,
  required String uiLanguage,
}) {
  // Official street names stay as the provider returns them. The UI language
  // still localises place context (Belgium → België) when the app is Dutch.
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
  final queryPostcode = limousineAddressQueryPostcode(query);
  if (queryPostcode != null && !limousineSuggestionAgreesWithQuery(suggestion, query)) {
    return 20;
  }
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
  return queryPostcode != null ? 4 : 8;
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
    String postcode = '';
    String locality = '';
    final context = map['context'];
    if (context is List) {
      for (final item in context) {
        if (item is! Map) continue;
        final id = (item['id'] ?? '').toString();
        final contextText = (item['text'] ?? '').toString().trim();
        if (contextText.isEmpty) continue;
        if (id.startsWith('postcode.')) postcode = contextText;
        if (locality.isEmpty &&
            (id.startsWith('place.') || id.startsWith('locality.'))) {
          locality = contextText;
        }
      }
    }
    if (postcode.isEmpty) {
      final properties = map['properties'];
      if (properties is Map) {
        postcode = (properties['postcode'] ?? '').toString().trim();
      }
    }
    out.add(
      LimousinePlaceSuggestion(
        label: label,
        lat: lat,
        lon: lon,
        placeId: placeId.isEmpty ? null : placeId,
        placeType: placeType,
        text: text,
        matchingText: matchingText,
        postcode: postcode,
        locality: locality,
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
