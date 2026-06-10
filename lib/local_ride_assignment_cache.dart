/// Resolved driver / vehicle label cache for the Local Ride Register
/// dashboard cards.
///
/// Compliance ledger entries (the source of the Local Ride Register list)
/// typically carry only `driver_id` and `vehicle_id` — no display names. The
/// receipt page already hydrates the full trip / booking record via
/// `_hydrateRegisterReceiptJson` (see `lib/main.dart`), which yields a merged
/// JSON containing rich driver/vehicle information. Whenever that hydration
/// runs, we extract the human-readable labels and store them here so the
/// dashboard cards can show "John Doe · ABC-123" instead of falling back to
/// "Driver not linked" / "Vehicle not linked".
///
/// The cache is in-memory only (not persisted) and intentionally minimal:
/// it never holds tokens, phone numbers, e-mail, or full IDs — only the
/// display labels the receipt itself shows.
library;

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/compliance_ledger_reader.dart';

class LocalRideAssignmentInfo {
  const LocalRideAssignmentInfo({this.driverLabel, this.vehicleLabel});

  final String? driverLabel;
  final String? vehicleLabel;

  bool get isEmpty =>
      (driverLabel == null || driverLabel!.trim().isEmpty) &&
      (vehicleLabel == null || vehicleLabel!.trim().isEmpty);
}

/// Keyed by `booking_id` and `trip_id`. We populate both indexes (when
/// available) so a Local Ride Register row that has only one of the IDs can
/// still benefit from a previously cached label set.
final Map<String, LocalRideAssignmentInfo> _byBookingId =
    <String, LocalRideAssignmentInfo>{};
final Map<String, LocalRideAssignmentInfo> _byTripId =
    <String, LocalRideAssignmentInfo>{};

/// Revision counter that listeners (e.g. the Local Ride Register dashboard)
/// observe via `ValueListenableBuilder` to rebuild whenever an entry is
/// added or updated. Avoids stale "Driver not linked" / "Vehicle not linked"
/// labels lingering on cards after the receipt opens or background prewarm
/// completes.
final ValueNotifier<int> localRideAssignmentCacheRevision = ValueNotifier<int>(
  0,
);

void _bumpRevision() {
  localRideAssignmentCacheRevision.value =
      localRideAssignmentCacheRevision.value + 1;
}

void recordLocalRideAssignment({
  required String? bookingId,
  required String? tripId,
  required LocalRideAssignmentInfo info,
}) {
  if (info.isEmpty) return;
  final b = (bookingId ?? '').trim();
  final t = (tripId ?? '').trim();
  var changed = false;
  if (b.isNotEmpty) {
    final existing = _byBookingId[b];
    final next = LocalRideAssignmentInfo(
      driverLabel: info.driverLabel ?? existing?.driverLabel,
      vehicleLabel: info.vehicleLabel ?? existing?.vehicleLabel,
    );
    if (existing == null ||
        existing.driverLabel != next.driverLabel ||
        existing.vehicleLabel != next.vehicleLabel) {
      _byBookingId[b] = next;
      changed = true;
    }
  }
  if (t.isNotEmpty) {
    final existing = _byTripId[t];
    final next = LocalRideAssignmentInfo(
      driverLabel: info.driverLabel ?? existing?.driverLabel,
      vehicleLabel: info.vehicleLabel ?? existing?.vehicleLabel,
    );
    if (existing == null ||
        existing.driverLabel != next.driverLabel ||
        existing.vehicleLabel != next.vehicleLabel) {
      _byTripId[t] = next;
      changed = true;
    }
  }
  if (changed) _bumpRevision();
}

// ---------------------------------------------------------------------------
// Background prewarm handler.
//
// The dashboard renders cards synchronously, but compliance ledger entries
// usually do not carry driver/vehicle names. When a card resolves to
// "not linked", the dashboard requests a prewarm — a non-blocking call that
// runs the same hydration pipeline the receipt page uses
// (`_hydrateRegisterReceiptJson` in `lib/main.dart`) and records the result.
// On completion the revision notifier above triggers a card rebuild.
//
// `main.dart` registers the handler at app startup; libraries that don't
// have access to `main.dart`'s private hydration can still call
// `requestLocalRideAssignmentPrewarm(entry)` and let it short-circuit if no
// handler was registered (e.g. unit tests).
// ---------------------------------------------------------------------------

