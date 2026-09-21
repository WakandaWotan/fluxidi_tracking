/// Reads `GET /partners/availability`.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// `lib/customer_booking/customer_booking_company_vehicles.dart` —
/// `CustomerBookingAvailabilitySnapshot`, `parseCustomerBookingAvailability`.
///
/// A vehicle is only available when the server says `available: true`.
library;

class FluxidiAvailabilityRow {
  const FluxidiAvailabilityRow({
    required this.vehicleId,
    required this.available,
    this.reason = '',
    this.driverId = '',
    this.driverDisplayName = '',
    this.driverPhotoUrl = '',
    this.passengerSeats,
  });

  final String vehicleId;
  final bool available;

  /// Server reason when unavailable, e.g. `no_driver`.
  final String reason;

  final String driverId;

  /// Only what the company published for public display.
  final String driverDisplayName;
  final String driverPhotoUrl;

  /// Seats as stated by the server, never guessed.
  final int? passengerSeats;
}

class FluxidiAvailabilitySnapshot {
  const FluxidiAvailabilitySnapshot({
    this.rows = const <FluxidiAvailabilityRow>[],
    this.fetched = false,
    this.loadFailed = false,
    this.expiresAt,
  });

  final List<FluxidiAvailabilityRow> rows;
  final bool fetched;
  final bool loadFailed;
  final DateTime? expiresAt;

  Set<String> get availableIds => <String>{
    for (final row in rows)
      if (row.available) row.vehicleId,
  };

  Set<String> get unavailableIds => <String>{
    for (final row in rows)
      if (!row.available) row.vehicleId,
  };

  FluxidiAvailabilityRow? rowFor(String vehicleId) {
    for (final row in rows) {
      if (row.vehicleId == vehicleId) return row;
    }
    return null;
  }

  bool get hasAnyAvailable => availableIds.isNotEmpty;
}

int? _seats(Map<String, dynamic> row) {
  for (final key in const <String>[
    'passenger_seats',
    'passengerSeats',
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

String _text(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = (row[key] ?? '').toString().trim();
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return '';
}

FluxidiAvailabilitySnapshot parseFluxidiAvailability(Object? decoded) {
  if (decoded is! Map) {
    return const FluxidiAvailabilitySnapshot(loadFailed: true, fetched: true);
  }
  final root = Map<String, dynamic>.from(decoded);
  if (root['ok'] == false) {
    return const FluxidiAvailabilitySnapshot(loadFailed: true, fetched: true);
  }
  final raw = root['vehicles'];
  if (raw is! List) {
    return const FluxidiAvailabilitySnapshot(loadFailed: true, fetched: true);
  }

  final rows = <FluxidiAvailabilityRow>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final row = Map<String, dynamic>.from(item);
    final id = _text(row, const <String>['vehicle_id', 'vehicleId']);
    if (id.isEmpty) continue;
    rows.add(
      FluxidiAvailabilityRow(
        vehicleId: id,
        available: row['available'] == true,
        reason: _text(row, const <String>['reason']),
        driverId: _text(row, const <String>['driver_id', 'driverId']),
        driverDisplayName: _text(row, const <String>[
          'public_display_name',
          'publicDisplayName',
          'display_name',
          'displayName',
        ]),
        driverPhotoUrl: _text(row, const <String>[
          'public_photo_url',
          'publicPhotoUrl',
          'photo_url',
          'photoUrl',
        ]),
        passengerSeats: _seats(row),
      ),
    );
  }

  DateTime? expiresAt;
  final rawExpiry = root['expires_at'] ?? root['expiresAt'];
  if (rawExpiry != null) {
    expiresAt = DateTime.tryParse(rawExpiry.toString().trim())?.toUtc();
  }

  return FluxidiAvailabilitySnapshot(
    rows: rows,
    fetched: true,
    expiresAt: expiresAt,
  );
}
