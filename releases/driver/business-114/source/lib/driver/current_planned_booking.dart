/// Current driver agenda only. Past bookings remain in history; this does not
/// cancel them or release a physical trip that is still running.
bool driverPlannedBookingIsCurrent({
  required String? pickupIso,
  required DateTime now,
  bool physicalTripRunning = false,
}) {
  if (physicalTripRunning) return true;
  final pickup = DateTime.tryParse((pickupIso ?? '').trim());
  if (pickup == null) return true;
  final localNow = now.toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  return !pickup.toLocal().isBefore(today);
}
