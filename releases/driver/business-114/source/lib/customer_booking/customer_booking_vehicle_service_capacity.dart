// Per-service vehicle capacity for customer booking.
//
// Mirrors the worker contract in `vehicle_service_capacity.mjs`: a vehicle may
// declare a different passenger/baggage capacity for taxi and for airport work.
// The server stays the authority; this layer only decides what a customer may
// select, so it never invents a capacity from a photo or a tier name.
//
// A missing service block or a missing baggage field keeps the existing
// behaviour: the vehicle stays selectable.

enum VehicleServiceKind { taxi, airport }

VehicleServiceKind normalizeVehicleServiceKind(String? service) {
  final token = (service ?? '').trim().toLowerCase();
  if (token == 'airport' ||
      token == 'luchthaven' ||
      token == 'airport_transfer' ||
      token == 'airporttransfer') {
    return VehicleServiceKind.airport;
  }
  return VehicleServiceKind.taxi;
}

String vehicleServiceKindToken(VehicleServiceKind kind) {
  return kind == VehicleServiceKind.airport ? 'airport' : 'taxi';
}

int? _positiveInt(Object? value) {
  if (value is num) {
    if (!value.isFinite || value < 0) return null;
    return value.floor();
  }
  final text = (value ?? '').toString().trim();
  if (text.isEmpty) return null;
  final parsed = num.tryParse(text.replaceAll(',', '.'));
  if (parsed == null || !parsed.isFinite || parsed < 0) return null;
  return parsed.floor();
}

