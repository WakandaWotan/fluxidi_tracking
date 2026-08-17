import 'dart:math' as math;

import 'package:fluxidi_tracking/app_config.dart';

import 'hotel_data_source.dart';
import 'hotel_model.dart';
import 'ratehawk_view_stay.dart';

const int kRatehawkInitialHotelLimit = 20;
const int kRatehawkLoadMoreIncrement = 20;
const int kRatehawkAbsoluteMaximum = 100;
const double kRatehawkGeoMatchMaxMeters = 75;
const String kRatehawkStalePriceLabelNl = 'Beschikbaarheid controleren';

enum RatehawkSearchLifecycleState {
  idle,
  searchingDestination,
  checkingRoomsAndPrices,
  verifyingTaxesAndConditions,
  insertingResults,
  fresh,
  retryable,
  unavailable,
}

class RatehawkSearchCriteria {
  const RatehawkSearchCriteria({
    this.destination = '',
    this.country,
    this.city,
    this.checkin,
    this.checkout,
    this.rooms = 1,
    this.adults = 2,
    this.childAges = const <int>[],
  });

  final String destination;
  final String? country;
  final String? city;
  final DateTime? checkin;
  final DateTime? checkout;
  final int rooms;
  final int adults;
  final List<int> childAges;

  String get checkinYmd => _ymd(checkin);
  String get checkoutYmd => _ymd(checkout);

  RatehawkSearchCriteria copyWith({
    String? destination,
    String? country,
    String? city,
    DateTime? checkin,
    DateTime? checkout,
    int? rooms,
    int? adults,
    List<int>? childAges,
    bool clearCheckin = false,
    bool clearCheckout = false,
  }) {
    return RatehawkSearchCriteria(
      destination: destination ?? this.destination,
      country: country ?? this.country,
      city: city ?? this.city,
      checkin: clearCheckin ? null : (checkin ?? this.checkin),
      checkout: clearCheckout ? null : (checkout ?? this.checkout),
      rooms: rooms ?? this.rooms,
      adults: adults ?? this.adults,
      childAges: childAges ?? this.childAges,
    );
  }
}

class RatehawkSearchCompleteness {
  const RatehawkSearchCompleteness({
    required this.complete,
    required this.hasDestination,
    required this.hasDates,
    required this.hasGuests,
  });

  final bool complete;
  final bool hasDestination;
  final bool hasDates;
  final bool hasGuests;
}

class RatehawkSearchResponse {
  const RatehawkSearchResponse({
    required this.ok,
    this.stays = const <HotelStay>[],
    this.warnings = const <String>[],
    this.invocationAllowed = false,
    this.reason,
    this.retrievedAt,
    this.malformed = false,
    this.timedOut = false,
  });

  final bool ok;
  final List<HotelStay> stays;
  final List<String> warnings;
  final bool invocationAllowed;
  final String? reason;
  final DateTime? retrievedAt;
  final bool malformed;
  final bool timedOut;
}

abstract class RatehawkHotelSearchClient {
  Future<RatehawkSearchResponse> search(RatehawkSearchCriteria criteria);
}

class BookingRatehawkHotelSearchClient implements RatehawkHotelSearchClient {
  const BookingRatehawkHotelSearchClient();

  @override
  Future<RatehawkSearchResponse> search(RatehawkSearchCriteria criteria) async {
    final resolved = resolveRatehawkSearchDestination(criteria);
    try {
      final payload = await fetchPublicHotelSearch(
        source: 'ratehawk',
        city: resolved.city,
        country: resolved.country,
        checkin: criteria.checkinYmd.isEmpty ? null : criteria.checkinYmd,
        checkout: criteria.checkoutYmd.isEmpty ? null : criteria.checkoutYmd,
        rooms: criteria.rooms,
        adults: criteria.adults,
        childAges: criteria.childAges,
      );
      if (payload == null) {
        return const RatehawkSearchResponse(
          ok: false,
          timedOut: true,
          reason: 'backend_unavailable',
        );
      }
      return parseRatehawkPublicSearchPayload(payload);
    } catch (_) {
      return const RatehawkSearchResponse(
        ok: false,
        malformed: true,
        reason: 'backend_error',
      );
    }
  }
}

