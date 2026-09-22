/// Public customer-facing booking references versus internal booking IDs.
///
/// The worker stores both:
/// * `booking_id` — internal id used for `GET /bookings/{id}`
/// * `public_booking_reference` — the number shown as "Ref."
///
/// Never derive one from the other by padding zeros or subtracting.
library;

bool isDistinctPublicCustomerReference({
  required String bookingId,
  required String candidate,
}) {
  final id = bookingId.trim();
  final value = candidate.trim();
  if (value.isEmpty) return false;
  final normalized = value.toLowerCase();
  if (normalized == 'null' || normalized == 'undefined' || value == '-') {
    return false;
  }
  if (id.isNotEmpty && normalized == id.toLowerCase()) return false;
  return true;
}

String distinctPublicCustomerReference({
  required String bookingId,
  required Iterable<String?> candidates,
}) {
  for (final candidate in candidates) {
    final value = (candidate ?? '').trim();
    if (isDistinctPublicCustomerReference(
      bookingId: bookingId,
      candidate: value,
    )) {
      return value;
    }
  }
  return '';
}

String customerFacingBookingReference({
  required String bookingId,
  required Iterable<String?> publicCandidates,
}) {
  final visible = distinctPublicCustomerReference(
    bookingId: bookingId,
    candidates: publicCandidates,
  );
  if (visible.isNotEmpty) return visible;
  return bookingId.trim();
}
