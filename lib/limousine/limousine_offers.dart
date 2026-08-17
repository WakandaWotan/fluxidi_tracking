// LIMOUSINE-MARKETPLACE-P2B2 — company Limousine offers: pure model, validation
// and safe public projection. Mirrors
// workers/booking/modules/limousine_offers.mjs so the admin UI, the tests and
// the server agree on one contract.
//
// Offers are plain JSON maps (same pattern as the airport fixed-fare rules in
// Business settings). All money is integer minor units (cents).

import '../app_config.dart';
import '../app_strings.dart';

abstract final class LimousinePricePresentation {
  static const String exactFixed = 'exact_fixed';
  static const String fromPrice = 'from_price';
  static const String indicative = 'indicative';
  static const String quoteRequired = 'quote_required';
  static const String unavailable = 'unavailable';

  static const List<String> all = <String>[
    exactFixed,
    fromPrice,
    indicative,
    quoteRequired,
    unavailable,
  ];
}

abstract final class LimousineOfferTarget {
  static const String vehicle = 'vehicle';
  static const String serviceClass = 'service_class';

  static const List<String> all = <String>[vehicle, serviceClass];
}

abstract final class LimousineMobilisationMethod {
  static const String included = 'included';
  static const String fixedFee = 'fixed_fee';
  static const String distanceTime = 'distance_time';

  static const List<String> all = <String>[included, fixedFee, distanceTime];
}

abstract final class LimousineJourneyTypeId {
  static const String pointToPoint = 'point_to_point';
  static const String airportTransfer = 'airport_transfer';
  static const String hotelTransfer = 'hotel_transfer';
  static const String eventTransfer = 'event_transfer';
  static const String hourlyPackage = 'hourly_package';

  static const List<String> all = <String>[
    pointToPoint,
    airportTransfer,
    hotelTransfer,
    eventTransfer,
    hourlyPackage,
  ];
}

abstract final class LimousineOfferError {
  static const String missingOfferId = 'missing_offer_id';
  static const String unknownTarget = 'unknown_target';
  static const String unknownVehicle = 'unknown_vehicle';
  static const String inactiveVehicle = 'inactive_vehicle';
  static const String vehicleNotLimousine = 'vehicle_not_limousine';
  static const String unknownServiceClass = 'unknown_service_class';
  static const String missingCurrency = 'missing_currency';
  static const String currencyConflict = 'currency_conflict';
  static const String negativeAmount = 'negative_amount';
  static const String invalidPresentation = 'invalid_presentation';
  static const String missingDisplayAmount = 'missing_display_amount';
  static const String incompleteFixedRule = 'incomplete_fixed_rule';
  static const String duplicateRule = 'duplicate_rule';
  static const String hourlyMissingMinimumDuration =
      'hourly_missing_minimum_duration';
  static const String hourlyIncomplete = 'hourly_incomplete';
  static const String packageIncomplete = 'package_incomplete';
  static const String mobilisationIncomplete = 'mobilisation_incomplete';
  static const String mobilisationContradictory = 'mobilisation_contradictory';
  static const String publishedWithoutReadiness = 'published_without_readiness';
  static const String distanceTimeIncomplete = 'distance_time_incomplete';
}

String limousineOfferToken(Object? raw) => (raw ?? '')
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s-]+'), '_');

bool _boolOf(Object? raw, {bool fallback = false}) {
  if (raw is bool) return raw;
  final t = limousineOfferToken(raw);
  if (t == 'true' || t == '1' || t == 'yes' || t == 'on') return true;
  if (t == 'false' || t == '0' || t == 'no' || t == 'off') return false;
  return fallback;
}

/// Integer cents. Returns null when absent/invalid; negatives are preserved so
/// validation can reject them explicitly rather than silently clamping.
int? limousineCentsOf(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.truncate();
  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  return int.tryParse(text);
}

int? _intOf(Object? raw) => limousineCentsOf(raw);