typedef LocalRideAssignmentPrewarmHandler =
    Future<void> Function(ComplianceLedgerEntry entry);

LocalRideAssignmentPrewarmHandler? _prewarmHandler;

void registerLocalRideAssignmentPrewarmHandler(
  LocalRideAssignmentPrewarmHandler? handler,
) {
  _prewarmHandler = handler;
}

/// Per-session dedup so background hydration runs at most once per booking
/// or trip during the app's lifetime. Prevents accidental re-fetching when
/// the dashboard rebuilds (e.g. on theme change, hot reload, or revision
/// bump).
final Set<String> _prewarmInFlightOrDone = <String>{};

/// Asynchronously kicks off hydration for [entry] if no assignment has been
/// resolved yet for its booking_id / trip_id. Non-blocking and safe to call
/// from `build()` — the handler is invoked once per booking/trip and any
/// resulting cache writes wake the [localRideAssignmentCacheRevision]
/// listeners so the visible card refreshes.
void requestLocalRideAssignmentPrewarm(ComplianceLedgerEntry entry) {
  final handler = _prewarmHandler;
  if (handler == null) return;

  final b = entry.bookingId.trim();
  final t = entry.tripId.trim();
  if (b.isEmpty && t.isEmpty) return;

  // If we already have a record (full or partial), do not re-fetch.
  final cached = lookupLocalRideAssignment(bookingId: b, tripId: t);
  if (cached != null && !cached.isEmpty) return;

  final key = 'b:$b|t:$t';
  if (_prewarmInFlightOrDone.contains(key)) return;
  _prewarmInFlightOrDone.add(key);

  // Fire-and-forget. Errors are swallowed inside `main.dart`'s handler so
  // we never crash the dashboard build.
  Future.microtask(() async {
    try {
      await handler(entry);
    } catch (_) {
      // Allow a later retry only if the handler raised; the cache is
      // otherwise the source of truth for "already attempted".
      _prewarmInFlightOrDone.remove(key);
    }
  });
}

LocalRideAssignmentInfo? lookupLocalRideAssignment({
  required String? bookingId,
  required String? tripId,
}) {
  final b = (bookingId ?? '').trim();
  final t = (tripId ?? '').trim();
  final byBooking = b.isEmpty ? null : _byBookingId[b];
  final byTrip = t.isEmpty ? null : _byTripId[t];
  if (byBooking == null && byTrip == null) return null;
  return LocalRideAssignmentInfo(
    driverLabel: byBooking?.driverLabel ?? byTrip?.driverLabel,
    vehicleLabel: byBooking?.vehicleLabel ?? byTrip?.vehicleLabel,
  );
}

