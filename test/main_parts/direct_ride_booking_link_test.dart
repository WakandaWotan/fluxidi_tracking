import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/direct_ride_booking_link.dart';

/// STREET-RIDE-BOOKING-LIFECYCLE-IMPLEMENTATION-1 — client contract tests.
///
/// These cover the client-side, unit-testable slice of Parts B–H. The backend
/// (create/finalize + /trip orchestration) has no in-repo test harness and is
/// validated on staging; these tests pin the client<->backend contract:
/// the START/STOP payload shape, start-response parsing, the compliance-ledger
/// booking_id decision, the idempotency key, and the status->bucket mapping.
void main() {
  Map<String, dynamic> baseStartPayload({
    String tenant = 'tenantA',
    String company = 'companyA',
    String driver = 'driver-1',
    String vehicle = 'veh-1',
  }) {
    return <String, dynamic>{
      'tenant_id': tenant,
      'company_id': company,
      'tenantId': tenant,
      'companyId': company,
      'driver_id': driver,
      'vehicle_id': vehicle,
      'origin': <String, dynamic>{'lat': 1.0, 'lon': 2.0},
      'destination': <String, dynamic>{'label': 'Station'},
      'client_started_at': '2026-07-15T06:00:00.000Z',
    };
  }

  group('Part B/C: START payload creates + links a street-ride booking', () {
    test('driver start payload carries source, ride_type, key and status', () {
      final payload = withDirectRideBookingStartFields(
        baseStartPayload(),
        directRideKey: 'direct_123_driver-1',
      );
      expect(payload['source'], kStreetRideBookingSource);
      expect(payload['source'], 'street_ride');
      expect(payload['ride_type'], kStreetRideRideType);
      expect(payload['ride_type'], 'direct');
      expect(payload['direct_ride_key'], 'direct_123_driver-1');
      expect(payload['booking_status'], kStreetRideStatusInProgress);
      // Existing fields preserved.
      expect(payload['driver_id'], 'driver-1');
      expect(payload['vehicle_id'], 'veh-1');
    });

    test('Part G: tenant/company/driver/vehicle scope is preserved for a '
        'company-started ride', () {
      final payload = withDirectRideBookingStartFields(
        baseStartPayload(
          tenant: 'tenantX',
          company: 'companyX',
          driver: 'company-driver-9',
          vehicle: 'veh-9',
        ),
        directRideKey: 'direct_999_company-driver-9',
      );
      expect(payload['tenant_id'], 'tenantX');
      expect(payload['company_id'], 'companyX');
      expect(payload['tenantId'], 'tenantX');
      expect(payload['companyId'], 'companyX');
      expect(payload['driver_id'], 'company-driver-9');
      expect(payload['vehicle_id'], 'veh-9');
    });

    test('start payload construction does not mutate the input map', () {
      final base = baseStartPayload();
      withDirectRideBookingStartFields(base, directRideKey: 'k');
      expect(base.containsKey('source'), isFalse);
      expect(base.containsKey('direct_ride_key'), isFalse);
    });
  });

  group('Part A/B: parsing POST /trip/start-direct response', () {
    test('driver start: trip + booking linked', () {
      final result = parseDirectRideStartResponse(<String, dynamic>{
        'ok': true,
        'trip_id': 'trip-1',
        'booking_id': 'street_1_abc',
        'booking_link_state': 'linked',
      });
      expect(result.ok, isTrue);
      expect(result.tripId, 'trip-1');
      expect(result.bookingId, 'street_1_abc');
      expect(result.hasLinkedBooking, isTrue);
      expect(result.bookingLinkState, 'linked');
    });

    test('link_state defaults to linked when booking present but state absent',
        () {
      final result = parseDirectRideStartResponse(<String, dynamic>{
        'ok': true,
        'trip_id': 'trip-2',
        'booking_id': 'street_2_def',
      });
      expect(result.bookingLinkState, 'linked');
      expect(result.hasLinkedBooking, isTrue);
    });

    test('Part E-2: trip started but booking link pending (no booking_id)', () {
      final result = parseDirectRideStartResponse(<String, dynamic>{
        'ok': true,
        'trip_id': 'trip-3',
      });
      expect(result.ok, isTrue);
      expect(result.tripId, 'trip-3');
      expect(result.bookingId, isNull);
      expect(result.hasLinkedBooking, isFalse);
      expect(result.bookingLinkState, 'pending');
    });

    test('Part E-9: failed start yields no silent orphan link state', () {
      final notOk = parseDirectRideStartResponse(<String, dynamic>{
        'ok': false,
        'error': 'trip_not_assigned_to_driver',
      });
      expect(notOk.ok, isFalse);
      expect(notOk.bookingId, isNull);
      expect(notOk.bookingLinkState, 'unknown');

      final malformed = parseDirectRideStartResponse('not-a-map');
      expect(malformed.ok, isFalse);
      expect(malformed.tripId, isEmpty);
      expect(malformed.bookingId, isNull);
      expect(malformed.bookingLinkState, 'unknown');
    });
  });

  group('Part D/E: STOP payload links the booking for finalization', () {
    Map<String, dynamic> baseStop() => <String, dynamic>{
          'trip_id': 'trip-1',
          'tenant_id': 'tenantA',
          'company_id': 'companyA',
          'km_total': 4.2,
          'wait_seconds_total': 30,
        };

    test('linked ride sends booking_id + source so backend finalizes it', () {
      final payload = withDirectRideBookingStopFields(
        baseStop(),
        bookingId: 'street_1_abc',
      );
      expect(payload['booking_id'], 'street_1_abc');
      expect(payload['source'], 'street_ride');
      expect(payload['trip_id'], 'trip-1');
    });

    test('local-only ride sends no empty booking_id', () {
      final nullId = withDirectRideBookingStopFields(baseStop(), bookingId: null);
      expect(nullId.containsKey('booking_id'), isFalse);
      final emptyId =
          withDirectRideBookingStopFields(baseStop(), bookingId: '   ');
      expect(emptyId.containsKey('booking_id'), isFalse);
    });
  });

  group('Part C: compliance ledger booking_id (no longer always null)', () {
    test('linked ride writes the real booking_id', () {
      expect(complianceLedgerBookingId('street_1_abc'), 'street_1_abc');
      expect(complianceLedgerBookingId('  street_2  '), 'street_2');
    });

    test('local-only ride writes null', () {
      expect(complianceLedgerBookingId(null), isNull);
      expect(complianceLedgerBookingId(''), isNull);
      expect(complianceLedgerBookingId('   '), isNull);
    });
  });

  group('Part E-7: idempotency key prevents duplicate booking on retry', () {
    test('same driver + start time yields the same stable key', () {
      final a = makeDirectRideKey(driverId: 'driver-1', startedAtMs: 111);
      final b = makeDirectRideKey(driverId: 'driver-1', startedAtMs: 111);
      expect(a, equals(b));
      expect(a, 'direct_111_driver-1');
    });

    test('different rides yield different keys', () {
      final a = makeDirectRideKey(driverId: 'driver-1', startedAtMs: 111);
      final b = makeDirectRideKey(driverId: 'driver-1', startedAtMs: 222);
      expect(a, isNot(equals(b)));
    });

    test('empty driver id still yields a usable key', () {
      expect(makeDirectRideKey(driverId: '', startedAtMs: 5), 'direct_5_driver');
    });
  });

  group('Part F: status tokens land in the intended company Bookings tabs', () {
    test('Part H-3: active street ride (IN_PROGRESS) -> Open/gepland', () {
      expect(kStreetRideStatusInProgress, 'IN_PROGRESS');
      expect(
        streetRideCompanyBucket(kStreetRideStatusInProgress),
        StreetRideCompanyBucket.open,
      );
    });

    test('Part H-4/5: completed street ride (COMPLETED) -> Afgerond/voltooid',
        () {
      expect(kStreetRideStatusCompleted, 'COMPLETED');
      expect(
        streetRideCompanyBucket(kStreetRideStatusCompleted),
        StreetRideCompanyBucket.completed,
      );
    });

    test('bucket mirror matches the company bucketer for common tokens', () {
      expect(streetRideCompanyBucket('CANCELLED'),
          StreetRideCompanyBucket.cancelled);
      expect(streetRideCompanyBucket('cancelled'),
          StreetRideCompanyBucket.cancelled);
      expect(streetRideCompanyBucket('DELETED'),
          StreetRideCompanyBucket.cancelled);
      expect(streetRideCompanyBucket('DONE'),
          StreetRideCompanyBucket.completed);
      expect(streetRideCompanyBucket('SCHEDULED'), StreetRideCompanyBucket.open);
      expect(streetRideCompanyBucket('in-progress'),
          StreetRideCompanyBucket.open);
    });
  });

  // ==========================================================================
  // DIRECT-RIDE-EXISTING-BOOKING-OWNERSHIP-1 — reopen safety helpers.
  //
  // These tests pin the single shared classification and resume-identity
  // resolution that the driver-home reopen path relies on. They exercise the
  // contract that:
  //   * every plausible street/direct signal classifies as street/direct;
  //   * ordinary planned bookings are never misclassified;
  //   * a resume can only proceed when BOTH tracking_trip_id AND
  //     direct_ride_key are supplied authoritatively;
  //   * missing identity yields streetUnavailable and never planned.
  // ==========================================================================

  group('DIRECT-RIDE-EXISTING-BOOKING-OWNERSHIP-1: isStreetDirectBooking', () {
    test('classifies a `street_` booking id as direct', () {
      expect(
        isStreetDirectBooking(<String, dynamic>{
          'booking_id': 'street_1721760000_abc123',
        }),
        isTrue,
      );
      expect(
        isStreetDirectBooking(<String, dynamic>{
          'bookingId': 'STREET_9999_zzz',
        }),
        isTrue,
      );
    });

    test('classifies source == `street_ride` as direct', () {
      expect(
        isStreetDirectBooking(<String, dynamic>{
          'booking_id': 'BK-1',
          'source': 'street_ride',
        }),
        isTrue,
      );
      expect(
        isStreetDirectBooking(<String, dynamic>{
          'booking_id': 'BK-2',
          'booking_source': 'street_ride',
        }),
        isTrue,
      );
    });

    test('classifies ride_type == `direct` as direct', () {
      expect(
        isStreetDirectBooking(<String, dynamic>{
          'booking_id': 'BK-3',
          'ride_type': 'direct',
        }),
        isTrue,
      );
      expect(
        isStreetDirectBooking(<String, dynamic>{
          'booking_id': 'BK-4',
          'rideType': 'DIRECT',
        }),
        isTrue,
      );
    });

    test('classifies nested booking.source / booking.ride_type', () {
      expect(
        isStreetDirectBooking(<String, dynamic>{
          'booking_id': 'BK-5',
          'booking': <String, dynamic>{'source': 'street_ride'},
        }),
        isTrue,
      );
      expect(
        isStreetDirectBooking(<String, dynamic>{
          'booking_id': 'BK-6',
          'booking': <String, dynamic>{'ride_type': 'direct'},
        }),
        isTrue,
      );
    });

    test('does NOT classify an ordinary planned booking as direct', () {
      expect(
        isStreetDirectBooking(<String, dynamic>{
          'booking_id': 'BK-1234',
          'source': 'planned',
          'ride_type': 'planned',
          'status': 'CONFIRMED',
        }),
        isFalse,
      );
      expect(
        isStreetDirectBooking(<String, dynamic>{
          'booking_id': '123e4567-e89b-12d3-a456-426614174000',
        }),
        isFalse,
      );
      expect(isStreetDirectBooking(null), isFalse);
      expect(isStreetDirectBooking(<String, dynamic>{}), isFalse);
    });
  });

  group('DIRECT-RIDE-EXISTING-BOOKING-OWNERSHIP-1: '
      'resolveStreetDirectResumeIdentity', () {
    test('returns identity when both trip id and direct ride key are present',
        () {
      final id = resolveStreetDirectResumeIdentity(
        <String, dynamic>{
          'booking_id': 'street_1_abc',
          'source': 'street_ride',
          'ride_type': 'direct',
          'tracking_trip_id': 'trip-9',
          'direct_ride_key': 'direct_1_driver-1',
        },
        bookingId: 'street_1_abc',
      );
      expect(id, isNotNull);
      expect(id!.bookingId, 'street_1_abc');
      expect(id.trackingTripId, 'trip-9');
      expect(id.directRideKey, 'direct_1_driver-1');
    });

    test('returns null when tracking_trip_id is missing', () {
      final id = resolveStreetDirectResumeIdentity(
        <String, dynamic>{
          'booking_id': 'street_1_abc',
          'direct_ride_key': 'direct_1_driver-1',
        },
        bookingId: 'street_1_abc',
      );
      expect(id, isNull);
    });

    test('returns null when direct_ride_key is missing', () {
      final id = resolveStreetDirectResumeIdentity(
        <String, dynamic>{
          'booking_id': 'street_1_abc',
          'tracking_trip_id': 'trip-9',
        },
        bookingId: 'street_1_abc',
      );
      expect(id, isNull);
    });

    test('returns null when identifiers are only empty strings', () {
      final id = resolveStreetDirectResumeIdentity(
        <String, dynamic>{
          'booking_id': 'street_1_abc',
          'tracking_trip_id': '   ',
          'direct_ride_key': '',
        },
        bookingId: 'street_1_abc',
      );
      expect(id, isNull);
    });

    test('returns null for a planned booking even if identifiers present', () {
      final id = resolveStreetDirectResumeIdentity(
        <String, dynamic>{
          'booking_id': 'BK-1234',
          'source': 'planned',
          'tracking_trip_id': 'trip-9',
          'direct_ride_key': 'direct_1_driver-1',
        },
        bookingId: 'BK-1234',
      );
      expect(id, isNull);
    });

    test('finds identifiers nested inside `booking`/`record`', () {
      final id = resolveStreetDirectResumeIdentity(
        <String, dynamic>{
          'booking_id': 'street_2_def',
          'record': <String, dynamic>{
            'tracking_trip_id': 'trip-77',
            'booking': <String, dynamic>{
              'direct_ride_key': 'direct_2_driver-9',
            },
          },
        },
        bookingId: 'street_2_def',
      );
      expect(id, isNotNull);
      expect(id!.trackingTripId, 'trip-77');
      expect(id.directRideKey, 'direct_2_driver-9');
    });
  });

  group('DIRECT-RIDE-EXISTING-BOOKING-OWNERSHIP-1: openExistingRideDecision', () {
    test('ordinary planned booking -> planned (unchanged lifecycle)', () {
      final d = openExistingRideDecision(
        bookingId: 'BK-1234',
        details: <String, dynamic>{
          'source': 'planned',
          'status': 'CONFIRMED',
        },
      );
      expect(d.isPlanned, isTrue);
      expect(d.identity, isNull);
    });

    test('street booking without identifiers -> streetUnavailable '
        '(safe fail; no planned lifecycle, no new key)', () {
      final d = openExistingRideDecision(
        bookingId: 'street_1721_abc',
        details: <String, dynamic>{
          'source': 'street_ride',
          'ride_type': 'direct',
          'status': 'IN_PROGRESS',
        },
      );
      expect(d.isStreetUnavailable, isTrue);
      expect(d.isPlanned, isFalse);
      expect(d.identity, isNull);
    });

    test('street booking with authoritative identifiers -> streetResume, '
        'preserving the same booking id (no new street booking)', () {
      final d = openExistingRideDecision(
        bookingId: 'street_1721_abc',
        details: <String, dynamic>{
          'source': 'street_ride',
          'ride_type': 'direct',
          'tracking_trip_id': 'trip-11',
          'direct_ride_key': 'direct_1721_driver-1',
        },
      );
      expect(d.isStreetResume, isTrue);
      expect(d.identity, isNotNull);
      expect(d.identity!.bookingId, 'street_1721_abc');
      expect(d.identity!.trackingTripId, 'trip-11');
      expect(d.identity!.directRideKey, 'direct_1721_driver-1');
    });

    test('reopening the same street record preserves the same booking id', () {
      const bookingId = 'street_1721_abc';
      final details = <String, dynamic>{
        'source': 'street_ride',
        'tracking_trip_id': 'trip-11',
        'direct_ride_key': 'direct_1721_driver-1',
      };
      final first = openExistingRideDecision(
        bookingId: bookingId,
        details: details,
      );
      final again = openExistingRideDecision(
        bookingId: bookingId,
        details: details,
      );
      // Reopen is idempotent: same booking id, same identifiers, no new key.
      expect(first.isStreetResume, isTrue);
      expect(again.isStreetResume, isTrue);
      expect(first.identity!.bookingId, again.identity!.bookingId);
      expect(first.identity!.directRideKey, again.identity!.directRideKey);
      expect(first.identity!.trackingTripId, again.identity!.trackingTripId);
    });

    test('missing identity does not synthesize a direct_ride_key on retry',
        () {
      const bookingId = 'street_1721_abc';
      final details = <String, dynamic>{
        'source': 'street_ride',
        'status': 'IN_PROGRESS',
      };
      final first = openExistingRideDecision(
        bookingId: bookingId,
        details: details,
      );
      final again = openExistingRideDecision(
        bookingId: bookingId,
        details: details,
      );
      expect(first.isStreetUnavailable, isTrue);
      expect(again.isStreetUnavailable, isTrue);
      // Neither call fabricates identifiers.
      expect(first.identity, isNull);
      expect(again.identity, isNull);
    });

    test('classified street/direct is NEVER routed to planned when identity '
        'is absent (invariant guard)', () {
      final variants = <Map<String, dynamic>>[
        <String, dynamic>{'source': 'street_ride'},
        <String, dynamic>{'ride_type': 'direct'},
        <String, dynamic>{'booking': <String, dynamic>{'source': 'street_ride'}},
        <String, dynamic>{'booking': <String, dynamic>{'ride_type': 'direct'}},
      ];
      for (final v in variants) {
        final d = openExistingRideDecision(
          bookingId: 'street_1_abc',
          details: v,
        );
        expect(d.isPlanned, isFalse,
            reason: 'planned lifecycle must not run for street/direct: $v');
        expect(d.isStreetUnavailable, isTrue,
            reason: 'without identity, must safe-fail: $v');
      }
    });
  });
}
