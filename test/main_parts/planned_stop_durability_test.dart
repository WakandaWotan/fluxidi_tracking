// PLANNED-STOP-HISTORY-DURABILITY-P0-8
//
// Regression coverage for the durability contract that keeps a completed planned
// ride in Driver History when the network is poor.
//
// Field incident being closed: PLN-2026-000387 / booking 2026-08-168. The
// OUTBOUND leg became COMPLETED at 05:09:58Z while `/trip/record-planned-stop`
// never landed, so no tracking trip, no trips_index/history row, no Chiron
// ride_stop and no consumer_sale existed. Nothing could repair it afterwards
// because both server recovery routes only reconcile trips that already exist.
//
// These tests pin the pure contract: the terminal-projection gate, the
// deterministic replay identity, and the intent queue's idempotency.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/planned_stop_durability.dart';

/// Mirrors the exact `/trip/record-planned-stop` body shape, including measured
/// ride metrics that recovery must replay verbatim.
Map<String, dynamic> _measuredStopPayload({
  double kmTotal = 7.4,
  int waitSeconds = 185,
  String stoppedAt = '2026-08-07T05:09:58.000Z',
}) {
  return <String, dynamic>{
    'booking_id': '2026-08-168',
    'leg_id': 'leg-outbound-1',
    'leg_type': 'outbound',
    'tenant_id': 'tenant-a',
    'company_id': 'company-a',
    'driver_id': 'driver-1',
    'status': 'stopped',
    'started_at': '2026-08-07T04:51:12.000Z',
    'stopped_at': stoppedAt,
    'km_total': kmTotal,
    'wait_seconds_total': waitSeconds,
    'total_eur': 9.6,
    'currency': 'EUR',
  };
}

PlannedStopIntent _intent({
  String bookingId = '2026-08-168',
  String? legId = 'leg-outbound-1',
  String tenantId = 'tenant-a',
  String companyId = 'company-a',
  String driverId = 'driver-1',
  Map<String, dynamic>? payload,
}) {
  return PlannedStopIntent.fromStopPayload(
    bookingId: bookingId,
    tenantId: tenantId,
    companyId: companyId,
    driverId: driverId,
    payload: payload ?? _measuredStopPayload(),
    nowUtc: DateTime.utc(2026, 8, 7, 5, 9, 58),
    legId: legId,
    rowKey: 'row-1',
    legType: 'outbound',
  );
}

