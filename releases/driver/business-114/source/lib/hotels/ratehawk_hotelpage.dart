import 'package:fluxidi_tracking/app_config.dart';

import 'hotel_model.dart';
import 'ratehawk_search.dart';
import 'ratehawk_view_stay.dart';

export 'ratehawk_view_stay.dart';

enum RatehawkHotelpageLifecycleState {
  idle,
  checkingRooms,
  verifyingPricesAndTaxes,
  checkingCancellationAndConditions,
  ready,
  retryable,
  unavailable,
}

class RatehawkMoneyLine {
  const RatehawkMoneyLine({this.name, this.amount, this.payableWhere});

  final String? name;
  final String? amount;
  final String? payableWhere;
}

class RatehawkPaymentDisclosure {
  const RatehawkPaymentDisclosure({
    this.type,
    this.recipient,
    this.timing,
    this.customerPays,
  });

  final String? type;
  final String? recipient;
  final String? timing;
  final String? customerPays;

  bool get isForbiddenDepositType => type?.trim().toLowerCase() == 'deposit';
}

class RatehawkHotelDepositDisclosure {
  const RatehawkHotelDepositDisclosure({
    this.disclosed = false,
    this.amount,
    this.currency,
    this.refundable = false,
    this.recipient,
    this.timing,
  });

  final bool disclosed;
  final String? amount;
  final String? currency;
  final bool refundable;
  final String? recipient;
  final String? timing;
}

class RatehawkCancellationDisclosure {
  const RatehawkCancellationDisclosure({
    this.refundable = false,
    this.freeCancellationBefore,
    this.penalties = const <RatehawkMoneyLine>[],
  });

  final bool refundable;
  final String? freeCancellationBefore;
  final List<RatehawkMoneyLine> penalties;
}

class RatehawkNoShowDisclosure {
  const RatehawkNoShowDisclosure({
    this.disclosed = false,
    this.amount,
    this.currency,
    this.fromTime,
    this.timezoneContext,
    this.includedInRoomTotal = false,
    this.converted = false,
  });

  final bool disclosed;
  final String? amount;
  final String? currency;
  final String? fromTime;
  final String? timezoneContext;
  final bool includedInRoomTotal;
  final bool converted;
}

class RatehawkHotelpageOffer {
  const RatehawkHotelpageOffer({
    required this.offerRef,
    this.roomName,
    this.roomDescription,
    this.occupancy,
    this.beds,
    this.mealPlan,
    this.breakfastIncluded = false,
    this.adults,
    this.childAges = const <int>[],
    this.remainingAvailability,
    this.customerTotal,
    this.customerTotalLabel,
    this.currency,
    this.includedTaxes = const <RatehawkMoneyLine>[],
    this.excludedTaxes = const <RatehawkMoneyLine>[],
    this.vatIncluded,
    this.payment,
    this.cardDataRequired = false,
    this.cvcRequired = false,
    this.deposit = const RatehawkHotelDepositDisclosure(),
    this.cancellation = const RatehawkCancellationDisclosure(),
    this.noShow = const RatehawkNoShowDisclosure(),
    this.retrievedAt,
    this.expiresAt,
    this.bookable = false,
    this.mustPrebookBeforeConfirmation = true,
  });

  final String offerRef;
  final String? roomName;
  final String? roomDescription;
  final String? occupancy;
  final String? beds;
  final String? mealPlan;
  final bool breakfastIncluded;
  final int? adults;
  final List<int> childAges;
  final String? remainingAvailability;
  final String? customerTotal;
  final String? customerTotalLabel;
  final String? currency;
  final List<RatehawkMoneyLine> includedTaxes;
  final List<RatehawkMoneyLine> excludedTaxes;
  final bool? vatIncluded;
  final RatehawkPaymentDisclosure? payment;
  final bool cardDataRequired;
  final bool cvcRequired;
  final RatehawkHotelDepositDisclosure deposit;
  final RatehawkCancellationDisclosure cancellation;
  final RatehawkNoShowDisclosure noShow;
  final DateTime? retrievedAt;
  final DateTime? expiresAt;
  final bool bookable;
  final bool mustPrebookBeforeConfirmation;

  bool isExpired([DateTime? now]) {
    if (expiresAt == null) return !bookable;
    return !expiresAt!.isAfter(now ?? DateTime.now());
  }

