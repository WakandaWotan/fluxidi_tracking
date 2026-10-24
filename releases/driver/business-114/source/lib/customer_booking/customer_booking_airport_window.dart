/// Presentation/confirmation guard for a company-defined airport lead time.
/// The server quote remains authoritative for price and actual availability.
bool customerBookingAirportWindowBlocked({
  required bool airport,
  required double? minimumHours,
  required bool whenNow,
  required DateTime? pickup,
  required DateTime now,
}) {
  if (!airport ||
      minimumHours == null ||
      !minimumHours.isFinite ||
      minimumHours <= 0)
    return false;
  if (whenNow || pickup == null) return true;
  return pickup.isBefore(
    now.add(
      Duration(
        microseconds: (minimumHours * Duration.microsecondsPerHour).round(),
      ),
    ),
  );
}