class RecordingRatehawkHotelSearchClient implements RatehawkHotelSearchClient {
  RecordingRatehawkHotelSearchClient({this.response});

  RatehawkSearchResponse? response;
  final List<RatehawkSearchCriteria> calls = <RatehawkSearchCriteria>[];

  @override
  Future<RatehawkSearchResponse> search(RatehawkSearchCriteria criteria) async {
    calls.add(criteria);
    return response ??
        const RatehawkSearchResponse(
          ok: true,
          invocationAllowed: false,
          reason: 'ratehawk_search_disabled',
          warnings: <String>['ratehawk_invocation_blocked'],
        );
  }
}

class RatehawkSearchController {
  RatehawkSearchController({
    RatehawkHotelSearchClient? client,
    this.reduceMotion = false,
  }) : client = client ?? const BookingRatehawkHotelSearchClient();

  final RatehawkHotelSearchClient client;
  final bool reduceMotion;

  RatehawkSearchCriteria criteria = const RatehawkSearchCriteria();
  RatehawkSearchLifecycleState state = RatehawkSearchLifecycleState.idle;
  List<HotelStay> insertedStays = const <HotelStay>[];
  DateTime? retrievedAt;
  String? reason;
  int requestCount = 0;
  int _generation = 0;
  final List<void Function()> _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void dispose() => _listeners.clear();

  void _notify() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }

  void setCriteria(RatehawkSearchCriteria next) {
    criteria = next;
    _notify();
  }

  void setDestinationHint({String? city, String? country, bool notify = true}) {
    criteria = criteria.copyWith(city: city, country: country);
    if (notify) _notify();
  }

  void cancelEdit() {
    _generation += 1;
    state = RatehawkSearchLifecycleState.idle;
    reason = null;
    _notify();
  }

  RatehawkSearchCompleteness completeness() {
    return evaluateRatehawkSearchCompleteness(criteria);
  }

  Future<void> submit() async {
    final check = completeness();
    if (!check.hasDestination) {
      state = RatehawkSearchLifecycleState.searchingDestination;
      reason = 'destination_incomplete';
      _notify();
      return;
    }
    if (!check.complete) {
      return;
    }
    final generation = ++_generation;
    requestCount += 1;
    state = RatehawkSearchLifecycleState.checkingRoomsAndPrices;
    reason = null;
    _notify();
    final response = await client.search(criteria);
    if (generation != _generation) return;
    _applyResponse(response);
  }

  void _applyResponse(RatehawkSearchResponse response) {
    if (response.timedOut || response.malformed || response.ok != true) {
      state = RatehawkSearchLifecycleState.retryable;
      reason = response.reason ?? 'backend_error';
      insertedStays = const <HotelStay>[];
      retrievedAt = null;
      _notify();
      return;
    }
    if (response.warnings.contains('ratehawk_invocation_blocked') ||
        response.invocationAllowed != true) {
      state = RatehawkSearchLifecycleState.unavailable;
      reason = response.reason ?? 'ratehawk_search_disabled';
      insertedStays = const <HotelStay>[];
      retrievedAt = null;
      _notify();
      return;
    }
    state = RatehawkSearchLifecycleState.verifyingTaxesAndConditions;
    _notify();
    final limited = applyRatehawkSearchLimits(response.stays);
    state = RatehawkSearchLifecycleState.insertingResults;
    insertedStays = limited;
    retrievedAt = response.retrievedAt ?? DateTime.now();
    state = RatehawkSearchLifecycleState.fresh;
    reason = null;
    _notify();
  }
}

class RatehawkResolvedDestination {
  const RatehawkResolvedDestination({this.city, this.country});
  final String? city;
  final String? country;
}

