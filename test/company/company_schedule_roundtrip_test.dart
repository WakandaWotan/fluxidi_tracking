import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_driver_status_facets.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';
import 'package:fluxidi_tracking/company/company_timezone.dart';

/// Exactly what `writeDriverSchedule` stores in the worker KV, including the
/// scope fields it adds. Keeping this literal is the point: it proves the app
/// parses the stored shape rather than a hand-tailored one.
Map<String, dynamic> _storedRoster() => <String, dynamic>{
  'driver_id': 'drv_anon',
  'timezone': 'Europe/Brussels',
  'tenant_id': 'tenant_anon',
  'company_id': 'company_anon',
  'updated_at': '2026-09-16T16:00:00.000Z',
  'weekdays': <String, dynamic>{
    '1': <Map<String, dynamic>>[
      <String, dynamic>{
        'start': '18:00',
        'end': '02:00',
        'breaks': <Map<String, dynamic>>[
          <String, dynamic>{'start': '22:00', 'end': '22:30'},
        ],
      },
    ],
    '3': <Map<String, dynamic>>[
      <String, dynamic>{'start': '06:00', 'end': '10:00'},
      <String, dynamic>{'start': '16:00', 'end': '20:00'},
    ],
  },
  'exceptions': <Map<String, dynamic>>[
    <String, dynamic>{'date': '2026-09-23', 'kind': 'leave'},
    <String, dynamic>{
      'date': '2026-09-30',
      'kind': 'custom_hours',
      'blocks': <Map<String, dynamic>>[
        <String, dynamic>{'start': '09:00', 'end': '12:00'},
      ],
    },
  ],
};

Map<String, dynamic> _activeDriver() => <String, dynamic>{
  'driver_id': 'drv_anon',
  'display_name': 'Anon Driver',
  'is_active': true,
  'availability_status': 'available',
};

/// Brussels summer time is UTC+2. 2026-09-14 is a Monday.
DateTime _brussels(int day, int hour, int minute) =>
    DateTime.utc(2026, 9, day, hour - 2, minute);

void main() {
  group('stored roster drives status and assignment', () {
    test('the worker shape parses without loss', () {
      final schedule = CompanyDriverSchedule.fromJson(_storedRoster())!;
      expect(schedule.driverId, 'drv_anon');
      expect(schedule.timezone, 'Europe/Brussels');
      expect(schedule.weekdayBlocks[1], hasLength(1));
      expect(schedule.weekdayBlocks[3], hasLength(2));
      expect(schedule.exceptions, hasLength(2));
      expect(schedule.isEmpty, isFalse);
    });

    test('working hours appear on the driver card', () {
      final schedule = CompanyDriverSchedule.fromJson(_storedRoster())!;
      final now = _brussels(14, 19, 0);
      final facets = companyDriverStatusFacets(
        lastSignalUtc: now.subtract(const Duration(minutes: 1)),
        nowUtc: now,
        rawWorkStatus: 'available',
        schedule: schedule,
      );
      expect(facets.plannedWindowLabel, '18:00–02:00');
      expect(facets.schedule, CompanyDriverScheduleState.scheduled);
      expect(facets.connection, CompanyDriverConnectionState.live);
      expect(facets.duty, CompanyDriverDutyState.working);
    });

    test('the same roster refuses a ride outside those hours', () {
      final schedule = CompanyDriverSchedule.fromJson(_storedRoster())!;
      final presence = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: schedule,
        rideStartUtc: _brussels(14, 10, 0),
        rideEndUtc: _brussels(14, 10, 40),
      );
      expect(presence.code, 'assignment_driver_outside_hours');
      expect(presence.tone, CompanyPlanPresenceTone.blocked);
    });

    test('and accepts one inside them', () {
      final schedule = CompanyDriverSchedule.fromJson(_storedRoster())!;
      final presence = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: schedule,
        rideStartUtc: _brussels(14, 19, 0),
        rideEndUtc: _brussels(14, 19, 40),
      );
      expect(presence.code, 'available');
    });

    test('leave stored as an exception blocks that date', () {
      final schedule = CompanyDriverSchedule.fromJson(_storedRoster())!;
      final presence = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: schedule,
        rideStartUtc: _brussels(23, 8, 0),
        rideEndUtc: _brussels(23, 8, 30),
      );
      expect(presence.code, 'assignment_driver_absent');
    });

    test('a driver with no stored roster is unaffected', () {
      final withoutRoster = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
      );
      final nullRoster = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: null,
        rideStartUtc: _brussels(14, 10, 0),
        rideEndUtc: _brussels(14, 10, 40),
      );
      expect(nullRoster.code, withoutRoster.code);
      expect(
        companyDriverScheduleStateAt(schedule: null, atUtc: _brussels(14, 10, 0)),
        CompanyDriverScheduleState.noSchedule,
      );
    });

    test('an unsupported timezone is flagged rather than mis-converted', () {
      final stored = _storedRoster()..['timezone'] = 'America/Cayenne';
      final schedule = CompanyDriverSchedule.fromJson(stored)!;
      expect(companyTimezoneIsResolvable(schedule.timezone), isFalse);
      // It still parses and still refuses rides; only the clock falls back to
      // the device zone, which the schedule screen states explicitly.
      expect(schedule.weekdayBlocks[1], hasLength(1));
    });
  });
}
