import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule_page.dart';
import 'package:fluxidi_tracking/company/company_driver_status_facets.dart';
import 'package:fluxidi_tracking/company/company_drivers_now.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';

/// Same working hours, but in a zone the app cannot convert exactly.
CompanyDriverSchedule _unsupportedZoneSchedule() {
  return CompanyDriverSchedule.fromJson(<String, dynamic>{
    'driver_id': 'drv_anon',
    'timezone': 'America/Cayenne',
    'weekdays': <String, dynamic>{
      '1': <Map<String, dynamic>>[
        <String, dynamic>{'start': '18:00', 'end': '02:00'},
      ],
    },
  })!;
}

Map<String, dynamic> _activeDriver() => <String, dynamic>{
  'driver_id': 'drv_anon',
  'display_name': 'Anon Driver',
  'is_active': true,
  'availability_status': 'available',
};

DateTime _at(int day, int hour) => DateTime.utc(2026, 9, day, hour);

void main() {
  group('unsupported roster timezone', () {
    test('availability is undeterminable, never assumed from the device', () {
      final schedule = _unsupportedZoneSchedule();
      expect(
        companyDriverScheduleStateAt(schedule: schedule, atUtc: _at(14, 19)),
        CompanyDriverScheduleState.unresolvableTimezone,
      );
      // Not treated as "scheduled" and not as "off hours" either.
      expect(
        companyDriverScheduleStateAt(schedule: schedule, atUtc: _at(14, 3)),
        CompanyDriverScheduleState.unresolvableTimezone,
      );
    });

    test('it blocks assignment instead of permitting it', () {
      final schedule = _unsupportedZoneSchedule();
      // A moment that would be inside the hours if the device clock were used.
      final presence = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: schedule,
        rideStartUtc: _at(14, 19),
        rideEndUtc: _at(14, 20),
      );
      expect(presence.tone, CompanyPlanPresenceTone.blocked);
      expect(presence.code, 'assignment_schedule_undeterminable');
      expect(
        companyPlanPresenceLabel(presence, AppLanguage.nl),
        'Roosterbeschikbaarheid niet vast te stellen',
      );
      expect(
        companyDriverScheduleConflictFor(
          schedule: schedule,
          rideStartUtc: _at(14, 19),
          rideEndUtc: _at(14, 20),
        ),
        CompanyDriverScheduleConflict.undeterminable,
      );
    });

    test('no working-hours window is invented on the card', () {
      final facets = companyDriverStatusFacets(
        lastSignalUtc: _at(14, 19),
        nowUtc: _at(14, 19),
        rawWorkStatus: 'available',
        schedule: _unsupportedZoneSchedule(),
      );
      expect(facets.schedule, CompanyDriverScheduleState.unresolvableTimezone);
      expect(facets.plannedWindowLabel, isEmpty);
      // Duty and connection are untouched by the timezone problem.
      expect(facets.duty, CompanyDriverDutyState.working);
      expect(facets.connection, CompanyDriverConnectionState.live);
    });

    test('a driver with no roster keeps the agreed existing behaviour', () {
      final withoutRoster = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
      );
      final nullRoster = resolveCompanyPlanPresence(
        driver: _activeDriver(),
        whenNow: false,
        schedule: null,
        rideStartUtc: _at(14, 19),
        rideEndUtc: _at(14, 20),
      );
      expect(nullRoster.code, withoutRoster.code);
      expect(nullRoster.tone, isNot(CompanyPlanPresenceTone.blocked));
      expect(
        companyDriverScheduleConflictFor(
          schedule: null,
          rideStartUtc: _at(14, 19),
          rideEndUtc: _at(14, 20),
        ),
        CompanyDriverScheduleConflict.noSchedule,
      );
    });

    testWidgets('the card states it cannot be determined', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyDriversNowStrip(
              language: AppLanguage.nl,
              rows: companyDriverNowRows(
                nowUtc: _at(14, 19),
                drivers: <Map<String, dynamic>>[_activeDriver()],
                rides: const <CompanyAgendaRide>[],
                schedules: <String, CompanyDriverSchedule>{
                  'drv_anon': _unsupportedZoneSchedule(),
                },
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining(
          kCompanyDriverScheduleUndeterminable.of(AppLanguage.nl),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('18:00–02:00'), findsNothing);
    });
  });

  group('schedule screen without a storage endpoint', () {
    testWidgets('saving is disabled and said so', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDriverSchedulePage(
            language: AppLanguage.nl,
            schedule: _unsupportedZoneSchedule(),
            driverName: 'Anon Driver',
          ),
        ),
      );
      expect(
        find.byKey(kCompanyDriverScheduleSaveUnavailableKey),
        findsOneWidget,
      );
      final save = tester.widget<FilledButton>(
        find.byKey(kCompanyDriverScheduleSaveKey),
      );
      expect(
        save.onPressed,
        isNull,
        reason: 'a tappable save button would suggest it was stored',
      );
    });

    testWidgets('with an endpoint the button works and returns the roster', (
      tester,
    ) async {
      CompanyDriverSchedule? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                saved = await openCompanyDriverSchedulePage(
                  context,
                  language: AppLanguage.nl,
                  schedule: _unsupportedZoneSchedule(),
                  driverName: 'Anon Driver',
                  canEdit: true,
                  persistenceAvailable: true,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(kCompanyDriverScheduleSaveUnavailableKey),
        findsNothing,
      );
      await tester.tap(find.byKey(kCompanyDriverScheduleSaveKey));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.driverId, 'drv_anon');
    });

    testWidgets('the unsupported zone is stated on the screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDriverSchedulePage(
            language: AppLanguage.nl,
            schedule: _unsupportedZoneSchedule(),
            driverName: 'Anon Driver',
          ),
        ),
      );
      expect(
        find.byKey(kCompanyDriverScheduleTimezoneWarningKey),
        findsOneWidget,
      );
      expect(
        find.textContaining('niet gebruikt voor beschikbaarheid'),
        findsOneWidget,
      );
    });
  });
}