  bool get isSelectable =>
      bookable && isRatehawkOfferRef(offerRef) && !isExpired();
}

class RatehawkSelectedOffer {
  const RatehawkSelectedOffer({
    required this.offerRef,
    required this.roomName,
    required this.customerTotalLabel,
  });

  final String offerRef;
  final String? roomName;
  final String? customerTotalLabel;
}

class RatehawkStaticPolicies {
  const RatehawkStaticPolicies({
    this.ok = true,
    this.unmappedCriticalFieldNames = const <String>[],
    this.amenities = const <String>[],
    this.pets = const <String>[],
    this.children = const <String>[],
    this.cots = const <String>[],
    this.extraBeds = const <String>[],
    this.accessibility = const <String>[],
    this.parking = const <String>[],
    this.internet = const <String>[],
    this.checkIn,
    this.checkOut,
    this.earlyLateCheckIn = const <String>[],
    this.importantInformation,
    this.policyStruct = const <String>[],
  });

  final bool ok;
  final List<String> unmappedCriticalFieldNames;
  final List<String> amenities;
  final List<String> pets;
  final List<String> children;
  final List<String> cots;
  final List<String> extraBeds;
  final List<String> accessibility;
  final List<String> parking;
  final List<String> internet;
  final String? checkIn;
  final String? checkOut;
  final List<String> earlyLateCheckIn;
  final String? importantInformation;
  final List<String> policyStruct;

  bool get hasUnmappedCritical => unmappedCriticalFieldNames.isNotEmpty || !ok;
}

class RatehawkHotelpageResponse {
  const RatehawkHotelpageResponse({
    this.ok = false,
    this.offers = const <RatehawkHotelpageOffer>[],
    this.policies,
    this.reason,
    this.retrievedAt,
    this.retryable = false,
    this.malformed = false,
    this.timedOut = false,
  });

  final bool ok;
  final List<RatehawkHotelpageOffer> offers;
  final RatehawkStaticPolicies? policies;
  final String? reason;
  final DateTime? retrievedAt;
  final bool retryable;
  final bool malformed;
  final bool timedOut;
}

abstract class RatehawkHotelpageClient {
  Future<RatehawkHotelpageResponse> load(RatehawkViewStaySnapshot snapshot);
}

class BookingRatehawkHotelpageClient implements RatehawkHotelpageClient {
  const BookingRatehawkHotelpageClient();

  @override
  Future<RatehawkHotelpageResponse> load(
    RatehawkViewStaySnapshot snapshot,
  ) async {
    try {
      final payload = await fetchPublicRatehawkHotelpage(
        hid: snapshot.hid,
        viewStayContext: snapshot.contextToken,
        checkin: snapshot.checkin,
        checkout: snapshot.checkout,
        residency: snapshot.residency,
        currency: snapshot.currency,
        guests: snapshot.guests.map((room) => room.toJson()).toList(),
      );
      if (payload == null) {
        return const RatehawkHotelpageResponse(
          timedOut: true,
          retryable: true,
          reason: 'backend_unavailable',
        );
      }
      return parseRatehawkHotelpagePayload(payload);
    } catch (_) {
      return const RatehawkHotelpageResponse(
        malformed: true,
        retryable: true,
        reason: 'backend_error',
      );
    }
  }
}

class RecordingRatehawkHotelpageClient implements RatehawkHotelpageClient {
  RecordingRatehawkHotelpageClient({this.response});

  RatehawkHotelpageResponse? response;
  final List<RatehawkViewStaySnapshot> calls = <RatehawkViewStaySnapshot>[];

  @override
  Future<RatehawkHotelpageResponse> load(
    RatehawkViewStaySnapshot snapshot,
  ) async {
    calls.add(snapshot);
    return response ??
        const RatehawkHotelpageResponse(
          ok: false,
          retryable: true,
          reason: 'ratehawk_hotelpage_disabled',
        );
  }
}

class RatehawkHotelpageController {
  RatehawkHotelpageController({
    RatehawkHotelpageClient? client,
    this.reduceMotion = false,
  }) : client = client ?? const BookingRatehawkHotelpageClient();

  final RatehawkHotelpageClient client;
  final bool reduceMotion;

