// COMPANY-CUSTOMER-OPS-P0 — ride options shared by quote and agenda.

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';

const List<String> kCompanyRideServices = <String>[
  'airport',
  'passenger',
  'business',
  'courier',
  'care',
  'event',
];

const List<String> kCompanyRideTiers = <String>['comfort', 'private', 'premium'];

const List<String> kCompanyRideExtras = <String>['none', 'drinks', 'worktable'];

const List<String> kCompanyRideAirportDirections = <String>[
  'from_airport',
  'to_airport',
];

class CompanyRideOptions {
  const CompanyRideOptions({
    this.service = '',
    this.tier = '',
    this.bags = 0,
    this.waitMin = 0,
    this.flightNumber = '',
    this.airportDirection = '',
    this.extra = '',
    this.meetAndGreet = false,
    this.nameBoard = '',
    this.airportIata = '',
    this.airportCountry = '',
    this.flightAt = '',
    this.pickupArrangement = '',
    this.pickupAfterMin = 0,
    this.flightTimezone = 'Europe/Brussels',
    this.returnAirportIata = '',
    this.returnFlightNumber = '',
    this.returnFlightAt = '',
    this.returnPickupArrangement = '',
    this.vehicleType = '',
  });

  final String service;
  final String tier;
  final int bags;
  final int waitMin;
  final String flightNumber;
  final String airportDirection;
  final String extra;
  final bool meetAndGreet;
  final String nameBoard;
  final String airportIata;
  final String airportCountry;
  final String flightAt;
  final String pickupArrangement;
  final int pickupAfterMin;
  final String flightTimezone;
  final String returnAirportIata;
  final String returnFlightNumber;
  final String returnFlightAt;
  final String returnPickupArrangement;
  final String vehicleType;

  bool get isAirport => service.trim().toLowerCase() == 'airport';

  bool get isEmpty =>
      service.trim().isEmpty &&
      tier.trim().isEmpty &&
      bags <= 0 &&
      waitMin <= 0 &&
      flightNumber.trim().isEmpty &&
      airportDirection.trim().isEmpty &&
      (extra.trim().isEmpty || extra.trim() == 'none') &&
      !meetAndGreet &&
      nameBoard.trim().isEmpty &&
      airportIata.trim().isEmpty &&
      flightAt.trim().isEmpty &&
      pickupArrangement.trim().isEmpty &&
      vehicleType.trim().isEmpty &&
      returnAirportIata.trim().isEmpty &&
      returnFlightNumber.trim().isEmpty &&
      returnFlightAt.trim().isEmpty;

