import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_timezone.dart';

CompanyDriverSchedule _nightShiftSchedule() {
  return CompanyDriverSchedule.fromJson(<String, dynamic>{
    'driver_id': 'drv_anon',
    'timezone': 'Europe/Brussels',
    'weekdays': <String, dynamic>{
      // Monday 18:00 → Tuesday 02:00, with a break at 22:00.
      '1': <Map<String, dynamic>>[
        <String, dynamic>{
          'start': '18:00',
          'end': '02:00',
          'breaks': <Map<String, dynamic>>[
            <String, dynamic>{'start': '22:00', 'end': '22:30'},
          ],
        },
      ],
      // Wednesday split shift.
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
  })!;
}

/// 2026-09-14 is a Monday; Brussels is on summer time (UTC+2).
DateTime _brusselsSummer(int day, int hour, int minute) =>
    DateTime.utc(2026, 9, day, hour - 2, minute);

void main() {
  group('company timezone', () {
    test('Brussels summer and winter offsets follow the EU rule', () {
      expect(
        companyTimezoneOffsetAt(DateTime.utc(2026, 7, 1), 'Europe/Brussels'),
        const Duration(hours: 2),
      );
      expect(
        companyTimezoneOffsetAt(DateTime.utc(2026, 1, 15), 'Europe/Brussels'),
        const Duration(hours: 1),
      );
      // Last Sunday of March 2026 is the 29th, switch at 01:00 UTC.
      expect(
        companyTimezoneOffsetAt(
          DateTime.utc(2026, 3, 29, 0, 59),
          'Europe/Brussels',
        ),
        const Duration(hours: 1),
      );
      expect(
        companyTimezoneOffsetAt(
          DateTime.utc(2026, 3, 29, 1, 0),
          'Europe/Brussels',
        ),
        const Duration(hours: 2),
      );
    });

    test('an unknown zone is reported instead of silently guessed', () {
      expect(companyTimezoneIsResolvable('Europe/Brussels'), isTrue);
      expect(companyTimezoneIsResolvable('America/Cayenne'), isFalse);
    });

    test('local to UTC round-trips across the winter change', () {
      const zone = 'Europe/Brussels';
      final winterLocal = DateTime(2026, 12, 1, 18);
      final utc = companyTimezoneLocalToUtc(winterLocal, zone);
      expect(utc, DateTime.utc(2026, 12, 1, 17));
      expect(companyTimezoneUtcToLocal(utc, zone).hour, 18);
    });
  });

  group('driver schedule', () {
    test('no schedule stays explicit and never blocks the driver', () {
      expect(
        companyDriverScheduleStateAt(
          schedule: null,
          atUtc: DateTime.utc(2026, 9, 14, 20),
        ),
        CompanyDriverScheduleState.noSchedule,
      );
      expect(
        companyDriverScheduleConflictFor(
          schedule: null,
          rideStartUtc: DateTime.utc(2026, 9, 14, 20),
          rideEndUtc: DateTime.utc(2026, 9, 14, 21),
        ),
        CompanyDriverScheduleConflict.noSchedule,
      );
    });

    test('night shift stays scheduled after midnight', () {
      final schedule = _nightShiftSchedule();
      // Monday 23:00 local.
      expect(
        companyDriverScheduleStateAt(
          schedule: schedule,
          atUtc: _brusselsSummer(14, 23, 0),
        ),
        CompanyDriverScheduleState.scheduled,
      );
      // Tuesday 01:30 local still belongs to Monday's block.
      expect(
        companyDriverScheduleStateAt(
          schedule: schedule,
          atUtc: _brusselsSummer(15, 1, 30),
        ),
        CompanyDriverScheduleState.scheduled,
      );
      // Tuesday 03:00 local is past the block.
      expect(
        companyDriverScheduleStateAt(
          schedule: schedule,
          atUtc: _brusselsSummer(15, 3, 0),
        ),
        CompanyDriverScheduleState.offHours,
      );
    });

    test('planned break is distinct from working and from off hours', () {
      final schedule = _nightShiftSchedule();
      expect(
        companyDriverScheduleStateAt(
          schedule: schedule,
          atUtc: _brusselsSummer(14, 22, 10),
        ),
        CompanyDriverScheduleState.onPlannedBreak,
      );
      expect(
        companyDriverScheduleStateAt(
          schedule: schedule,
          atUtc: _brusselsSummer(14, 22, 45),
        ),
        CompanyDriverScheduleState.scheduled,
      );
    });

    test('multiple blocks on one day leave a real gap', () {
      final schedule = _nightShiftSchedule();
      // Wednesday 2026-09-16.
      expect(
        companyDriverScheduleStateAt(
          schedule: schedule,
          atUtc: _brusselsSummer(16, 7, 0),
        ),
        CompanyDriverScheduleState.scheduled,
      );
      expect(
        companyDriverScheduleStateAt(
          schedule: schedule,
          atUtc: _brusselsSummer(16, 12, 0),
        ),
        CompanyDriverScheduleState.offHours,
      );
      expect(
        companyDriverScheduleStateAt(
          schedule: schedule,
          atUtc: _brusselsSummer(16, 17, 0),
        ),
        CompanyDriverScheduleState.scheduled,
      );
    });

    test('leave blocks the day and custom hours replace it', () {
      final schedule = _nightShiftSchedule();
      // 2026-09-23 is a Wednesday marked as leave.
      expect(
        companyDriverScheduleStateAt(
          schedule: schedule,
          atUtc: _brusselsSummer(23, 7, 0),
        ),
        CompanyDriverScheduleState.absent,
      );
      // 2026-09-30 Wednesday is overridden to 09:00–12:00.
      expect(
        companyDriverScheduleStateAt(
          schedule: schedule,
          atUtc: _brusselsSummer(30, 10, 0),
        ),
        CompanyDriverScheduleState.scheduled,
      );
      expect(
        companyDriverScheduleStateAt(
          schedule: schedule,
          atUtc: _brusselsSummer(30, 7, 0),
        ),
        CompanyDriverScheduleState.offHours,
      );
    });

    test('working hours today read back as a clock range', () {
      final schedule = _nightShiftSchedule();
      final windows = companyDriverScheduleWindowsForDay(
        schedule: schedule,
        localDay: DateTime(2026, 9, 14),
      );
      expect(windows, hasLength(1));
      expect(windows.single.clockRange, '18:00–02:00');
    });

    test('a future ride outside working hours names the conflict', () {
      final schedule = _nightShiftSchedule();
      // Monday 10:00 local, well before the 18:00 block.
      expect(
        companyDriverScheduleConflictFor(
          schedule: schedule,
          rideStartUtc: _brusselsSummer(14, 10, 0),
          rideEndUtc: _brusselsSummer(14, 10, 40),
        ),
        CompanyDriverScheduleConflict.outsideWorkingHours,
      );
    });

    test('a ride overlapping the planned break is refused with that reason', () {
      final schedule = _nightShiftSchedule();
      expect(
        companyDriverScheduleConflictFor(
          schedule: schedule,
          rideStartUtc: _brusselsSummer(14, 21, 50),
          rideEndUtc: _brusselsSummer(14, 22, 20),
        ),
        CompanyDriverScheduleConflict.plannedBreak,
      );
    });

    test('approach time is counted before the ride starts', () {
      final schedule = _nightShiftSchedule();
      // Ride at 18:10 is inside hours, but 25 minutes of approach is not.
      expect(
        companyDriverScheduleConflictFor(
          schedule: schedule,
          rideStartUtc: _brusselsSummer(14, 18, 10),
          rideEndUtc: _brusselsSummer(14, 18, 50),
        ),
        CompanyDriverScheduleConflict.none,
      );
      expect(
        companyDriverScheduleConflictFor(
          schedule: schedule,
          rideStartUtc: _brusselsSummer(14, 18, 10),
          rideEndUtc: _brusselsSummer(14, 18, 50),
          approach: const Duration(minutes: 25),
        ),
        CompanyDriverScheduleConflict.outsideWorkingHours,
      );
    });

    test('a ride running past the shift end is refused, not silently allowed', () {
      final schedule = _nightShiftSchedule();
      expect(
        companyDriverScheduleConflictFor(
          schedule: schedule,
          rideStartUtc: _brusselsSummer(15, 1, 40),
          rideEndUtc: _brusselsSummer(15, 2, 30),
        ),
        CompanyDriverScheduleConflict.rideEndsAfterWorkingHours,
      );
    });

    test('leave refuses a future ride with the absent reason', () {
      final schedule = _nightShiftSchedule();
      expect(
        companyDriverScheduleConflictFor(
          schedule: schedule,
          rideStartUtc: _brusselsSummer(23, 8, 0),
          rideEndUtc: _brusselsSummer(23, 8, 30),
        ),
        CompanyDriverScheduleConflict.absent,
      );
    });

    test('clock and weekday parsing accept the stored shapes', () {
      expect(companyDriverScheduleMinuteOfDay('18:00'), 1080);
      expect(companyDriverScheduleMinuteOfDay('1800'), 1080);
      expect(companyDriverScheduleMinuteOfDay('18'), 1080);
      expect(companyDriverScheduleMinuteOfDay('99:99'), isNull);
      expect(companyDriverScheduleWeekday('maandag'), 1);
      expect(companyDriverScheduleWeekday('Sun'), 7);
      expect(companyDriverScheduleWeekday('9'), isNull);
      expect(companyDriverScheduleClock(1560), '02:00');
    });

    test('schedule survives a JSON round trip', () {
      final schedule = _nightShiftSchedule();
      final again = CompanyDriverSchedule.fromJson(schedule.toJson())!;
      expect(again.timezone, 'Europe/Brussels');
      expect(again.weekdayBlocks[1]!.single.clockRangeForTest, '18:00–02:00');
      expect(again.exceptions, hasLength(2));
      expect(
        companyDriverScheduleStateAt(
          schedule: again,
          atUtc: _brusselsSummer(15, 1, 30),
        ),
        CompanyDriverScheduleState.scheduled,
      );
    });
  });
}

extension on CompanyDriverShiftBlock {
  String get clockRangeForTest =>
      '${companyDriverScheduleClock(startMinute)}–'
      '${companyDriverScheduleClock(endMinute)}';
}