RatehawkResolvedDestination resolveRatehawkSearchDestination(
  RatehawkSearchCriteria criteria,
) {
  var city = (criteria.city ?? '').trim();
  var country = (criteria.country ?? '').trim();
  final destination = criteria.destination.trim();
  if (destination.contains(',')) {
    final parts = destination
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isNotEmpty && city.isEmpty) city = parts.first;
    if (parts.length > 1 && country.isEmpty) country = parts[1];
  } else if (city.isEmpty && destination.isNotEmpty) {
    city = destination;
  }
  return RatehawkResolvedDestination(
    city: city.isEmpty ? null : city,
    country: country.isEmpty ? null : country,
  );
}

RatehawkSearchCompleteness evaluateRatehawkSearchCompleteness(
  RatehawkSearchCriteria criteria,
) {
  final resolved = resolveRatehawkSearchDestination(criteria);
  final hasDestination =
      (resolved.city ?? '').isNotEmpty && (resolved.country ?? '').isNotEmpty;
  final hasDates =
      criteria.checkin != null &&
      criteria.checkout != null &&
      criteria.checkout!.isAfter(criteria.checkin!);
  final guestsOk =
      criteria.rooms >= 1 &&
      criteria.adults >= 1 &&
      criteria.childAges.every((age) => age >= 0);
  return RatehawkSearchCompleteness(
    complete: hasDestination && hasDates && guestsOk,
    hasDestination: hasDestination,
    hasDates: hasDates,
    hasGuests: guestsOk,
  );
}

