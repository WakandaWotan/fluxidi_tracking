// P0-FIELD-REPAIR-1 (A) — Flutter safety net: a street/direct ride is never
// shown in the driver's Planned ("Gepland") list or "Next ride" card.
//
// The booking worker is authoritative and already excludes these rows. These
// tests pin the CLIENT guarantee so a stale worker, a cached response or a
// future read path cannot resurrect the ghost row, and so the filter can never
// start matching on a display label instead of canonical identity.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/driver_planned_street_ride_filter.dart';

Map<String, dynamic> plannedRow({
  String bookingId = 'BK-2026-000123',
  String status = 'PENDING',
}) => <String, dynamic>{
  'booking_id': bookingId,
  'source': 'planning',
  'booking_source': 'planning',
  'ride_type': 'planned',
  'status': status,
  'is_street_direct': false,
  'isStreetDirect': false,
};

Map<String, dynamic> streetRow({
  String bookingId = 'street_1752863820000_ab12cd34',
  String status = 'COMPLETED',
  bool withHint = true,
}) => <String, dynamic>{
  'booking_id': bookingId,
  'source': 'street_ride',
  'booking_source': 'street_ride',
  'ride_type': 'direct',
  'status': status,
  if (withHint) 'is_street_direct': true,
  if (withHint) 'isStreetDirect': true,
};

