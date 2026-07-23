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

  // ==========================================================================
  // DIRECT-RIDE-PLANNED-STOP-GUARD-1 — stop lifecycle routing.
  //
  // The stop lifecycle previously branched primarily on `_directRideActive`.
  // Booking source is now authoritative: a street/direct booking must never
  // route through the planned stop path (no `/track/session/stop` as planned,
  // no `/trip/record-planned-stop`, no generic `/bookings/{id}/status`
  // COMPLETED as substitute for direct finalization), regardless of how it
  // reached driver state.
  // ==========================================================================

  group('DIRECT-RIDE-PLANNED-STOP-GUARD-1: stopTripLifecycleDecision', () {
    test('planned booking with `_directRideActive=false` -> planned '
        '(existing flow retained)', () {
      final d = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{
          'source': 'planned',
          'status': 'CONFIRMED',
        },
        bookingId: 'BK-1234',
        activeDirectTripId: null,
        directRideActive: false,
      );
      expect(d.isPlanned, isTrue);
      expect(d.tripId, isNull);
    });

    test('planned booking + direct identity leftover from prior state '
        'still resolves as planned', () {
      final d = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{'source': 'planned'},
        bookingId: 'BK-9999',
        activeDirectTripId: 'stale-trip-id',
        directRideActive: true,
      );
      expect(d.isPlanned, isTrue,
          reason: 'planned classification wins even when direct flags are set');
    });

    test('street booking with `_directRideActive=false` NEVER routes to '
        'planned (booking source is authoritative)', () {
      final d = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{
          'source': 'street_ride',
          'ride_type': 'direct',
        },
        bookingId: 'street_1721_abc',
        activeDirectTripId: null,
        directRideActive: false,
      );
      expect(d.isPlanned, isFalse);
      expect(d.isDirectUnavailable, isTrue);
    });

    test('`source: street_ride` triggers the guard', () {
      final d = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{'source': 'street_ride'},
        bookingId: 'BK-1',
        activeDirectTripId: null,
        directRideActive: false,
      );
      expect(d.isStreetDirect, isTrue);
      expect(d.isDirectUnavailable, isTrue);
    });

    test('`ride_type: direct` triggers the guard', () {
      final d = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{'ride_type': 'direct'},
        bookingId: 'BK-2',
        activeDirectTripId: null,
        directRideActive: false,
      );
      expect(d.isStreetDirect, isTrue);
      expect(d.isDirectUnavailable, isTrue);
    });

    test('`street_` booking id triggers the guard', () {
      final d = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{},
        bookingId: 'street_1721_xyz',
        activeDirectTripId: null,
        directRideActive: false,
      );
      expect(d.isStreetDirect, isTrue);
      expect(d.isDirectUnavailable, isTrue);
    });

    test('nested street/direct metadata triggers the guard', () {
      final d1 = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{
          'booking': <String, dynamic>{'source': 'street_ride'},
        },
        bookingId: 'BK-3',
        activeDirectTripId: null,
        directRideActive: false,
      );
      expect(d1.isStreetDirect, isTrue);
      expect(d1.isDirectUnavailable, isTrue);

      final d2 = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{
          'record': <String, dynamic>{
            'booking': <String, dynamic>{'ride_type': 'direct'},
          },
        },
        bookingId: 'BK-4',
        activeDirectTripId: null,
        directRideActive: false,
      );
      expect(d2.isStreetDirect, isTrue);
      expect(d2.isDirectUnavailable, isTrue);
    });

    test('street booking + complete authoritative identity -> directFinalize '
        '(direct stop + finalize-direct path)', () {
      final d = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{
          'source': 'street_ride',
          'ride_type': 'direct',
        },
        bookingId: 'street_1721_abc',
        activeDirectTripId: 'trip-77',
        directRideActive: true,
      );
      expect(d.isDirectFinalize, isTrue);
      expect(d.tripId, 'trip-77');
    });

    test('street booking + incomplete direct identity fails safely, does '
        'not fabricate a trip id', () {
      final d = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{'source': 'street_ride'},
        bookingId: 'street_2_def',
        activeDirectTripId: '   ',
        directRideActive: false,
      );
      expect(d.isDirectUnavailable, isTrue);
      expect(d.tripId, isNull);
    });

    test('street booking is direct even when `_directRideActive == false` '
        'as long as a trip id is present (recovered session)', () {
      final d = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{
          'booking': <String, dynamic>{'source': 'street_ride'},
        },
        bookingId: 'street_recovered_1',
        activeDirectTripId: 'recovered-trip',
        directRideActive: false,
      );
      expect(d.isDirectFinalize, isTrue,
          reason:
              'stale `_directRideActive == false` must not divert into planned');
      expect(d.tripId, 'recovered-trip');
    });

    test('empty booking id + street identifiers still classified as direct',
        () {
      final d = stopTripLifecycleDecision(
        bookingDetails: <String, dynamic>{'source': 'street_ride'},
        bookingId: '',
        activeDirectTripId: null,
        directRideActive: false,
      );
      expect(d.isDirectUnavailable, isTrue);
    });

    test('repeated Stop taps remain idempotent (pure function returns same '
        'decision on same input)', () {
      Map<String, dynamic> details() => <String, dynamic>{
            'source': 'street_ride',
            'ride_type': 'direct',
          };
      final a = stopTripLifecycleDecision(
        bookingDetails: details(),
        bookingId: 'street_x',
        activeDirectTripId: 'trip-1',
        directRideActive: true,
      );
      final b = stopTripLifecycleDecision(
        bookingDetails: details(),
        bookingId: 'street_x',
        activeDirectTripId: 'trip-1',
        directRideActive: true,
      );
      expect(a.kind, b.kind);
      expect(a.tripId, b.tripId);
    });
  });

  // ==========================================================================
  // DIRECT-RIDE-FINALIZE-ACK-GATE-1 — structured stop outcome + ack gate.
  // ==========================================================================

  group('DIRECT-RIDE-FINALIZE-ACK-GATE-1: DirectRideStopOutcome', () {
    test('finalized `/trip/stop` response maps to acknowledged outcome', () {
      final parsed = parseDirectRideStopResponse(<String, dynamic>{
        'ok': true,
        'booking_id': 'street_1_ab',
        'booking_finalize_state': 'completed',
        'booking_finalized': true,
        'totals': <String, dynamic>{'total_eur': 4.2},
      });
      final o = mapDirectRideStopOutcome(
        parsed: parsed,
        transportSucceeded: true,
      );
      expect(o.transportSucceeded, isTrue);
      expect(o.trackingTripStopped, isTrue);
      expect(o.bookingFinalized, isTrue);
      expect(o.bookingFinalizeState, DirectRideFinalizeState.completed);
      expect(o.totalsPresent, isTrue);
      expect(o.totalEur, 4.2);
      expect(
        isDirectRideFinalizeAcknowledged(
          outcome: o,
          expectedBookingId: 'street_1_ab',
        ),
        isTrue,
      );
    });

    test('pending finalize response maps to non-acknowledged outcome', () {
      final parsed = parseDirectRideStopResponse(<String, dynamic>{
        'ok': true,
        'booking_id': 'street_1_ab',
        'booking_finalize_state': 'pending',
        'booking_finalized': false,
        'totals': <String, dynamic>{'total_eur': 4.2},
      });
      final o = mapDirectRideStopOutcome(
        parsed: parsed,
        transportSucceeded: true,
      );
      expect(o.trackingTripStopped, isTrue);
      expect(o.bookingFinalized, isFalse);
      expect(o.bookingFinalizeState, DirectRideFinalizeState.pending);
      expect(o.totalsPresent, isTrue);
      expect(
        isDirectRideFinalizeAcknowledged(
          outcome: o,
          expectedBookingId: 'street_1_ab',
        ),
        isFalse,
      );
    });

    test('transport failure maps to unknown/non-acknowledged outcome', () {
      final o = mapDirectRideStopOutcome(
        parsed: null,
        transportSucceeded: false,
      );
      expect(o.transportSucceeded, isFalse);
      expect(o.trackingTripStopped, isFalse);
      expect(o.bookingFinalized, isFalse);
      expect(o.bookingFinalizeState, DirectRideFinalizeState.unknown);
      expect(o.totalsPresent, isFalse);
      expect(
        isDirectRideFinalizeAcknowledged(
          outcome: o,
          expectedBookingId: 'street_1_ab',
        ),
        isFalse,
      );
      expect(
        isDirectRideFinalizeAcknowledged(
          outcome: DirectRideStopOutcome.unknown,
          expectedBookingId: 'street_1_ab',
        ),
        isFalse,
      );
    });

    test('booking-id mismatch cannot acknowledge completion', () {
      final parsed = parseDirectRideStopResponse(<String, dynamic>{
        'ok': true,
        'booking_id': 'street_OTHER',
        'booking_finalize_state': 'completed',
        'booking_finalized': true,
        'totals': <String, dynamic>{'total_eur': 1.0},
      });
      final o = mapDirectRideStopOutcome(
        parsed: parsed,
        transportSucceeded: true,
      );
      expect(
        isDirectRideFinalizeAcknowledged(
          outcome: o,
          expectedBookingId: 'street_1_ab',
        ),
        isFalse,
      );
    });

    test('missing totals cannot acknowledge full completion', () {
      final parsed = parseDirectRideStopResponse(<String, dynamic>{
        'ok': true,
        'booking_id': 'street_1_ab',
        'booking_finalize_state': 'completed',
        'booking_finalized': true,
      });
      final o = mapDirectRideStopOutcome(
        parsed: parsed,
        transportSucceeded: true,
      );
      expect(o.totalsPresent, isFalse);
      expect(
        isDirectRideFinalizeAcknowledged(
          outcome: o,
          expectedBookingId: 'street_1_ab',
        ),
        isFalse,
      );
    });

    test('HTTP ok alone is insufficient without booking_finalized', () {
      final parsed = parseDirectRideStopResponse(<String, dynamic>{
        'ok': true,
        'booking_id': 'street_1_ab',
        'status': 'stopped',
        'totals': <String, dynamic>{'total_eur': 9.9},
      });
      final o = mapDirectRideStopOutcome(
        parsed: parsed,
        transportSucceeded: true,
      );
      expect(o.trackingTripStopped, isTrue);
      expect(
        isDirectRideFinalizeAcknowledged(
          outcome: o,
          expectedBookingId: 'street_1_ab',
        ),
        isFalse,
        reason: 'tracking totals alone must not prove booking completion',
      );
    });

    test('ack gate is the sole gate for local COMPLETED mutations '
        '(pending => leave server truth; finalized => apply once)', () {
      // Mirrors `_completeStoppedBooking` street/direct branch:
      // local COMPLETED / remove / _deletedBookingIds only when acknowledged.
      bool mayApplyLocalCompleted({required bool ack}) => ack;

      expect(mayApplyLocalCompleted(ack: true), isTrue);
      expect(mayApplyLocalCompleted(ack: false), isFalse);
    });

    test('pending outcome implies reconcile path, not another `/trip/stop`',
        () {
      // Contract for `_stopTrip`: when finalize pending, set
      // `_directStopFinalizePending` and call reconcile; repeat Stop must not
      // re-issue `/trip/stop`.
      bool shouldCallTripStopAgain({required bool finalizePending}) =>
          !finalizePending;
      bool shouldCallReconcile({
        required bool trackingStopped,
        required bool finalizeAcknowledged,
      }) =>
          trackingStopped && !finalizeAcknowledged;

      final pending = mapDirectRideStopOutcome(
        parsed: parseDirectRideStopResponse(<String, dynamic>{
          'ok': true,
          'booking_id': 'street_1_ab',
          'booking_finalize_state': 'pending',
          'booking_finalized': false,
          'totals': <String, dynamic>{'total_eur': 2.0},
        }),
        transportSucceeded: true,
      );
      final ack = isDirectRideFinalizeAcknowledged(
        outcome: pending,
        expectedBookingId: 'street_1_ab',
      );
      expect(ack, isFalse);
      expect(
        shouldCallReconcile(
          trackingStopped: pending.trackingTripStopped,
          finalizeAcknowledged: ack,
        ),
        isTrue,
      );
      expect(shouldCallTripStopAgain(finalizePending: true), isFalse);
    });

    test('empty expected booking id cannot acknowledge', () {
      final o = mapDirectRideStopOutcome(
        parsed: parseDirectRideStopResponse(<String, dynamic>{
          'ok': true,
          'booking_id': 'street_1_ab',
          'booking_finalize_state': 'completed',
          'booking_finalized': true,
          'totals': <String, dynamic>{'total_eur': 1.0},
        }),
        transportSucceeded: true,
      );
      expect(
        isDirectRideFinalizeAcknowledged(outcome: o, expectedBookingId: ''),
        isFalse,
      );
      expect(
        isDirectRideFinalizeAcknowledged(outcome: o, expectedBookingId: null),
        isFalse,
      );
    });
  });

  // ==========================================================================
  // DIRECT-RIDE-STOP-RECOVERY-RACE-1 Commit 1 — reconcile acknowledgement.
  // ==========================================================================

  group('DIRECT-RIDE-STOP-RECOVERY-RACE-1 C1: DirectRideReconcileOutcome', () {
    const trip = 'trip_abc';
    const booking = 'street_1_ab';

    DirectRideReconcileOutcome map({
      Object? decoded,
      int? status = 200,
      String reqTrip = trip,
      String expBooking = booking,
      bool transportOk = true,
    }) {
      return mapDirectRideReconcileOutcome(
        decoded: decoded,
        httpStatus: status,
        requestedTripId: reqTrip,
        expectedBookingId: expBooking,
        transportSucceeded: transportOk,
      );
    }

    test('matching completed response is acknowledged', () {
      final o = map(
        decoded: <String, dynamic>{
          'ok': true,
          'trip_id': trip,
          'booking_id': booking,
          'booking_finalize_state': 'completed',
          'booking_finalized': true,
          'reconciled': true,
          'reason': 'repairable',
        },
      );
      expect(o.isAcknowledged, isTrue);
      expect(isDirectRideReconcileAcknowledged(o), isTrue);
      expect(o.bookingFinalizeState, DirectRideFinalizeState.completed);
    });

    test('`already_completed` with matching ids is acknowledged', () {
      final o = map(
        decoded: <String, dynamic>{
          'ok': true,
          'trip_id': trip,
          'booking_id': booking,
          'booking_finalize_state': 'completed',
          'booking_finalized': true,
          'reconciled': false,
          'reason': 'already_completed',
        },
      );
      expect(o.isAcknowledged, isTrue);
      expect(o.reconciled, isFalse);
    });

    test('trip-id mismatch is rejected', () {
      final o = map(
        decoded: <String, dynamic>{
          'ok': true,
          'trip_id': 'trip_OTHER',
          'booking_id': booking,
          'booking_finalize_state': 'completed',
          'booking_finalized': true,
        },
      );
      expect(o.isAcknowledged, isFalse);
    });

    test('booking-id mismatch is rejected', () {
      final o = map(
        decoded: <String, dynamic>{
          'ok': true,
          'trip_id': trip,
          'booking_id': 'street_OTHER',
          'booking_finalize_state': 'completed',
          'booking_finalized': true,
        },
      );
      expect(o.isAcknowledged, isFalse);
    });

    test('missing trip id is rejected', () {
      final o = map(
        decoded: <String, dynamic>{
          'ok': true,
          'booking_id': booking,
          'booking_finalize_state': 'completed',
          'booking_finalized': true,
        },
      );
      expect(o.isAcknowledged, isFalse);
      expect(
        map(
          decoded: <String, dynamic>{
            'ok': true,
            'trip_id': trip,
            'booking_id': booking,
            'booking_finalize_state': 'completed',
            'booking_finalized': true,
          },
          reqTrip: '',
        ).isAcknowledged,
        isFalse,
      );
    });

    test('missing booking id is rejected', () {
      final o = map(
        decoded: <String, dynamic>{
          'ok': true,
          'trip_id': trip,
          'booking_finalize_state': 'completed',
          'booking_finalized': true,
        },
      );
      expect(o.isAcknowledged, isFalse);
      expect(
        map(
          decoded: <String, dynamic>{
            'ok': true,
            'trip_id': trip,
            'booking_id': booking,
            'booking_finalize_state': 'completed',
            'booking_finalized': true,
          },
          expBooking: '',
        ).isAcknowledged,
        isFalse,
      );
    });

    test('completed boolean with state pending is rejected', () {
      final o = map(
        decoded: <String, dynamic>{
          'ok': true,
          'trip_id': trip,
          'booking_id': booking,
          'booking_finalize_state': 'pending',
          'booking_finalized': true,
        },
      );
      expect(o.isAcknowledged, isFalse);
    });

    test('state completed with boolean false is rejected', () {
      final o = map(
        decoded: <String, dynamic>{
          'ok': true,
          'trip_id': trip,
          'booking_id': booking,
          'booking_finalize_state': 'completed',
          'booking_finalized': false,
        },
      );
      expect(o.isAcknowledged, isFalse);
    });

    test('HTTP 409 non-terminal maps explicitly', () {
      final o = map(
        status: 409,
        decoded: <String, dynamic>{
          'ok': false,
          'trip_id': trip,
          'booking_id': booking,
          'booking_finalize_state': 'pending',
          'booking_finalized': false,
          'reconciled': false,
          'reason': 'skipped_non_terminal',
        },
      );
      expect(o.transportSucceeded, isTrue);
      expect(o.isNonTerminal, isTrue);
      expect(o.isAcknowledged, isFalse);
      expect(o.reason, kDirectReconcileReasonNonTerminal);
    });

    test('HTTP 200 pending remains non-acknowledged', () {
      final o = map(
        decoded: <String, dynamic>{
          'ok': false,
          'trip_id': trip,
          'booking_id': booking,
          'booking_finalize_state': 'pending',
          'booking_finalized': false,
          'reconciled': false,
          'reason': 'pending',
        },
      );
      expect(o.transportSucceeded, isTrue);
      expect(o.isNonTerminal, isFalse);
      expect(o.isAcknowledged, isFalse);
      expect(o.bookingFinalizeState, DirectRideFinalizeState.pending);
    });

    test('transport failure remains unknown', () {
      final o = map(transportOk: false, decoded: null, status: null);
      expect(o.transportSucceeded, isFalse);
      expect(o.isAcknowledged, isFalse);
      expect(o.bookingFinalizeState, DirectRideFinalizeState.unknown);
    });

    test('decode failure remains unknown', () {
      final o = map(decoded: 'not-a-map', status: 200);
      expect(o.transportSucceeded, isFalse);
      expect(o.isAcknowledged, isFalse);
    });

    test('immediate reconcile cannot locally complete on identity mismatch '
        '(shared helper is sole gate)', () {
      // Mirrors `_stopTrip` post-stop reconcile: local COMPLETED only when
      // isDirectRideReconcileAcknowledged(outcome).
      bool mayApplyLocalCompleted(DirectRideReconcileOutcome o) =>
          isDirectRideReconcileAcknowledged(o);

      final mismatch = map(
        decoded: <String, dynamic>{
          'ok': true,
          'trip_id': trip,
          'booking_id': 'street_WRONG',
          'booking_finalize_state': 'completed',
          'booking_finalized': true,
        },
      );
      expect(mayApplyLocalCompleted(mismatch), isFalse);

      final ok = map(
        decoded: <String, dynamic>{
          'ok': true,
          'trip_id': trip,
          'booking_id': booking,
          'booking_finalize_state': 'completed',
          'booking_finalized': true,
        },
      );
      expect(mayApplyLocalCompleted(ok), isTrue);
    });
  });

  // ==========================================================================
  // DIRECT-RIDE-STOP-RECOVERY-RACE-1 Commit 2 — server-truth recovery probe.
  // ==========================================================================

  group('DIRECT-RIDE-STOP-RECOVERY-RACE-1 C2: classifyDirectTripRecoveryProbe',
      () {
    DirectTripSession activeSession({
      String tripId = 'trip_abc',
      String bookingId = 'street_1_ab',
      String key = 'direct_1_driver',
      String lifecycle = kDirectTripLocalLifecycleActive,
      String finalize = kDirectTripFinalizePending,
    }) {
      return DirectTripSession(
        directRideKey: key,
        tripId: tripId,
        bookingId: bookingId,
        startedAtIso: '2026-07-23T10:00:00.000Z',
        localLifecycle: lifecycle,
        bookingFinalizeState: finalize,
      );
    }

    DirectRideReconcileOutcome probe({
      Object? decoded,
      int? status = 200,
      String reqTrip = 'trip_abc',
      String expBooking = 'street_1_ab',
      bool transportOk = true,
    }) {
      return mapDirectRideReconcileOutcome(
        decoded: decoded,
        httpStatus: status,
        requestedTripId: reqTrip,
        expectedBookingId: expBooking,
        transportSucceeded: transportOk,
      );
    }

    test('persisted active + acknowledged completed → clearAcknowledged '
        '(no meter restore implied by action)', () {
      final session = activeSession();
      final o = probe(
        decoded: <String, dynamic>{
          'ok': true,
          'trip_id': 'trip_abc',
          'booking_id': 'street_1_ab',
          'booking_finalize_state': 'completed',
          'booking_finalized': true,
          'reason': 'already_completed',
        },
      );
      expect(
        classifyDirectTripRecoveryProbe(session: session, outcome: o),
        DirectTripRecoveryProbeAction.clearAcknowledged,
      );
      // Recovery must never invent a new key or call /trip/stop.
      expect(session.directRideKey, 'direct_1_driver');
    });

    test('persisted active + non-terminal 409 → retainServerActive '
        '(no /trip/stop)', () {
      final o = probe(
        status: 409,
        decoded: <String, dynamic>{
          'ok': false,
          'trip_id': 'trip_abc',
          'booking_id': 'street_1_ab',
          'booking_finalize_state': 'pending',
          'booking_finalized': false,
          'reason': 'skipped_non_terminal',
        },
      );
      expect(
        classifyDirectTripRecoveryProbe(
          session: activeSession(),
          outcome: o,
        ),
        DirectTripRecoveryProbeAction.retainServerActive,
      );
      expect(o.isNonTerminal, isTrue);
      expect(o.isAcknowledged, isFalse);
    });

    test('persisted active + pending finalize → rewriteStoppedPending '
        'and preserves identity fields', () {
      final session = activeSession();
      final o = probe(
        decoded: <String, dynamic>{
          'ok': false,
          'trip_id': 'trip_abc',
          'booking_id': 'street_1_ab',
          'booking_finalize_state': 'pending',
          'booking_finalized': false,
          'reason': 'pending',
        },
      );
      expect(
        classifyDirectTripRecoveryProbe(session: session, outcome: o),
        DirectTripRecoveryProbeAction.rewriteStoppedPending,
      );
      final rewritten = session.copyWith(
        localLifecycle: kDirectTripLocalLifecycleStopped,
        bookingFinalizeState: kDirectTripFinalizePending,
      );
      expect(rewritten.tripId, session.tripId);
      expect(rewritten.bookingId, session.bookingId);
      expect(rewritten.directRideKey, session.directRideKey);
      expect(rewritten.isStopped, isTrue);
      expect(rewritten.isCompleted, isFalse);
      // Pending rewrite must not look like local COMPLETED.
      expect(
        streetRideCompanyBucket(kStreetRideStatusInProgress),
        StreetRideCompanyBucket.open,
      );
    });

    test('transport failure retains evidence', () {
      expect(
        classifyDirectTripRecoveryProbe(
          session: activeSession(),
          outcome: probe(transportOk: false, decoded: null, status: null),
        ),
        DirectTripRecoveryProbeAction.retainTransportUnknown,
      );
    });

    test('identity mismatch retains evidence', () {
      expect(
        classifyDirectTripRecoveryProbe(
          session: activeSession(),
          outcome: probe(
            decoded: <String, dynamic>{
              'ok': true,
              'trip_id': 'trip_OTHER',
              'booking_id': 'street_1_ab',
              'booking_finalize_state': 'completed',
              'booking_finalized': true,
            },
          ),
        ),
        DirectTripRecoveryProbeAction.retainIdentityMismatch,
      );
      expect(
        classifyDirectTripRecoveryProbe(
          session: activeSession(),
          outcome: probe(
            decoded: <String, dynamic>{
              'ok': true,
              'trip_id': 'trip_abc',
              'booking_id': 'street_WRONG',
              'booking_finalize_state': 'completed',
              'booking_finalized': true,
            },
          ),
        ),
        DirectTripRecoveryProbeAction.retainIdentityMismatch,
      );
    });

    test('stale active with ids still probes (pure action would abandon, '
        'probe identity remains available)', () {
      final now = DateTime.parse('2026-07-24T10:00:00.000Z');
      final stale = activeSession().copyWith(
        startedAtIso: '2026-07-23T10:00:00.000Z',
        updatedAtIso: '2026-07-23T10:00:00.000Z',
      );
      expect(
        directTripRecoveryAction(stale, now: now),
        DirectTripRecoveryAction.abandon,
      );
      expect(directTripSessionHasProbeIdentity(stale), isTrue);
      // With ids present, recovery orchestration must probe — not silent clear.
      final completedProbe = probe(
        decoded: <String, dynamic>{
          'ok': true,
          'trip_id': 'trip_abc',
          'booking_id': 'street_1_ab',
          'booking_finalize_state': 'completed',
          'booking_finalized': true,
          'reason': 'already_completed',
        },
      );
      expect(
        classifyDirectTripRecoveryProbe(session: stale, outcome: completedProbe),
        DirectTripRecoveryProbeAction.clearAcknowledged,
      );
      final pendingProbe = probe(
        decoded: <String, dynamic>{
          'ok': false,
          'trip_id': 'trip_abc',
          'booking_id': 'street_1_ab',
          'booking_finalize_state': 'pending',
          'booking_finalized': false,
        },
      );
      expect(
        classifyDirectTripRecoveryProbe(session: stale, outcome: pendingProbe),
        DirectTripRecoveryProbeAction.rewriteStoppedPending,
      );
      expect(
        classifyDirectTripRecoveryProbe(
          session: stale,
          outcome: probe(transportOk: false, decoded: null, status: null),
        ),
        DirectTripRecoveryProbeAction.retainTransportUnknown,
      );
    });

    test('structurally unusable session (no ids) cannot probe', () {
      final unusable = activeSession(tripId: '', bookingId: '');
      expect(directTripSessionHasProbeIdentity(unusable), isFalse);
      expect(directTripSessionHasProbeIdentity(null), isFalse);
    });

    test('stopped/pending existing recovery decision remains reconcilePending',
        () {
      final stopped = activeSession(
        lifecycle: kDirectTripLocalLifecycleStopped,
        finalize: kDirectTripFinalizePending,
      );
      expect(
        directTripRecoveryAction(stopped),
        DirectTripRecoveryAction.reconcilePending,
      );
    });

    test('startup recovery never implies /trip/stop or new key generation', () {
      // Contract: every probe action is retain / rewrite / clear — never "stop".
      const forbidden = {'stop', 'start', 'create'};
      for (final a in DirectTripRecoveryProbeAction.values) {
        expect(forbidden.contains(a.name), isFalse);
      }
      final keyBefore = 'direct_1_driver';
      final session = activeSession(key: keyBefore);
      final rewritten = session.copyWith(
        localLifecycle: kDirectTripLocalLifecycleStopped,
      );
      expect(rewritten.directRideKey, keyBefore);
      expect(makeDirectRideKey(driverId: 'x', startedAtMs: 1), isNot(keyBefore),
          reason: 'rewrite must not call makeDirectRideKey');
    });
  });
}