void main() {
  group('terminal projection gate (product invariant)', () {
    test(
      'scenario 1: planned STOP online success completes on a confirmed chain',
      () {
        expect(
          plannedTerminalProjectionDecision(
            trackingStopMaterialized: true,
            durableIntentPersisted: false,
          ),
          PlannedTerminalProjectionDecision.allowedChainConfirmed,
        );
        expect(
          plannedTerminalProjectionAllowed(
            trackingStopMaterialized: true,
            durableIntentPersisted: false,
          ),
          isTrue,
        );
      },
    );

    test(
      'scenario 2/3: network loss still completes when a durable intent exists',
      () {
        // Whether the request never left the device or died before the worker
        // materialized the trip is indistinguishable to the client. Both are
        // safe precisely because the intent is already durable.
        expect(
          plannedTerminalProjectionDecision(
            trackingStopMaterialized: false,
            durableIntentPersisted: true,
          ),
          PlannedTerminalProjectionDecision.allowedDurableIntent,
        );
      },
    );

    test(
      'scenario 9: COMPLETED is blocked when neither durability path holds',
      () {
        // This is the exact 2026-08-168 shape: no confirmed chain and no durable
        // intent, so the driven ride would exist nowhere.
        expect(
          plannedTerminalProjectionDecision(
            trackingStopMaterialized: false,
            durableIntentPersisted: false,
          ),
          PlannedTerminalProjectionDecision.blockedNoDurability,
        );
        expect(
          plannedTerminalProjectionAllowed(
            trackingStopMaterialized: false,
            durableIntentPersisted: false,
          ),
          isFalse,
        );
      },
    );

    test('a confirmed chain wins even with an intent still on disk', () {
      expect(
        plannedTerminalProjectionDecision(
          trackingStopMaterialized: true,
          durableIntentPersisted: true,
        ),
        PlannedTerminalProjectionDecision.allowedChainConfirmed,
      );
    });
  });

  group('deterministic replay identity', () {
    test('mirrors the tracking worker planned trip_id derivation', () {
      // Worker: `planned_${booking_id}_${sanitizeTripIdentityToken(leg_id ?? row_key)}`
      expect(
        plannedStopTripId(bookingId: '2026-08-168', legId: 'leg-outbound-1'),
        'planned_2026-08-168_leg-outbound-1',
      );
      expect(
        plannedStopTripId(bookingId: '2026-08-168'),
        'planned_2026-08-168',
      );
      // Falls back to row_key exactly like the worker does.
      expect(
        plannedStopTripId(bookingId: '2026-08-168', rowKey: 'ROW Key#2'),
        'planned_2026-08-168_row_key_2',
      );
    });

    test('token sanitiser matches the worker rules', () {
      expect(sanitizePlannedTripIdentityToken('Leg Outbound#1'), 'leg_outbound_1');
      expect(sanitizePlannedTripIdentityToken('__leading--trailing__'), 'leading--trailing');
      expect(sanitizePlannedTripIdentityToken('   '), isNull);
      expect(sanitizePlannedTripIdentityToken('###'), isNull);
      expect(sanitizePlannedTripIdentityToken(null), isNull);
      expect(sanitizePlannedTripIdentityToken('a' * 200)?.length, 96);
    });

    test('identity is stable across repeated stops of the same leg', () {
      expect(_intent().intentId, _intent().intentId);
      expect(_intent().intentId, 'planned_2026-08-168_leg-outbound-1');
    });

    test('outbound and return legs never share an identity', () {
      expect(
        _intent(legId: 'leg-outbound-1').intentId,
        isNot(_intent(legId: 'leg-return-1').intentId),
      );
    });
  });

  group('scenario 4: process death after the durable intent', () {
    test('intent survives a JSON round-trip with metrics untouched', () {
      final original = _intent();
      final restored = PlannedStopIntent.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, isNotNull);
      expect(restored!.intentId, original.intentId);
      expect(restored.bookingId, '2026-08-168');
      expect(restored.tenantId, 'tenant-a');
      expect(restored.companyId, 'company-a');
      expect(restored.driverId, 'driver-1');
      // Recovery must never invent ride truth: replay the measured values.
      expect(restored.payload['km_total'], 7.4);
      expect(restored.payload['wait_seconds_total'], 185);
      expect(restored.payload['stopped_at'], '2026-08-07T05:09:58.000Z');
      expect(restored.payload['total_eur'], 9.6);
    });

    test('corrupt rows are dropped instead of crashing recovery', () {
      expect(PlannedStopIntent.fromJson(null), isNull);
      expect(PlannedStopIntent.fromJson('not-a-map'), isNull);
      expect(PlannedStopIntent.fromJson(<String, dynamic>{}), isNull);
      // Missing payload cannot be replayed, so it must not be resurrected.
      expect(
        PlannedStopIntent.fromJson(<String, dynamic>{
          'intent_id': 'planned_x',
          'booking_id': 'x',
        }),
        isNull,
      );
    });
  });

  group('scenario 5/6: retry and duplicate retry stay idempotent', () {
    test('re-queuing the same stop replaces instead of duplicating', () {
      final first = _intent();
      var queue = upsertPlannedStopIntent(<PlannedStopIntent>[], first);
      queue = upsertPlannedStopIntent(queue, first);
      queue = upsertPlannedStopIntent(queue, first);

      expect(queue, hasLength(1));
      expect(queue.single.intentId, 'planned_2026-08-168_leg-outbound-1');
    });

    test('failed attempts accumulate without mutating the payload', () {
      final first = _intent();
      var queue = upsertPlannedStopIntent(<PlannedStopIntent>[], first);
      final retried = queue.single.markAttemptFailed(
        nowUtc: DateTime.utc(2026, 8, 7, 5, 15),
        error: 'TimeoutException',
      );
      queue = upsertPlannedStopIntent(queue, retried);

      expect(queue, hasLength(1));
      expect(queue.single.attemptCount, 1);
      expect(queue.single.lastError, 'TimeoutException');
      expect(queue.single.payload['km_total'], 7.4);
      expect(queue.single.createdAtIso, first.createdAtIso);
    });

    test('distinct legs of one booking queue independently', () {
      var queue = upsertPlannedStopIntent(
        <PlannedStopIntent>[],
        _intent(legId: 'leg-outbound-1'),
      );
      queue = upsertPlannedStopIntent(queue, _intent(legId: 'leg-return-1'));

      expect(queue, hasLength(2));
    });

    test('scenario 7: a confirmed stop is removed so it replays exactly once', () {
      final intent = _intent();
      final queue = upsertPlannedStopIntent(<PlannedStopIntent>[], intent);

      final cleared = removePlannedStopIntent(queue, intent.intentId);
      expect(cleared, isEmpty);
      // Clearing twice is harmless, so a racing drain cannot resurrect it.
      expect(removePlannedStopIntent(cleared, intent.intentId), isEmpty);
    });

    test('the queue is capped so an offline streak cannot grow unbounded', () {
      var queue = <PlannedStopIntent>[];
      for (var i = 0; i < kPlannedStopIntentMaxRecords + 15; i++) {
        queue = upsertPlannedStopIntent(queue, _intent(legId: 'leg-$i'));
      }
      expect(queue, hasLength(kPlannedStopIntentMaxRecords));
      // Newest first: the most recent stop must never be the one evicted.
      expect(queue.first.intentId, contains('leg-${kPlannedStopIntentMaxRecords + 14}'));
    });
  });

  group('tenant / company / driver isolation', () {
    test('only same-tenant, same-company, same-driver intents replay', () {
      final queue = <PlannedStopIntent>[
        _intent(legId: 'leg-mine'),
        _intent(legId: 'leg-other-company', companyId: 'company-b'),
        _intent(legId: 'leg-other-tenant', tenantId: 'tenant-b'),
        _intent(legId: 'leg-other-driver', driverId: 'driver-2'),
      ];

      final mine = plannedStopIntentsForScope(
        queue,
        tenantId: 'tenant-a',
        companyId: 'company-a',
        driverId: 'driver-1',
      );

      expect(mine, hasLength(1));
      expect(mine.single.intentId, contains('leg-mine'));
    });

    test('legacy rows without a driver stamp stay recoverable', () {
      final queue = <PlannedStopIntent>[_intent(driverId: '')];
      expect(
        plannedStopIntentsForScope(
          queue,
          tenantId: 'tenant-a',
          companyId: 'company-a',
          driverId: 'driver-1',
        ),
        hasLength(1),
      );
    });

    test('an unresolved scope replays nothing', () {
      final queue = <PlannedStopIntent>[_intent()];
      expect(
        plannedStopIntentsForScope(
          queue,
          tenantId: '',
          companyId: 'company-a',
          driverId: 'driver-1',
        ),
        isEmpty,
      );
      expect(
        plannedStopIntentsForScope(
          queue,
          tenantId: 'tenant-a',
          companyId: '',
          driverId: 'driver-1',
        ),
        isEmpty,
      );
    });
  });

  group('intent construction', () {
    test('stores the measured payload verbatim', () {
      final payload = _measuredStopPayload(kmTotal: 12.25, waitSeconds: 42);
      final intent = _intent(payload: payload);

      expect(intent.payload['km_total'], 12.25);
      expect(intent.payload['wait_seconds_total'], 42);
      // Defensive copy: later payload edits must not rewrite stored ride truth.
      payload['km_total'] = 999;
      expect(intent.payload['km_total'], 12.25);
    });

    test('carries leg identity needed for a leg-scoped replay', () {
      final intent = _intent();
      expect(intent.legId, 'leg-outbound-1');
      expect(intent.rowKey, 'row-1');
      expect(intent.legType, 'outbound');
    });
  });
}