  CompanyRideOptions copyWith({
    String? service,
    String? tier,
    int? bags,
    int? waitMin,
    String? flightNumber,
    String? airportDirection,
    String? extra,
    bool? meetAndGreet,
    String? nameBoard,
    String? airportIata,
    String? airportCountry,
    String? flightAt,
    String? pickupArrangement,
    int? pickupAfterMin,
    String? flightTimezone,
    String? returnAirportIata,
    String? returnFlightNumber,
    String? returnFlightAt,
    String? returnPickupArrangement,
    String? vehicleType,
  }) {
    return CompanyRideOptions(
      service: service ?? this.service,
      tier: tier ?? this.tier,
      bags: bags ?? this.bags,
      waitMin: waitMin ?? this.waitMin,
      flightNumber: flightNumber ?? this.flightNumber,
      airportDirection: airportDirection ?? this.airportDirection,
      extra: extra ?? this.extra,
      meetAndGreet: meetAndGreet ?? this.meetAndGreet,
      nameBoard: nameBoard ?? this.nameBoard,
      airportIata: airportIata ?? this.airportIata,
      airportCountry: airportCountry ?? this.airportCountry,
      flightAt: flightAt ?? this.flightAt,
      pickupArrangement: pickupArrangement ?? this.pickupArrangement,
      pickupAfterMin: pickupAfterMin ?? this.pickupAfterMin,
      flightTimezone: flightTimezone ?? this.flightTimezone,
      returnAirportIata: returnAirportIata ?? this.returnAirportIata,
      returnFlightNumber: returnFlightNumber ?? this.returnFlightNumber,
      returnFlightAt: returnFlightAt ?? this.returnFlightAt,
      returnPickupArrangement:
          returnPickupArrangement ?? this.returnPickupArrangement,
      vehicleType: companyRideSanitizeVehicleType(
        vehicleType ?? this.vehicleType,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (service.trim().isNotEmpty) 'service': service.trim(),
      if (tier.trim().isNotEmpty) 'tier': tier.trim(),
      'bags': bags < 0 ? 0 : bags,
      'wait_min': waitMin < 0 ? 0 : waitMin,
      if (flightNumber.trim().isNotEmpty)
        'flight_number': flightNumber.trim().toUpperCase(),
      if (airportDirection.trim().isNotEmpty)
        'airport_direction': airportDirection.trim(),
      if (extra.trim().isNotEmpty && extra.trim() != 'none') 'extra': extra.trim(),
      if (meetAndGreet) 'meet_and_greet': true,
      if (nameBoard.trim().isNotEmpty) 'name_board': nameBoard.trim(),
      if (airportIata.trim().isNotEmpty)
        'airport_iata': airportIata.trim().toUpperCase(),
      if (airportCountry.trim().isNotEmpty)
        'airport_country': airportCountry.trim().toUpperCase(),
      if (flightAt.trim().isNotEmpty) 'flight_at': flightAt.trim(),
      if (pickupArrangement.trim().isNotEmpty)
        'pickup_arrangement': pickupArrangement.trim(),
      if (pickupAfterMin > 0) 'pickup_after_min': pickupAfterMin,
      if (flightTimezone.trim().isNotEmpty)
        'flight_timezone': flightTimezone.trim(),
      if (returnAirportIata.trim().isNotEmpty)
        'return_airport_iata': returnAirportIata.trim().toUpperCase(),
      if (returnFlightNumber.trim().isNotEmpty)
        'return_flight_number': returnFlightNumber.trim().toUpperCase(),
      if (returnFlightAt.trim().isNotEmpty)
        'return_flight_at': returnFlightAt.trim(),
      if (returnPickupArrangement.trim().isNotEmpty)
        'return_pickup_arrangement': returnPickupArrangement.trim(),
      if (companyRideSanitizeVehicleType(vehicleType).isNotEmpty)
        'vehicle_type': companyRideSanitizeVehicleType(vehicleType),
    };
  }
}

CompanyRideOptions parseCompanyRideOptions(Object? raw) {
  if (raw is! Map) return const CompanyRideOptions();
  final map = Map<dynamic, dynamic>.from(raw);
  int asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  String pick(List<String> keys) {
    for (final key in keys) {
      final text = map[key]?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  var service = pick(const ['service', 'service_id']).toLowerCase();
  final tier = pick(const ['tier', 'vehicle_tier', 'tier_id']).toLowerCase();
  final extra = pick(const ['extra', 'extra_option']).toLowerCase();
  final direction = pick(const [
    'airport_direction',
    'airportDirection',
  ]).toLowerCase();
  var vehicleType = pick(const ['vehicle_type', 'vehicleType']).toLowerCase();
  if (companyRideVehicleTypeIsServiceMode(vehicleType)) {
    if (service.isEmpty) service = 'airport';
    vehicleType = '';
  }
  return CompanyRideOptions(
    service: kCompanyRideServices.contains(service) ? service : '',
    tier: kCompanyRideTiers.contains(tier) ? tier : '',
    bags: asInt(map['bags']).clamp(0, 8),
    waitMin: asInt(map['wait_min'] ?? map['waitMin']).clamp(0, 240),
    flightNumber: pick(const ['flight_number', 'flightNumber']).toUpperCase(),
    airportDirection: kCompanyRideAirportDirections.contains(direction)
        ? direction
        : '',
    extra: kCompanyRideExtras.contains(extra) ? extra : '',
    meetAndGreet:
        map['meet_and_greet'] == true ||
        map['meetAndGreet'] == true ||
        map['meet_and_greet']?.toString().trim().toLowerCase() == 'true',
    nameBoard: pick(const ['name_board', 'nameBoard', 'pickup_sign']),
    airportIata: pick(const ['airport_iata', 'airportIata']).toUpperCase(),
    airportCountry: pick(const ['airport_country', 'airportCountry']).toUpperCase(),
    flightAt: pick(const ['flight_at', 'flightAt']),
    pickupArrangement: pick(const [
      'pickup_arrangement',
      'pickupArrangement',
    ]).toLowerCase(),
    pickupAfterMin: asInt(map['pickup_after_min'] ?? map['pickupAfterMin'])
        .clamp(0, 240),
    flightTimezone: pick(const ['flight_timezone', 'flightTimezone']).isEmpty
        ? 'Europe/Brussels'
        : pick(const ['flight_timezone', 'flightTimezone']),
    returnAirportIata: pick(const [
      'return_airport_iata',
      'returnAirportIata',
    ]).toUpperCase(),
    returnFlightNumber: pick(const [
      'return_flight_number',
      'returnFlightNumber',
    ]).toUpperCase(),
    returnFlightAt: pick(const ['return_flight_at', 'returnFlightAt']),
    returnPickupArrangement: pick(const [
      'return_pickup_arrangement',
      'returnPickupArrangement',
    ]).toLowerCase(),
    vehicleType: companyRideSanitizeVehicleType(vehicleType),
  );
}

bool companyRideVehicleTypeIsServiceMode(String raw) {
  switch (raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_')) {
    case 'airport':
    case 'airport_ride':
      return true;
    default:
      return false;
  }
}

String companyRideSanitizeVehicleType(String raw) {
  if (companyRideVehicleTypeIsServiceMode(raw)) return '';
  return raw.trim().toLowerCase();
}

String companyRideOptionLabel(String id, AppLanguage language) {
  final needle = id.trim().toLowerCase();
  if (needle.isEmpty) return '';
  for (final option in <AppOption>[
    ...appConfig.enabledServices,
    ...appConfig.enabledTiers,
    ...appConfig.enabledExtraOptions,
  ]) {
    if (option.id.trim().toLowerCase() == needle) {
      return option.labelFor(language);
    }
  }
  switch (needle) {
    case 'from_airport':
      return language == AppLanguage.fr
          ? 'Depuis l’aéroport'
          : language == AppLanguage.es
              ? 'Desde el aeropuerto'
              : language == AppLanguage.nl
                  ? 'Vanaf de luchthaven'
                  : 'From the airport';
    case 'to_airport':
      return language == AppLanguage.fr
          ? 'Vers l’aéroport'
          : language == AppLanguage.es
              ? 'Hacia el aeropuerto'
              : language == AppLanguage.nl
                  ? 'Naar de luchthaven'
                  : 'To the airport';
    default:
      return id.trim();
  }
}

String formatCompanyRideOptionsSummary(
  CompanyRideOptions options, {
  required AppLanguage language,
}) {
  if (options.isEmpty) return '';
  final bagsLabel = language == AppLanguage.fr
      ? '${options.bags} bagages'
      : language == AppLanguage.es
          ? '${options.bags} maletas'
          : language == AppLanguage.nl
              ? '${options.bags} bagage'
              : '${options.bags} bags';
  final parts = <String>[
    if (options.service.isNotEmpty)
      companyRideOptionLabel(options.service, language),
    if (options.tier.isNotEmpty) companyRideOptionLabel(options.tier, language),
    if (options.bags > 0) bagsLabel,
    if (options.waitMin > 0)
      language == AppLanguage.fr
          ? 'attente ${options.waitMin} min'
          : language == AppLanguage.es
              ? 'espera ${options.waitMin} min'
              : language == AppLanguage.nl
                  ? 'wacht ${options.waitMin} min'
                  : 'wait ${options.waitMin} min',
    if (options.airportDirection.isNotEmpty)
      companyRideOptionLabel(options.airportDirection, language),
    if (options.airportIata.isNotEmpty) options.airportIata,
    if (options.flightNumber.isNotEmpty) options.flightNumber,
    if (options.flightAt.isNotEmpty) options.flightAt,
    if (options.pickupArrangement.isNotEmpty) options.pickupArrangement,
    if (options.returnAirportIata.isNotEmpty)
      '${options.returnAirportIata} ${options.returnFlightNumber}'.trim(),
    if (options.extra.isNotEmpty && options.extra != 'none')
      companyRideOptionLabel(options.extra, language),
    if (options.meetAndGreet)
      language == AppLanguage.fr
          ? 'Accueil personnalisé'
          : language == AppLanguage.es
              ? 'Recibimiento'
              : language == AppLanguage.nl
                  ? 'Meet-and-greet'
                  : 'Meet and greet',
    if (options.nameBoard.trim().isNotEmpty) options.nameBoard.trim(),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' · ');
}

List<AppOption> companyRideServiceOptions() {
  final enabled = appConfig.enabledServices;
  if (enabled.isEmpty) return const <AppOption>[];
  return enabled;
}

List<AppOption> companyRideTierOptions() {
  final enabled = appConfig.enabledTiers;
  if (enabled.isEmpty) return const <AppOption>[];
  return enabled;
}

List<AppOption> companyRideExtraOptions() {
  final enabled = appConfig.enabledExtraOptions;
  if (enabled.isEmpty) return const <AppOption>[];
  return enabled;
}
