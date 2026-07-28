import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/chiron_dossier_grouping.dart';

class _Evt {
  _Evt({this.bookingId, this.tripId, this.eventId, this.createdAt});
  final String? bookingId;
  final String? tripId;
  final String? eventId;
  final String? createdAt;
}

Map<String, List<_Evt>> _group(List<_Evt> events) {
  return groupChironDossiers<_Evt>(
    events: events,
    identitiesOf: (e) => ChironEventIdentities(
      bookingIdRaw: e.bookingId,
      tripIdRaw: e.tripId,
      eventIdRaw: e.eventId,
      createdAtUtcRaw: e.createdAt,
    ),
  );
}

void main() {
  group('groupChironDossiers', () {
    test('8. START trip+booking STOP booking+trip group as one ride', () {
      final grouped = _group([
        _Evt(bookingId: 'B1', tripId: 'T1', eventId: 'e-start'),
        _Evt(bookingId: 'B1', tripId: 'T1', eventId: 'e-stop'),
      ]);
      expect(grouped.length, 1);
      expect(grouped.keys.single, 'booking:b1');
      expect(grouped.values.single.length, 2);
    });

    test('9. reversed arrival order produces the same canonical ride', () {
      final forward = _group([
        _Evt(tripId: 'T1', eventId: 'e1'),
        _Evt(bookingId: 'B1', tripId: 'T1', eventId: 'e2'),
      ]);
      final reversed = _group([
        _Evt(bookingId: 'B1', tripId: 'T1', eventId: 'e2'),
        _Evt(tripId: 'T1', eventId: 'e1'),
      ]);
      expect(forward.keys.single, 'booking:b1');
      expect(reversed.keys.single, 'booking:b1');
      expect(forward.values.single.length, 2);
      expect(reversed.values.single.length, 2);
    });

    test('10. direct ride without booking_id remains trip-based', () {
      final grouped = _group([
        _Evt(tripId: 'T9', eventId: 's'),
        _Evt(tripId: 'T9', eventId: 'e'),
      ]);
      expect(grouped.keys.single, 'trip:t9');
    });

    test('11. unrelated trip_id/booking_id records remain separate', () {
      final grouped = _group([
        _Evt(tripId: 'T1', eventId: 'a'),
        _Evt(bookingId: 'B2', eventId: 'b'),
      ]);
      expect(grouped.length, 2);
    });

    test('12. retry/duplicate events do not duplicate the displayed ride', () {
      final grouped = _group([
        _Evt(bookingId: 'B1', tripId: 'T1', eventId: 'e1'),
        _Evt(bookingId: 'B1', tripId: 'T1', eventId: 'e1-retry'),
        _Evt(bookingId: 'B1', tripId: 'T1', eventId: 'e2'),
      ]);
      expect(grouped.length, 1);
      expect(grouped.values.single.length, 3);
    });

    test('13. planned ride behavior remains booking-canonical', () {
      final grouped = _group([
        _Evt(bookingId: 'PB1', eventId: 'ps'),
        _Evt(bookingId: 'PB1', tripId: 'PT1', eventId: 'pe'),
      ]);
      expect(grouped.keys.single, 'booking:pb1');
      expect(grouped.values.single.length, 2);
    });

    test('never invents equivalence without same-event alias', () {
      // START trip-only and STOP booking-only with NO shared event alias
      // must remain separate — Flutter must not guess.
      final grouped = _group([
        _Evt(tripId: 'T1', eventId: 'start'),
        _Evt(bookingId: 'B1', eventId: 'stop'),
      ]);
      expect(grouped.length, 2);
    });

    test('legacy START trip-only + STOP with both ids unifies via alias', () {
      final grouped = _group([
        _Evt(tripId: 'T1', eventId: 'start'),
        _Evt(bookingId: 'B1', tripId: 'T1', eventId: 'stop'),
      ]);
      expect(grouped.length, 1);
      expect(grouped.keys.single, 'booking:b1');
    });
  });
}
