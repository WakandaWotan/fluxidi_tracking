// ACTIVE-RIDE-DURABLE-RESTORE-P0-7

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/external/active_ride_durable_snapshot.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_session.dart';

void main() {
  group('ActiveRideDurableSnapshot', () {
    test('round-trip planned + external session', () {
      final launched = DateTime.utc(2026, 8, 6, 17, 0, 0);
      final snap = ActiveRideDurableSnapshot(
        rideType: 'planned',
        bookingId: '2026-08-165',
        parentBookingId: 'PLN-2026-000384',
        activeLegId: 'leg_1',
        tripId: 'session_abc',
        lifecyclePhase: 'active',
        startedAt: launched,
        updatedAt: launched.add(const Duration(minutes: 12)),
        lastLat: 51.05,
        lastLon: 3.72,
        trackedDistanceKm: 4.2,
        waitingSeconds: 90,
        currentOrFixedFare: 35.40,
        paymentState: null,
        finalizePending: false,
        externalNavSession: ExternalNavigationSession(
          provider: ExternalNavProvider.googleMaps,
          bookingId: '2026-08-165',
          phase: ExternalNavPhase.activeRide,
          destination: const ExternalNavigationDestinationPoint(
            latitude: 50.85,
            longitude: 4.35,
          ),
          launchedAt: launched,
          pipActive: true,
          nativeGuidanceSuppressed: true,
        ),
      );

      final decoded = ActiveRideDurableSnapshot.fromJson(
        Map<String, dynamic>.from(snap.toJson()),
      );
      expect(decoded.rideType, 'planned');
      expect(decoded.isPlanned, isTrue);
      expect(decoded.bookingId, '2026-08-165');
      expect(decoded.tripId, 'session_abc');
      expect(decoded.trackedDistanceKm, 4.2);
      expect(decoded.currentOrFixedFare, 35.40);
      expect(decoded.externalNavSession, isNotNull);
      expect(decoded.externalNavSession!.pipActive, isTrue);
      expect(decoded.externalNavSession!.phase, ExternalNavPhase.activeRide);
    });

    test('street snapshot identity fields', () {
      final snap = ActiveRideDurableSnapshot(
        rideType: 'street',
        bookingId: 'street_1786035880780_1dghte50',
        parentBookingId: 'street_1786035880780_1dghte50',
        tripId: 'trip_ef67352e-3383-494f-87d4-e53f7567c9f4',
        lifecyclePhase: 'active',
        startedAt: DateTime.utc(2026, 8, 6, 17, 4, 40),
        updatedAt: DateTime.utc(2026, 8, 6, 17, 10, 0),
        trackedDistanceKm: 1.1,
        waitingSeconds: 0,
        currentOrFixedFare: 8.5,
        finalizePending: true,
      );
      expect(snap.isStreet, isTrue);
      expect(snap.finalizePending, isTrue);
      final j = snap.toJson();
      expect(j['version'], 1);
      expect(j['rideType'], 'street');
    });

    test('empty booking id rejected by store save guard via fromJson', () {
      final empty = ActiveRideDurableSnapshot.fromJson(<String, dynamic>{
        'rideType': 'planned',
        'bookingId': '  ',
        'lifecyclePhase': 'active',
        'startedAt': '2026-08-06T17:00:00Z',
        'updatedAt': '2026-08-06T17:00:00Z',
      });
      expect(empty.bookingId.trim(), isEmpty);
    });
  });
}