  RatehawkHotelpageLifecycleState state = RatehawkHotelpageLifecycleState.idle;
  List<RatehawkHotelpageOffer> offers = const <RatehawkHotelpageOffer>[];
  RatehawkStaticPolicies? policies;
  RatehawkSelectedOffer? selected;
  DateTime? retrievedAt;
  String? reason;
  int requestCount = 0;
  final Set<String> staleOfferRefs = <String>{};
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

  Future<void> loadForStay(HotelStay stay, {DateTime? now}) async {
    final snapshot = ratehawkViewStayForRequest(stay, now: now);
    if (snapshot == null) {
      state = RatehawkHotelpageLifecycleState.unavailable;
      reason = stay.viewStay == null
          ? 'view_stay_context_required'
          : 'view_stay_context_invalid';
      offers = const <RatehawkHotelpageOffer>[];
      selected = null;
      retrievedAt = null;
      _notify();
      return;
    }
    final generation = ++_generation;
    requestCount += 1;
    state = RatehawkHotelpageLifecycleState.checkingRooms;
    reason = null;
    selected = null;
    staleOfferRefs.clear();
    _notify();
    final response = await client.load(snapshot);
    if (generation != _generation) return;
    _applyResponse(response);
  }

  void retry(HotelStay stay) {
    loadForStay(stay);
  }

  void selectOffer(RatehawkHotelpageOffer offer) {
    if (!isOfferSelectable(offer)) return;
    selected = RatehawkSelectedOffer(
      offerRef: offer.offerRef,
      roomName: offer.roomName,
      customerTotalLabel: offer.customerTotalLabel ?? offer.customerTotal,
    );
    _notify();
  }

  bool isOfferSelectable(RatehawkHotelpageOffer offer) {
    return offer.isSelectable && !staleOfferRefs.contains(offer.offerRef);
  }

  void clearSelected() {
    selected = null;
    _notify();
  }

  void markSelectedStale() {
    final ref = selected?.offerRef;
    if (ref != null) staleOfferRefs.add(ref);
    _notify();
  }

  void _applyResponse(RatehawkHotelpageResponse response) {
    if (response.timedOut || response.malformed) {
      state = RatehawkHotelpageLifecycleState.retryable;
      reason = response.reason ?? 'backend_error';
      offers = const <RatehawkHotelpageOffer>[];
      policies = null;
      retrievedAt = null;
      _notify();
      return;
    }
    state = RatehawkHotelpageLifecycleState.verifyingPricesAndTaxes;
    _notify();
    state = RatehawkHotelpageLifecycleState.checkingCancellationAndConditions;
    _notify();
    if (response.ok != true) {
      state = response.retryable
          ? RatehawkHotelpageLifecycleState.retryable
          : RatehawkHotelpageLifecycleState.unavailable;
      reason = response.reason ?? 'ratehawk_hotelpage_unavailable';
      offers = const <RatehawkHotelpageOffer>[];
      policies = response.policies;
      retrievedAt = null;
      _notify();
      return;
    }
    offers = response.offers;
    policies = response.policies;
    retrievedAt = response.retrievedAt ?? DateTime.now();
    state = RatehawkHotelpageLifecycleState.ready;
    reason = null;
    _notify();
  }
}

bool canRequestRatehawkHotelpage(HotelStay stay, {DateTime? now}) {
  return ratehawkViewStayForRequest(stay, now: now) != null;
}

RatehawkViewStaySnapshot? ratehawkViewStayForRequest(
  HotelStay stay, {
  DateTime? now,
}) {
  if (!isRatehawkStay(stay)) return null;
  final hid = parseRatehawkHid(stay);
  final snapshot = stay.viewStay;
  if (hid == null || hid <= 0 || snapshot == null) return null;
  if (snapshot.hid != hid) return null;
  if (!snapshot.hasServerContextPrefix || !snapshot.hasCompleteClaims) {
    return null;
  }
  if (snapshot.isExpired(now)) return null;
  return snapshot;
}

const Set<String> kRatehawkHotelpageForbiddenKeys = <String>{
  'book_hash',
  'match_hash',
  'reconciliation_amount',
  'commission',
  'commission_info',
  'commission_percent',
  'affiliate_percent',
  'authorization',
  'RATEHAWK_API_KEY',
  'RATEHAWK_KEY_ID',
};