Map<String, dynamic>? _asMap(Object? raw) {
  if (raw is! Map) return null;
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

class VehicleServiceCapacityRow {
  const VehicleServiceCapacityRow({this.passengers, this.baggage});

  final int? passengers;
  final int? baggage;

  bool get isEmpty => passengers == null && baggage == null;
}

VehicleServiceCapacityRow? _row(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  final passengers = _positiveInt(
    raw['passengers'] ?? raw['passenger_capacity'] ?? raw['passengerCapacity'],
  );
  final baggage = _positiveInt(
    raw['baggage'] ??
        raw['luggage'] ??
        raw['luggage_capacity'] ??
        raw['luggageCapacity'],
  );
  if (passengers == null && baggage == null) return null;
  return VehicleServiceCapacityRow(passengers: passengers, baggage: baggage);
}

class VehicleServiceCapacityBlock {
  const VehicleServiceCapacityBlock({this.taxi, this.airport});

  final VehicleServiceCapacityRow? taxi;
  final VehicleServiceCapacityRow? airport;

  VehicleServiceCapacityRow? forKind(VehicleServiceKind kind) {
    return kind == VehicleServiceKind.airport ? airport : taxi;
  }
}

VehicleServiceCapacityBlock? readVehicleServiceCapacityBlock(
  Map<String, dynamic> vehicle,
) {
  final raw = _asMap(vehicle['service_capacity'] ?? vehicle['serviceCapacity']);
  if (raw == null) return null;
  final taxi = _row(_asMap(raw['taxi']));
  final airport = _row(_asMap(raw['airport']));
  if (taxi == null && airport == null) return null;
  return VehicleServiceCapacityBlock(taxi: taxi, airport: airport);
}

class VehicleServiceCapacity {
  const VehicleServiceCapacity({
    required this.service,
    this.passengers,
    this.baggage,
  });

  final VehicleServiceKind service;
  final int? passengers;
  final int? baggage;
}

VehicleServiceCapacity resolveVehicleServiceCapacity(
  Map<String, dynamic> vehicle,
  String? service,
) {
  final kind = normalizeVehicleServiceKind(service);
  final specific = readVehicleServiceCapacityBlock(vehicle)?.forKind(kind);
  final passengers =
      specific?.passengers ??
      _positiveInt(
        vehicle['passenger_capacity'] ??
            vehicle['passengerCapacity'] ??
            vehicle['max_passengers'] ??
            vehicle['maxPassengers'] ??
            vehicle['pax'],
      );
  final baggage =
      specific?.baggage ??
      _positiveInt(
        vehicle['luggage_capacity'] ??
            vehicle['luggageCapacity'] ??
            vehicle['bag_capacity'] ??
            vehicle['bagCapacity'] ??
            vehicle['luggage'] ??
            vehicle['bags'],
      );
  return VehicleServiceCapacity(
    service: kind,
    passengers: passengers,
    baggage: baggage,
  );
}

/// Whether this vehicle is offered for [service].
///
/// An explicit `false` wins. When the company declared nothing at all the
/// vehicle stays offered, so companies that never configured per-service
/// vehicles keep their existing selection.
bool vehicleEnabledForService(Map<String, dynamic> vehicle, String? service) {
  final kind = normalizeVehicleServiceKind(service);
  final keys = kind == VehicleServiceKind.airport
      ? const <String>[
          'airport_enabled',
          'airportEnabled',
          'airport_transfer_enabled',
          'airportTransferEnabled',
        ]
      : const <String>['taxi_enabled', 'taxiEnabled'];
  for (final source in <Map<String, dynamic>?>[
    vehicle,
    _asMap(vehicle['services']),
    _asMap(vehicle['capabilities']),
    _asMap(vehicle['service_enabled'] ?? vehicle['serviceEnabled']),
  ]) {
    if (source == null) continue;
    for (final key in keys) {
      if (!source.containsKey(key)) continue;
      final value = source[key];
      if (value is bool) return value;
      final token = value?.toString().trim().toLowerCase() ?? '';
      if (token == 'false' || token == '0' || token == 'no') return false;
      if (token == 'true' || token == '1' || token == 'yes') return true;
    }
  }
  final declared = vehicle['services'];
  if (declared is List) {
    final tokens = declared
        .map((e) => e.toString().trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (tokens.isNotEmpty) {
      final wanted = kind == VehicleServiceKind.airport
          ? const <String>{'airport', 'airport_transfer', 'luchthaven'}
          : const <String>{'taxi', 'taxi_vvb', 'passenger'};
      if (tokens.any(wanted.contains)) return true;
      // A vehicle that names only other services is not offered here.
      const known = <String>{
        'taxi',
        'taxi_vvb',
        'passenger',
        'airport',
        'airport_transfer',
        'luchthaven',
      };
      if (tokens.any(known.contains)) return false;
    }
  }
  // Per-service capacity is also a declaration of intent.
  final block = readVehicleServiceCapacityBlock(vehicle);
  if (block != null && block.forKind(kind) == null) {
    final other = block.forKind(
      kind == VehicleServiceKind.airport
          ? VehicleServiceKind.taxi
          : VehicleServiceKind.airport,
    );
    if (other != null) return false;
  }
  return true;
}

/// Why a vehicle cannot serve this request, or an empty string when it fits.
///
/// Reason codes reuse the existing customer-booking vocabulary so the current
/// "no suitable vehicle" copy keeps working.
String vehicleServiceCapacityRefusal(
  Map<String, dynamic> vehicle, {
  String? service,
  int? passengers,
  int? baggage,
}) {
  if (!vehicleEnabledForService(vehicle, service)) {
    return 'assignment_service';
  }
  final cap = resolveVehicleServiceCapacity(vehicle, service);
  final wantedPax = _positiveInt(passengers);
  if (wantedPax != null &&
      wantedPax > 0 &&
      cap.passengers != null &&
      cap.passengers! > 0 &&
      wantedPax > cap.passengers!) {
    return 'assignment_capacity';
  }
  final wantedBags = _positiveInt(baggage);
  if (wantedBags != null &&
      wantedBags > 0 &&
      cap.baggage != null &&
      wantedBags > cap.baggage!) {
    return 'assignment_baggage';
  }
  return '';
}

bool vehicleFitsServiceCapacity(
  Map<String, dynamic> vehicle, {
  String? service,
  int? passengers,
  int? baggage,
}) {
  return vehicleServiceCapacityRefusal(
    vehicle,
    service: service,
    passengers: passengers,
    baggage: baggage,
  ).isEmpty;
}
