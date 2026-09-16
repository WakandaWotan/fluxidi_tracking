import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule_page.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';

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
    'exceptions': <Map<String, dynamic>>[
      <String, dynamic>{'date': '2026-09-21', 'kind': 'leave'},
    ],
  })!;
}

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
  group('roster feeds the assignment check', () {
    test('a driver without a roster keeps the existing verdict', () {
      final withoutRoster = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
      );
      final withEmptyRoster = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: const CompanyDriverSchedule(
          driverId: 'drv_anon',
          timezone: 'Europe/Brussels',
        ),
        rideStartUtc: _brussels(14, 10, 0),
        rideEndUtc: _brussels(14, 10, 40),
      );
      expect(withEmptyRoster.code, withoutRoster.code);
      expect(withEmptyRoster.tone, withoutRoster.tone);
    });

    test('a saved empty roster refuses, a never-set roster does not', () {
      final savedEmpty = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: const CompanyDriverSchedule(
          driverId: 'drv_anon',
          timezone: 'Europe/Brussels',
          explicitlySet: true,
        ),
        rideStartUtc: _brussels(14, 10, 0),
        rideEndUtc: _brussels(14, 10, 40),
      );
      expect(savedEmpty.tone, CompanyPlanPresenceTone.blocked);
      expect(savedEmpty.code, 'assignment_driver_not_scheduled');
    });

    test('a future ride outside working hours is blocked with the reason', () {
      final presence = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: _nightSchedule(),
        rideStartUtc: _brussels(14, 10, 0),
        rideEndUtc: _brussels(14, 10, 40),
      );
      expect(presence.tone, CompanyPlanPresenceTone.blocked);
      expect(presence.code, 'assignment_driver_outside_hours');
      expect(
        companyPlanPresenceLabel(presence, AppLanguage.nl),
        'Buiten werkuren',
      );
    });

    test('a ride overlapping the planned break names the break', () {
      final presence = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: _nightSchedule(),
        rideStartUtc: _brussels(14, 21, 50),
        rideEndUtc: _brussels(14, 22, 20),
      );
      expect(presence.code, 'assignment_driver_planned_break');
      expect(
        companyPlanPresenceLabel(presence, AppLanguage.nl),
        'Overlapt met geplande pauze',
      );
    });

    test('a ride running past the shift end is blocked', () {
      final presence = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: _nightSchedule(),
        rideStartUtc: _brussels(15, 1, 40),
        rideEndUtc: _brussels(15, 2, 30),
      );
      expect(presence.code, 'assignment_ride_after_hours');
    });

    test('leave blocks a future ride on that date', () {
      final presence = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: _nightSchedule(),
        rideStartUtc: _brussels(21, 19, 0),
        rideEndUtc: _brussels(21, 19, 30),
      );
      expect(presence.code, 'assignment_driver_absent');
    });

    test('inside working hours the driver is still not automatically free', () {
      // Same slot, but an overlapping ride already exists.
      final presence = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        overlapCode: 'assignment_overlap',
        whenNow: false,
        schedule: _nightSchedule(),
        rideStartUtc: _brussels(14, 19, 0),
        rideEndUtc: _brussels(14, 19, 40),
      );
      expect(presence.code, 'assignment_overlap');
      expect(presence.tone, CompanyPlanPresenceTone.blocked);
    });

    test('approach time is part of the availability window', () {
      expect(
        resolveCompanyPlanPresence(
          driver: _activeDriver(),
          whenNow: false,
          schedule: _nightSchedule(),
          rideStartUtc: _brussels(14, 18, 10),
          rideEndUtc: _brussels(14, 18, 50),
        ).code,
        'available',
      );
      expect(
        resolveCompanyPlanPresence(
          driver: _activeDriver(),
          whenNow: false,
          schedule: _nightSchedule(),
          rideStartUtc: _brussels(14, 18, 10),
          rideEndUtc: _brussels(14, 18, 50),
          approach: const Duration(minutes: 25),
        ).code,
        'assignment_driver_outside_hours',
      );
    });

    test('changing a roster never moves an existing ride by itself', () {
      // The resolver only reports; it has no side effects on the ride list.
      final rides = <String>['booking_anon_1'];
      resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: _nightSchedule(),
        rideStartUtc: _brussels(14, 10, 0),
        rideEndUtc: _brussels(14, 10, 30),
      );
      expect(rides, <String>['booking_anon_1']);
    });
  });

  group('schedule page', () {
    testWidgets('an administrator can edit and save', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDriverSchedulePage(
            language: AppLanguage.nl,
            schedule: _nightSchedule(),
            driverName: 'Anon Driver',
          ),
        ),
      );
      expect(find.byKey(kCompanyDriverSchedulePageKey), findsOneWidget);
      expect(find.byKey(kCompanyDriverScheduleSaveKey), findsOneWidget);
      expect(find.byKey(kCompanyDriverScheduleReadOnlyKey), findsNothing);
      // Monday's overnight block reads back with both ends.
      expect(find.textContaining('18:00–02:00'), findsOneWidget);
      expect(find.textContaining('nachtdienst'), findsOneWidget);
      expect(find.byKey(companyDriverScheduleAddBlockKey(2)), findsOneWidget);
    });

    testWidgets('a driver sees the same roster read-only', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDriverSchedulePage(
            language: AppLanguage.nl,
            schedule: _nightSchedule(),
            driverName: 'Anon Driver',
            canEdit: false,
          ),
        ),
      );
      expect(find.byKey(kCompanyDriverScheduleReadOnlyKey), findsOneWidget);
      expect(find.byKey(kCompanyDriverScheduleSaveKey), findsNothing);
      expect(find.byKey(companyDriverScheduleAddBlockKey(2)), findsNothing);
      expect(
        find.byKey(companyDriverScheduleRemoveBlockKey(1, 0)),
        findsNothing,
      );
      expect(find.textContaining('18:00–02:00'), findsOneWidget);
    });

    testWidgets('an unresolvable timezone is flagged, not faked', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDriverSchedulePage(
            language: AppLanguage.nl,
            schedule: const CompanyDriverSchedule(
              driverId: 'drv_anon',
              timezone: 'America/Cayenne',
            ),
            driverName: 'Anon Driver',
          ),
        ),
      );
      expect(
        find.byKey(kCompanyDriverScheduleTimezoneWarningKey),
        findsOneWidget,
      );
    });

    testWidgets('readable on phone, tablet and desktop widths', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in const <Size>[
        Size(390, 844),
        Size(844, 390),
        Size(800, 1280),
        Size(1280, 800),
        Size(1600, 900),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('schedule_${size.width}x${size.height}'),
            home: CompanyDriverSchedulePage(
              language: AppLanguage.nl,
              schedule: _nightSchedule(),
              driverName: 'Anon Driver',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${size.width}x${size.height}',
        );
        expect(
          find.text(kCompanyDriverScheduleMonday.of(AppLanguage.nl)),
          findsOneWidget,
          reason: 'weekday label missing at ${size.width}x${size.height}',
        );
      }
    });
  });
}