bool ratehawkPayloadContainsForbiddenClientFields(dynamic raw) {
  if (raw is Map) {
    for (final key in raw.keys) {
      final name = key.toString();
      if (kRatehawkHotelpageForbiddenKeys.contains(name)) return true;
      if (ratehawkPayloadContainsForbiddenClientFields(raw[key])) return true;
    }
  } else if (raw is List) {
    for (final item in raw) {
      if (ratehawkPayloadContainsForbiddenClientFields(item)) return true;
    }
  }
  return false;
}

RatehawkHotelpageResponse parseRatehawkHotelpagePayload(
  Map<String, dynamic> payload,
) {
  if (ratehawkPayloadContainsForbiddenClientFields(payload)) {
    return const RatehawkHotelpageResponse(
      malformed: true,
      reason: 'forbidden_provider_fields',
    );
  }
  final ratehawk = payload['ratehawk'] is Map
      ? Map<String, dynamic>.from(payload['ratehawk'] as Map)
      : payload;
  final reason = (payload['reason'] ?? ratehawk['reason'])?.toString();
  final retryable =
      payload['retryable'] == true || ratehawk['retryable'] == true;
  if (payload['ok'] != true && ratehawk['ok'] != true) {
    return RatehawkHotelpageResponse(
      ok: false,
      reason: reason ?? 'ratehawk_hotelpage_unavailable',
      retryable: retryable || reason == 'rate_limited',
      policies: parseRatehawkStaticPolicies(payload['static_policies']),
    );
  }

  final rawOffers = ratehawk['offers'] ?? payload['offers'];
  final offers = <RatehawkHotelpageOffer>[];
  if (rawOffers is List) {
    for (final item in rawOffers) {
      if (item is! Map) continue;
      final offer = parseRatehawkHotelpageOffer(
        Map<String, dynamic>.from(item),
      );
      if (offer != null) offers.add(offer);
    }
  }

  DateTime? retrievedAt;
  final retrievedRaw = payload['retrieved_at'] ?? ratehawk['retrieved_at'];
  if (retrievedRaw is num && retrievedRaw.isFinite) {
    retrievedAt = DateTime.fromMillisecondsSinceEpoch(retrievedRaw.round());
  } else if (retrievedRaw is String) {
    retrievedAt = DateTime.tryParse(retrievedRaw.trim());
  }

  return RatehawkHotelpageResponse(
    ok: true,
    offers: offers,
    policies: parseRatehawkStaticPolicies(payload['static_policies']),
    reason: reason,
    retrievedAt: retrievedAt,
  );
}

RatehawkHotelpageOffer? parseRatehawkHotelpageOffer(Map<String, dynamic> json) {
  if (ratehawkPayloadContainsForbiddenClientFields(json)) return null;
  final payment = _payment(json['payment']);
  if (payment != null && payment.isForbiddenDepositType) return null;
  final offerRef = (json['offer_ref'] ?? json['offerRef'] ?? '')
      .toString()
      .trim();
  if (!isRatehawkOfferRef(offerRef)) return null;

  final occupancy = json['occupancy'];
  int? adults;
  var childAges = const <int>[];
  if (occupancy is Map) {
    adults = int.tryParse('${occupancy['adults'] ?? ''}');
    childAges = parseRatehawkGuestRooms(<dynamic>[occupancy]).isEmpty
        ? const <int>[]
        : parseRatehawkGuestRooms(<dynamic>[occupancy]).first.children;
  }

  return RatehawkHotelpageOffer(
    offerRef: offerRef,
    roomName: _text(json['room_name'] ?? json['roomName']),
    roomDescription: _text(json['room_description'] ?? json['roomDescription']),
    occupancy: occupancy is String
        ? occupancy
        : occupancy is Map
        ? _text(occupancy['label'])
        : null,
    beds: _text(json['beds'] ?? json['bed_information']),
    mealPlan: _text(json['meal_plan'] ?? json['mealPlan']),
    breakfastIncluded: json['breakfast_included'] == true,
    adults: adults,
    childAges: childAges,
    remainingAvailability: _text(
      json['remaining_availability'] ?? json['remainingAvailability'],
    ),
    customerTotal: _text(json['customer_total'] ?? json['customerTotal']),
    customerTotalLabel: _text(
      json['customer_total_label'] ?? json['customerTotalLabel'],
    ),
    currency: _text(json['currency']),
    includedTaxes: _moneyLines(json['included_taxes']),
    excludedTaxes: _moneyLines(json['excluded_taxes']),
    vatIncluded: json['vat'] is Map ? json['vat']['included'] == true : null,
    payment: payment,
    cardDataRequired: json['card_data_required'] == true,
    cvcRequired: json['cvc_required'] == true,
    deposit: _deposit(json['deposit']),
    cancellation: _cancellation(json['cancellation'], json),
    noShow: _noShow(json['no_show'] ?? json['noShow']),
    retrievedAt: _date(json['retrieved_at']),
    expiresAt: _date(json['expires_at']),
    bookable: json['bookable'] == true,
    mustPrebookBeforeConfirmation:
        json['must_prebook_before_confirmation'] != false,
  );
}

