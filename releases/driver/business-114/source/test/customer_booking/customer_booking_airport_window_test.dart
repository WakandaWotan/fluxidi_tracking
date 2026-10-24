import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_airport_window.dart';

void main() {
  final now = DateTime.utc(2026, 10, 9, 12);
  bool blocked(
    DateTime? pickup, {
    bool airport = true,
    bool asap = false,
    double? hours = 48,
  }) => customerBookingAirportWindowBlocked(
    airport: airport,
    minimumHours: hours,
    whenNow: asap,
    pickup: pickup,
    now: now,
  );
  test('airport window: below, exactly and above company lead time', () {
    expect(
      blocked(
        now
            .add(const Duration(hours: 48))
            .subtract(const Duration(microseconds: 1)),
      ),
      isTrue,
    );
    expect(blocked(now.add(const Duration(hours: 48))), isFalse);
    expect(
      blocked(now.add(const Duration(hours: 48, microseconds: 1))),
      isFalse,
    );
    expect(blocked(null), isTrue);
    expect(blocked(now.add(const Duration(hours: 72)), asap: true), isTrue);
  });
  test('ordinary taxi and other company policies stay independent', () {
    expect(blocked(null, airport: false, asap: true), isFalse);
    expect(blocked(null, hours: null, asap: true), isFalse);
    expect(blocked(now.add(const Duration(hours: 25)), hours: 24), isFalse);
    expect(blocked(now.add(const Duration(hours: 23)), hours: 24), isTrue);
  });
}
