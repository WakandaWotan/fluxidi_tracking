import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/current_planned_booking.dart';

void main() {
  final today = DateTime(2026, 10, 4, 11);
  test('week-old and yesterday reservations leave current agenda', () {
    for (final pickup in ['2026-09-27T13:00:00', '2026-10-03T23:59:59']) {
      expect(driverPlannedBookingIsCurrent(pickupIso: pickup, now: today), false);
    }
  });
  test('today including a delayed pickup and future dates remain visible', () {
    for (final pickup in ['2026-10-04T00:00:00', '2026-10-04T10:55:00', '2026-10-05T13:00:00']) {
      expect(driverPlannedBookingIsCurrent(pickupIso: pickup, now: today), true);
    }
  });
  test('an overnight physical trip remains operable', () {
    expect(driverPlannedBookingIsCurrent(pickupIso: '2026-10-03T23:30:00', now: today, physicalTripRunning: true), true);
  });
  test('midnight changes eligibility without modifying booking status', () {
    expect(driverPlannedBookingIsCurrent(pickupIso: '2026-10-04T23:00:00', now: DateTime(2026, 10, 5)), false);
  });
  test('unknown date stays visible for resolution and UTC uses local day', () {
    expect(driverPlannedBookingIsCurrent(pickupIso: 'unknown', now: today), true);
    final instant = DateTime(2026, 10, 4, 0, 1).toUtc().toIso8601String();
    expect(driverPlannedBookingIsCurrent(pickupIso: instant, now: today), true);
  });
}