String limousineCurrencyOf(Object? raw) {
  final c = (raw ?? '').toString().trim().toUpperCase();
  return RegExp(r'^[A-Z]{3}$').hasMatch(c) ? c : '';
}

Map<String, dynamic> _mapOf(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _listOf(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw.whereType<Map>().map(_mapOf).toList(growable: false);
}

/// A localized {nl,en,fr,es} block.
Map<String, String> limousineLocalizedOf(Object? raw) {
  final src = _mapOf(raw);
  return <String, String>{
    for (final lang in const ['nl', 'en', 'fr', 'es'])
      lang: (src[lang] ?? '').toString().trim(),
  };
}

String limousineLocalizedFor(Object? raw, AppLanguage language) {
  final map = limousineLocalizedOf(raw);
  switch (language) {
    case AppLanguage.nl:
      return map['nl'] ?? '';
    case AppLanguage.fr:
      return map['fr'] ?? '';
    case AppLanguage.es:
      return map['es'] ?? '';
    case AppLanguage.en:
    case AppLanguage.de:
      return map['en'] ?? '';
  }
}

bool _localizedIsEmpty(Object? raw) =>
    limousineLocalizedOf(raw).values.every((v) => v.trim().isEmpty);

class LimousineOfferValidation {
  const LimousineOfferValidation({required this.errors});

  final List<String> errors;

  bool get valid => errors.isEmpty;
}

bool _fixedRuleComplete(Map<String, dynamic> rule) {
  if ((rule['rule_id'] ?? '').toString().trim().isEmpty) return false;
  final journey = limousineOfferToken(rule['journey_type']);
  if (!LimousineJourneyTypeId.all.contains(journey)) return false;
  final amount = limousineCentsOf(rule['amount_cents']);
  if (amount == null || amount <= 0) return false;
  if (limousineCurrencyOf(rule['currency']).isEmpty) return false;
  if (journey == LimousineJourneyTypeId.airportTransfer &&
      (rule['airport_iata'] ?? '').toString().trim().isEmpty) {
    return false;
  }
  final zoneType = limousineOfferToken(rule['zone_type']);
  if (zoneType == 'radius') {
    final lat = double.tryParse('${rule['zone_center_lat']}');
    final lng = double.tryParse('${rule['zone_center_lng']}');
    final radius = double.tryParse('${rule['radius_km']}');
    if (lat == null || lng == null || radius == null || radius <= 0)
      return false;
  }
  if (zoneType == 'postcode' || zoneType == 'city' || zoneType == 'country') {
    if ((rule['zone_value'] ?? '').toString().trim().isEmpty) return false;
  }
  return true;
}

bool _distanceTimeComplete(Map<String, dynamic> dt) {
  if (!_boolOf(dt['enabled'])) return true;
  for (final key in const [
    'base_incl_vat_cents',
    'per_km_incl_vat_cents',
    'per_minute_incl_vat_cents',
    'minimum_incl_vat_cents',
  ]) {
    if (limousineCentsOf(dt[key]) == null) return false;
  }
  return limousineCurrencyOf(dt['currency']).isNotEmpty;
}

/// Authoritative offer validation. Fails closed on every rule in the P2B2
/// contract. `vehicles` are the company's authoritative vehicles.
LimousineOfferValidation validateLimousineOffer(
  Map<String, dynamic> offer, {
  List<VehicleProfile> vehicles = const <VehicleProfile>[],
  List<String> knownClassIds = const <String>[],
  bool readiness = false,
}) {
  final errors = <String>{};

  final offerId = (offer['offer_id'] ?? '').toString().trim();
  if (offerId.isEmpty) errors.add(LimousineOfferError.missingOfferId);

  final targetType = limousineOfferToken(offer['target_type']);
  if (!LimousineOfferTarget.all.contains(targetType)) {
    errors.add(LimousineOfferError.unknownTarget);
  }

  final presentation = limousineOfferToken(offer['price_presentation']);
  if (!LimousinePricePresentation.all.contains(presentation)) {
    errors.add(LimousineOfferError.invalidPresentation);
  }

  final currency = limousineCurrencyOf(offer['currency']);
  if (currency.isEmpty) errors.add(LimousineOfferError.missingCurrency);

  final classIds = knownClassIds.map(limousineOfferToken).toSet();

  if (targetType == LimousineOfferTarget.vehicle) {
    final vehicleId = (offer['vehicle_id'] ?? '').toString().trim();
    VehicleProfile? vehicle;
    for (final v in vehicles) {
      if (v.id == vehicleId) {
        vehicle = v;
        break;
      }
    }
    if (vehicleId.isEmpty || vehicle == null) {
      errors.add(LimousineOfferError.unknownVehicle);
    } else {
      if (!vehicle.isActive) errors.add(LimousineOfferError.inactiveVehicle);
      if (limousineOfferToken(vehicle.serviceCategory) != 'limousine') {
        errors.add(LimousineOfferError.vehicleNotLimousine);
      }
      if (!classIds.contains(limousineOfferToken(vehicle.serviceClassId))) {
        errors.add(LimousineOfferError.unknownServiceClass);
      }
    }
  } else if (targetType == LimousineOfferTarget.serviceClass) {
    if (!classIds.contains(limousineOfferToken(offer['service_class_id']))) {
      errors.add(LimousineOfferError.unknownServiceClass);
    }
  }

  final fixedRules = _listOf(offer['fixed_rules']);
  final hourly = _mapOf(offer['hourly']);
  final distanceTime = _mapOf(offer['distance_time']);
  final mobilisation = _mapOf(offer['mobilisation']);
  final paidExtras = _listOf(offer['paid_extras']);

  // Negative amounts anywhere fail closed.
  final amounts = <int?>[
    limousineCentsOf(offer['display_amount_cents']),
    ...fixedRules.map((r) => limousineCentsOf(r['amount_cents'])),
    limousineCentsOf(hourly['first_hour_cents']),
    limousineCentsOf(hourly['additional_hour_cents']),
    limousineCentsOf(hourly['package_amount_cents']),
    limousineCentsOf(hourly['excess_hour_cents']),
    limousineCentsOf(distanceTime['base_incl_vat_cents']),
    limousineCentsOf(distanceTime['per_km_incl_vat_cents']),
    limousineCentsOf(distanceTime['per_minute_incl_vat_cents']),
    limousineCentsOf(distanceTime['minimum_incl_vat_cents']),
    limousineCentsOf(mobilisation['fee_cents']),
    ...paidExtras.map((e) => limousineCentsOf(e['amount_cents'])),
  ];
  if (amounts.any((a) => a != null && a < 0)) {
    errors.add(LimousineOfferError.negativeAmount);
  }

  // One currency across every priced element.
  final currencies = <String>{
    if (currency.isNotEmpty) currency,
    for (final r in fixedRules)
      if (limousineCurrencyOf(r['currency']).isNotEmpty)
        limousineCurrencyOf(r['currency']),
    if (limousineCurrencyOf(hourly['currency']).isNotEmpty)
      limousineCurrencyOf(hourly['currency']),
    if (limousineCurrencyOf(distanceTime['currency']).isNotEmpty)
      limousineCurrencyOf(distanceTime['currency']),
    if (limousineCurrencyOf(mobilisation['currency']).isNotEmpty)
      limousineCurrencyOf(mobilisation['currency']),
    for (final e in paidExtras)
      if (limousineCurrencyOf(e['currency']).isNotEmpty)
        limousineCurrencyOf(e['currency']),
  };
  if (currencies.length > 1) errors.add(LimousineOfferError.currencyConflict);

  // exact_fixed must be able to resolve from complete data.
  if (presentation == LimousinePricePresentation.exactFixed) {
    final enabledRules = fixedRules
        .where((r) => _boolOf(r['enabled']))
        .toList(growable: false);
    final hourlyOn = _boolOf(hourly['enabled']);
    final dtOn = _boolOf(distanceTime['enabled']);
    if (enabledRules.isNotEmpty && !enabledRules.every(_fixedRuleComplete)) {
      errors.add(LimousineOfferError.incompleteFixedRule);
    }
    if (enabledRules.isEmpty && !hourlyOn && !dtOn) {
      errors.add(LimousineOfferError.incompleteFixedRule);
    }
  }

  // Marketing presentations need a display amount.
  if (presentation == LimousinePricePresentation.fromPrice ||
      presentation == LimousinePricePresentation.indicative) {
    final display = limousineCentsOf(offer['display_amount_cents']);
    if (display == null || display <= 0) {
      errors.add(LimousineOfferError.missingDisplayAmount);
    }
  }

  final ruleIds = fixedRules
      .map((r) => (r['rule_id'] ?? '').toString().trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
  if (ruleIds.toSet().length != ruleIds.length) {
    errors.add(LimousineOfferError.duplicateRule);
  }

  // Hourly hire.
  if (_boolOf(hourly['enabled'])) {
    final first = limousineCentsOf(hourly['first_hour_cents']);
    final additional = limousineCentsOf(hourly['additional_hour_cents']);
    if (first == null || first <= 0 || additional == null || additional < 0) {
      errors.add(LimousineOfferError.hourlyIncomplete);
    }
    final minimum = _intOf(hourly['minimum_duration_minutes']);
    if (minimum == null || minimum <= 0) {
      errors.add(LimousineOfferError.hourlyMissingMinimumDuration);
    }
    final packageAmount = limousineCentsOf(hourly['package_amount_cents']);
    final packageDuration = _intOf(hourly['package_duration_minutes']);
    final hasAmount = packageAmount != null;
    final hasDuration = packageDuration != null && packageDuration > 0;
    if (hasAmount != hasDuration) {
      errors.add(LimousineOfferError.packageIncomplete);
    }
  }

  if (!_distanceTimeComplete(distanceTime)) {
    errors.add(LimousineOfferError.distanceTimeIncomplete);
  }

  // Mobilisation.
  if (mobilisation.isNotEmpty) {
    final method = limousineOfferToken(mobilisation['method']);
    final charged =
        _boolOf(mobilisation['outbound_charged']) ||
        _boolOf(mobilisation['return_charged']);
    if (!LimousineMobilisationMethod.all.contains(method)) {
      errors.add(LimousineOfferError.mobilisationIncomplete);
    } else if (charged && method == LimousineMobilisationMethod.included) {
      errors.add(LimousineOfferError.mobilisationContradictory);
    } else if (charged && method == LimousineMobilisationMethod.fixedFee) {
      final fee = limousineCentsOf(mobilisation['fee_cents']);
      if (fee == null ||
          fee <= 0 ||
          limousineCurrencyOf(mobilisation['currency']).isEmpty) {
        errors.add(LimousineOfferError.mobilisationIncomplete);
      }
    } else if (charged && method == LimousineMobilisationMethod.distanceTime) {
      if (!_boolOf(distanceTime['enabled']) ||
          !_distanceTimeComplete(distanceTime)) {
        errors.add(LimousineOfferError.mobilisationIncomplete);
      }
    }
  }

  if (_boolOf(offer['published']) && !readiness) {
    errors.add(LimousineOfferError.publishedWithoutReadiness);
  }

  return LimousineOfferValidation(errors: errors.toList(growable: false));
}

/// An exact vehicle offer overrides a service-class offer when both match.
Map<String, dynamic>? selectLimousineOfferForRequest(
  List<Map<String, dynamic>> offers, {
  String vehicleId = '',
  String serviceClassId = '',
  String journeyType = '',
}) {
  final enabled = offers
      .where((o) => _boolOf(o['enabled']))
      .toList(growable: false);
  final wantedJourney = limousineOfferToken(journeyType);
  bool journeyOk(Map<String, dynamic> offer) {
    final types =
        (offer['journey_types'] as List?)
            ?.map(limousineOfferToken)
            .where((t) => t.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    return wantedJourney.isEmpty ||
        types.isEmpty ||
        types.contains(wantedJourney);
  }

  final wantedVehicle = vehicleId.trim();
  if (wantedVehicle.isNotEmpty) {
    for (final o in enabled) {
      if (limousineOfferToken(o['target_type']) ==
              LimousineOfferTarget.vehicle &&
          (o['vehicle_id'] ?? '').toString().trim() == wantedVehicle &&
          journeyOk(o)) {
        return o;
      }
    }
  }
  final wantedClass = limousineOfferToken(serviceClassId);
  if (wantedClass.isNotEmpty) {
    for (final o in enabled) {
      if (limousineOfferToken(o['target_type']) ==
              LimousineOfferTarget.serviceClass &&
          limousineOfferToken(o['service_class_id']) == wantedClass &&
          journeyOk(o)) {
        return o;
      }
    }
  }
  return null;
}

/// Only `exact_fixed` may ever become a resolved, bookable price. `from_price`
/// and `indicative` are marketing and must never enter a snapshot.
bool limousineOfferCanResolvePrice(Map<String, dynamic> offer) =>
    limousineOfferToken(offer['price_presentation']) ==
    LimousinePricePresentation.exactFixed;

bool limousineOfferAmountIsSnapshotEligible(Map<String, dynamic> offer) =>
    limousineOfferCanResolvePrice(offer);

/// Customer-safe projection. Never exposes the private operating-base address,
/// unpublished rules, internal costs or raw pricing records.
List<Map<String, dynamic>> buildSafePublicLimousineOffers(
  List<Map<String, dynamic>> offers, {
  bool eligible = false,
  List<VehicleProfile> vehicles = const <VehicleProfile>[],
  List<String> knownClassIds = const <String>[],
  bool readiness = false,
}) {
  if (!eligible) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final offer in offers) {
    if (!_boolOf(offer['enabled'])) continue;
    if (!_boolOf(offer['published'])) continue;
    final validation = validateLimousineOffer(
      offer,
      vehicles: vehicles,
      knownClassIds: knownClassIds,
      readiness: readiness,
    );
    if (!validation.valid) continue;
    final presentation = limousineOfferToken(offer['price_presentation']);
    if (presentation == LimousinePricePresentation.unavailable) continue;

    final display = limousineCentsOf(offer['display_amount_cents']);
    final showsAmount =
        presentation != LimousinePricePresentation.quoteRequired &&
        display != null &&
        display > 0;

    final mobilisation = _mapOf(offer['mobilisation']);
    final charged =
        _boolOf(mobilisation['outbound_charged']) ||
        _boolOf(mobilisation['return_charged']);

    out.add(<String, dynamic>{
      'offer_id': (offer['offer_id'] ?? '').toString(),
      'target_type': limousineOfferToken(offer['target_type']),
      if (limousineOfferToken(offer['target_type']) ==
          LimousineOfferTarget.vehicle)
        'vehicle_id': (offer['vehicle_id'] ?? '').toString(),
      'service_class_id': limousineOfferToken(offer['service_class_id']),
      'title': limousineLocalizedOf(offer['title']),
      'description': limousineLocalizedOf(offer['description']),
      'price_presentation': presentation,
      if (showsAmount) 'display_amount_cents': display,
      'currency': limousineCurrencyOf(offer['currency']),
      'journey_types':
          (offer['journey_types'] as List?)
              ?.map(limousineOfferToken)
              .where((t) => t.isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
      'included_services': _listOf(offer['included_services'])
          .where((s) => _boolOf(s['active'], fallback: true))
          .where((s) => !_localizedIsEmpty(s['label']))
          .map(
            (s) => <String, dynamic>{
              'item_id': (s['item_id'] ?? '').toString(),
              'label': limousineLocalizedOf(s['label']),
            },
          )
          .toList(growable: false),
      'paid_extras': _listOf(offer['paid_extras'])
          .where((e) => _boolOf(e['active'], fallback: true))
          .where((e) => _boolOf(e['public'], fallback: true))
          .where((e) => !_localizedIsEmpty(e['label']))
          .map((e) {
            final quoteRequired = _boolOf(e['quote_required']);
            final amount = limousineCentsOf(e['amount_cents']);
            return <String, dynamic>{
              'extra_id': (e['extra_id'] ?? '').toString(),
              'label': limousineLocalizedOf(e['label']),
              'quote_required': quoteRequired,
              if (!quoteRequired && amount != null) 'amount_cents': amount,
              'currency': limousineCurrencyOf(e['currency']),
            };
          })
          .toList(growable: false),
      // Safe statement only — the private operating-base address is excluded.
      'mobilisation': <String, dynamic>{
        'included':
            !charged &&
            limousineOfferToken(mobilisation['method']) ==
                LimousineMobilisationMethod.included,
        'charged_separately': charged,
        'disclosure': limousineLocalizedOf(mobilisation['disclosure']),
      },
      'source_revision': _intOf(offer['source_revision']) ?? 0,
    });
  }
  return out;
}

/// Monotonic guard: an older revision may never overwrite newer configuration.
bool limousineOffersRevisionAccepts({
  required int currentRevision,
  required int incomingRevision,
}) => incomingRevision > currentRevision;

// ---------------------------------------------------------------------------
// Localized labels (NL/EN/FR/ES)
// ---------------------------------------------------------------------------

const Map<String, LocalizedText> kLimousinePresentationLabels =
    <String, LocalizedText>{
      LimousinePricePresentation.exactFixed: LocalizedText(
        nl: 'Exacte boekbare prijs',
        en: 'Exact bookable price',
        fr: 'Prix exact réservable',
        es: 'Precio exacto reservable',
      ),
      LimousinePricePresentation.fromPrice: LocalizedText(
        nl: 'Vanafprijs',
        en: 'Price from',
        fr: 'Prix à partir de',
        es: 'Precio desde',
      ),
      LimousinePricePresentation.indicative: LocalizedText(
        nl: 'Indicatieve prijs',
        en: 'Indicative price',
        fr: 'Prix indicatif',
        es: 'Precio indicativo',
      ),
      LimousinePricePresentation.quoteRequired: LocalizedText(
        nl: 'Offerte op aanvraag',
        en: 'Quote required',
        fr: 'Devis requis',
        es: 'Presupuesto requerido',
      ),
      LimousinePricePresentation.unavailable: LocalizedText(
        nl: 'Niet beschikbaar',
        en: 'Unavailable',
        fr: 'Indisponible',
        es: 'No disponible',
      ),
    };

const Map<String, LocalizedText> kLimousineJourneyTypeLabels =
    <String, LocalizedText>{
      LimousineJourneyTypeId.pointToPoint: LocalizedText(
        nl: 'Van punt naar punt',
        en: 'Point to point',
        fr: 'Point à point',
        es: 'Punto a punto',
      ),
      LimousineJourneyTypeId.airportTransfer: LocalizedText(
        nl: 'Luchthaventransfer',
        en: 'Airport transfer',
        fr: 'Transfert aéroport',
        es: 'Traslado aeropuerto',
      ),
      LimousineJourneyTypeId.hotelTransfer: LocalizedText(
        nl: 'Hoteltransfer',
        en: 'Hotel transfer',
        fr: 'Transfert hôtel',
        es: 'Traslado hotel',
      ),
      LimousineJourneyTypeId.eventTransfer: LocalizedText(
        nl: 'Eventtransfer',
        en: 'Event transfer',
        fr: 'Transfert événement',
        es: 'Traslado evento',
      ),
      LimousineJourneyTypeId.hourlyPackage: LocalizedText(
        nl: 'Uurhuur / pakket',
        en: 'Hourly hire / package',
        fr: 'Location horaire / forfait',
        es: 'Alquiler por horas / paquete',
      ),
    };

const Map<String, LocalizedText> kLimousineMobilisationLabels =
    <String, LocalizedText>{
      LimousineMobilisationMethod.included: LocalizedText(
        nl: 'Voorrijden inbegrepen',
        en: 'Mobilisation included',
        fr: 'Acheminement inclus',
        es: 'Movilización incluida',
      ),
      LimousineMobilisationMethod.fixedFee: LocalizedText(
        nl: 'Vaste voorrijkost',
        en: 'Fixed mobilisation fee',
        fr: 'Frais d’acheminement fixes',
        es: 'Tarifa fija de movilización',
      ),
      LimousineMobilisationMethod.distanceTime: LocalizedText(
        nl: 'Voorrijden per afstand/tijd',
        en: 'Mobilisation by distance/time',
        fr: 'Acheminement selon distance/temps',
        es: 'Movilización por distancia/tiempo',
      ),
    };

const Map<String, LocalizedText>
kLimousineOfferErrorLabels = <String, LocalizedText>{
  LimousineOfferError.missingOfferId: LocalizedText(
    nl: 'Aanbod-ID ontbreekt.',
    en: 'Offer ID is missing.',
    fr: 'L’identifiant de l’offre est manquant.',
    es: 'Falta el ID de la oferta.',
  ),
  LimousineOfferError.unknownTarget: LocalizedText(
    nl: 'Kies een voertuig of een serviceklasse.',
    en: 'Choose a vehicle or a service class.',
    fr: 'Choisissez un véhicule ou une classe de service.',
    es: 'Elige un vehículo o una clase de servicio.',
  ),
  LimousineOfferError.unknownVehicle: LocalizedText(
    nl: 'Het gekozen voertuig bestaat niet.',
    en: 'The selected vehicle does not exist.',
    fr: 'Le véhicule sélectionné n’existe pas.',
    es: 'El vehículo seleccionado no existe.',
  ),
  LimousineOfferError.inactiveVehicle: LocalizedText(
    nl: 'Het gekozen voertuig is niet actief.',
    en: 'The selected vehicle is not active.',
    fr: 'Le véhicule sélectionné n’est pas actif.',
    es: 'El vehículo seleccionado no está activo.',
  ),
  LimousineOfferError.vehicleNotLimousine: LocalizedText(
    nl: 'Het voertuig is niet als limousine geconfigureerd.',
    en: 'The vehicle is not configured as a limousine.',
    fr: 'Le véhicule n’est pas configuré comme limousine.',
    es: 'El vehículo no está configurado como limusina.',
  ),
  LimousineOfferError.unknownServiceClass: LocalizedText(
    nl: 'Onbekende of inactieve limousineklasse.',
    en: 'Unknown or inactive limousine class.',
    fr: 'Classe de limousine inconnue ou inactive.',
    es: 'Clase de limusina desconocida o inactiva.',
  ),
  LimousineOfferError.missingCurrency: LocalizedText(
    nl: 'Valuta ontbreekt.',
    en: 'Currency is missing.',
    fr: 'La devise est manquante.',
    es: 'Falta la moneda.',
  ),
  LimousineOfferError.currencyConflict: LocalizedText(
    nl: 'Tegenstrijdige valuta in dit aanbod.',
    en: 'Conflicting currencies in this offer.',
    fr: 'Devises contradictoires dans cette offre.',
    es: 'Monedas contradictorias en esta oferta.',
  ),
  LimousineOfferError.negativeAmount: LocalizedText(
    nl: 'Bedragen mogen niet negatief zijn.',
    en: 'Amounts cannot be negative.',
    fr: 'Les montants ne peuvent pas être négatifs.',
    es: 'Los importes no pueden ser negativos.',
  ),
  LimousineOfferError.invalidPresentation: LocalizedText(
    nl: 'Kies hoe de prijs wordt getoond.',
    en: 'Choose how the price is presented.',
    fr: 'Choisissez la présentation du prix.',
    es: 'Elige cómo se muestra el precio.',
  ),
  LimousineOfferError.missingDisplayAmount: LocalizedText(
    nl: 'Een vanaf- of indicatieve prijs vereist een bedrag.',
    en: 'A from/indicative price requires an amount.',
    fr: 'Un prix à partir de/indicatif exige un montant.',
    es: 'Un precio desde/indicativo requiere un importe.',
  ),
  LimousineOfferError.incompleteFixedRule: LocalizedText(
    nl: 'Een exacte prijs vereist volledige tariefgegevens.',
    en: 'An exact price requires complete rule data.',
    fr: 'Un prix exact exige des données de règle complètes.',
    es: 'Un precio exacto requiere datos de regla completos.',
  ),
  LimousineOfferError.duplicateRule: LocalizedText(
    nl: 'Dubbele of dubbelzinnige tariefregels.',
    en: 'Duplicate or ambiguous rules.',
    fr: 'Règles en double ou ambiguës.',
    es: 'Reglas duplicadas o ambiguas.',
  ),
  LimousineOfferError.hourlyMissingMinimumDuration: LocalizedText(
    nl: 'Uurhuur vereist een minimumduur.',
    en: 'Hourly hire requires a minimum duration.',
    fr: 'La location horaire exige une durée minimale.',
    es: 'El alquiler por horas requiere una duración mínima.',
  ),
  LimousineOfferError.hourlyIncomplete: LocalizedText(
    nl: 'Vul het eerste uur en het bijkomende uur in.',
    en: 'Enter the first-hour and additional-hour price.',
    fr: 'Saisissez le prix de la première heure et des heures suivantes.',
    es: 'Introduce el precio de la primera hora y de las horas adicionales.',
  ),
  LimousineOfferError.packageIncomplete: LocalizedText(
    nl: 'Een pakket vereist zowel duur als bedrag.',
    en: 'A package requires both a duration and an amount.',
    fr: 'Un forfait exige une durée et un montant.',
    es: 'Un paquete requiere duración e importe.',
  ),
  LimousineOfferError.mobilisationIncomplete: LocalizedText(
    nl: 'Voorrijkosten zijn onvolledig geconfigureerd.',
    en: 'Mobilisation charging is incompletely configured.',
    fr: 'Les frais d’acheminement sont incomplets.',
    es: 'El cobro de movilización está incompleto.',
  ),
  LimousineOfferError.mobilisationContradictory: LocalizedText(
    nl: 'Voorrijden is inbegrepen én aangerekend.',
    en: 'Mobilisation is both included and charged.',
    fr: 'L’acheminement est à la fois inclus et facturé.',
    es: 'La movilización está incluida y cobrada a la vez.',
  ),
  LimousineOfferError.publishedWithoutReadiness: LocalizedText(
    nl: 'Publiceren kan niet: je limousinestatus is niet gereed.',
    en: 'Cannot publish: your limousine readiness is not met.',
    fr: 'Publication impossible : votre statut limousine n’est pas prêt.',
    es: 'No se puede publicar: tu estado de limusina no está listo.',
  ),
  LimousineOfferError.distanceTimeIncomplete: LocalizedText(
    nl: 'Afstand/tijd-tarief is onvolledig.',
    en: 'Distance/time pricing is incomplete.',
    fr: 'La tarification distance/temps est incomplète.',
    es: 'La tarificación distancia/tiempo está incompleta.',
  ),
};

String limousineOfferErrorLabel(String code, AppLanguage language) {
  final text = kLimousineOfferErrorLabels[code];
  if (text == null) return code;
  return text.of(language);
}

String limousinePresentationLabel(String code, AppLanguage language) =>
    kLimousinePresentationLabels[code]?.of(language) ?? code;

String limousineJourneyTypeLabel(String code, AppLanguage language) =>
    kLimousineJourneyTypeLabels[code]?.of(language) ?? code;

String limousineMobilisationLabel(String code, AppLanguage language) =>
    kLimousineMobilisationLabels[code]?.of(language) ?? code;