void main() {
  group('driverRowIsStreetDirectRide — canonical identity only', () {
    test('authoritative worker hint wins when present', () {
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{'is_street_direct': true}),
        isTrue,
      );
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{'isStreetDirect': true}),
        isTrue,
      );
      // An explicit worker negative wins even over a street-looking id, so a
      // current worker projection is never second-guessed by the client.
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{
          'is_street_direct': false,
          'booking_id': 'street_should_be_ignored',
        }),
        isFalse,
      );
    });

    test('string-encoded hints are honoured', () {
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{'is_street_direct': 'true'}),
        isTrue,
      );
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{'is_street_direct': '1'}),
        isTrue,
      );
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{'is_street_direct': 'false'}),
        isFalse,
      );
    });

    test('absent hint falls through to canonical fields (not to false)', () {
      expect(streetDirectWorkerHint(<String, dynamic>{}), isNull);
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{'source': 'street_ride'}),
        isTrue,
      );
    });

    test('canonical source / booking_source variants match', () {
      for (final value in <String>[
        'street_ride',
        'STREET_RIDE',
        'streetride',
        'street-ride',
        'direct',
        'direct_ride',
      ]) {
        expect(
          driverRowIsStreetDirectRide(<String, dynamic>{'source': value}),
          isTrue,
          reason: 'source=$value must be street/direct',
        );
        expect(
          driverRowIsStreetDirectRide(<String, dynamic>{'booking_source': value}),
          isTrue,
          reason: 'booking_source=$value must be street/direct',
        );
      }
    });

    test('canonical ride_type=direct matches', () {
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{'ride_type': 'direct'}),
        isTrue,
      );
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{'rideType': 'DIRECT'}),
        isTrue,
      );
    });

    test('street_ booking id prefix matches (legacy records)', () {
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{'booking_id': 'street_abc'}),
        isTrue,
      );
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{
          'parent_booking_id': 'street_abc',
        }),
        isTrue,
      );
    });

    test('nested booking / record / details payloads are inspected', () {
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{
          'booking_id': 'BK-1',
          'booking': <String, dynamic>{'source': 'street_ride'},
        }),
        isTrue,
      );
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{
          'booking_id': 'BK-1',
          'record': <String, dynamic>{'ride_type': 'direct'},
        }),
        isTrue,
      );
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{
          'booking_id': 'BK-1',
          'details': <String, dynamic>{
            'booking': <String, dynamic>{'booking_source': 'street_ride'},
          },
        }),
        isTrue,
      );
    });

    test('genuine planned rides never match', () {
      expect(driverRowIsStreetDirectRide(plannedRow()), isFalse);
      expect(
        driverRowIsStreetDirectRide(<String, dynamic>{
          'booking_id': 'BK-2026-000777',
          'source': 'planning',
          'ride_type': 'planned',
          'leg_type': 'return',
        }),
        isFalse,
      );
      expect(driverRowIsStreetDirectRide(<String, dynamic>{}), isFalse);
    });

    test('never decides on a display label', () {
      // A localized label must be inert: only canonical fields may decide.
      for (final label in <String>['Straatrit', 'Directe rit', 'Street ride']) {
        expect(
          driverRowIsStreetDirectRide(<String, dynamic>{
            'booking_id': 'BK-2026-000123',
            'source': 'planning',
            'ride_type': 'planned',
            'label': label,
            'display_label': label,
            'title': label,
            'customer_name': label,
          }),
          isFalse,
          reason: 'label "$label" must not drive the decision',
        );
      }
    });
  });

  group('filterPlannedRidesExcludingStreetDirect', () {
    List<Map<String, dynamic>> run(
      List<Map<String, dynamic>> rows, {
      void Function(DriverPlannedStreetRideExclusionLog)? onLog,
    }) => filterPlannedRidesExcludingStreetDirect<Map<String, dynamic>>(
      rows,
      canonicalFieldsOf: (r) => r,
      statusOf: (r) => (r['status'] ?? '').toString(),
      segment: 'my_rides',
      onLog: onLog,
    );

    test('completed street ride is removed, planned rides survive', () {
      final out = run(<Map<String, dynamic>>[
        plannedRow(bookingId: 'BK-1'),
        streetRow(status: 'COMPLETED'),
        plannedRow(bookingId: 'BK-2'),
      ]);
      expect(out.map((r) => r['booking_id']), <String>['BK-1', 'BK-2']);
    });

    test('street ride is removed in every lifecycle state', () {
      for (final status in <String>[
        'PENDING',
        'SCHEDULED',
        'IN_PROGRESS',
        'ACTIVE',
        'COMPLETED',
        'CANCELLED',
      ]) {
        final out = run(<Map<String, dynamic>>[
          plannedRow(bookingId: 'BK-KEEP'),
          streetRow(status: status),
        ]);
        expect(
          out.map((r) => r['booking_id']),
          <String>['BK-KEEP'],
          reason: 'street ride in $status must not be planned',
        );
      }
    });

    test('stale shadow-leg row without a worker hint is still removed', () {
      final out = run(<Map<String, dynamic>>[
        plannedRow(bookingId: 'BK-KEEP'),
        <String, dynamic>{
          'booking_id': 'street_1752863820000_ab12cd34',
          'parent_booking_id': 'street_1752863820000_ab12cd34',
          'leg_id': 'street_1752863820000_ab12cd34_outbound',
          'leg_type': 'outbound',
          'is_operational_leg': true,
          'status': 'PENDING',
        },
      ]);
      expect(out.map((r) => r['booking_id']), <String>['BK-KEEP']);
    });

    test('planned round-trip open return leg is preserved', () {
      final out = run(<Map<String, dynamic>>[
        <String, dynamic>{
          'booking_id': 'BK-2026-000777',
          'leg_id': 'BK-2026-000777_return',
          'leg_type': 'return',
          'is_operational_leg': true,
          'source': 'planning',
          'ride_type': 'planned',
          'status': 'PENDING',
          'is_street_direct': false,
        },
      ]);
      expect(out, hasLength(1));
      expect(out.single['leg_type'], 'return');
    });

    test('order is preserved and input list is never mutated', () {
      final input = <Map<String, dynamic>>[
        plannedRow(bookingId: 'BK-1'),
        streetRow(),
        plannedRow(bookingId: 'BK-2'),
        plannedRow(bookingId: 'BK-3'),
      ];
      final out = run(input);
      expect(out.map((r) => r['booking_id']), <String>['BK-1', 'BK-2', 'BK-3']);
      expect(input, hasLength(4), reason: 'input must not be mutated');
    });

    test('empty input yields empty output', () {
      expect(run(<Map<String, dynamic>>[]), isEmpty);
    });

    test('deterministic across repeated runs (refresh / restart)', () {
      final input = <Map<String, dynamic>>[
        plannedRow(bookingId: 'BK-1'),
        streetRow(status: 'COMPLETED'),
        plannedRow(bookingId: 'BK-2'),
      ];
      final first = run(input).map((r) => r['booking_id']).toList();
      final second = run(input).map((r) => r['booking_id']).toList();
      final third = run(input).map((r) => r['booking_id']).toList();
      expect(second, first);
      expect(third, first);
    });
  });

  group('exclusion diagnostics are bounded and PII-free', () {
    test('one log per excluded row, carrying no identifying data', () {
      final logs = <DriverPlannedStreetRideExclusionLog>[];
      filterPlannedRidesExcludingStreetDirect<Map<String, dynamic>>(
        <Map<String, dynamic>>[
          plannedRow(bookingId: 'BK-1'),
          <String, dynamic>{
            ...streetRow(status: 'COMPLETED'),
            'customer_name': 'Jan Janssen',
            'customer_phone': '+32470112233',
            'customer_email': 'jan@example.com',
            'from': 'Kerkstraat 1, Antwerpen',
            'to': 'Grote Markt 2, Brussel',
          },
        ],
        canonicalFieldsOf: (r) => r,
        statusOf: (r) => (r['status'] ?? '').toString(),
        segment: 'my_rides',
        onLog: logs.add,
      );

      expect(logs, hasLength(1));
      final line = logs.single.toLogLine();
      expect(line, contains('segment=my_rides'));
      expect(line, contains('status=COMPLETED'));
      expect(line, contains('hasWorkerHint=true'));
      expect(line, contains('reason=street_direct_never_planned'));

      for (final secret in <String>[
        'Jan Janssen',
        '+32470112233',
        'jan@example.com',
        'Kerkstraat',
        'Grote Markt',
        'street_1752863820000_ab12cd34',
      ]) {
        expect(
          line,
          isNot(contains(secret)),
          reason: 'diagnostic must not leak "$secret"',
        );
      }
    });

    test('no log is emitted when nothing is excluded', () {
      final logs = <DriverPlannedStreetRideExclusionLog>[];
      filterPlannedRidesExcludingStreetDirect<Map<String, dynamic>>(
        <Map<String, dynamic>>[plannedRow()],
        canonicalFieldsOf: (r) => r,
        segment: 'my_rides',
        onLog: logs.add,
      );
      expect(logs, isEmpty);
    });

    test('hasWorkerHint is false when the decision came from canonical fields', () {
      final logs = <DriverPlannedStreetRideExclusionLog>[];
      filterPlannedRidesExcludingStreetDirect<Map<String, dynamic>>(
        <Map<String, dynamic>>[
          <String, dynamic>{'booking_id': 'street_legacy', 'status': 'PENDING'},
        ],
        canonicalFieldsOf: (r) => r,
        statusOf: (r) => (r['status'] ?? '').toString(),
        onLog: logs.add,
      );
      expect(logs.single.hasWorkerHint, isFalse);
    });
  });
}
