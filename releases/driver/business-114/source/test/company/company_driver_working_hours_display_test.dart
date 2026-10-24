import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule_page.dart';

Map<String, dynamic> _weekdayRoster(String start, String end) {
  final block = <String, dynamic>{'start': start, 'end': end};
  final empty = <Map<String, dynamic>>[];
  return <String, dynamic>{
    'timezone': 'Europe/Brussels',
    'explicitly_set': true,
    'days': <String, dynamic>{
      'mon': <Map<String, dynamic>>[block],
      'tue': <Map<String, dynamic>>[block],
      'wed': <Map<String, dynamic>>[block],
      'thu': <Map<String, dynamic>>[block],
      'fri': <Map<String, dynamic>>[block],
      'sat': empty,
      'sun': empty,
    },
  };
}

Map<String, dynamic> _weekendRoster() {
  final block = <String, dynamic>{'start': '08:00', 'end': '16:00'};
  final empty = <Map<String, dynamic>>[];
  return <String, dynamic>{
    'timezone': 'Europe/Brussels',
    'explicitly_set': true,
    'days': <String, dynamic>{
      'mon': empty,
      'tue': empty,
      'wed': empty,
      'thu': empty,
      'fri': empty,
      'sat': <Map<String, dynamic>>[block],
      'sun': <Map<String, dynamic>>[block],
    },
  };
}

void main() {
  test('weekly_roster wins over driver_schedule', () {
    final schedule = companyDriverScheduleFromDriverRecord(<String, dynamic>{
      'driver_id': 'drv_test_4',
      'driver_schedule': <String, dynamic>{
        'timezone': 'Europe/Brussels',
        'explicitly_set': true,
        'weekdays': <String, dynamic>{},
      },
      'weekly_roster': _weekdayRoster('08:00', '16:00'),
    });
    expect(schedule, isNotNull);
    expect(schedule!.weekdayBlocks[1]!.single.startMinute, 8 * 60);
    expect(schedule.weekdayBlocks[1]!.single.endMinute, 16 * 60);
    expect(schedule.weekdayBlocks[6] ?? const <CompanyDriverShiftBlock>[], isEmpty);
  });

  test('schedule.weekdays is used when the endpoint is present', () {
    final fromEndpoint = CompanyDriverSchedule.fromJson(<String, dynamic>{
      'driver_id': 'drv_test_16',
      'timezone': 'Europe/Brussels',
      'explicitly_set': true,
      'weekdays': <String, dynamic>{
        '6': <Map<String, dynamic>>[
          <String, dynamic>{'start': '08:00', 'end': '16:00'},
        ],
        '7': <Map<String, dynamic>>[
          <String, dynamic>{'start': '08:00', 'end': '16:00'},
        ],
      },
    });
    final shown = companyDriverWorkingHours(
      driverId: 'drv_test_16',
      fromScheduleEndpoint: fromEndpoint,
      indexRecord: <String, dynamic>{
        'driver_id': 'drv_test_16',
        'weekly_roster': _weekdayRoster('00:00', '08:00'),
      },
    );
    expect(shown.weekdayBlocks[1] ?? const <CompanyDriverShiftBlock>[], isEmpty);
    expect(shown.weekdayBlocks[6]!.single.startMinute, 8 * 60);
    expect(shown.weekdayBlocks[7]!.single.endMinute, 16 * 60);
  });

  test('index weekly_roster is used when the endpoint has no hours', () {
    final shown = companyDriverWorkingHours(
      driverId: 'drv_test_4',
      fromScheduleEndpoint: CompanyDriverSchedule(
        driverId: 'drv_test_4',
        timezone: 'Europe/Brussels',
      ),
      indexRecord: <String, dynamic>{
        'driver_id': 'drv_test_4',
        'driver_schedule': <String, dynamic>{'explicitly_set': false},
        'weekly_roster': _weekdayRoster('08:00', '16:00'),
      },
    );
    expect(shown.weekdayBlocks[4]!.single.endMinute, 16 * 60);
  });

  testWidgets('drv_test_4 and drv_test_16 render their stored hours', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> show(String id, CompanyDriverSchedule schedule) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDriverSchedulePage(
            key: ValueKey<String>(id),
            language: AppLanguage.nl,
            schedule: schedule,
            driverName: id,
            canEdit: false,
            persistenceAvailable: true,
          ),
        ),
      );
      await tester.pump();
    }

    final weekday = companyDriverScheduleFromDriverRecord(<String, dynamic>{
      'driver_id': 'drv_test_4',
      'weekly_roster': _weekdayRoster('08:00', '16:00'),
    })!;
    final weekend = companyDriverScheduleFromDriverRecord(<String, dynamic>{
      'driver_id': 'drv_test_16',
      'weekly_roster': _weekendRoster(),
    })!;

    await show('drv_test_4', weekday);
    expect(find.text('08:00–16:00'), findsNWidgets(5));
    expect(find.text('Geen werkuren'), findsNWidgets(2));
    await expectLater(
      find.byType(CompanyDriverSchedulePage),
      matchesGoldenFile('goldens/drv_test_4_hours.png'),
    );

    await show('drv_test_16', weekend);
    expect(find.text('08:00–16:00'), findsNWidgets(2));
    expect(find.text('Geen werkuren'), findsNWidgets(5));
    await expectLater(
      find.byType(CompanyDriverSchedulePage),
      matchesGoldenFile('goldens/drv_test_16_hours.png'),
    );
  });
}
