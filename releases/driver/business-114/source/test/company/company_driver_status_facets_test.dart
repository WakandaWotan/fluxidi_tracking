import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_driver_status_facets.dart';

/// Monday 18:00–02:00 Brussels, break 22:00–22:30.
CompanyDriverSchedule _nightSchedule() {
  return CompanyDriverSchedule.fromJson(<String, dynamic>{
    'driver_id': 'drv_anon',
    'timezone': 'Europe/Brussels',
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
    },
  })!;
}

/// Brussels summer time is UTC+2.
DateTime _brussels(int day, int hour, int minute) =>
    DateTime.utc(2026, 9, day, hour - 2, minute);

void main() {
  group('driver status facets stay independent', () {
    test('scheduled but offline is not reported as not working', () {
      final now = _brussels(14, 19, 0);
      final facets = companyDriverStatusFacets(
        lastSignalUtc: null,
        nowUtc: now,
        rawWorkStatus: '',
        schedule: _nightSchedule(),
      );
      expect(facets.connection, CompanyDriverConnectionState.unknown);
      expect(facets.duty, CompanyDriverDutyState.unknown);
      expect(facets.schedule, CompanyDriverScheduleState.scheduled);
      expect(facets.plannedWindowLabel, '18:00–02:00');
      // The roster must not be read as proof of being live or on duty.
      expect(facets.duty, isNot(CompanyDriverDutyState.working));
    });

    test('live but off duty keeps both facts side by side', () {
      final now = _brussels(14, 10, 0);
      final facets = companyDriverStatusFacets(
        lastSignalUtc: now.subtract(const Duration(minutes: 2)),
        nowUtc: now,
        rawWorkStatus: 'offline',
        schedule: _nightSchedule(),
      );
      expect(facets.connection, CompanyDriverConnectionState.live);
      expect(facets.duty, CompanyDriverDutyState.dutyEnded);
      expect(facets.schedule, CompanyDriverScheduleState.offHours);
    });

    test('working and free during the shift', () {
      final now = _brussels(14, 19, 30);
      final facets = companyDriverStatusFacets(
        lastSignalUtc: now.subtract(const Duration(minutes: 1)),
        nowUtc: now,
        rawWorkStatus: 'available',
        schedule: _nightSchedule(),
      );
      expect(facets.connection, CompanyDriverConnectionState.live);
      expect(facets.duty, CompanyDriverDutyState.working);
      expect(facets.schedule, CompanyDriverScheduleState.scheduled);
    });

    test('driver break and planned break are separate facts', () {
      final now = _brussels(14, 22, 10);
      final driverPaused = companyDriverStatusFacets(
        lastSignalUtc: now,
        nowUtc: now,
        rawWorkStatus: 'paused',
        schedule: _nightSchedule(),
      );
      expect(driverPaused.duty, CompanyDriverDutyState.onBreak);
      expect(driverPaused.schedule, CompanyDriverScheduleState.onPlannedBreak);

      // Still driving through the planned break: the roster says break, the
      // driver says working. Neither is rewritten.
      final stillDriving = companyDriverStatusFacets(
        lastSignalUtc: now,
        nowUtc: now,
        rawWorkStatus: 'on_trip',
        schedule: _nightSchedule(),
      );
      expect(stillDriving.duty, CompanyDriverDutyState.working);
      expect(stillDriving.schedule, CompanyDriverScheduleState.onPlannedBreak);
    });

    test('a stale signal is not the same as no signal', () {
      final now = _brussels(14, 19, 0);
      final stale = companyDriverStatusFacets(
        lastSignalUtc: now.subtract(const Duration(minutes: 40)),
        nowUtc: now,
        rawWorkStatus: 'available',
        schedule: _nightSchedule(),
      );
      expect(stale.connection, CompanyDriverConnectionState.staleOrLost);
      expect(stale.lastDriverSignalUtc, isNotNull);
      expect(stale.updateSource, CompanyDriverUpdateSource.driverSignal);
      // Duty still reflects what the driver pressed.
      expect(stale.duty, CompanyDriverDutyState.working);

      final never = companyDriverStatusFacets(
        lastSignalUtc: null,
        nowUtc: now,
        rawWorkStatus: 'available',
      );
      expect(never.connection, CompanyDriverConnectionState.unknown);
      expect(never.updateSource, CompanyDriverUpdateSource.none);
    });

    test('no roster is explicit and leaves duty untouched', () {
      final now = _brussels(14, 19, 0);
      final facets = companyDriverStatusFacets(
        lastSignalUtc: now,
        nowUtc: now,
        rawWorkStatus: 'available',
      );
      expect(facets.schedule, CompanyDriverScheduleState.noSchedule);
      expect(facets.hasRoster, isFalse);
      expect(facets.plannedWindowLabel, isEmpty);
      expect(facets.duty, CompanyDriverDutyState.working);
    });

    test('night shift after midnight still shows tonight window', () {
      final now = _brussels(15, 1, 0);
      final facets = companyDriverStatusFacets(
        lastSignalUtc: now,
        nowUtc: now,
        rawWorkStatus: 'available',
        schedule: _nightSchedule(),
      );
      expect(facets.schedule, CompanyDriverScheduleState.scheduled);
      expect(facets.plannedWindowLabel, '18:00–02:00');
    });

    test('an idle account never becomes working by itself', () {
      final now = _brussels(14, 19, 0);
      expect(
        companyDriverDutyState(rawWorkStatus: '', rawPresenceLabel: ''),
        CompanyDriverDutyState.unknown,
      );
      final facets = companyDriverStatusFacets(
        lastSignalUtc: now,
        nowUtc: now,
        rawWorkStatus: '',
        schedule: _nightSchedule(),
      );
      expect(facets.connection, CompanyDriverConnectionState.live);
      expect(facets.duty, CompanyDriverDutyState.unknown);
    });
  });
}
