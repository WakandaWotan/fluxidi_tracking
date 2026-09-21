/// Ride options shared by the quote request and the later booking payload.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// `lib/company/company_ride_options.dart` — `CompanyRideOptions`,
/// `companyRideOptionsStripWaitFields`, `kCompanyRideWaitPayloadKeys`,
/// `companyRideSanitizeVehicleType`.
///
/// The airport-specific flight fields are intentionally left out; this phase
/// covers the taxi chain only.
library;

const List<String> kFluxidiRideServices = <String>[
  'airport',
  'passenger',
  'business',
  'courier',
  'care',
  'event',
];

const List<String> kFluxidiRideTiers = <String>['comfort', 'private', 'premium'];

class FluxidiRideOptions {
  const FluxidiRideOptions({
    this.service = '',
    this.tier = '',
    this.bags = 0,
    this.waitMin = 0,
    this.vehicleType = '',
  });

  final String service;
  final String tier;
  final int bags;
  final int waitMin;
  final String vehicleType;

  bool get isAirport => service.trim().toLowerCase() == 'airport';

  FluxidiRideOptions copyWith({
    String? service,
    String? tier,
    int? bags,
    int? waitMin,
    String? vehicleType,
  }) {
    return FluxidiRideOptions(
      service: service ?? this.service,
      tier: tier ?? this.tier,
      bags: bags ?? this.bags,
      waitMin: waitMin ?? this.waitMin,
      vehicleType: fluxidiSanitizeVehicleType(vehicleType ?? this.vehicleType),
    );
  }

  /// Wire shape of `ride_options`. Wait minutes are omitted for an airport ride.
  Map<String, dynamic> toJson() {
    final airport = isAirport;
    return <String, dynamic>{
      if (service.trim().isNotEmpty) 'service': service.trim(),
      if (tier.trim().isNotEmpty) 'tier': tier.trim(),
      'bags': bags < 0 ? 0 : bags,
      if (!airport) 'wait_min': waitMin < 0 ? 0 : waitMin,
      if (fluxidiSanitizeVehicleType(vehicleType).isNotEmpty)
        'vehicle_type': fluxidiSanitizeVehicleType(vehicleType),
    };
  }
}

bool fluxidiVehicleTypeIsServiceMode(String raw) {
  switch (raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_')) {
    case 'airport':
    case 'airport_ride':
      return true;
    default:
      return false;
  }
}

String fluxidiSanitizeVehicleType(String raw) {
  if (fluxidiVehicleTypeIsServiceMode(raw)) return '';
  return raw.trim().toLowerCase();
}

const List<String> kFluxidiRideWaitPayloadKeys = <String>[
  'wait_min',
  'waitMin',
  'waiting',
  'wait_minutes',
  'waitMinutes',
  'booked_wait_minutes',
  'bookedWaitMinutes',
];

/// Removes every wait field, top level and nested, for rides that cannot wait.
Map<String, dynamic> fluxidiStripWaitFields(Map<String, dynamic> body) {
  for (final key in kFluxidiRideWaitPayloadKeys) {
    body.remove(key);
  }
  final nested = body['ride_options'];
  if (nested is Map) {
    final options = Map<String, dynamic>.from(nested);
    for (final key in kFluxidiRideWaitPayloadKeys) {
      options.remove(key);
    }
    body['ride_options'] = options;
  }
  return body;
}