RatehawkStaticPolicies? parseRatehawkStaticPolicies(dynamic raw) {
  if (raw is! Map) return null;
  final json = Map<String, dynamic>.from(raw);
  return RatehawkStaticPolicies(
    ok: json['ok'] != false,
    unmappedCriticalFieldNames: _stringList(
      json['unmapped_critical_field_names'],
    ),
    amenities: _policyValues(json['amenities']),
    pets: _policyValues(json['pets']),
    children: _policyValues(json['children']),
    cots: _policyValues(json['cots']),
    extraBeds: _policyValues(json['extra_beds']),
    accessibility: _policyValues(json['accessibility']),
    parking: _policyValues(json['parking']),
    internet: _policyValues(json['internet']),
    checkIn: _text(json['check_in_time']),
    checkOut: _text(json['check_out_time']),
    earlyLateCheckIn: _policyValues(json['early_late_check_in']),
    importantInformation: _text(json['important_hotel_information']),
    policyStruct: _policyValues(
      json['important_policies'] ?? json['policy_struct'],
    ),
  );
}

RatehawkPaymentDisclosure? _payment(dynamic raw) {
  if (raw is! Map) return null;
  return RatehawkPaymentDisclosure(
    type: _text(raw['type'] ?? raw['payment_type']),
    recipient: _text(raw['recipient'] ?? raw['payment_recipient']),
    timing: _text(raw['timing'] ?? raw['payment_timing']),
    customerPays: _text(raw['customer_pays']),
  );
}

RatehawkHotelDepositDisclosure _deposit(dynamic raw) {
  if (raw is! Map) return const RatehawkHotelDepositDisclosure();
  return RatehawkHotelDepositDisclosure(
    disclosed: raw['disclosed'] == true,
    amount: _text(raw['amount']),
    currency: _text(raw['currency']),
    refundable: raw['refundable'] == true,
    recipient: _text(raw['payment_recipient'] ?? raw['recipient']),
    timing: _text(raw['payment_timing'] ?? raw['timing']),
  );
}

RatehawkCancellationDisclosure _cancellation(
  dynamic raw,
  Map<String, dynamic> offer,
) {
  final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  return RatehawkCancellationDisclosure(
    refundable: map['refundable'] == true || offer['refundable'] == true,
    freeCancellationBefore: _text(
      map['free_cancellation_before'] ?? offer['free_cancellation_before'],
    ),
    penalties: _moneyLines(map['penalties']),
  );
}

RatehawkNoShowDisclosure _noShow(dynamic raw) {
  if (raw is! Map) return const RatehawkNoShowDisclosure();
  return RatehawkNoShowDisclosure(
    disclosed: raw['disclosed'] == true,
    amount: _text(raw['amount']),
    currency: _text(raw['currency']),
    fromTime: _text(raw['from_time']),
    timezoneContext: _text(raw['timezone_context']),
    includedInRoomTotal: raw['included_in_room_total'] == true,
    converted: raw['converted'] == true,
  );
}

