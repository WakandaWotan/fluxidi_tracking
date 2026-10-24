/// Combines published vehicles with server availability into one offer list.
///
/// Mirrors how the existing flow composes vehicle cards at golden commit
/// 9df7e7b92ecc86a11184ee995e255da7b8f6fb68
/// (`lib/customer_booking/customer_booking_vehicle_offers.dart`).
///
/// Nothing is invented: a vehicle without server availability is not offered,
/// capacity and driver details are only shown when the server sent them.
library;

import 'availability.dart';

class FluxidiVehicleOffer {
  const FluxidiVehicleOffer({
    required this.vehicleId,
    required this.name,
    required this.available,
    this.reason = '',
    this.photoUrl = '',
    this.passengerSeats,
    this.driverId = '',
    this.driverDisplayName = '',
    this.driverPhotoUrl = '',
  });

  final String vehicleId;
  final String name;
  final bool available;
  final String reason;
  final String photoUrl;
  final int? passengerSeats;
  final String driverId;
  final String driverDisplayName;
  final String driverPhotoUrl;

  bool get hasDriverDetails => driverDisplayName.isNotEmpty;

  /// True when the server stated a capacity and it is too small.
  bool tooSmallFor(int passengers) =>
      passengerSeats != null && passengerSeats! < passengers;
}

String _text(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = (row[key] ?? '').toString().trim();
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return '';
}

int? _seats(Map<String, dynamic> row) {
  for (final key in const <String>[
    'passenger_capacity',
    'passengerCapacity',
    'pax',
    'seats',
  ]) {
    final raw = row[key];
    if (raw is num && raw > 0) return raw.round();
    final parsed = int.tryParse((raw ?? '').toString().trim());
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

bool _isActive(Map<String, dynamic> row) {
  if (row.containsKey('is_active') || row.containsKey('isActive')) {
    return row['is_active'] == true || row['isActive'] == true;
  }
  return true;
}

/// Builds the offer list from `profile.vehicles[]` plus an availability snapshot.
///
/// Server order is preserved. Returns an empty list when availability has not
/// been fetched, so no vehicle is ever presented as bookable on guesswork.
List<FluxidiVehicleOffer> buildFluxidiVehicleOffers({
  required List<Map<String, dynamic>> profileVehicles,
  required FluxidiAvailabilitySnapshot availability,
}) {
  if (!availability.fetched || availability.loadFailed) {
    return const <FluxidiVehicleOffer>[];
  }
  final offers = <FluxidiVehicleOffer>[];
  for (final raw in profileVehicles) {
    final vehicle = Map<String, dynamic>.from(raw);
    final id = _text(vehicle, const <String>['vehicle_id', 'vehicleId']);
    if (id.isEmpty) continue;
    if (!_isActive(vehicle)) continue;
    final row = availability.rowFor(id);
    if (row == null) continue;
    final photo = _text(vehicle, const <String>[
      'public_photo_url',
      'publicPhotoUrl',
      'photo_url',
      'photoUrl',
    ]);
    offers.add(
      FluxidiVehicleOffer(
        vehicleId: id,
        name: _text(vehicle, const <String>[
          'name',
          'vehicle_name',
          'vehicleName',
        ]),
        available: row.available,
        reason: row.reason,
        photoUrl: photo.startsWith('https://') ? photo : '',
        passengerSeats: row.passengerSeats ?? _seats(vehicle),
        driverId: row.driverId,
        driverDisplayName: row.driverDisplayName,
        driverPhotoUrl: row.driverPhotoUrl.startsWith('https://')
            ? row.driverPhotoUrl
            : '',
      ),
    );
  }
  return offers;
}
