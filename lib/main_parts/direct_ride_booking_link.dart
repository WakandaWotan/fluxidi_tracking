/// Street-ride (direct ride) <-> company booking linking helpers.
///
/// A "street ride" is implemented as a direct ride (`ride_type: direct`).
/// Historically it lived only in the Tracking Worker + local compliance
/// ledger and never produced a Booking Worker record, so completed street
/// rides could not appear in the company Bookings screen.
///
/// These pure, dependency-free helpers build the START/STOP payloads, parse
/// the start response, and decide the compliance-ledger `booking_id`, so the
/// linking contract can be unit-tested without pumping the driver home widget
/// (which needs Mapbox / geolocation / http).
library;

/// Canonical source tag written on street-ride bookings.
const String kStreetRideBookingSource = 'street_ride';

/// Canonical `ride_type` for direct/street rides.
const String kStreetRideRideType = 'direct';

/// Lifecycle status token for an active street ride.
///
/// MUST be a token the company bookings bucketer (`_bucketFromStatus` in
/// `company_bookings_helpers.dart`) maps to the "Open / gepland" bucket:
/// `IN_PROGRESS` is neither cancelled nor completed, so it falls into the
/// default `open` bucket.
const String kStreetRideStatusInProgress = 'IN_PROGRESS';

/// Lifecycle status token for a finalized street ride.
///
/// MUST be a token the company bookings bucketer maps to the
/// "Afgerond / voltooid" bucket: it contains `COMPLETE`.
const String kStreetRideStatusCompleted = 'COMPLETED';

/// Company-bookings tab bucket, mirrored 1:1 from `_bucketFromStatus`
/// (`company_bookings_helpers.dart`). Kept here so tests can assert the
/// street-ride status tokens land in the intended tabs without importing the
/// private `part of main.dart` bucketer.
enum StreetRideCompanyBucket { open, completed, cancelled }

/// Mirror of `_normStatus` + `_bucketFromStatus` from the company bookings
/// screen. If that logic changes, this must be updated in lockstep (there is a
/// guard test asserting the mapping for the street-ride tokens).
StreetRideCompanyBucket streetRideCompanyBucket(String statusRaw) {
  final normalized =
      statusRaw.trim().toUpperCase().replaceAll('-', '_').replaceAll(' ', '_');
  if (normalized.contains('CANCEL')) return StreetRideCompanyBucket.cancelled;
  if (normalized == 'DELETED') return StreetRideCompanyBucket.cancelled;
  if (normalized.contains('COMPLETE') ||
      normalized == 'DONE' ||
      normalized == 'FINISHED') {
    return StreetRideCompanyBucket.completed;
  }
  return StreetRideCompanyBucket.open;
}

/// Stable idempotency key so a retried START call never creates a duplicate
/// booking. Derived from the driver id + start timestamp; it is stable for the
/// lifetime of a single ride and unique across rides.
String makeDirectRideKey({
  required String driverId,
  required int startedAtMs,
}) {
  final safeDriver = driverId.trim().isEmpty ? 'driver' : driverId.trim();
  return 'direct_${startedAtMs}_$safeDriver';
}

/// Extend an existing direct-trip START payload with the fields the backend
/// needs to create + link a street-ride booking. Returns a new map; the input
/// is not mutated.
Map<String, dynamic> withDirectRideBookingStartFields(
  Map<String, dynamic> base, {
  required String directRideKey,
}) {
  return <String, dynamic>{
    ...base,
    'source': kStreetRideBookingSource,
    'ride_type': kStreetRideRideType,
    'direct_ride_key': directRideKey,
    'booking_status': kStreetRideStatusInProgress,
  };
}

/// Parsed result of `POST /trip/start-direct`.
class DirectRideStartResult {
  const DirectRideStartResult({
    required this.ok,
    required this.tripId,
    required this.bookingId,
    required this.bookingLinkState,
  });

  final bool ok;
  final String tripId;

  /// Non-null only when the backend created + returned a linked booking.
  final String? bookingId;

  /// `linked` when a booking_id is present, `pending` when the ride started
  /// but no booking was linked yet (reconcilable), `unknown` on malformed or
  /// not-ok responses.
  final String bookingLinkState;

  bool get hasLinkedBooking => (bookingId ?? '').trim().isNotEmpty;
}

DirectRideStartResult parseDirectRideStartResponse(Object? decoded) {
  if (decoded is! Map) {
    return const DirectRideStartResult(
      ok: false,
      tripId: '',
      bookingId: null,
      bookingLinkState: 'unknown',
    );
  }
  final ok = decoded['ok'] == true;
  final tripId = (decoded['trip_id'] ?? decoded['tripId'] ?? '').toString().trim();
  final bookingIdRaw =
      (decoded['booking_id'] ?? decoded['bookingId'] ?? '').toString().trim();
  final bookingId = bookingIdRaw.isEmpty ? null : bookingIdRaw;
  final linkStateRaw =
      (decoded['booking_link_state'] ?? decoded['bookingLinkState'] ?? '')
          .toString()
          .trim();
  final linkState = linkStateRaw.isNotEmpty
      ? linkStateRaw
      : (bookingId != null ? 'linked' : 'pending');
  return DirectRideStartResult(
    ok: ok,
    tripId: tripId,
    bookingId: bookingId,
    bookingLinkState: ok ? linkState : 'unknown',
  );
}

/// Add booking linkage to a direct-trip STOP payload so the backend finalizes
/// the same booking record. Returns a new map; the input is not mutated. When
/// no booking is linked (local-only ride), the base payload is returned
/// unchanged so no empty `booking_id` is sent.
Map<String, dynamic> withDirectRideBookingStopFields(
  Map<String, dynamic> base, {
  required String? bookingId,
}) {
  final id = (bookingId ?? '').trim();
  if (id.isEmpty) return <String, dynamic>{...base};
  return <String, dynamic>{
    ...base,
    'booking_id': id,
    'source': kStreetRideBookingSource,
  };
}

/// The `booking_id` value to write into the compliance ledger for a direct
/// ride: the trimmed booking id when the ride is linked to a booking, else
/// null for a local-only ride. This replaces the previous unconditional
/// `booking_id: null` so a successfully linked direct ride is auditable.
String? complianceLedgerBookingId(String? bookingId) {
  final id = (bookingId ?? '').trim();
  return id.isEmpty ? null : id;
}