List<RatehawkMoneyLine> _moneyLines(dynamic raw) {
  if (raw is! List) return const <RatehawkMoneyLine>[];
  final lines = <RatehawkMoneyLine>[];
  for (final item in raw) {
    if (item is! Map) continue;
    lines.add(
      RatehawkMoneyLine(
        name: _text(item['name'] ?? item['start_at']),
        amount: _text(item['amount'] ?? item['show_amount']),
        payableWhere: _text(item['payable_where'] ?? item['end_at']),
      ),
    );
  }
  return lines;
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<String> _policyValues(dynamic raw) {
  if (raw == null) return const <String>[];
  if (raw is String) {
    final text = raw.trim();
    return text.isEmpty ? const <String>[] : <String>[text];
  }
  if (raw is! List) return const <String>[];
  final values = <String>[];
  for (final item in raw) {
    if (item is String) {
      final text = item.trim();
      if (text.isNotEmpty) values.add(text);
      continue;
    }
    if (item is Map) {
      final text = _text(
        item['name'] ??
            item['title'] ??
            item['text'] ??
            item['description'] ??
            item['amenity'],
      );
      if (text != null) values.add(text);
    }
  }
  return values;
}

String? _text(dynamic raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _date(dynamic raw) {
  if (raw is num && raw.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(raw.round());
  }
  if (raw is String) return DateTime.tryParse(raw.trim());
  return null;
}

String ratehawkHotelpageStateLabel(
  RatehawkHotelpageLifecycleState state,
  String languageCode,
) {
  switch (state) {
    case RatehawkHotelpageLifecycleState.idle:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Kamers nog niet opgevraagd',
        en: 'Rooms not requested yet',
        fr: 'Chambres pas encore demandées',
        es: 'Habitaciones aún no solicitadas',
      );
    case RatehawkHotelpageLifecycleState.checkingRooms:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Actuele kamers controleren',
        en: 'Checking current rooms',
        fr: 'Vérification des chambres actuelles',
        es: 'Comprobando habitaciones actuales',
      );
    case RatehawkHotelpageLifecycleState.verifyingPricesAndTaxes:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Prijzen en belastingen controleren',
        en: 'Verifying prices and taxes',
        fr: 'Vérification des prix et taxes',
        es: 'Verificando precios e impuestos',
      );
    case RatehawkHotelpageLifecycleState.checkingCancellationAndConditions:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Annulering en hotelvoorwaarden controleren',
        en: 'Checking cancellation and hotel conditions',
        fr: 'Vérification des conditions d’annulation et d’hôtel',
        es: 'Comprobando cancelación y condiciones del hotel',
      );
    case RatehawkHotelpageLifecycleState.ready:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Resultaten klaar',
        en: 'Results ready',
        fr: 'Résultats prêts',
        es: 'Resultados listos',
      );
    case RatehawkHotelpageLifecycleState.retryable:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Opnieuw proberen',
        en: 'Try again',
        fr: 'Réessayer',
        es: 'Reintentar',
      );
    case RatehawkHotelpageLifecycleState.unavailable:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Live kamers niet beschikbaar',
        en: 'Live rooms unavailable',
        fr: 'Chambres en direct indisponibles',
        es: 'Habitaciones en vivo no disponibles',
      );
  }
}

String ratehawkExpiredAvailabilityLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Beschikbaarheid controleren',
    en: 'Check availability',
    fr: 'Vérifier la disponibilité',
    es: 'Comprobar disponibilidad',
  );
}

String ratehawkHotelpageSectionTitle(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Kamers en actuele prijzen',
    en: 'Rooms and current prices',
    fr: 'Chambres et prix actuels',
    es: 'Habitaciones y precios actuales',
  );
}

String ratehawkPrebookRecheckLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Prijs en voorwaarden worden vóór de definitieve bevestiging opnieuw gecontroleerd.',
    en: 'Price and conditions will be checked again before final confirmation.',
    fr: 'Le prix et les conditions seront revérifiés avant la confirmation finale.',
    es: 'El precio y las condiciones se comprobarán de nuevo antes de la confirmación final.',
  );
}

String ratehawkSelectOfferLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Deze kamer kiezen',
    en: 'Select this room',
    fr: 'Choisir cette chambre',
    es: 'Elegir esta habitación',
  );
}

String ratehawkRetryLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Opnieuw',
    en: 'Retry',
    fr: 'Réessayer',
    es: 'Reintentar',
  );
}

String ratehawkUnmappedPolicyLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Onbekende boekingskritische inhoud — niet stilzwijgend weggelaten',
    en: 'Unknown booking-critical content — not silently discarded',
    fr: 'Contenu critique de réservation inconnu — non écarté silencieusement',
    es: 'Contenido crítico de reserva desconocido — no se omitió en silencio',
  );
}
