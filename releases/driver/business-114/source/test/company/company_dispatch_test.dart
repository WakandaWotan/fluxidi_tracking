import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_assignment_choice_field.dart';
import 'package:fluxidi_tracking/company/company_dispatch.dart';
import 'package:fluxidi_tracking/company/company_driver_roster.dart';

void main() {
  test('current driver is removed from alternatives', () {
    final alternatives = companyDispatchAlternativeDrivers(
      currentDriverId: 'drv_karel',
      drivers: <Map<String, dynamic>>[
        <String, dynamic>{
          'driver_id': 'drv_karel',
          'display_name': 'Karel',
          'is_active': true,
        },
        <String, dynamic>{
          'driver_id': 'drv_amira',
          'display_name': 'Amira',
          'is_active': true,
        },
        <String, dynamic>{
          'driver_id': 'drv_old',
          'display_name': 'Old',
          'is_active': false,
        },
      ],
    );
    expect(alternatives, hasLength(1));
    expect(alternatives.single['driver_id'], 'drv_amira');
  });

  test('expired heartbeat is never live', () {
    final now = DateTime.utc(2026, 9, 14, 12);
    expect(
      companyDispatchIsLive(
        lastSeenUtc: DateTime.utc(2026, 9, 14, 11, 56),
        nowUtc: now,
      ),
      isFalse,
    );
    expect(
      companyDispatchIsLive(
        lastSeenUtc: DateTime.utc(2026, 9, 14, 11, 58),
        nowUtc: now,
      ),
      isTrue,
    );
  });

  test('assignment errors stay specific', () {
    expect(
      companyAgendaAssignmentExceptionText(
        const CompanyAgendaException('assignment_driver_not_live'),
        AppLanguage.nl,
      ),
      kCompanyAgendaDriverNotLive.of(AppLanguage.nl),
    );
    expect(
      companyAgendaAssignmentExceptionText(
        const CompanyAgendaException('route_required'),
        AppLanguage.nl,
      ),
      isNot(kCompanyAgendaSaveFailed.of(AppLanguage.nl)),
    );
  });

  test('copy Monday roster to weekdays keeps overnight blocks', () {
    final copied = companyDriverCopyRosterDay(
      days: <String, List<CompanyRosterBlock>>{
        'mon': const [CompanyRosterBlock(start: '22:00', end: '06:00')],
      },
      fromDay: 'mon',
      toDays: const ['tue', 'wed'],
    );
    expect(copied['tue']!.single.isOvernight, isTrue);
    expect(copied['tue']!.single.start, '22:00');
    expect(
      companyDriverRosterToJson(days: copied)['timezone'],
      kCompanyDriverRosterTimezone,
    );
  });
}