/// Extracts a human-readable driver / vehicle label pair from a merged
/// trip-history JSON (the same shape `_TripHistoryItem.fromJson` consumes).
///
/// Prefers display-quality names over IDs:
///   - driver: `driver.name` / `driver.full_name` / `driver_name` /
///     `assigned_driver(.name|.full_name)` / `employee_number` / etc.
///   - vehicle: `vehicle.label` / `vehicle.name` / `vehicle_label` /
///     `vehicle.license_plate` / `assigned_vehicle(.label|.name)` / etc.
/// Returns `null` per field when no display-quality candidate exists; raw
/// IDs alone are NOT returned (the dashboard keeps profile lookup +
/// "not linked" / "profile not found" fallbacks intact).
LocalRideAssignmentInfo extractLocalRideAssignmentFromMergedJson(
  Map<String, dynamic> merged,
) {
  Map<String, dynamic> asMap(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
  String? cleanText(Object? value) {
    if (value == null) return null;
    if (value is Map || value is Iterable) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    if (text == '—' || text == '-') return null;
    return text;
  }

  String? pickFromMap(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final t = cleanText(map[key]);
      if (t != null) return t;
    }
    return null;
  }

  String? pickFirst(List<Object?> values) {
    for (final v in values) {
      final t = cleanText(v);
      if (t != null) return t;
    }
    return null;
  }

  String? composeVehicle({
    required String? primary,
    required String? plate,
    required String? brand,
    required String? model,
  }) {
    if (primary != null && plate != null && primary != plate) {
      return '$primary · $plate';
    }
    if (primary != null) return primary;
    if (brand != null && model != null && plate != null) {
      return '$brand $model · $plate';
    }
    if (brand != null && model != null) return '$brand $model';
    if (plate != null) return plate;
    if (brand != null) return brand;
    if (model != null) return model;
    return null;
  }

  final root = merged;
  final bookingDetails = asMap(merged['booking_details']);
  final booking = asMap(merged['booking']);
  final record = asMap(merged['record']);
  final recordBooking = asMap(record['booking']);
  final recordPayload = asMap(record['payload']);
  final payload = asMap(merged['payload']);
  final driverMap = asMap(merged['driver']);
  final bookingDriver = asMap(booking['driver']);
  final recordBookingDriver = asMap(recordBooking['driver']);
  final assignedDriver = asMap(merged['assigned_driver']);
  final assignedDriverCamel = asMap(merged['assignedDriver']);
  final bookingAssignedDriver = asMap(booking['assigned_driver']);
  final bookingAssignedDriverCamel = asMap(booking['assignedDriver']);
  final recordBookingAssignedDriver = asMap(recordBooking['assigned_driver']);
  final recordBookingAssignedDriverCamel = asMap(
    recordBooking['assignedDriver'],
  );
  final vehicleMap = asMap(merged['vehicle']);
  final bookingVehicle = asMap(booking['vehicle']);
  final recordBookingVehicle = asMap(recordBooking['vehicle']);
  final assignedVehicle = asMap(merged['assigned_vehicle']);
  final assignedVehicleCamel = asMap(merged['assignedVehicle']);
  final bookingAssignedVehicle = asMap(booking['assigned_vehicle']);
  final bookingAssignedVehicleCamel = asMap(booking['assignedVehicle']);
  final recordBookingAssignedVehicle = asMap(recordBooking['assigned_vehicle']);
  final recordBookingAssignedVehicleCamel = asMap(
    recordBooking['assignedVehicle'],
  );

  const driverNameKeys = <String>[
    'name',
    'full_name',
    'fullName',
    'display_name',
    'displayName',
    'driver_name',
    'driverName',
  ];
  final driverNested = pickFirst(<Object?>[
    pickFromMap(driverMap, driverNameKeys),
    pickFromMap(bookingDriver, driverNameKeys),
    pickFromMap(recordBookingDriver, driverNameKeys),
    pickFromMap(assignedDriver, driverNameKeys),
    pickFromMap(assignedDriverCamel, driverNameKeys),
    pickFromMap(bookingAssignedDriver, driverNameKeys),
    pickFromMap(bookingAssignedDriverCamel, driverNameKeys),
    pickFromMap(recordBookingAssignedDriver, driverNameKeys),
    pickFromMap(recordBookingAssignedDriverCamel, driverNameKeys),
  ]);
  final driverFlat = pickFirst(<Object?>[
    root['driver_name'],
    root['driverName'],
    root['assigned_driver_name'],
    root['assignedDriverName'],
    root['driver_label'],
    root['driverLabel'],
    root['chauffeur_name'],
    root['chauffeurName'],
    root['employee_number'],
    root['employeeNumber'],
    bookingDetails['driver_name'],
    bookingDetails['driverName'],
    bookingDetails['assigned_driver_name'],
    bookingDetails['assignedDriverName'],
    bookingDetails['driver_label'],
    bookingDetails['driverLabel'],
    bookingDetails['employee_number'],
    bookingDetails['employeeNumber'],
    booking['driver_name'],
    booking['driverName'],
    booking['assigned_driver_name'],
    booking['assignedDriverName'],
    booking['driver_label'],
    booking['driverLabel'],
    booking['employee_number'],
    booking['employeeNumber'],
    recordBooking['driver_name'],
    recordBooking['driverName'],
    recordBooking['assigned_driver_name'],
    recordBooking['assignedDriverName'],
    record['driver_name'],
    record['driverName'],
    record['assigned_driver_name'],
    record['assignedDriverName'],
    record['driver_label'],
    record['driverLabel'],
    payload['driver_name'],
    payload['driverName'],
    recordPayload['driver_name'],
    recordPayload['driverName'],
  ]);
  final driverLabel = driverNested ?? driverFlat;

  const vehicleLabelKeys = <String>[
    'label',
    'name',
    'display_label',
    'displayLabel',
    'vehicle_label',
    'vehicleLabel',
    'vehicle_name',
    'vehicleName',
  ];
  const plateKeys = <String>[
    'license_plate',
    'licensePlate',
    'plate',
    'registration_number',
    'registrationNumber',
  ];
  String? primaryFromMap(Map<String, dynamic> map) =>
      pickFromMap(map, vehicleLabelKeys);
  String? plateFromMap(Map<String, dynamic> map) => pickFromMap(map, plateKeys);
  final vehicleNestedPrimary = pickFirst(<Object?>[
    primaryFromMap(vehicleMap),
    primaryFromMap(bookingVehicle),
    primaryFromMap(recordBookingVehicle),
    primaryFromMap(assignedVehicle),
    primaryFromMap(assignedVehicleCamel),
    primaryFromMap(bookingAssignedVehicle),
    primaryFromMap(bookingAssignedVehicleCamel),
    primaryFromMap(recordBookingAssignedVehicle),
    primaryFromMap(recordBookingAssignedVehicleCamel),
  ]);
  final vehicleNestedPlate = pickFirst(<Object?>[
    plateFromMap(vehicleMap),
    plateFromMap(bookingVehicle),
    plateFromMap(recordBookingVehicle),
    plateFromMap(assignedVehicle),
    plateFromMap(assignedVehicleCamel),
    plateFromMap(bookingAssignedVehicle),
    plateFromMap(bookingAssignedVehicleCamel),
    plateFromMap(recordBookingAssignedVehicle),
    plateFromMap(recordBookingAssignedVehicleCamel),
  ]);
  final vehicleFlatPrimary = pickFirst(<Object?>[
    root['vehicle_label'],
    root['vehicleLabel'],
    root['vehicle_name'],
    root['vehicleName'],
    root['assigned_vehicle_name'],
    root['assignedVehicleName'],
    root['assigned_vehicle_label'],
    root['assignedVehicleLabel'],
    bookingDetails['vehicle_label'],
    bookingDetails['vehicleLabel'],
    bookingDetails['vehicle_name'],
    bookingDetails['vehicleName'],
    bookingDetails['assigned_vehicle_name'],
    bookingDetails['assignedVehicleName'],
    booking['vehicle_label'],
    booking['vehicleLabel'],
    booking['vehicle_name'],
    booking['vehicleName'],
    booking['assigned_vehicle_name'],
    booking['assignedVehicleName'],
    recordBooking['vehicle_label'],
    recordBooking['vehicleLabel'],
    recordBooking['vehicle_name'],
    recordBooking['vehicleName'],
    record['vehicle_label'],
    record['vehicleLabel'],
    record['vehicle_name'],
    record['vehicleName'],
    payload['vehicle_label'],
    payload['vehicleLabel'],
    recordPayload['vehicle_label'],
    recordPayload['vehicleLabel'],
  ]);
  final vehicleFlatPlate = pickFirst(<Object?>[
    root['license_plate'],
    root['licensePlate'],
    root['plate'],
    root['registration_number'],
    root['registrationNumber'],
    bookingDetails['license_plate'],
    bookingDetails['licensePlate'],
    bookingDetails['plate'],
    booking['license_plate'],
    booking['licensePlate'],
    booking['plate'],
    recordBooking['license_plate'],
    recordBooking['licensePlate'],
    record['license_plate'],
    record['licensePlate'],
  ]);
  final vehiclePlate = vehicleNestedPlate ?? vehicleFlatPlate;
  final vehiclePrimary = vehicleNestedPrimary ?? vehicleFlatPrimary;
  final vehicleBrand = pickFirst(<Object?>[
    vehicleMap['make'],
    vehicleMap['brand'],
    bookingVehicle['make'],
    bookingVehicle['brand'],
    recordBookingVehicle['make'],
    recordBookingVehicle['brand'],
  ]);
  final vehicleModel = pickFirst(<Object?>[
    vehicleMap['model'],
    bookingVehicle['model'],
    recordBookingVehicle['model'],
  ]);
  final vehicleLabel = composeVehicle(
    primary: vehiclePrimary,
    plate: vehiclePlate,
    brand: vehicleBrand,
    model: vehicleModel,
  );

  return LocalRideAssignmentInfo(
    driverLabel: driverLabel,
    vehicleLabel: vehicleLabel,
  );
}