int? parseRatehawkHid(HotelStay stay) {
  if (stay.hid != null && stay.hid! > 0) return stay.hid;
  final candidates = <String?>[
    stay.externalProviderReference,
    stay.externalProviderId,
    stay.sourceId,
    stay.id.startsWith('ratehawk:')
        ? stay.id.substring('ratehawk:'.length)
        : null,
  ];
  for (final candidate in candidates) {
    final parsed = int.tryParse((candidate ?? '').trim());
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

bool isRatehawkStay(HotelStay stay) {
  return isRatehawkCatalogValue(stay.provider) ||
      isRatehawkCatalogValue(stay.source) ||
      stay.id.startsWith('ratehawk:') ||
      stay.hid != null;
}

String normalizeRatehawkAddress(String? value) {
  return (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[.,/#-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

double haversineMeters(double aLat, double aLng, double bLat, double bLng) {
  const earth = 6371000.0;
  final dLat = _toRad(bLat - aLat);
  final dLng = _toRad(bLng - aLng);
  final sinLat = math.sin(dLat / 2);
  final sinLng = math.sin(dLng / 2);
  final h =
      sinLat * sinLat +
      math.cos(_toRad(aLat)) * math.cos(_toRad(bLat)) * sinLng * sinLng;
  return 2 * earth * math.asin(math.sqrt(h.clamp(0, 1)));
}

double _toRad(double deg) => deg * math.pi / 180;

class RatehawkHotelMatch {
  const RatehawkHotelMatch({
    required this.matched,
    required this.method,
    this.existingIndex,
  });

  final bool matched;
  final String method;
  final int? existingIndex;
}

RatehawkHotelMatch resolveRatehawkHotelStayMatch({
  required HotelStay incoming,
  required List<HotelStay> existing,
}) {
  final incomingHid = parseRatehawkHid(incoming);
  if (incomingHid != null) {
    for (var i = 0; i < existing.length; i++) {
      final existingHid = parseRatehawkHid(existing[i]);
      if (existingHid != null && existingHid == incomingHid) {
        return RatehawkHotelMatch(
          matched: true,
          method: 'hid',
          existingIndex: i,
        );
      }
    }
  }

  final incomingAddress = normalizeRatehawkAddress(incoming.address);
  for (var i = 0; i < existing.length; i++) {
    final current = existing[i];
    final addressEqual =
        incomingAddress.isNotEmpty &&
        incomingAddress == normalizeRatehawkAddress(current.address);
    final meters = haversineMeters(
      incoming.lat,
      incoming.lng,
      current.lat,
      current.lng,
    );
    if (addressEqual && meters <= kRatehawkGeoMatchMaxMeters) {
      return RatehawkHotelMatch(
        matched: true,
        method: 'address_geo',
        existingIndex: i,
      );
    }
  }

  final incomingName = incoming.name.trim().toLowerCase();
  if (incomingName.isNotEmpty &&
      existing.any((stay) => stay.name.trim().toLowerCase() == incomingName)) {
    return const RatehawkHotelMatch(
      matched: false,
      method: 'name_only_rejected',
    );
  }
  return const RatehawkHotelMatch(matched: false, method: 'unmatched');
}

List<HotelStay> dedupeRatehawkStaysByHid(List<HotelStay> incoming) {
  final seen = <int>{};
  final out = <HotelStay>[];
  for (final stay in incoming) {
    final hid = parseRatehawkHid(stay);
    if (hid == null) {
      out.add(stay);
      continue;
    }
    if (!seen.add(hid)) continue;
    out.add(stay);
  }
  return out;
}

List<HotelStay> applyRatehawkSearchLimits(
  List<HotelStay> incoming, {
  int initialLimit = kRatehawkInitialHotelLimit,
  int absoluteMaximum = kRatehawkAbsoluteMaximum,
}) {
  final deduped = dedupeRatehawkStaysByHid(incoming);
  final limit = initialLimit < absoluteMaximum ? initialLimit : absoluteMaximum;
  if (deduped.length <= limit) return List<HotelStay>.from(deduped);
  return deduped.take(limit).toList(growable: false);
}

List<HotelStay> mergeRatehawkHotelStays({
  required List<HotelStay> existing,
  required List<HotelStay> incoming,
  int initialLimit = kRatehawkInitialHotelLimit,
}) {
  final merged = List<HotelStay>.from(existing);
  final limited = applyRatehawkSearchLimits(
    incoming,
    initialLimit: initialLimit,
  );
  for (final stay in limited) {
    final match = resolveRatehawkHotelStayMatch(
      incoming: stay,
      existing: merged,
    );
    if (match.matched && match.existingIndex != null) {
      merged[match.existingIndex!] = overlayRatehawkLiveFields(
        merged[match.existingIndex!],
        stay,
      );
      continue;
    }
    final hid = parseRatehawkHid(stay);
    final fallbackId = hid == null ? stay.id : 'ratehawk:$hid';
    merged.add(stay.copyWith(id: fallbackId, hid: hid));
  }
  return merged;
}

List<HotelStay> attachEnvelopeViewStay({
  required List<HotelStay> stays,
  required Map<String, dynamic> payload,
}) {
  final envelope = parseRatehawkViewStaySnapshot(payload);
  if (envelope == null) return stays;
  return stays
      .map((stay) {
        final hid = parseRatehawkHid(stay);
        if (hid == null || hid != envelope.hid) return stay;
        return stay.copyWith(hid: hid, viewStay: envelope);
      })
      .toList(growable: false);
}

HotelStay overlayRatehawkLiveFields(HotelStay existing, HotelStay incoming) {
  final stale = isRatehawkStalePrice(incoming);
  return existing.copyWith(
    hid: incoming.hid ?? existing.hid,
    viewStay: incoming.viewStay ?? existing.viewStay,
    priceHint: stale ? kRatehawkStalePriceLabelNl : incoming.priceHint,
    availabilityLabel: stale
        ? kRatehawkStalePriceLabelNl
        : incoming.availabilityLabel,
    retrievedAt: incoming.retrievedAt,
    clearPriceHint: incoming.priceHint == null && !stale,
    clearAvailabilityLabel: incoming.availabilityLabel == null && !stale,
  );
}

bool isRatehawkStalePrice(HotelStay stay) {
  final price = (stay.priceHint ?? '').trim();
  final availability = (stay.availabilityLabel ?? '').trim();
  if (price == kRatehawkStalePriceLabelNl ||
      availability == kRatehawkStalePriceLabelNl) {
    return true;
  }
  return isRatehawkStay(stay) && price.isEmpty;
}

String ratehawkStalePriceLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: kRatehawkStalePriceLabelNl,
    en: 'Checking availability',
    fr: 'Vérification des disponibilités',
    es: 'Comprobando disponibilidad',
  );
}

String displayRatehawkPriceHint(HotelStay stay, String languageCode) {
  if (isRatehawkStalePrice(stay)) {
    return ratehawkStalePriceLabel(languageCode);
  }
  return (stay.priceHint ?? '').trim();
}

RatehawkSearchResponse parseRatehawkPublicSearchPayload(
  Map<String, dynamic> payload,
) {
  if (payload['ok'] != true) {
    return RatehawkSearchResponse(
      ok: false,
      reason: payload['reason']?.toString(),
      malformed: true,
    );
  }
  final rawStays = payload['stays'];
  final stays = <HotelStay>[];
  if (rawStays is List) {
    for (final item in rawStays) {
      if (item is! Map) continue;
      final stay = hotelStayFromPublicHotelJson(
        Map<String, dynamic>.from(item),
      );
      if (stay != null) stays.add(stay);
    }
  }
  final warnings = <String>[];
  final rawWarnings = payload['warnings'];
  if (rawWarnings is List) {
    for (final warning in rawWarnings) {
      final text = warning.toString().trim();
      if (text.isNotEmpty) warnings.add(text);
    }
  }
  final ratehawk = payload['ratehawk'];
  final invocationAllowed = ratehawk is Map
      ? ratehawk['invocation_allowed'] == true
      : false;
  return RatehawkSearchResponse(
    ok: true,
    stays: attachEnvelopeViewStay(stays: stays, payload: payload),
    warnings: warnings,
    invocationAllowed: invocationAllowed,
    reason: payload['reason']?.toString(),
    retrievedAt: DateTime.tryParse('${payload['retrieved_at'] ?? ''}'),
  );
}

String ratehawkSearchLabel(
  String languageCode, {
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (languageCode) {
    case 'en':
      return en;
    case 'fr':
      return fr;
    case 'es':
      return es;
    case 'nl':
    default:
      return nl;
  }
}

String ratehawkStateLabel(
  RatehawkSearchLifecycleState state,
  String languageCode,
) {
  switch (state) {
    case RatehawkSearchLifecycleState.idle:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Kamers zoeken',
        en: 'Search rooms',
        fr: 'Rechercher des chambres',
        es: 'Buscar habitaciones',
      );
    case RatehawkSearchLifecycleState.searchingDestination:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Bestemming zoeken',
        en: 'Searching destination',
        fr: 'Recherche de destination',
        es: 'Buscando destino',
      );
    case RatehawkSearchLifecycleState.checkingRoomsAndPrices:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Kamers en actuele prijzen controleren',
        en: 'Checking rooms and current prices',
        fr: 'Vérification des chambres et des prix',
        es: 'Comprobando habitaciones y precios',
      );
    case RatehawkSearchLifecycleState.verifyingTaxesAndConditions:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Belastingen en voorwaarden controleren',
        en: 'Verifying taxes and conditions',
        fr: 'Vérification des taxes et conditions',
        es: 'Verificando impuestos y condiciones',
      );
    case RatehawkSearchLifecycleState.insertingResults:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Resultaten invoegen',
        en: 'Inserting results',
        fr: 'Insertion des résultats',
        es: 'Insertando resultados',
      );
    case RatehawkSearchLifecycleState.fresh:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Actuele beschikbaarheid',
        en: 'Current availability',
        fr: 'Disponibilité actuelle',
        es: 'Disponibilidad actual',
      );
    case RatehawkSearchLifecycleState.retryable:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Opnieuw proberen',
        en: 'Try again',
        fr: 'Réessayer',
        es: 'Reintentar',
      );
    case RatehawkSearchLifecycleState.unavailable:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Live beschikbaarheid niet beschikbaar',
        en: 'Live availability unavailable',
        fr: 'Disponibilité en direct indisponible',
        es: 'Disponibilidad en vivo no disponible',
      );
  }
}

String ratehawkNeutralAvailabilityLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Bekijk beschikbaarheid',
    en: 'Check availability',
    fr: 'Voir les disponibilités',
    es: 'Ver disponibilidad',
  );
}

String _ymd(DateTime? value) {
  if (value == null) return '';
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
